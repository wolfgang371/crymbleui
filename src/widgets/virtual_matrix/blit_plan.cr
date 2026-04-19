module CrymbleUI
  class VirtualMatrix < Widget
    # Check if sticky cells can use the blit-plan fast path.
    # Returns false on first frame or if any non-compound sticky cell lacks a cached texture.
    # Compound cells and rulers are handled via blit_plan_render_widgets (rendered after blits).
    private def sticky_cells_can_use_blit_plan? : Bool
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return false if sticky_rows == 0 && sticky_cols == 0

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return false unless col_sizes && row_sizes

      cells_with_backend = 0
      @active_cells.each do |key, widget|
        row, col = key
        next unless row < sticky_rows || col < sticky_cols

        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        if is_compound
          is_sticky_row = row < sticky_rows
          is_sticky_col = col < sticky_cols
          # Compound cells that resize on scroll are rendered via blit_plan_render_widgets.
          # They need widget_backend to be blitted when they only moved (not resized).
          if !is_sticky_col || !is_sticky_row
            cells_with_backend += 1 if widget.widget_backend
            next
          end
        end

        # Non-compound cells without widget_backend are freshly created (e.g.
        # bounds grew and a new sticky cell became visible). The fast path can
        # still run — those cells will be added to blit_plan_render_widgets and
        # rendered normally after the blits. So no "return false" here.
        # But if the cell already has a backend and needs a re-render, the cache
        # is stale — full render is required.
        return false if widget.widget_backend && widget.needs_render?
        cells_with_backend += 1 if widget.widget_backend
      end
      cells_with_backend > 0  # Need at least one cell with cached texture
    end

    # Compute blit plans for sticky layers.
    # Called AFTER reposition_sticky_cells (which handles compound cell sizing).
    # Non-compound sticky cells: blit cached widget_backend at current bounds position (O(blit)).
    # Compound cells + rulers: added to blit_plan_render_widgets for normal rendering.
    # This overrides the mark_needs_clear_and_render set by reposition_sticky_cells,
    # replacing full re-render with the much cheaper blit-plan fast path.
    private def compute_sticky_blit_plans
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      sv = @content_scroll_view
      return unless sv

      sticky_row_layer = sv.sticky_row_layer
      sticky_col_layer = sv.sticky_col_layer
      sticky_corner_layer = sv.sticky_corner_layer

      vm_abs = absolute_bounds

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return unless col_sizes && row_sizes
      col_cum = @cached_col_physical_cum
      row_cum = @cached_row_physical_cum
      ruler_x_offset = ruler_col_width_pixels
      ruler_y_offset = ruler_row_height_pixels

      row_entries = [] of BlitEntry
      col_entries = [] of BlitEntry
      corner_entries = [] of BlitEntry

      # Widgets needing normal rendering after blit-plan:
      # rulers (CachePolicy::Never) + compound cells that resize on scroll
      row_render = [] of Widget
      col_render = [] of Widget
      corner_render = [] of Widget

      # Add ruler widgets to render-after lists
      row_render << @col_ruler_widget.not_nil! if @col_ruler_widget && @show_rulers
      col_render << @row_ruler_widget.not_nil! if @row_ruler_widget && @show_rulers
      corner_render << @corner_ruler_widget.not_nil! if @corner_ruler_widget && @show_rulers
      corner_render << @corner_row_strip_widget.not_nil! if @corner_row_strip_widget && @show_rulers

      @active_cells.each do |key, widget|
        row, col = key
        is_sticky_row = row < sticky_rows
        is_sticky_col = col < sticky_cols
        next unless is_sticky_row || is_sticky_col

        wb = widget.widget_backend

        # Determine target layer
        if is_sticky_row && is_sticky_col
          layer = sticky_corner_layer
          target = corner_entries
          render_list = corner_render
        elsif is_sticky_row
          layer = sticky_row_layer
          target = row_entries
          render_list = row_render
        else
          layer = sticky_col_layer
          target = col_entries
          render_list = col_render
        end
        next unless layer

        # Check if compound cell needs full re-render or can be blitted
        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        if is_compound && (!is_sticky_col || !is_sticky_row)
          # Compound cell that may resize on scroll. Always reposition (sets correct
          # bounds including OFFSCREEN_PARK when off-screen). Then decide render vs blit.
          reposition_compound_in_blit_plan(widget, key, bounding,
            is_sticky_row, is_sticky_col,
            col_sizes, row_sizes, col_cum, row_cum,
            ruler_x_offset, ruler_y_offset)
          if wb && !widget.needs_render? && widget.has_valid_primitive_cache?
            # Compound cell only moved — blit cached texture
            dest_x = (vm_abs.x + widget.bounds.x - layer.bounds.x).to_i
            dest_y = (vm_abs.y + widget.bounds.y - layer.bounds.y).to_i
            target << BlitEntry.new(wb, dest_x, dest_y)
          else
            # Resized, needs render, or newly created (no wb) — render normally.
            # Without this, new compound cells appear blank until the next frame
            # (visible during scrollbar thumb drag where cell update is deferred).
            render_list << widget unless widget.bounds.x < -100.0  # Skip off-screen
          end
          next
        end

        # Non-compound: if no cached texture yet (newly created after bounds
        # grow), render it normally after the blit-plan runs. Otherwise, blit
        # the cached widget_backend at the (possibly updated) position.
        unless wb
          render_list << widget unless widget.bounds.x < -100.0
          next
        end
        # Compute new position and blit cached texture
        if !is_sticky_col
          if @viewport_col_positions.has_key?(col) && col < @viewport_col_shifting_index
            new_x = ruler_x_offset + @viewport_col_positions[col].to_f64
          else
            content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
            new_x = ruler_x_offset + content_x - @scroll_offset.x.to_i.to_f64
          end
        else
          new_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
        end

        if !is_sticky_row
          if @viewport_row_positions.has_key?(row) && row < @viewport_row_shifting_index
            new_y = ruler_y_offset + @viewport_row_positions[row].to_f64
          else
            content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
            new_y = ruler_y_offset + content_y - @scroll_offset.y.to_i.to_f64
          end
        else
          new_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
        end

        if widget.bounds.x != new_x || widget.bounds.y != new_y
          widget.bounds = Rect.new(new_x, new_y, widget.bounds.width, widget.bounds.height)
        end

        dest_x = (vm_abs.x + new_x - layer.bounds.x).to_i
        dest_y = (vm_abs.y + new_y - layer.bounds.y).to_i
        target << BlitEntry.new(wb, dest_x, dest_y)
      end

      # Set blit plans on layers (triggers fast path in render_layer).
      # The blit-plan path clears the buffer and blits data cells, then renders
      # remaining widgets (rulers + compound cells) normally.
      if sticky_row_layer && (row_entries.any? || row_render.any?)
        sticky_row_layer.blit_plan = row_entries
        sticky_row_layer.blit_plan_render_widgets = row_render if row_render.any?
        sticky_row_layer.mark_needs_full_render
      end
      if sticky_col_layer && (col_entries.any? || col_render.any?)
        sticky_col_layer.blit_plan = col_entries
        sticky_col_layer.blit_plan_render_widgets = col_render if col_render.any?
        sticky_col_layer.mark_needs_full_render
      end
      if sticky_corner_layer && (corner_entries.any? || corner_render.any?)
        sticky_corner_layer.blit_plan = corner_entries
        sticky_corner_layer.blit_plan_render_widgets = corner_render if corner_render.any?
        sticky_corner_layer.mark_needs_full_render
      end
    end

    # Reposition a single compound cell within the blit-plan path.
    # Same logic as reposition_sticky_cells but for one cell only.
    # Updates widget bounds and calls invalidate_primitive_cache if size changed.
    private def reposition_compound_in_blit_plan(
        widget : Widget, key : Tuple(Int32, Int32),
        bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)),
        is_sticky_row : Bool, is_sticky_col : Bool,
        col_sizes : Array(Int32), row_sizes : Array(Int32),
        col_cum : Array(Int32)?, row_cum : Array(Int32)?,
        ruler_x_offset : Float64, ruler_y_offset : Float64)
      row, col = key
      true_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
      true_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)

      compound_w = 0.0
      compound_h = 0.0
      new_x = true_x
      new_y = true_y

      if !is_sticky_col
        bb_c1 = bounding[0][1]
        bb_c2 = bounding[1][1]
        min_screen_x = Float64::MAX
        max_screen_x = -Float64::MAX
        sticky_col_w = sticky_col_width_pixels + ruler_col_width_pixels
        viewport_right = self.bounds.width
        visible_col_count = 0
        single_col_x = 0.0
        single_col_size = 0.0
        (bb_c1..bb_c2).each do |ci|
          next if ci >= col_sizes.size
          true_ci_x = ruler_x_offset + (col_cum ? col_cum[ci].to_f64 : (0...ci).sum { |c| col_sizes[c] }.to_f64)
          unclamped_scr_x = true_ci_x - @scroll_offset.x.to_i.to_f64
          col_right = unclamped_scr_x + col_sizes[ci].to_f64
          next if col_right <= sticky_col_w
          next if unclamped_scr_x >= viewport_right
          visible_col_count += 1
          single_col_x = unclamped_scr_x
          single_col_size = col_sizes[ci].to_f64
          scr_x = {unclamped_scr_x, sticky_col_w}.max
          capped_right = {col_right, viewport_right}.min
          min_screen_x = {min_screen_x, scr_x}.min
          max_screen_x = {max_screen_x, capped_right}.max
        end
        if min_screen_x < Float64::MAX
          if visible_col_count > 1
            new_x = min_screen_x
            compound_w = max_screen_x - min_screen_x
          else
            new_x = single_col_x
            compound_w = single_col_size
          end
        else
          new_x = OFFSCREEN_PARK
          compound_w = 0.0
        end
      end

      if !is_sticky_row
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
          next if ri >= row_sizes.size
          true_ri_y = ruler_y_offset + (row_cum ? row_cum[ri].to_f64 : (0...ri).sum { |r| row_sizes[r] }.to_f64)
          unclamped_scr_y = true_ri_y - @scroll_offset.y.to_i.to_f64
          row_bottom = unclamped_scr_y + row_sizes[ri].to_f64
          next if row_bottom <= sticky_row_h
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
            new_y = min_screen_y
            compound_h = max_screen_y - min_screen_y
          else
            new_y = single_row_y
            compound_h = single_row_size
          end
        else
          new_y = OFFSCREEN_PARK
          compound_h = 0.0
        end
      end

      new_w = is_sticky_col ? widget.bounds.width : (compound_w == 0.0 ? 0.0 : {compound_w - grid_spacing, 1.0}.max)
      new_h = is_sticky_row ? widget.bounds.height : (compound_h == 0.0 ? 0.0 : {compound_h - grid_spacing, 1.0}.max)

      if widget.bounds.x != new_x || widget.bounds.y != new_y || widget.bounds.width != new_w || widget.bounds.height != new_h
        size_changed = widget.bounds.width != new_w || widget.bounds.height != new_h
        cell_constraints = BoxConstraints.tight(Size.new(new_w, new_h))
        widget.layout(cell_constraints, Vec2.new(new_x, new_y))
        widget.invalidate_primitive_cache if size_changed
      end
    end
  end
end
