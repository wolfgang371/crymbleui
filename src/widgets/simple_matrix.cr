require "./virtual_matrix"

module CrymbleUI
  # Sugar over VirtualMatrix for the common case of a small static tabular
  # view with optional header rows and sticky regions — without writing a
  # MatrixAdapter. Each cell is just a Widget supplied by the caller. The
  # adapter plumbing is hidden.
  #
  # Usage via the `matrix` DSL helper:
  # ```
  # matrix(max_height: 200.0, sticky_row_count: 1, id: "summary") do |m|
  #   m.header "Name", "Size", "Modified"
  #   rows.each do |entry|
  #     m.row do |r|
  #       r << text(entry.name)
  #       r << text(entry.size.to_s)
  #       r << text(entry.modified.to_s)
  #     end
  #   end
  # end
  # ```
  #
  # The first `sticky_row_count` rows (including a header row if declared
  # via `m.header`) are rendered on the matrix's sticky_row layer — they
  # stay visible while the body scrolls.
  #
  # If `sticky_col_count` > 0, the first N columns stay visible while the
  # body scrolls horizontally. Useful for row-labels.
  class SimpleMatrixAdapter
    include Widgets::VirtualMatrix::MatrixAdapter

    getter rows : Array(Array(Widget))
    getter sticky_row_count : Int32
    getter sticky_col_count : Int32
    getter header_row_count : Int32

    def initialize(
      @rows : Array(Array(Widget)),
      @sticky_row_count : Int32 = 0,
      @sticky_col_count : Int32 = 0,
      @header_row_count : Int32 = 0,
    )
    end

    private def row_count : Int32
      @rows.size
    end

    private def col_count : Int32
      @rows.first?.try(&.size) || 0
    end

    # Sticky rows / cols are a contiguous trailing set {0..K-1} of the
    # scroll_order. Put non-sticky indices first, then sticky at the tail.
    def get_scrollorder : {Array(Int32), Array(Int32)}
      r_total = row_count
      c_total = col_count
      r_order = if @sticky_row_count > 0 && @sticky_row_count <= r_total
                  (@sticky_row_count...r_total).to_a + (0...@sticky_row_count).to_a
                else
                  (0...r_total).to_a
                end
      c_order = if @sticky_col_count > 0 && @sticky_col_count <= c_total
                  (@sticky_col_count...c_total).to_a + (0...@sticky_col_count).to_a
                else
                  (0...c_total).to_a
                end
      {r_order, c_order}
    end

    def cell_paint(row : Int32, col : Int32) : Widget
      row_widgets = @rows[row]?
      return Text.new("") unless row_widgets
      row_widgets[col]? || Text.new("")
    end

    # Header rows: the first `@header_row_count` rows are header. VM renders
    # header cells with ruler styling (column-name visuals).
    def cell_get_header_info(row : Int32, col : Int32) : Tuple(Bool, Int32)?
      row < @header_row_count ? {true, 0} : nil
    end

    # Override get_sizes to derive row heights + column widths from the actual
    # cell widgets' measured sizes (+ small padding), rather than VM's default
    # 1.0 × frame_height rows / 5.0 × frame_height columns. Yields a
    # right-sized grid for content-bound small matrices without the caller
    # having to configure sizes manually.
    def get_sizes : {Array(Float64), Array(Float64)}
      return custom_sized_override if custom_row_heights && custom_col_widths
      r_total = @rows.size
      c_total = col_count
      return {[] of Float64, [] of Float64} if r_total == 0 || c_total == 0

      # Approximate the same frame_height VM uses (no public accessor):
      # VM's formula is FRAME_HEIGHT_BASE * FontSizing.zoom_factor.
      fh = VirtualMatrix::FRAME_HEIGHT_BASE * FontSizing.zoom_factor
      # Breathing room per cell. Horizontal needs generous buffer for
      # button borders + avoiding right-edge clipping by the vertical
      # scrollbar. Vertical can be tight — widgets measure their own text
      # heights accurately.
      col_pad_px = 16.0
      row_pad_px = 2.0

      col_widths_px = Array(Float64).new(c_total, 0.0)
      row_heights_px = Array(Float64).new(r_total, 0.0)

      loose = BoxConstraints.loose(Size.new(Float64::INFINITY, Float64::INFINITY))
      r_total.times do |ri|
        c_total.times do |ci|
          w = @rows[ri][ci]?
          next unless w
          sz = w.measure(loose)
          col_widths_px[ci] = {col_widths_px[ci], sz.width + col_pad_px}.max
          row_heights_px[ri] = {row_heights_px[ri], sz.height + row_pad_px}.max
        end
      end

      # VM expects sizes in multiples of frame_height — convert.
      rows = row_heights_px.map { |px| px / fh }
      cols = col_widths_px.map { |px| px / fh }
      {rows, cols}
    end

    private def custom_sized_override : {Array(Float64), Array(Float64)}
      {custom_row_heights.not_nil!, custom_col_widths.not_nil!}
    end
  end

  # Collector used inside the `matrix` DSL block. Keeps optional header row
  # plus a growable list of data rows. Each row is itself accumulated via a
  # nested block; a row-building context appends cells.
  class SimpleMatrixBuilder
    getter rows : Array(Array(Widget)) = [] of Array(Widget)
    getter header_count : Int32 = 0

    # Declare a header row. Strings become Text widgets with the theme's
    # ruler label colour. Call once; multiple header rows can be supported
    # later if needed.
    def header(*labels : String)
      @header_count += 1
      row = labels.map { |l| Text.new(l, color: Theme.ref(&.ruler_label)).as(Widget) }.to_a # live theme
      @rows << row
    end

    # Declare a data row. Widgets are appended by the block via RowContext.
    def row(&block : RowContext ->)
      ctx = RowContext.new
      block.call(ctx)
      @rows << ctx.widgets
    end

    # Row-building context. Appends cells in order.
    class RowContext
      getter widgets : Array(Widget) = [] of Widget

      def <<(widget : Widget) : self
        @widgets << widget
        self
      end

      # Convenience: text cell.
      def text(content : String)
        @widgets << Text.new(content).as(Widget)
      end
    end
  end
end
