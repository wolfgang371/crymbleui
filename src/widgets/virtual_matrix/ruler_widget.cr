module CrymbleUI
  class VirtualMatrix < Widget
    # Ruler dimension constants (in frame_height multiples).
    # Column ruler (top) is narrow (1.0) since labels are short ("c1","c2").
    # Row ruler (left) is wider (2.0) to fit longer row numbers.
    RULER_ROW_HEIGHT = 1.0  # Column ruler strip height (top)
    RULER_COL_WIDTH  = 2.0  # Row ruler strip width (left)

    # Ruler colors — evaluated at render time so runtime theme switches take effect.
    protected def self.ruler_bg_color
      Theme.current.ruler_background
    end

    protected def self.ruler_label_color
      Theme.current.ruler_label
    end

    protected def self.ruler_line_color
      Theme.current.ruler_line
    end

    # Shared base for all ruler widgets — provides boilerplate (cache policy, measure, layout).
    private abstract class RulerBaseWidget < Widget
      include PrimitiveBuilder

      property matrix : VirtualMatrix

      def initialize(@matrix : VirtualMatrix, id : String)
        super(id: id)
      end

      # Dynamic (was Never) so the primitives node AUTO-CAPTURES matrix.scroll_offset
      # (a Source, read in to_primitives) — a scroll then enqueues this ruler SELECTIVELY via the node's
      # on_dirty callback, instead of the old per-scroll-site mark_ruler_widgets_dirty. (Size changes
      # aren't Sources, so the resize path still marks explicitly — see mark_ruler_widgets_dirty.)
      def cache_policy : CachePolicy
        CachePolicy::Dynamic
      end

      def measure(constraints : BoxConstraints) : Size
        width = constraints.max_width.finite? ? constraints.max_width : 100.0
        height = constraints.max_height.finite? ? constraints.max_height : 100.0
        Size.new(width, height)
      end

      def perform_layout(constraints : BoxConstraints, position : Vec2)
        @bounds = Rect.new(position, measure(constraints))
      end

      # Render a sequence of labels along an axis with border lines.
      # axis=:col renders horizontally (labels "c1","c2",...), axis=:row renders vertically ("1","2",...).
      # acc_start: starting position, scroll: scroll offset to subtract, range: which indices to draw.
      protected def draw_labels(bounds : Rect, sizes : Array(Int32), range : Range(Int32, Int32),
                                axis : Symbol, acc_start : Float64, scroll : Float64 = 0.0)
        font_size = FontSizing.calculate_size(-2)

        range.each do |i|
          cell_size = sizes[i].to_f64
          screen_pos = acc_start - scroll

          # Skip off-screen elements
          if axis == :col
            unless screen_pos + cell_size < 0 || screen_pos > bounds.width
              label = "c#{i + 1}"
              text_dims = measure_text(label, font_size)
              text_x = screen_pos + (cell_size - text_dims.width) / 2.0
              text_y = (bounds.height - font_size) / 2.0
              draw_text(label, Vec2.new(text_x, text_y), VirtualMatrix.ruler_label_color, font_scale: -2)
              border_x = screen_pos + cell_size
              draw_line(Vec2.new(border_x, 0.0), Vec2.new(border_x, bounds.height), VirtualMatrix.ruler_line_color)
            end
          else # :row
            unless screen_pos + cell_size < 0 || screen_pos > bounds.height
              label = "#{i + 1}"
              text_dims = measure_text(label, font_size)
              text_x = (bounds.width - text_dims.width) / 2.0
              text_y = screen_pos + (cell_size - font_size) / 2.0
              draw_text(label, Vec2.new(text_x, text_y), VirtualMatrix.ruler_label_color, font_scale: -2)
              border_y = screen_pos + cell_size
              draw_line(Vec2.new(0.0, border_y), Vec2.new(bounds.width, border_y), VirtualMatrix.ruler_line_color)
            end
          end

          acc_start += cell_size
        end
      end
    end

    # === COLUMN RULER WIDGET ===
    # Renders non-sticky column labels ("c1","c2",...) in the top ruler strip.
    # Lives on sticky_row_layer (scrolls X with content, fixed Y).
    private class ColumnRulerWidget < RulerBaseWidget
      def initialize(matrix : VirtualMatrix)
        super(matrix, "#{matrix.id}_col_ruler")
      end

      def to_primitives(bounds : Rect) : Array(DrawPrimitive)
        col_sizes = @matrix.@cached_col_sizes
        return [] of DrawPrimitive unless col_sizes

        scroll_x = @matrix.scroll_offset.x
        sticky_cols = @matrix.sticky_col_count
        acc_x = @matrix.ruler_col_width_pixels + @matrix.sticky_col_width_pixels

        # Clamp ruler background to actual data extent (don't fill beyond last column)
        total_data_w = acc_x + (sticky_cols...col_sizes.size).sum { |i| col_sizes[i] } - scroll_x
        fill_w = {total_data_w, bounds.width}.min

        primitives do
          fill_rect(Rect.new(0.0, 0.0, fill_w, bounds.height), VirtualMatrix.ruler_bg_color)
          draw_line(Vec2.new(acc_x - scroll_x, 0.0), Vec2.new(acc_x - scroll_x, bounds.height), VirtualMatrix.ruler_line_color)
          draw_labels(bounds, col_sizes, sticky_cols...col_sizes.size, :col, acc_x, scroll_x)
        end
      end
    end

    # === ROW RULER WIDGET ===
    # Renders non-sticky row labels ("1","2",...) in the left ruler strip.
    # Lives on sticky_col_layer (scrolls Y with content, fixed X).
    private class RowRulerWidget < RulerBaseWidget
      def initialize(matrix : VirtualMatrix)
        super(matrix, "#{matrix.id}_row_ruler")
      end

      def to_primitives(bounds : Rect) : Array(DrawPrimitive)
        row_sizes = @matrix.@cached_row_sizes
        return [] of DrawPrimitive unless row_sizes

        scroll_y = @matrix.scroll_offset.y
        sticky_rows = @matrix.sticky_row_count
        acc_y = @matrix.ruler_row_height_pixels + @matrix.sticky_row_height_pixels

        # Clamp ruler background to actual data extent (don't fill beyond last row)
        total_data_h = acc_y + (sticky_rows...row_sizes.size).sum { |i| row_sizes[i] } - scroll_y
        fill_h = {total_data_h, bounds.height}.min

        primitives do
          fill_rect(Rect.new(0.0, 0.0, bounds.width, fill_h), VirtualMatrix.ruler_bg_color)
          draw_line(Vec2.new(0.0, acc_y - scroll_y), Vec2.new(bounds.width, acc_y - scroll_y), VirtualMatrix.ruler_line_color)
          draw_labels(bounds, row_sizes, sticky_rows...row_sizes.size, :row, acc_y, scroll_y)
        end
      end
    end

    # === CORNER RULER WIDGET ===
    # Fills the top-left corner and draws sticky column labels in the top strip.
    # Lives on sticky_corner_layer (no scroll).
    private class CornerRulerWidget < RulerBaseWidget
      def initialize(matrix : VirtualMatrix)
        super(matrix, "#{matrix.id}_corner_ruler")
      end

      def to_primitives(bounds : Rect) : Array(DrawPrimitive)
        col_sizes = @matrix.@cached_col_sizes
        ruler_w = @matrix.ruler_col_width_pixels
        sticky_cols = @matrix.sticky_col_count

        primitives do
          fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), VirtualMatrix.ruler_bg_color)
          if col_sizes
            draw_labels(bounds, col_sizes, 0...sticky_cols, :col, ruler_w)
          end
        end
      end
    end

    # === CORNER ROW STRIP WIDGET ===
    # Draws sticky row labels in the left strip of the corner layer.
    # Position: (0, ruler_h) on sticky_corner_layer.
    private class CornerRowStripWidget < RulerBaseWidget
      def initialize(matrix : VirtualMatrix)
        super(matrix, "#{matrix.id}_corner_row_strip")
      end

      def to_primitives(bounds : Rect) : Array(DrawPrimitive)
        row_sizes = @matrix.@cached_row_sizes
        sticky_rows = @matrix.sticky_row_count

        primitives do
          fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), VirtualMatrix.ruler_bg_color)
          if row_sizes
            draw_labels(bounds, row_sizes, 0...sticky_rows, :row, 0.0)
          end
        end
      end
    end
  end
end
