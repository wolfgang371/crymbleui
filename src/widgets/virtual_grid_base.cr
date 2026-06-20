require "../core/widget"
require "../core/types"
require "../core/layer"
require "./virtual_matrix/sticky_math"

module CrymbleUI
  # VirtualGridBase: A module providing generic virtual grid scrolling behavior.
  #
  # Features:
  # - Sparse cell storage (only visible cells exist as widgets)
  # - Cell lifecycle with hysteresis buffers (creation/destruction zones)
  # - Multi-layer cell assignment for sticky headers
  # - Scroll position tracking
  #
  # Host classes (VirtualMatrix) implement abstract methods for:
  # - Grid dimensions and cell sizing
  # - Cell widget creation
  # - Merged cell support
  # - Sticky row/col configuration
  #
  module VirtualGridBase
    # ==================== Abstract Methods ====================
    # Host class must implement these

    # Grid dimensions
    abstract def grid_rows : Int32
    abstract def grid_cols : Int32

    # Cell sizing (in pixels)
    abstract def cell_width_pixels(col : Int32) : Float64
    abstract def cell_height_pixels(row : Int32) : Float64

    # Cell creation (returns nil for empty cells)
    abstract def create_cell_widget(row : Int32, col : Int32) : Widget?

    # ==================== Optional Overrides ====================
    # Host class can override for specialized behavior

    # Number of sticky rows/columns
    def vgb_sticky_row_count : Int32
      0
    end

    def vgb_sticky_col_count : Int32
      0
    end

    # Check if cell is the "handle" (top-left of merged region)
    def vgb_is_handle_cell?(row : Int32, col : Int32) : Bool
      true
    end

    # Get bounding box for merged cells
    # Returns { {min_row, min_col}, {max_row, max_col} }
    def vgb_cell_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
      { {row, col}, {row, col} }
    end

    # Get scroll order for rows/columns (for sticky behavior)
    def vgb_row_scroll_order : Array(Int32)
      (0...grid_rows).to_a
    end

    def vgb_col_scroll_order : Array(Int32)
      (0...grid_cols).to_a
    end

    # ==================== Cell Storage ====================

    # Initialize cell storage - call in host's initialize
    def vgb_init_cells
      @vgb_active_cells = {} of Tuple(Int32, Int32) => Widget
      @vgb_visible_rows = [] of Int32
      @vgb_visible_cols = [] of Int32
      @vgb_last_visible_key = nil
      @vgb_force_cell_update = false
      @vgb_last_update_scroll_offset = Vec2.new(-1000.0, -1000.0)
    end

    # Access active cells
    def vgb_active_cells : Hash(Tuple(Int32, Int32), Widget)
      @vgb_active_cells ||= {} of Tuple(Int32, Int32) => Widget
    end

    def vgb_visible_rows : Array(Int32)
      @vgb_visible_rows ||= [] of Int32
    end

    def vgb_visible_cols : Array(Int32)
      @vgb_visible_cols ||= [] of Int32
    end

    def vgb_active_cell_count : Int32
      vgb_active_cells.size
    end

    def vgb_force_cell_update!
      @vgb_force_cell_update = true
    end

    # ==================== Instrumentation ====================

    @@vgb_update_visible_cells_call_count : Int32 = 0

    def self.update_visible_cells_call_count : Int32
      @@vgb_update_visible_cells_call_count
    end

    def self.reset_update_visible_cells_counter
      @@vgb_update_visible_cells_call_count = 0
    end

    # ==================== Core Cell Update Logic ====================

    # Update visible cells based on scroll position and viewport
    #
    # Parameters:
    # - viewport_width/height: Size of visible area in pixels
    # - scroll_offset: Current scroll position (Vec2)
    # - content_layer: Main content layer for non-sticky cells
    # - sticky_row_layer: Layer for header row cells (optional)
    # - sticky_col_layer: Layer for header column cells (optional)
    # - sticky_corner_layer: Layer for corner cells (optional)
    # - host_widget: The widget that will be parent of cells
    #
    # Returns true if cells were created/destroyed
    def vgb_update_visible_cells(
      viewport_width : Float64,
      viewport_height : Float64,
      scroll_offset : Vec2,
      content_layer : Layer?,
      sticky_row_layer : Layer? = nil,
      sticky_col_layer : Layer? = nil,
      sticky_corner_layer : Layer? = nil,
      host_widget : Widget? = nil
    ) : Bool
      # Initialize if needed
      @vgb_active_cells ||= {} of Tuple(Int32, Int32) => Widget
      @vgb_visible_rows ||= [] of Int32
      @vgb_visible_cols ||= [] of Int32
      @vgb_last_visible_key ||= nil
      @vgb_force_cell_update ||= false
      @vgb_last_update_scroll_offset ||= Vec2.new(-1000.0, -1000.0)

      # === EARLY EXIT CHECK ===
      # Skip full recompute if scroll hasn't moved beyond threshold
      creation_buffer = 50.0
      scroll_threshold = creation_buffer
      scroll_delta_x = (scroll_offset.x - @vgb_last_update_scroll_offset.x).abs
      scroll_delta_y = (scroll_offset.y - @vgb_last_update_scroll_offset.y).abs

      if !@vgb_force_cell_update && scroll_delta_x < scroll_threshold && scroll_delta_y < scroll_threshold
        @vgb_last_update_scroll_offset = scroll_offset
        return false
      end

      # Build size arrays
      col_sizes = (0...grid_cols).map { |c| cell_width_pixels(c).to_i32 }
      row_sizes = (0...grid_rows).map { |r| cell_height_pixels(r).to_i32 }

      # Get scroll order
      col_scroll_order = vgb_col_scroll_order
      row_scroll_order = vgb_row_scroll_order

      # Use sticky algorithm to compute visible indices
      min_x = scroll_offset.x.floor.to_i32
      max_x = (scroll_offset.x + viewport_width).ceil.to_i32
      min_y = scroll_offset.y.floor.to_i32
      max_y = (scroll_offset.y + viewport_height).ceil.to_i32

      _, col_positions, _, visible_cols, _ = Widgets::VirtualMatrix::StickyMath.sticky(col_sizes, col_scroll_order, min_x, max_x)
      _, row_positions, _, visible_rows, _ = Widgets::VirtualMatrix::StickyMath.sticky(row_sizes, row_scroll_order, min_y, max_y)

      @vgb_visible_rows = visible_rows
      @vgb_visible_cols = visible_cols

      # Extended bounds for creation/destruction
      creation_buffer_ext = 75.0
      destruction_buffer = 125.0

      creation_min_x = (scroll_offset.x - creation_buffer_ext).floor.to_i32.clamp(0, Int32::MAX)
      creation_max_x = (scroll_offset.x + viewport_width + creation_buffer_ext).ceil.to_i32
      creation_min_y = (scroll_offset.y - creation_buffer_ext).floor.to_i32.clamp(0, Int32::MAX)
      creation_max_y = (scroll_offset.y + viewport_height + creation_buffer_ext).ceil.to_i32

      _, _, _, creation_cols, _ = Widgets::VirtualMatrix::StickyMath.sticky(col_sizes, col_scroll_order, creation_min_x, creation_max_x)
      _, _, _, creation_rows, _ = Widgets::VirtualMatrix::StickyMath.sticky(row_sizes, row_scroll_order, creation_min_y, creation_max_y)

      destruction_min_x = (scroll_offset.x - destruction_buffer).floor.to_i32.clamp(0, Int32::MAX)
      destruction_max_x = (scroll_offset.x + viewport_width + destruction_buffer).ceil.to_i32
      destruction_min_y = (scroll_offset.y - destruction_buffer).floor.to_i32.clamp(0, Int32::MAX)
      destruction_max_y = (scroll_offset.y + viewport_height + destruction_buffer).ceil.to_i32

      _, _, _, destruction_cols, _ = Widgets::VirtualMatrix::StickyMath.sticky(col_sizes, col_scroll_order, destruction_min_x, destruction_max_x)
      _, _, _, destruction_rows, _ = Widgets::VirtualMatrix::StickyMath.sticky(row_sizes, row_scroll_order, destruction_min_y, destruction_max_y)

      # Early-exit check
      visible_key = {visible_rows, visible_cols}
      exact_indices_changed = @vgb_last_visible_key != visible_key || @vgb_force_cell_update

      unless exact_indices_changed
        @vgb_last_update_scroll_offset = scroll_offset
        return false
      end

      @vgb_last_visible_key = visible_key
      @vgb_force_cell_update = false
      @vgb_last_update_scroll_offset = scroll_offset

      # Build cell sets
      creation_cells = Set(Tuple(Int32, Int32)).new
      creation_rows.each do |row|
        creation_cols.each do |col|
          creation_cells << {row, col}
        end
      end

      keep_alive_cells = Set(Tuple(Int32, Int32)).new
      destruction_rows.each do |row|
        destruction_cols.each do |col|
          keep_alive_cells << {row, col}
        end
      end

      # Filter to handle cells only
      handle_cells = Set(Tuple(Int32, Int32)).new
      creation_cells.each do |cell|
        row, col = cell
        bounding = vgb_cell_bounding_box(row, col)
        handle_row, handle_col = bounding[0]
        handle = {handle_row, handle_col}
        next if handle_cells.includes?(handle)

        min_row, min_col = bounding[0]
        max_row, max_col = bounding[1]
        rows_intersect = (min_row..max_row).any? { |r| creation_rows.includes?(r) }
        cols_intersect = (min_col..max_col).any? { |c| creation_cols.includes?(c) }

        if rows_intersect && cols_intersect
          handle_cells << handle
        end
      end

      keep_alive_handles = keep_alive_cells.select { |cell| vgb_is_handle_cell?(cell[0], cell[1]) }

      # Destroy cells outside destruction buffer
      cells_to_remove = vgb_active_cells.keys.reject { |key| keep_alive_handles.includes?(key) }
      cells_destroyed = cells_to_remove.size > 0

      cells_to_remove.each do |key|
        if widget = vgb_active_cells.delete(key)
          widget.parent = nil
          if hw = host_widget
            hw.children.delete(widget)
          end
        end
      end

      # Create new cells
      cells_created = false
      new_cells = [] of Widget
      sticky_row_count = vgb_sticky_row_count
      sticky_col_count = vgb_sticky_col_count

      handle_cells.each do |key|
        next if vgb_active_cells.has_key?(key)

        row, col = key
        widget = create_cell_widget(row, col)
        next unless widget

        cells_created = true
        widget.parent = host_widget
        if hw = host_widget
          hw.children << widget
        end
        vgb_active_cells[key] = widget
        new_cells << widget

        # Layout cell at fixed content-space position
        x = (0...col).sum { |c| col_sizes[c] }
        y = (0...row).sum { |r| row_sizes[r] }
        bounding = vgb_cell_bounding_box(row, col)
        cell_width = vgb_calculate_merged_width(bounding, col_sizes)
        cell_height = vgb_calculate_merged_height(bounding, row_sizes)
        # Apply spacing (hardcoded for now, should be configurable)
        spacing = 3
        cell_constraints = BoxConstraints.tight(Size.new(cell_width - spacing, cell_height - spacing))
        widget.layout(cell_constraints, Vec2.new(x.to_f64, y.to_f64))
      end

      # Assign cells to layers
      if cells_created || cells_destroyed
        # Clear all layer widget lists
        content_layer.try(&.widgets.clear)
        sticky_row_layer.try(&.widgets.clear)
        sticky_col_layer.try(&.widgets.clear)
        sticky_corner_layer.try(&.widgets.clear)

        # Assign each active cell to appropriate layer
        vgb_active_cells.each do |key, widget|
          row, col = key
          layer = vgb_get_cell_layer(row, col, sticky_row_count, sticky_col_count,
                                     content_layer, sticky_row_layer, sticky_col_layer, sticky_corner_layer)
          layer.try(&.widgets.<< widget)
        end

        # Mark new cells for render
        new_cells.each do |cell|
          row, col = vgb_active_cells.key_for(cell)
          layer = vgb_get_cell_layer(row, col, sticky_row_count, sticky_col_count,
                                     content_layer, sticky_row_layer, sticky_col_layer, sticky_corner_layer)
          layer.try(&.mark_needs_render(cell))
        end

        if new_cells.size > 0
          @@vgb_update_visible_cells_call_count += 1
        end
      end

      cells_created || cells_destroyed
    end

    # Determine which layer a cell belongs to based on sticky configuration
    private def vgb_get_cell_layer(
      row : Int32,
      col : Int32,
      sticky_row_count : Int32,
      sticky_col_count : Int32,
      content_layer : Layer?,
      sticky_row_layer : Layer?,
      sticky_col_layer : Layer?,
      sticky_corner_layer : Layer?
    ) : Layer?
      is_sticky_row = row < sticky_row_count
      is_sticky_col = col < sticky_col_count

      if is_sticky_row && is_sticky_col
        sticky_corner_layer || content_layer
      elsif is_sticky_row
        sticky_row_layer || content_layer
      elsif is_sticky_col
        sticky_col_layer || content_layer
      else
        content_layer
      end
    end

    # Calculate merged cell dimensions
    private def vgb_calculate_merged_width(bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)), col_sizes : Array(Int32)) : Float64
      min_col = bounding[0][1]
      max_col = bounding[1][1]
      (min_col..max_col).sum { |c| col_sizes[c]? || cell_width_pixels(c).to_i32 }.to_f64
    end

    private def vgb_calculate_merged_height(bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)), row_sizes : Array(Int32)) : Float64
      min_row = bounding[0][0]
      max_row = bounding[1][0]
      (min_row..max_row).sum { |r| row_sizes[r]? || cell_height_pixels(r).to_i32 }.to_f64
    end
  end
end
