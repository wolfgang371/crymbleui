module CrymbleUI
  class VirtualMatrix < Widget
    # Reposition sticky cells to account for scroll offset.
    # Sticky layers (row/col/corner) are non-viewport_cache, so they don't apply
    # scroll_offset during compositing. Cells must be positioned at screen-space
    # coordinates for correct alignment with the viewport_cache content layer.
    #
    # Uses TRUE content-space positions (linear sum of sizes) rather than StickyMath
    # offset+positions, because StickyMath output includes a scroll-dependent offset
    # that only works correctly with viewport_cache layers.
    #
    # - sticky_row cells: x = true_x - scroll_offset.x, y = true_y (fixed vertically)
    # - sticky_col cells: x = true_x (fixed horizontally), y = true_y - scroll_offset.y
    # - sticky_corner cells: x = true_x, y = true_y (fixed both ways)
    # - content cells: not touched (viewport_cache handles scroll)
    private def reposition_sticky_cells
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return unless col_sizes && row_sizes

      col_cum = @cached_col_physical_cum
      row_cum = @cached_row_physical_cum

      any_changed = false

      @active_cells.each do |key, widget|
        row, col = key
        is_sticky_row = row < sticky_rows
        is_sticky_col = col < sticky_cols
        next unless is_sticky_row || is_sticky_col

        # Grid-order position (for sticky dimensions that don't scroll)
        # Ruler offsets shift all data cells right/down within the sticky layers
        ruler_x_offset = ruler_col_width_pixels
        ruler_y_offset = ruler_row_height_pixels
        true_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
        true_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)

        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]

        # For compound cells, compute BOTH screen-space position AND visible width
        # from constituent columns' viewport positions. This ensures:
        # (a) correct screen-space position (not content-space from WU3)
        # (b) width shrinks as constituent columns shift out (prevents sibling overlap)
        compound_w = 0.0
        compound_h = 0.0

        if !is_sticky_col
          if is_compound
            # Compute screen-space bounding box using physical cumulative positions.
            # Pin compound left edge at sticky_col_w (the boundary), matching the
            # reference painters_algo where pos_compound = pos_clipped = sticky
            # boundary position. Columns fully behind the boundary are skipped.
            # viewport_col_positions.has_key? ensures shifted-out columns are excluded.
            # BUG FIX: Also include columns NOT in viewport_col_positions if they are
            # physically visible and not shifted out. This catches right-edge columns
            # that the cached viewport_col_positions misses (max_x changed but sticky_key didn't).
            bb_c1 = bounding[0][1]
            bb_c2 = bounding[1][1]
            min_screen_x = Float64::MAX
            max_screen_x = -Float64::MAX
            sticky_col_w = sticky_col_width_pixels + ruler_col_width_pixels
            viewport_right = self.bounds.width
            visible_col_count = 0
            single_col_x = 0.0
            single_col_size = 0.0
            col_shifted = @cached_col_sorted_shifted
            (bb_c1..bb_c2).each do |ci|
              # Primary check: column is in the cached visible set (handles shift-out correctly)
              unless @viewport_col_positions.has_key?(ci)
                # Fallback for right-edge columns: include if NOT shifted out and
                # physically within viewport bounds. The cache misses these because
                # max_x changed (scroll) but the sticky cache key didn't update.
                if shifted = col_shifted
                  is_shifted = shifted.bsearch { |s| s >= ci }.try { |s| s == ci }
                  next if is_shifted  # Column is shifted out — skip
                end
                # Not shifted (or no shift data) — check physical screen visibility below
              end
              true_ci_x = ruler_x_offset + (col_cum ? col_cum[ci].to_f64 : (0...ci).sum { |c| col_sizes[c] }.to_f64)
              unclamped_scr_x = true_ci_x - @scroll_offset.x.to_i.to_f64
              col_right = unclamped_scr_x + col_sizes[ci].to_f64
              next if col_right <= sticky_col_w        # fully behind sticky header
              next if unclamped_scr_x >= viewport_right # right of viewport
              visible_col_count += 1
              single_col_x = unclamped_scr_x
              single_col_size = col_sizes[ci].to_f64
              scr_x = {unclamped_scr_x, sticky_col_w}.max  # PIN at boundary
              capped_right = {col_right, viewport_right}.min
              min_screen_x = {min_screen_x, scr_x}.min
              max_screen_x = {max_screen_x, capped_right}.max
            end

            if min_screen_x < Float64::MAX
              if visible_col_count > 1
                new_x = min_screen_x        # pinned compound position
                compound_w = max_screen_x - min_screen_x
              else
                new_x = single_col_x        # unclamped — scroll off naturally
                compound_w = single_col_size # regular cell size
              end
            else
              # All constituent columns outside viewport. Distinguish scrolled-past
              # (behind sticky header) from not-yet-visible (right of viewport).
              sticky_col_w = sticky_col_width_pixels + ruler_col_width_pixels
              last_col_right = ruler_x_offset + (col_cum ? col_cum[bb_c2 + 1].to_f64 : (0..bb_c2).sum { |c| col_sizes[c] }.to_f64)
              if last_col_right - @scroll_offset.x <= sticky_col_w
                # Scrolled past sticky header — park off-screen with zero size
                new_x = OFFSCREEN_PARK
                compound_w = 0.0
              else
                # Not yet visible — keep full width at content position
                new_x = true_x
                compound_w = (bb_c1..bb_c2).sum { |ci| col_sizes[ci] }.to_f64
              end
            end
          else
            # Non-compound: PINNING for col < shifting_index (see compound path comment).
            # Guard: has_key? ensures shifted-out cols (in creation buffer but not viewport)
            # use the scroll-subtraction path instead of direct screen-space positioning.
            if @viewport_col_positions.has_key?(col) && col < @viewport_col_shifting_index
              new_x = ruler_x_offset + @viewport_col_positions[col].to_f64
            else
              content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
              new_x = ruler_x_offset + content_x - @scroll_offset.x.to_i.to_f64
            end
          end
        else
          new_x = true_x
        end

        if !is_sticky_row
          if is_compound
            # Compute screen-space bounding box from all constituent rows.
            # For sticky-col compound cells, use direct content positions (not
            # viewport_row_positions which are for the content layer), and clamp
            # to sticky header bottom so the cell doesn't slide behind the header.
            bb_r1 = bounding[0][0]
            bb_r2 = bounding[1][0]
            min_screen_y = Float64::MAX
            max_screen_y = -Float64::MAX
            sticky_row_h = sticky_row_height_pixels + ruler_row_height_pixels
            viewport_bottom = self.bounds.height
            visible_row_count = 0
            single_row_y = 0.0
            single_row_size = 0.0
            (bb_r1..bb_r2).each do |ri|
              true_ri_y = ruler_y_offset + (row_cum ? row_cum[ri].to_f64 : (0...ri).sum { |r| row_sizes[r] }.to_f64)
              unclamped_scr_y = true_ri_y - @scroll_offset.y.to_i.to_f64
              row_bottom = unclamped_scr_y + row_sizes[ri].to_f64
              # Skip rows entirely behind the sticky header
              next if row_bottom <= sticky_row_h
              # Skip rows below viewport
              next if unclamped_scr_y >= viewport_bottom
              visible_row_count += 1
              single_row_y = unclamped_scr_y
              single_row_size = row_sizes[ri].to_f64
              scr_y = {unclamped_scr_y, sticky_row_h}.max
              capped_bottom = {row_bottom, viewport_bottom}.min
              min_screen_y = {min_screen_y, scr_y}.min
              max_screen_y = {max_screen_y, capped_bottom}.max
            end

            if min_screen_y < Float64::MAX
              if visible_row_count > 1
                new_y = min_screen_y        # pinned compound position
                compound_h = max_screen_y - min_screen_y
              else
                new_y = single_row_y        # unclamped — scroll off naturally
                compound_h = single_row_size # regular cell size
              end
            else
              # All constituent rows behind sticky header — park off-screen with zero size
              new_y = OFFSCREEN_PARK
              compound_h = 0.0
            end
          else
            # Non-compound: PINNING for row < shifting_index (see compound X path comment).
            # Guard: has_key? ensures shifted-out rows (in creation buffer but not viewport)
            # use the scroll-subtraction path instead of direct screen-space positioning.
            if @viewport_row_positions.has_key?(row) && row < @viewport_row_shifting_index
              new_y = ruler_y_offset + @viewport_row_positions[row].to_f64
            else
              content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
              new_y = ruler_y_offset + content_y - @scroll_offset.y.to_i.to_f64
            end
          end
        else
          new_y = true_y
        end

        # Compute target size: compound cells use visible size, others keep current
        # Allow zero size for cells fully behind sticky header (prevents overlap assertions)
        if is_compound
          new_w = is_sticky_col ? widget.bounds.width : (compound_w == 0.0 ? 0.0 : {compound_w - grid_spacing, 1.0}.max)
          new_h = is_sticky_row ? widget.bounds.height : (compound_h == 0.0 ? 0.0 : {compound_h - grid_spacing, 1.0}.max)
        else
          # Use fresh sizes from col_sizes/row_sizes — during resize drag,
          # widget.bounds still has stale width from initial layout
          new_w = (col_sizes[col] - grid_spacing).to_f64
          new_h = (row_sizes[row] - grid_spacing).to_f64
        end

        # Only reposition/resize if changed (avoids unnecessary layout calls)
        if widget.bounds.x != new_x || widget.bounds.y != new_y || widget.bounds.width != new_w || widget.bounds.height != new_h
          {% if flag?(:DEBUG_BLIT) %}
            File.open("/tmp/blit_trace.log", "a") do |f|
              f.puts "REPOSITION: #{widget.class.name.split("::").last}##{widget.path_id} (#{widget.bounds.width.round(1)}x#{widget.bounds.height.round(1)}) → (#{new_w.round(1)}x#{new_h.round(1)}) at (#{new_x.round(1)},#{new_y.round(1)})"
            end
          {% end %}
          # Only invalidate primitive cache if SIZE changed (not just position).
          # Position-only changes: cached widget_backend texture is still valid,
          # just needs to be blitted at the new position. Avoids expensive primitive
          # regeneration + full re-render for every scroll frame.
          size_changed = widget.bounds.width != new_w || widget.bounds.height != new_h
          cell_constraints = BoxConstraints.tight(Size.new(new_w, new_h))
          widget.layout(cell_constraints, Vec2.new(new_x, new_y))
          widget.invalidate_primitive_cache if size_changed
          any_changed = true
        end
      end

      # Clear and re-render sticky layers to reflect new cell positions.
      # Use mark_needs_clear_and_render (NOT mark_needs_layout) — lighter:
      # no sibling validation, NeedsRender semantics, but still clears old pixels.
      if any_changed
        sv = @content_scroll_view
        sv.try(&.sticky_row_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_col_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_corner_layer).try(&.mark_needs_clear_and_render)
      end
    end
  end
end
