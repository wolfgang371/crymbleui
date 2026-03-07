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
        band_color = Color.new(255_u8, 255_u8, 255_u8, band_delta.to_u8)
        cell_flash_color = Color.new(255_u8, 255_u8, 255_u8, flash_delta.to_u8)

        # Sticky region dimensions for clipping (includes ruler space)
        sticky_h = @matrix.sticky_row_height_pixels + @matrix.ruler_row_height_pixels
        sticky_w = @matrix.sticky_col_width_pixels + @matrix.ruler_col_width_pixels

        # Non-sticky bands must be at least partially visible beyond sticky area
        unless is_sticky_row
          return [] of DrawPrimitive unless band_y + row_h > sticky_h && band_y < bounds.height
        end
        unless is_sticky_col
          return [] of DrawPrimitive unless band_x + col_w > sticky_w && band_x < bounds.width
        end

        # Clamp band positions to sticky boundary (don't draw behind sticky area)
        effective_band_y = is_sticky_row ? band_y : {band_y, sticky_h}.max
        effective_band_x = is_sticky_col ? band_x : {band_x, sticky_w}.max
        effective_row_h = row_h - (effective_band_y - band_y)
        effective_col_w = col_w - (effective_band_x - band_x)

        # Col band: extends into sticky row area to highlight column header,
        # UNLESS cursor is on a sticky col (avoid header-highlighting-header).
        # effective_band_x clamping prevents bleeding into sticky col area.
        col_band_y = is_sticky_col ? sticky_h : 0.0
        col_band_h = bounds.height - col_band_y

        # Row band: extends into sticky col area to highlight row label,
        # UNLESS cursor is on a sticky row (avoid header-highlighting-header).
        # effective_band_y clamping prevents bleeding into sticky row area.
        row_band_x = is_sticky_row ? sticky_w : 0.0
        row_band_w = bounds.width - row_band_x

        primitives do
          fill_rect(Rect.new(row_band_x, effective_band_y, row_band_w, effective_row_h), band_color)
          fill_rect(Rect.new(effective_band_x, col_band_y, effective_col_w, col_band_h), band_color)
          if @flash_on
            fill_rect(Rect.new(effective_band_x, effective_band_y, effective_col_w, effective_row_h), cell_flash_color)
          end
        end
      end
    end
  end
end
