module CrymbleUI::Widgets::VirtualMatrix
  # Abstract interface for matrix data binding.
  # Implement this module to connect VirtualMatrix to your data source.
  #
  # Example:
  # ```
  # class MyDataAdapter
  #   include MatrixAdapter
  #
  #   def get_scrollorder : {Array(Int32), Array(Int32)}
  #     {(0...@data.size).to_a, (0...@headers.size).to_a}
  #   end
  #
  #   def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
  #     CrymbleUI::TextInput.new(value: @data[row][col])
  #   end
  #
  #   # ... implement other methods
  # end
  # ```
  module MatrixAdapter
    DEFAULT_ROW_HEIGHT   = 1.0_f64  # In multiples of frame_height
    DEFAULT_COLUMN_WIDTH = 5.0_f64  # In multiples of frame_height

    # Scroll order for rows and columns.
    # Returns {row_order, col_order} arrays.
    # Array sizes implicitly define row_count and col_count.
    # Controls both visibility lifetime AND sticky behavior:
    # - Elements early in the array scroll out first
    # - Elements at the tail that form a contiguous set {0,1,...,N-1}
    #   are treated as sticky (rendered on fixed-position layers)
    # Default: must be implemented by subclass
    abstract def get_scrollorder : {Array(Int32), Array(Int32)}

    # Create a widget for the given cell position.
    # Called by VirtualMatrix when a cell enters the visible region.
    abstract def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget

    # Called at the start of each render frame (for change animation buffer swap)
    def start_frame : Nil
    end

    # Read cell value (for change detection). Default: no-op, returns empty string.
    def cell_read(row : Int32, col : Int32) : String
      ""
    end

    # Custom sizes persisted by VirtualMatrix after drag resize.
    # When set, get_sizes returns these instead of defaults.
    property custom_row_heights : Array(Float64)? = nil
    property custom_col_widths : Array(Float64)? = nil

    # Initial row/col sizes (frame_height multiples). Called at init + invalidate_all!.
    # VirtualMatrix owns the mutable copy (drag resize modifies it directly).
    # Override to set custom sizes (e.g. wider header columns, taller header rows).
    def get_sizes : {Array(Float64), Array(Float64)}
      row_order, col_order = get_scrollorder
      rows = fit_custom_sizes(custom_row_heights, row_order.size, DEFAULT_ROW_HEIGHT)
      cols = fit_custom_sizes(custom_col_widths, col_order.size, DEFAULT_COLUMN_WIDTH)
      {rows, cols}
    end

    # Normalize a persisted custom-size array to EXACTLY `count` entries. The row/column structure
    # can change (commits added/removed, fields added) AFTER custom_row_heights/custom_col_widths
    # were persisted on a drag-resize, leaving them the wrong length. Returning a mismatched array
    # desyncs VirtualMatrix's @col_widths from @cols: the ruler iterates 0...@cols while the data
    # extent uses @col_widths, so they disagree (only the ruler scrolls), and get_col_width(col)
    # raises IndexError past the array end (seen in copy_state_from → max_content_scroll_x). Preserve
    # the existing prefix (per-column resize survives), pad new columns with the default, drop removed.
    private def fit_custom_sizes(custom : Array(Float64)?, count : Int32, default : Float64) : Array(Float64)
      return Array.new(count, default) unless custom
      return custom if custom.size == count
      Array.new(count) { |i| custom[i]? || default }
    end

    # Row operations (optional - default implementations do nothing)
    def insert_row(at : Int32) : Int32
      at
    end

    def delete_row(at : Int32)
    end

    # Assign a new string value to a cell (commit edit).
    # Returns the (possibly adjusted) cursor position after assignment.
    # Default: no-op, returns same position.
    def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
      {row, col}
    end

    # Check if cell has content (for cut/paste validation)
    def cell_has_content?(row : Int32, col : Int32) : Bool
      true
    end

    # Optional: Get bounding box for merged cells (used during painting)
    # Default: cell spans only itself
    def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
      { {row, col}, {row, col} }
    end

    # Bounding box for drag/cut operations (may span more cells than painting bounds)
    # Default: same as cell_get_bounding_box. Override for real record-level bounds.
    def cell_get_drag_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
      cell_get_bounding_box(row, col)
    end

    # Optional: Get header info for a cell
    # Returns nil for non-header cells
    # Returns {is_header_row, header_level} for header cells
    def cell_get_header_info(row : Int32, col : Int32) : Tuple(Bool, Int32)?
      nil
    end

    # Optional: Get cell name for tooltips/status bar
    def cell_get_name(row : Int32, col : Int32) : String
      "#{row},#{col}"
    end

    # Optional: Get highlight alpha for change animation (0 = no highlight, 1-255 = white border)
    # Override in adapters that track cell changes across frames
    def cell_highlight_alpha(row : Int32, col : Int32) : UInt8
      0_u8
    end

    # Whether any cells currently have active change highlights
    # Used to skip per-cell iteration in cursor overlay when no highlights exist
    def has_active_highlights? : Bool
      false
    end

    # Optional: Move cell content from one location to another
    # Returns the new cursor position after move
    def cell_move(from_row : Int32, from_col : Int32, to_row : Int32, to_col : Int32) : Tuple(Int32, Int32)
      {to_row, to_col}
    end

    # === Push-Based Invalidation ===
    # Callbacks set by VirtualMatrix during binding. Adapter authors call
    # invalidate_cell! / invalidate_all! to notify the matrix of changes.
    # Safe when unbound (nil procs = no-ops).

    @_on_invalidate_cell : Proc(Int32, Int32, Nil)?
    @_on_invalidate_all : Proc(Nil)?

    # Framework-internal: called by VirtualMatrix to wire up callbacks
    def _bind_invalidation(on_cell : Proc(Int32, Int32, Nil), on_all : Proc(Nil))
      @_on_invalidate_cell = on_cell
      @_on_invalidate_all = on_all
    end

    def _unbind_invalidation
      @_on_invalidate_cell = nil
      @_on_invalidate_all = nil
    end

    # Public API for adapter authors: signal that a single cell changed
    def invalidate_cell!(row : Int32, col : Int32)
      @_on_invalidate_cell.try &.call(row, col)
    end

    # Public API for adapter authors: signal that structure changed (dimensions, merges, etc.)
    def invalidate_all!
      @_on_invalidate_all.try &.call
    end
  end

  # Convenience module for adapters without sticky headers.
  # Provides a default sequential get_scrollorder derived from
  # row_count and col_count, so implementors only need:
  #
  # ```
  # class MySimpleAdapter
  #   include HeaderlessMatrixAdapter
  #
  #   def row_count : Int32
  #     @data.size
  #   end
  #
  #   def col_count : Int32
  #     @headers.size
  #   end
  #
  #   def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
  #     CrymbleUI::TextInput.new(value: @data[row][col])
  #   end
  # end
  # ```
  module HeaderlessMatrixAdapter
    include MatrixAdapter

    abstract def row_count : Int32
    abstract def col_count : Int32

    def get_scrollorder : {Array(Int32), Array(Int32)}
      {(0...row_count).to_a, (0...col_count).to_a}
    end
  end
end
