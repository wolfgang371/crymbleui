require "../core/widget"
require "../core/types"
require "../core/recursive_grid_data"
require "../dsl/primitive_builder"
require "./vstack"

module CrymbleUI
  # RecursiveGrid layout widget
  # Arranges children in a 2D grid with automatic cell spanning
  #
  # Cells can contain widgets OR nested RecursiveGrids.
  # Nested grids automatically cause sibling cells to span multiple rows/columns.
  #
  # ## Example
  #
  # ```crystal
  # recursive_grid([
  #   [button("A") { }, button("B") { }],
  #   [button("C") { }, recursive_grid([
  #     [button("D1") { }],
  #     [button("D2") { }]
  #   ])]
  # ])
  # # Result: A and C span 2 rows because nested grid has 2 rows
  # # [A, B ]
  # # [A, D1]
  # # [C, D2]
  # ```
  class RecursiveGrid < Widget
    include PrimitiveBuilder

    # Spacing between cells
    layout_property spacing : Float64 = 0.0

    # Border width in pixels
    BORDER_WIDTH = 2.0

    # The underlying grid data structure
    @grid : RecursiveGridData::Grid(Widget)

    # Border color (nil = no border)
    @border_color : Color?

    # Cell background color (nil = no auto-wrap)
    # When set, non-RecursiveGrid cells are wrapped in VStack with this background
    @cell_background_color : Color?

    # Cached row heights and column widths (computed during measure)
    @row_heights : Array(Float64) = [] of Float64
    @col_widths : Array(Float64) = [] of Float64

    # Track nested RecursiveGrid widgets (maps inner_grid -> widget)
    # This allows us to preserve the widget for rendering while using its grid data for spanning
    @nested_widgets : Hash(RecursiveGridData::Grid(Widget), RecursiveGrid)

    # Border color getter
    def border_color : Color?
      @border_color
    end

    # Border color setter
    def border_color=(color : Color?)
      @border_color = color
      mark_needs_layout  # Border affects layout (padding)
      mark_needs_render
    end

    # Cell background color getter
    def cell_background_color : Color?
      @cell_background_color
    end

    # Cell background color setter
    def cell_background_color=(color : Color?)
      @cell_background_color = color
      mark_needs_render
    end

    # Border padding (border line + visual padding inside)
    # Extra padding creates visible gap between border and content
    private def border_padding : Float64
      @border_color ? BORDER_WIDTH + 4.0 : 0.0
    end

    def initialize(
      content : Array(Array(Widget)) = [] of Array(Widget),
      id : String? = nil,
      @spacing : Float64 = 0.0,
      @cell_background_color : Color? = nil
    )
      super(id: id)
      @border_color = nil
      @nested_widgets = {} of RecursiveGridData::Grid(Widget) => RecursiveGrid

      # Convert content, extracting inner grids from nested RecursiveGrid widgets
      # This allows proper spanning when RecursiveGrids are nested
      # We also track the widget so we can preserve it for rendering (borders, etc.)
      # If cell_background_color is set, wrap non-RecursiveGrid cells in VStack
      converted_content = content.map do |row|
        row.map do |cell|
          if cell.is_a?(RecursiveGrid)
            # Extract the inner grid for proper nesting/spanning
            inner = cell.inner_grid
            @nested_widgets[inner] = cell  # Remember the widget!
            inner.as(Widget | RecursiveGridData::Grid(Widget))
          elsif bg = @cell_background_color
            # Wrap in VStack with background color for proper span visualization.
            # VStack is used here, but HStack would work equally well for a single-child
            # wrapper - both position the child at (0,0) and fill bounds with background.
            wrapper = VStack.new(background_color: bg)
            wrapper.add_child(cell)
            wrapper.as(Widget | RecursiveGridData::Grid(Widget))
          else
            cell.as(Widget | RecursiveGridData::Grid(Widget))
          end
        end
      end
      @grid = RecursiveGridData::Grid(Widget).new(converted_content)

      # Register direct leaf widgets as children (not those inside nested grids)
      @grid.elements do |widget, _bmin, _bmax, local_grid, _local_index|
        add_child(widget) if local_grid == @grid
      end

      # Register nested RecursiveGrid widgets as children (level 1 = direct children)
      @grid.grids do |level, grid, _bmin, _bmax|
        if level == 1 && @nested_widgets.has_key?(grid)
          add_child(@nested_widgets[grid])
        end
      end
    end

    # Access to inner grid (for nesting extraction)
    protected def inner_grid : RecursiveGridData::Grid(Widget)
      @grid
    end

    # Override label for path_id generation
    def label : String?
      "recursive_grid"
    end

    # Measure total size needed for grid
    def measure(constraints : BoxConstraints) : Size
      rows, cols = @grid.size
      padding = border_padding
      return Size.new(padding * 2, padding * 2) if rows == 0 || cols == 0

      # Initialize row heights and column widths
      @row_heights = Array.new(rows, 0.0)
      @col_widths = Array.new(cols, 0.0)

      child_constraints = BoxConstraints.loose(Size.new(
        constraints.max_width,
        constraints.max_height
      ))

      # Measure direct leaf widgets (not inside nested grids)
      @grid.elements do |widget, bmin, bmax, local_grid, _local_index|
        next unless local_grid == @grid  # Only direct children
        measure_child_with_span(widget, bmin, bmax, child_constraints)
      end

      # Measure nested RecursiveGrid widgets
      @grid.grids do |level, grid, bmin, bmax|
        next unless level == 1 && @nested_widgets.has_key?(grid)
        widget = @nested_widgets[grid]
        measure_child_with_span(widget, bmin, bmax, child_constraints)
      end

      # Calculate total size with spacing and border padding
      total_width = @col_widths.sum + @spacing * (cols - 1).clamp(0, Int32::MAX) + padding * 2
      total_height = @row_heights.sum + @spacing * (rows - 1).clamp(0, Int32::MAX) + padding * 2

      constraints.constrain(Size.new(total_width, total_height))
    end

    # Helper to measure a child and distribute its size across spanned cells
    private def measure_child_with_span(widget : Widget, bmin : RecursiveGridData::Index, bmax : RecursiveGridData::Index, constraints : BoxConstraints)
      r1, c1 = bmin
      r2, c2 = bmax

      child_size = widget.measure(constraints)

      # Calculate number of spanned rows/cols
      row_span = r2 - r1 + 1
      col_span = c2 - c1 + 1

      # Distribute width across spanned columns
      width_per_col = child_size.width / col_span
      (c1..c2).each do |c|
        @col_widths[c] = Math.max(@col_widths[c], width_per_col)
      end

      # Distribute height across spanned rows
      height_per_row = child_size.height / row_span
      (r1..r2).each do |r|
        @row_heights[r] = Math.max(@row_heights[r], height_per_row)
      end
    end

    # Layout children in grid positions
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      rows, cols = @grid.size
      return if rows == 0 || cols == 0

      padding = border_padding

      # Calculate natural size (before constraint clamping)
      natural_width = @col_widths.sum + @spacing * (cols - 1).clamp(0, Int32::MAX) + padding * 2
      natural_height = @row_heights.sum + @spacing * (rows - 1).clamp(0, Int32::MAX) + padding * 2

      # Scale row/col sizes when allocated space exceeds natural size
      if size.width > natural_width && natural_width > padding * 2
        content_width = natural_width - padding * 2
        available_width = size.width - padding * 2 - @spacing * (cols - 1).clamp(0, Int32::MAX)
        natural_col_sum = @col_widths.sum
        if natural_col_sum > 0
          scale_x = available_width / natural_col_sum
          @col_widths = @col_widths.map { |w| w * scale_x }
        end
      end
      if size.height > natural_height && natural_height > padding * 2
        content_height = natural_height - padding * 2
        available_height = size.height - padding * 2 - @spacing * (rows - 1).clamp(0, Int32::MAX)
        natural_row_sum = @row_heights.sum
        if natural_row_sum > 0
          scale_y = available_height / natural_row_sum
          @row_heights = @row_heights.map { |h| h * scale_y }
        end
      end

      # Compute cumulative row/column offsets (prefix sums with spacing)
      row_offsets = compute_offsets(@row_heights)
      col_offsets = compute_offsets(@col_widths)

      # Layout direct leaf widgets (not inside nested grids)
      @grid.elements do |widget, bmin, bmax, local_grid, _local_index|
        next unless local_grid == @grid  # Only direct children
        layout_child_with_span(widget, bmin, bmax, row_offsets, col_offsets, rows, cols, padding)
      end

      # Layout nested RecursiveGrid widgets
      @grid.grids do |level, grid, bmin, bmax|
        next unless level == 1 && @nested_widgets.has_key?(grid)
        widget = @nested_widgets[grid]
        layout_child_with_span(widget, bmin, bmax, row_offsets, col_offsets, rows, cols, padding)
      end
    end

    # Helper to layout a child at its spanned position
    private def layout_child_with_span(widget : Widget, bmin : RecursiveGridData::Index, bmax : RecursiveGridData::Index,
                                       row_offsets : Array(Float64), col_offsets : Array(Float64),
                                       rows : Int32, cols : Int32, padding : Float64)
      r1, c1 = bmin
      r2, c2 = bmax

      # Calculate position from offsets (add border padding)
      x = col_offsets[c1] + padding
      y = row_offsets[r1] + padding

      # Calculate size from span (including spacing within span)
      width = col_offsets[c2 + 1] - col_offsets[c1] - (c2 < cols - 1 ? @spacing : 0.0)
      height = row_offsets[r2 + 1] - row_offsets[r1] - (r2 < rows - 1 ? @spacing : 0.0)

      # Layout widget with tight constraints at calculated position
      child_constraints = BoxConstraints.tight(Size.new(width, height))
      widget.layout(child_constraints, Vec2.new(x, y))
    end

    # Draw border as 4 filled rectangles (avoids clipping issues with draw_rect outline)
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      if color = @border_color
        primitives do
          w = BORDER_WIDTH
          # Top edge
          fill_rect(Rect.new(0.0, 0.0, bounds.width, w), color)
          # Bottom edge
          fill_rect(Rect.new(0.0, bounds.height - w, bounds.width, w), color)
          # Left edge (between top and bottom)
          fill_rect(Rect.new(0.0, w, w, bounds.height - 2*w), color)
          # Right edge (between top and bottom)
          fill_rect(Rect.new(bounds.width - w, w, w, bounds.height - 2*w), color)
        end
      else
        [] of DrawPrimitive
      end
    end

    # Compute cumulative offsets from sizes (prefix sum with spacing)
    # Spacing is only added between cells, not after the last cell
    private def compute_offsets(sizes : Array(Float64)) : Array(Float64)
      offsets = [0.0]
      sizes.each_with_index do |size, i|
        spacing_after = (i < sizes.size - 1) ? @spacing : 0.0
        offsets << offsets.last + size + spacing_after
      end
      offsets
    end

  end
end
