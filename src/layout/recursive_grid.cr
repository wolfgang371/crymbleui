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
    @nested_widgets : Hash(RecursiveGridData::Grid(Widget), RecursiveGrid)

    # Structural flags (computed once in initialize, never change)
    @has_direct_leaves : Bool = false
    @level1_grids_with_leaves : Set(RecursiveGridData::Grid(Widget)) = Set(RecursiveGridData::Grid(Widget)).new

    # Parent-provided sizes for column alignment in nested grids
    protected setter parent_col_widths : Array(Float64)? = nil
    protected setter parent_row_heights : Array(Float64)? = nil

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
    # Protected so parent grids can account for it in column size calculations
    protected def border_padding : Float64
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

      # Recursively collect nested widgets from child RecursiveGrids so that
      # level-2+ grids are available for all-nested measurement. Without this,
      # the outer grid can't see sub-grids within level-1 grids.
      collect_queue = @nested_widgets.values.dup
      while child_rg = collect_queue.pop?
        child_rg.nested_widgets_map.each do |inner_grid, rg_widget|
          unless @nested_widgets.has_key?(inner_grid)
            @nested_widgets[inner_grid] = rg_widget
            collect_queue << rg_widget
          end
        end
      end

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

      # Cache structural properties for measure/layout
      @grid.elements do |_w, _bmin, _bmax, local_grid, _li|
        if local_grid == @grid
          @has_direct_leaves = true
          break
        end
      end
      unless @has_direct_leaves
        @grid.grids do |level, grid, _bmin, _bmax|
          next unless level == 1 && @nested_widgets.has_key?(grid)
          @grid.elements do |_w, _bmin2, _bmax2, lg, _li|
            if lg == grid
              @level1_grids_with_leaves.add(grid)
              break
            end
          end
        end
      end
    end

    # Access to inner grid (for nesting extraction)
    protected def inner_grid : RecursiveGridData::Grid(Widget)
      @grid
    end

    # Access to nested widgets map (for recursive collection in parent grids)
    protected def nested_widgets_map : Hash(RecursiveGridData::Grid(Widget), RecursiveGrid)
      @nested_widgets
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

      if @has_direct_leaves
        # Standard: measure direct leaves + nested grids as wholes
        @grid.elements do |widget, bmin, bmax, local_grid, _local_index|
          next unless local_grid == @grid
          measure_child_with_span(widget, bmin, bmax, child_constraints)
        end
        @grid.grids do |level, grid, bmin, bmax|
          next unless level == 1 && @nested_widgets.has_key?(grid)
          measure_child_with_span(@nested_widgets[grid], bmin, bmax, child_constraints)
        end
      else
        # All-nested: measure level-1 grid leaves individually for column alignment.
        # We must add the sub-grid's border_padding to each leaf's measured size so
        # that the outer @col_widths correctly accounts for the full cell width
        # (content + border on both sides). This ensures that when parent_col_widths
        # is passed back to sub-grids, compute_inner_col_widths can subtract the
        # border to give the correct content-only widths.

        # Pre-collect level-1 grid bounds for containment checks on deeper grids
        level1_bounds = Array({RecursiveGridData::Index, RecursiveGridData::Index, Float64}).new
        @grid.grids do |level, grid, bmin, bmax|
          next unless level == 1 && @level1_grids_with_leaves.includes?(grid)
          bp = @nested_widgets[grid]?.try(&.border_padding) || 0.0
          level1_bounds << {bmin, bmax, bp}
        end

        @grid.elements do |widget, bmin, bmax, local_grid, _local_index|
          next unless @level1_grids_with_leaves.includes?(local_grid)
          sub_bp = @nested_widgets[local_grid]?.try(&.border_padding) || 0.0
          measure_child_with_span_plus_border(widget, bmin, bmax, child_constraints, sub_bp)
        end
        # Measure sub-grids (level 2+) within level-1 grids that have leaves.
        # The leaf measurement above only sees direct elements; nested RecursiveGrid
        # widgets are invisible without this, causing under-allocation and overflow.
        @grid.grids do |level, grid, bmin, bmax|
          next unless level >= 2 && @nested_widgets.has_key?(grid)
          level1_bounds.each do |(l1_bmin, l1_bmax, bp)|
            if bmin[0] >= l1_bmin[0] && bmax[0] <= l1_bmax[0] &&
               bmin[1] >= l1_bmin[1] && bmax[1] <= l1_bmax[1]
              measure_child_with_span_plus_border(@nested_widgets[grid], bmin, bmax, child_constraints, bp)
              break
            end
          end
        end
        @grid.grids do |level, grid, bmin, bmax|
          next unless level == 1 && @nested_widgets.has_key?(grid)
          next if @level1_grids_with_leaves.includes?(grid)
          measure_child_with_span(@nested_widgets[grid], bmin, bmax, child_constraints)
        end
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

    # Like measure_child_with_span but adds border_padding to the measured size.
    # Used in the all-nested path so that outer @col_widths accounts for the
    # sub-grid's border (content size + 2*bp per dimension).
    private def measure_child_with_span_plus_border(widget : Widget, bmin : RecursiveGridData::Index, bmax : RecursiveGridData::Index, constraints : BoxConstraints, extra_border_padding : Float64)
      r1, c1 = bmin
      r2, c2 = bmax

      child_size = widget.measure(constraints)

      row_span = r2 - r1 + 1
      col_span = c2 - c1 + 1

      # Include the sub-grid's border_padding in the outer allocation so that
      # the outer @col_widths correctly reflects the full cell size (content + border)
      width_per_col = (child_size.width + extra_border_padding * 2) / col_span
      (c1..c2).each do |c|
        @col_widths[c] = Math.max(@col_widths[c], width_per_col)
      end

      height_per_row = (child_size.height + extra_border_padding * 2) / row_span
      (r1..r2).each do |r|
        @row_heights[r] = Math.max(@row_heights[r], height_per_row)
      end
    end

    # Layout children in grid positions
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      if pcw = @parent_col_widths
        # Parent-provided widths for column alignment — skip re-measuring and scaling
        @col_widths = pcw
        @row_heights = @parent_row_heights || @row_heights
        size = Size.new(constraints.max_width, constraints.max_height)
        @bounds = Rect.new(position, size)
        @parent_col_widths = nil
        @parent_row_heights = nil
      else
        size = measure(constraints)
        @bounds = Rect.new(position, size)
        scale_to_fill(size)
      end

      rows, cols = @grid.size
      return if rows == 0 || cols == 0

      padding = border_padding
      row_offsets = compute_offsets(@row_heights)
      col_offsets = compute_offsets(@col_widths)

      # Layout direct leaf widgets
      @grid.elements do |widget, bmin, bmax, local_grid, _local_index|
        next unless local_grid == @grid
        layout_child_with_span(widget, bmin, bmax, row_offsets, col_offsets, rows, cols, padding)
      end

      # Layout nested RecursiveGrid widgets
      @grid.grids do |level, grid, bmin, bmax|
        next unless level == 1 && @nested_widgets.has_key?(grid)
        widget = @nested_widgets[grid]

        # All-nested case: pass column widths for alignment
        if !@has_direct_leaves && @level1_grids_with_leaves.includes?(grid)
          widget.parent_col_widths = compute_inner_col_widths(grid, bmin, bmax)
          widget.parent_row_heights = compute_inner_row_heights(grid, bmin, bmax)
        end

        layout_child_with_span(widget, bmin, bmax, row_offsets, col_offsets, rows, cols, padding)
      end
    end

    # Scale col/row sizes proportionally to match allocated space.
    # Scales both UP (fill extra space) and DOWN (fit tight constraints).
    # Without downscaling, nested grids overflow their parent when the child's
    # natural size exceeds the allocated cell (accumulated border_padding at
    # deep nesting levels can exceed the available space).
    private def scale_to_fill(size : Size)
      rows, cols = @grid.size
      return if rows == 0 || cols == 0
      padding = border_padding
      natural_width = @col_widths.sum + @spacing * (cols - 1).clamp(0, Int32::MAX) + padding * 2
      natural_height = @row_heights.sum + @spacing * (rows - 1).clamp(0, Int32::MAX) + padding * 2

      if size.width != natural_width && natural_width > padding * 2
        available = (size.width - padding * 2 - @spacing * (cols - 1).clamp(0, Int32::MAX)).clamp(0.0, Float64::MAX)
        total = @col_widths.sum
        @col_widths = @col_widths.map { |w| w * available / total } if total > 0
      end
      if size.height != natural_height && natural_height > padding * 2
        available = (size.height - padding * 2 - @spacing * (rows - 1).clamp(0, Int32::MAX)).clamp(0.0, Float64::MAX)
        total = @row_heights.sum
        @row_heights = @row_heights.map { |h| h * available / total } if total > 0
      end
    end

    # Map outer virtual columns to inner grid columns.
    # Returns content widths (without the sub-grid's border_padding) so that
    # when used as parent_col_widths, the inner @col_widths represent exactly
    # the column sizes within the sub-grid's content area.
    private def compute_inner_col_widths(grid : RecursiveGridData::Grid(Widget),
                                          bmin : RecursiveGridData::Index,
                                          bmax : RecursiveGridData::Index) : Array(Float64)
      bp = @nested_widgets[grid]?.try(&.border_padding) || 0.0
      c1 = bmin[1]; c2 = bmax[1]
      inner_cols = grid.size[1]
      (0...inner_cols).map do |k|
        if k < inner_cols - 1
          @col_widths[c1 + k]
        else
          # Last col absorbs remaining outer cols + spacings, minus sub-grid border
          start = c1 + k
          (start..c2).sum { |c| @col_widths[c] } + @spacing * (c2 - start) - 2.0 * bp
        end
      end
    end

    # Map outer virtual rows to inner grid rows.
    # Returns content heights (without the sub-grid's border_padding).
    private def compute_inner_row_heights(grid : RecursiveGridData::Grid(Widget),
                                           bmin : RecursiveGridData::Index,
                                           bmax : RecursiveGridData::Index) : Array(Float64)
      bp = @nested_widgets[grid]?.try(&.border_padding) || 0.0
      r1 = bmin[0]; r2 = bmax[0]
      inner_rows = grid.size[0]
      (0...inner_rows).map do |k|
        if k < inner_rows - 1
          @row_heights[r1 + k]
        else
          # Last row absorbs remaining outer rows + spacings, minus sub-grid border
          start = r1 + k
          (start..r2).sum { |r| @row_heights[r] } + @spacing * (r2 - start) - 2.0 * bp
        end
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
