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

      # ONE content-space scroll quantization per axis for the whole pass. The park
      # predicates and the per-constituent visibility gates below are the same
      # expression on this value — sharing the local (here and in the blit-plan
      # mirror) makes a mixed quantization basis, where reposition and the blit
      # plan disagree about whether a header is parked, structurally impossible.
      scroll_x_i = scroll_offset.x.to_i.to_f64
      scroll_y_i = scroll_offset.y.to_i.to_f64

      # Per-axis compound-disposition context, built ONCE per pass — the same
      # StickyMath.compound_axis serves the blit-plan fast path, so the two
      # passes cannot disagree on a compound header's extent or park state.
      # Y passes shifted: nil (physical-only) — pending its own arc.
      col_view = AxisView.new(
        sizes: col_sizes, cum: col_cum, ruler_offset: ruler_col_width_pixels,
        sticky_extent: sticky_col_width_pixels + ruler_col_width_pixels,
        viewport_extent: bounds.width, scroll_q: scroll_x_i,
        shifted: @cached_col_shifted, park: OFFSCREEN_PARK)
      row_view = AxisView.new(
        sizes: row_sizes, cum: row_cum, ruler_offset: ruler_row_height_pixels,
        sticky_extent: sticky_row_height_pixels + ruler_row_height_pixels,
        viewport_extent: bounds.height, scroll_q: scroll_y_i,
        shifted: nil, park: OFFSCREEN_PARK)

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

        # Compound cells derive BOTH screen-space position AND visible extent per
        # axis from StickyMath.compound_axis (shared with the blit-plan fast path):
        # (a) correct screen-space position (not content-space)
        # (b) extent shrinks as constituents shift out (prevents sibling overlap)
        compound_w = 0.0
        compound_h = 0.0

        if !is_sticky_col
          if is_compound
            new_x, compound_w = Widgets::VirtualMatrix::StickyMath.compound_axis(
              col_view, bounding[0][1], bounding[1][1], true_x)
          else
            # Non-compound: screen-space position = content position − live scroll. Sticky layers
            # are NOT viewport_cache (see this file's header), so the cell bounds must carry the
            # scroll themselves. Using the cached @viewport_col_positions here was a bug: those
            # StickyMath positions are recomputed only when a whole column crosses the boundary, so
            # they dropped the sub-column scroll and froze the cells whenever scroll < one column.
            content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
            new_x = ruler_x_offset + content_x - scroll_x_i
          end
        else
          new_x = true_x
        end

        if !is_sticky_row
          if is_compound
            new_y, compound_h = Widgets::VirtualMatrix::StickyMath.compound_axis(
              row_view, bounding[0][0], bounding[1][0], true_y)
          else
            # Non-compound: screen-space position = content position − live scroll (see the X path
            # above for why the cached @viewport_row_positions branch was a freeze bug).
            content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
            new_y = ruler_y_offset + content_y - scroll_y_i
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
      # This is the FALLBACK path (a sticky cell has no cached texture yet); the common scroll/resize
      # case goes through compute_sticky_blit_plans, which is per-layer (only touches changed layers).
      if any_changed
        sv = @content_scroll_view
        sv.try(&.sticky_row_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_col_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_corner_layer).try(&.mark_needs_clear_and_render)
      end
      {% if flag?(:verify_bounds) %} verify_sticky_positions! {% end %}
    end
  end
end
