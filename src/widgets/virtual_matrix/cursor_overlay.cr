module CrymbleUI
  class VirtualMatrix < Widget
    # === CURSOR OVERLAY WIDGET ===

    # Renders cursor row/col highlight bands on the overlay layer.
    # Reads cursor_rc, scroll_offset, and cached sizes from the parent matrix
    # at render time, so cursor movement only requires marking this widget dirty.
    private class CursorOverlayWidget < Widget
      include PrimitiveBuilder

      property matrix : VirtualMatrix
      property flash_on : Bool = true

      def initialize(@matrix : VirtualMatrix)
        super(id: "#{matrix.id}_cursor_overlay")
      end

      def cache_policy : CachePolicy
        CachePolicy::Never
      end

      def measure(constraints : BoxConstraints) : Size
        width = constraints.max_width.finite? ? constraints.max_width : 100.0
        height = constraints.max_height.finite? ? constraints.max_height : 100.0
        Size.new(width, height)
      end

      def perform_layout(constraints : BoxConstraints, position : Vec2)
        size = measure(constraints)
        @bounds = Rect.new(position, size)
      end

      def to_primitives(bounds : Rect) : Array(DrawPrimitive)
        cursor_row, cursor_col = @matrix.cursor_rc
        col_sizes = @matrix.@cached_col_sizes
        row_sizes = @matrix.@cached_row_sizes
        scroll = @matrix.scroll_offset

        return [] of DrawPrimitive unless col_sizes && row_sizes

        is_sticky_row = cursor_row < @matrix.sticky_row_count
        is_sticky_col = cursor_col < @matrix.sticky_col_count

        # Compute cursor position in content space (linear sum of sizes)
        # Add ruler offsets since all cells are shifted by ruler space
        ruler_x = @matrix.ruler_col_width_pixels
        ruler_y = @matrix.ruler_row_height_pixels
        cursor_y = ruler_y + (0...cursor_row).sum { |r| row_sizes[r] }.to_f64
        cursor_x = ruler_x + (0...cursor_col).sum { |c| col_sizes[c] }.to_f64

        # Sticky rows/cols are at fixed viewport positions (no scroll subtraction).
        # Content rows/cols need scroll adjustment.
        band_y = is_sticky_row ? cursor_y : cursor_y - scroll.y
        band_x = is_sticky_col ? cursor_x : cursor_x - scroll.x

        # Band dimensions
        row_h = cursor_row < row_sizes.size ? row_sizes[cursor_row].to_f64 : 0.0
        col_w = cursor_col < col_sizes.size ? col_sizes[cursor_col].to_f64 : 0.0

        delta = @matrix.cursor_highlight_delta.abs.clamp(0, 255)
        band_delta = (delta * 1.5).to_i.clamp(0, 255)
        flash_delta = (delta * 2.5).to_i.clamp(0, 255)
        band_base = Theme.current.grid_cursor_band
        flash_base = Theme.current.grid_cursor_flash
        band_color = Color.new(band_base.r, band_base.g, band_base.b, band_delta.to_u8)
        cell_flash_color = Color.new(flash_base.r, flash_base.g, flash_base.b, flash_delta.to_u8)

        # Sticky region dimensions for clipping (includes ruler space)
        sticky_h = @matrix.sticky_row_height_pixels + @matrix.ruler_row_height_pixels
        sticky_w = @matrix.sticky_col_width_pixels + @matrix.ruler_col_width_pixels

        # Check visibility of each band independently (don't kill both when one is off-screen)
        row_visible = is_sticky_row || (band_y + row_h > sticky_h && band_y < bounds.height)
        col_visible = is_sticky_col || (band_x + col_w > sticky_w && band_x < bounds.width)

        return [] of DrawPrimitive unless row_visible || col_visible

        # Clamp band positions to sticky boundary (don't draw behind sticky area)
        effective_band_y = is_sticky_row ? band_y : {band_y, sticky_h}.max
        effective_band_x = is_sticky_col ? band_x : {band_x, sticky_w}.max
        effective_row_h = row_h - (effective_band_y - band_y)
        effective_col_w = col_w - (effective_band_x - band_x)

        # Clamp bands to actual data extent (prevents visible darkening beyond last row/col
        # since subtractive blending on the content background creates gray stripes).
        # Use actual layer bounds (not widget bounds) for robustness during resize transitions.
        overlay_h = @matrix.cursor_overlay_layer.try(&.bounds.height) || bounds.height
        overlay_w = @matrix.cursor_overlay_layer.try(&.bounds.width) || bounds.width
        total_data_h = ruler_y + row_sizes.sum(&.to_f64) - scroll.y
        total_data_w = ruler_x + col_sizes.sum(&.to_f64) - scroll.x
        data_bottom = {total_data_h, overlay_h}.min
        data_right = {total_data_w, overlay_w}.min

        # Col band: extends into sticky row area to highlight column header,
        # UNLESS cursor is on a sticky col (avoid header-highlighting-header).
        col_band_y = is_sticky_col ? sticky_h : 0.0
        col_band_h = {data_bottom - col_band_y, 0.0}.max

        # Row band: extends into sticky col area to highlight row label,
        # UNLESS cursor is on a sticky row (avoid header-highlighting-header).
        row_band_x = is_sticky_row ? sticky_w : 0.0
        row_band_w = {data_right - row_band_x, 0.0}.max

        # Drag highlight color (reddish, matching ImGui's CellDragDropColor)
        drag_color = Color.new(204_u8, 102_u8, 102_u8, 128_u8)

        primitives do
          if row_visible
            fill_rect(Rect.new(row_band_x, effective_band_y, row_band_w, effective_row_h), band_color)
          end
          if col_visible
            fill_rect(Rect.new(effective_band_x, col_band_y, effective_col_w, col_band_h), band_color)
          end
          if row_visible && col_visible && @flash_on
            fill_rect(Rect.new(effective_band_x, effective_band_y, effective_col_w, effective_row_h), cell_flash_color)
          end

          # Drag source/target highlights (bounding box regions)
          {@matrix.@drag_source_cell, @matrix.@drag_target_cell}.each do |drag_cell|
            next unless drag_cell
            if adapter = @matrix.adapter
              bb = adapter.cell_get_drag_bounding_box(drag_cell[0], drag_cell[1])
              min_r, min_c = bb[0]
              max_r, max_c = bb[1]
              bb_y = ruler_y + (0...min_r).sum { |r| row_sizes[r] }.to_f64 - scroll.y
              bb_x = ruler_x + (0...min_c).sum { |c| col_sizes[c] }.to_f64 - scroll.x
              bb_h = (min_r..max_r).sum { |r| row_sizes[r] }.to_f64
              bb_w = (min_c..max_c).sum { |c| col_sizes[c] }.to_f64
              fill_rect(Rect.new(bb_x, bb_y, bb_w, bb_h), drag_color)
            end
          end

          # Change animation: white borders on cells with active highlights (skip when idle)
          if (adapter = @matrix.adapter) && adapter.has_active_highlights?
            @matrix.@visible_rows.each do |r|
              @matrix.@visible_cols.each do |c|
                alpha = adapter.cell_highlight_alpha(r, c)
                next if alpha == 0
                cell_y = ruler_y + (0...r).sum { |ri| row_sizes[ri] }.to_f64 - scroll.y
                cell_x = ruler_x + (0...c).sum { |ci| col_sizes[ci] }.to_f64 - scroll.x
                cell_h = r < row_sizes.size ? row_sizes[r].to_f64 : 0.0
                cell_w = c < col_sizes.size ? col_sizes[c].to_f64 : 0.0
                glow_color = Color.new(255_u8, 255_u8, 255_u8, (alpha // 2).to_u8)
                fill_rect(Rect.new(cell_x, cell_y, cell_w, cell_h), glow_color)
              end
            end
          end
        end
      end
    end
  end
end
