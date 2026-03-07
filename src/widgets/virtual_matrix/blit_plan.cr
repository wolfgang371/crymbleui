module CrymbleUI
  class VirtualMatrix < Widget
    # Check if sticky cells can use the blit-plan fast path.
    # Returns false on first frame, if any sticky cell lacks a cached texture,
    # if content changed (needs_render), or if compound cells need resizing.
    private def sticky_cells_can_use_blit_plan? : Bool
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return false if sticky_rows == 0 && sticky_cols == 0
      return false if @show_rulers  # Rulers are separate widgets, not in @active_cells — blit_plan would clear them

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return false unless col_sizes && row_sizes

      cells_with_backend = 0
      @active_cells.each do |key, widget|
        row, col = key
        next unless row < sticky_rows || col < sticky_cols
        next unless widget.widget_backend                     # Out-of-bounds cells have no backend (skip, won't blit)
        cells_with_backend += 1
        return false if widget.needs_render?                  # Content changed, need full render

        # Compound cells may need resizing (Phase 2a: reject them)
        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        if is_compound
          is_sticky_row = row < sticky_rows
          is_sticky_col = col < sticky_cols
          # Compound cells that are NOT in the sticky dimension get variable sizes
          # which may differ from their widget_backend size — can't safely blit
          return false if !is_sticky_col  # compound row-header cells resize on X-scroll
          return false if !is_sticky_row  # compound col-header cells resize on Y-scroll
        end
      end
      cells_with_backend > 0  # Need at least one cell with cached texture to blit
    end

    # Compute blit plans for sticky layers instead of calling reposition_sticky_cells.
    # Reuses the same position computation logic but produces BlitEntry arrays
    # instead of calling widget.layout(). This skips layout + render for O(blit) per cell.
    private def compute_sticky_blit_plans
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return unless col_sizes && row_sizes

      col_cum = @cached_col_physical_cum
      row_cum = @cached_row_physical_cum

      # Cache absolute position once — needed to convert parent-relative new_x/new_y
      # to absolute coords before subtracting layer.bounds (which is absolute).
      vm_abs = absolute_bounds

      sv = @content_scroll_view
      return unless sv

      sticky_row_layer = sv.sticky_row_layer
      sticky_col_layer = sv.sticky_col_layer
      sticky_corner_layer = sv.sticky_corner_layer

      row_entries = [] of BlitEntry
      col_entries = [] of BlitEntry
      corner_entries = [] of BlitEntry

      @active_cells.each do |key, widget|
        row, col = key
        is_sticky_row = row < sticky_rows
        is_sticky_col = col < sticky_cols
        next unless is_sticky_row || is_sticky_col

        wb = widget.widget_backend
        next unless wb  # Guard (should be guaranteed by can_use check)

        # Compute new position — same logic as reposition_sticky_cells
        # Ruler offsets shift all data cells right/down within the sticky layers
        ruler_x_offset = ruler_col_width_pixels
        ruler_y_offset = ruler_row_height_pixels
        true_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
        true_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)

        if !is_sticky_col
          # Non-compound path only (compound rejected by guard)
          # Guard: has_key? ensures shifted-out cols (in creation buffer but not viewport)
          # use the scroll-subtraction path instead of direct screen-space positioning.
          if @viewport_col_positions.has_key?(col) && col < @viewport_col_shifting_index
            new_x = ruler_x_offset + @viewport_col_positions[col].to_f64
          else
            content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
            new_x = ruler_x_offset + content_x - @scroll_offset.x.to_i.to_f64
          end
        else
          new_x = true_x
        end

        if !is_sticky_row
          # Non-compound path only (compound rejected by guard)
          # Guard: has_key? ensures shifted-out rows (in creation buffer but not viewport)
          # use the scroll-subtraction path instead of direct screen-space positioning.
          if @viewport_row_positions.has_key?(row) && row < @viewport_row_shifting_index
            new_y = ruler_y_offset + @viewport_row_positions[row].to_f64
          else
            content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
            new_y = ruler_y_offset + content_y - @scroll_offset.y.to_i.to_f64
          end
        else
          new_y = true_y
        end

        # Determine which layer and compute layer-local blit position
        if is_sticky_row && is_sticky_col
          layer = sticky_corner_layer
          target = corner_entries
        elsif is_sticky_row
          layer = sticky_row_layer
          target = row_entries
        else
          layer = sticky_col_layer
          target = col_entries
        end

        next unless layer

        # Update widget bounds position (for hit-testing and test assertions)
        # without calling layout() (which would re-render)
        if widget.bounds.x != new_x || widget.bounds.y != new_y
          widget.bounds = Rect.new(new_x, new_y, widget.bounds.width, widget.bounds.height)
        end

        dest_x = (vm_abs.x + new_x - layer.bounds.x).to_i
        dest_y = (vm_abs.y + new_y - layer.bounds.y).to_i

        target << BlitEntry.new(wb, dest_x, dest_y)
      end

      # Set blit plans on layers (triggers fast path in render_layer)
      if sticky_row_layer && row_entries.any?
        sticky_row_layer.blit_plan = row_entries
        sticky_row_layer.mark_needs_full_render
      end
      if sticky_col_layer && col_entries.any?
        sticky_col_layer.blit_plan = col_entries
        sticky_col_layer.mark_needs_full_render
      end
      if sticky_corner_layer && corner_entries.any?
        sticky_corner_layer.blit_plan = corner_entries
        sticky_corner_layer.mark_needs_full_render
      end
    end
  end
end
