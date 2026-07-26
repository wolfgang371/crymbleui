require "../core/widget"
require "../core/types"
require "../core/layer"
require "../core/layer_owner"
require "../dsl/primitive_builder"
require "./virtual_matrix/sticky_math"
require "./virtual_matrix/blit_plan"
require "./virtual_matrix/cursor_overlay"
require "./virtual_matrix/ruler_widget"
require "./virtual_matrix/sticky_reposition"
require "./virtual_matrix/cursor"
require "./virtual_matrix/event_handlers"
require "./virtual_matrix/adapter"

module CrymbleUI
  # VirtualMatrix: A high-performance grid widget.
  #
  # Features:
  # - Virtual rendering (only visible cells exist as widgets)
  # - Adapter-based scroll_order for sticky behavior (headers are data cells styled via cell_paint)
  # - Compound/merged cells
  # - Cross-highlight cursor
  #
  # Architecture: Single content layer + ScrollView for scrollbars
  # - Content layer with viewport_cache for efficient scrolling
  # - ScrollView provides scrollbar chrome
  # - Sticky behavior via adapter's get_scrollorder
  #
  # KEY DESIGN INVARIANT: layout is expensive, render is cheap.
  # After initial layout, VirtualMatrix's size/position is constant. Scrolling and
  # cursor movement only change WHICH cells are visible — they must NEVER trigger
  # mark_needs_layout. Instead they should:
  #   1. Update scroll_offset via the canonical path (Source.set or self.scroll_offset=)
  #   2. Sync to ScrollView via set_scroll_offset_for_sync (NOT the setter)
  #   3. Update layer.scroll_offset for viewport_cache compositing
  #   4. Call update_visible_cells to refresh which cell widgets exist
  #   5. Call mark_needs_render (NOT mark_needs_layout)
  # See apply_scroll / on_mouse_wheel for the correct pattern.
  #
  # Drag data for cell drag-and-drop within VirtualMatrix
  class CellDragData < DragData
    getter row : Int32
    getter col : Int32
    getter display : String
    # Identity of the matrix this cell was dragged from (copied from the
    # source VM's drag_owner_key). Lets a drop on a *different* matrix
    # recognise the payload as cross-owner. nil = untagged (legacy callers).
    getter owner_key : String?

    def initialize(@row : Int32, @col : Int32, @display : String, @owner_key : String? = nil)
    end

    def data_type : String
      "matrix_cell"
    end

    def display_text : String?
      @display
    end
  end

  class VirtualMatrix < Widget
    include LayerOwner
    include PrimitiveBuilder
    include Draggable
    include DropTarget

    # Cell drag state
    getter drag_source_cell : Tuple(Int32, Int32)? = nil

    # An EXTERNAL assignment (an app-level cut highlight) is a committed source:
    # it paints its decal immediately. Only the internal mouse-down candidate
    # (set on the ivar directly, then flagged provisional) is withheld until a
    # drag actually starts — see drag_source_provisional? and on_mouse_down.
    def drag_source_cell=(value : Tuple(Int32, Int32)?)
      @drag_source_cell = value
      @drag_source_provisional = false
    end

    # True while drag_source_cell is only the mouse-down candidate DragManager
    # reads to build the ghost — no drag has crossed the threshold yet, so the
    # source decal must stay hidden (prevents the salmon flash on a plain click).
    getter? drag_source_provisional : Bool = false
    property drag_source_was_preexisting : Bool = false

    # Callback after cell drop completes (for app-level updates like a data refresh + rebuild)
    property on_cell_drop_handler : Proc(Nil)? = nil

    # Identity of the owner this matrix belongs to. Stamped into the
    # drag data (get_drag_data) so a drop on a *different* matrix can tell
    # the payload is cross-owner and route it differently.
    property drag_owner_key : String? = nil

    # Handler for a cross-owner cell drop (payload whose owner_key differs
    # from this matrix's drag_owner_key). When set, such a drop is delegated
    # here with (data, target_row, target_col) INSTEAD of the native
    # intra-owner cell_move. Same-owner / untagged drops are unaffected.
    property cross_drop_handler : Proc(CellDragData, Int32, Int32, Nil)? = nil

    # App-level cell activation callback. Invoked before default handling on:
    #   - double-click (before proxy.on_mouse_up forward)
    #   - Enter/Space key (before proxy.on_key_down forward)
    #   - first typed character (before proxy.on_text_input forward)
    # Return true to indicate the activation was handled — skips the default
    # proxy forwarding. Return false / leave unset to get default behavior.
    # Typical use: drill-down on aggregate cells.
    property on_cell_activate : Proc(Tuple(Int32, Int32), Bool)? = nil

    @drag_target_cell : Tuple(Int32, Int32)? = nil

    # Grid dimensions
    getter rows : Int32
    getter cols : Int32

    # Optional adapter for data binding
    getter adapter : Widgets::VirtualMatrix::MatrixAdapter?

    # Push-based invalidation: pending state (flushed in pre_render_flush)
    @pending_cell_invalidations : Set(Tuple(Int32, Int32)) = Set(Tuple(Int32, Int32)).new
    @pending_invalidate_all : Bool = false

    # Cell sizing (in frame_height multiples)
    GRID_SPACING_BASE = 3.0  # Pixels between grid cells at zoom 1.0 (balances readability vs density)
    GRID_SPACING      = 3    # Integer alias at zoom 1.0 (for spec backwards compat)
    # Backward-compat aliases (canonical location: MatrixAdapter)
    DEFAULT_COLUMN_WIDTH = Widgets::VirtualMatrix::MatrixAdapter::DEFAULT_COLUMN_WIDTH
    DEFAULT_ROW_HEIGHT   = Widgets::VirtualMatrix::MatrixAdapter::DEFAULT_ROW_HEIGHT
    OFFSCREEN_PARK       = -1000.0 # Parking position for invisible cells (far off-screen to avoid rendering)

    # Interactive resize constants
    RESIZE_TOLERANCE_BASE = 4.0  # pixels from border to trigger resize (at zoom 1.0)
    MIN_COL_WIDTH    = 0.5  # minimum column width in frame_height units
    MIN_ROW_HEIGHT   = 0.5  # minimum row height in frame_height units

    private def resize_tolerance : Float64
      RESIZE_TOLERANCE_BASE * FontSizing.zoom_factor
    end

    enum ResizeAxis
      None
      Col
      Row
    end

    # Frame height for pixel conversion: one "frame height unit" = 20 physical pixels at zoom 1.0.
    # All cell dimensions (col_width, row_height) are specified in frame_height multiples.
    FRAME_HEIGHT_BASE = 20.0

    # Viewport cache buffer (pixels beyond viewport kept pre-rendered for smooth scrolling)
    CACHE_EXTENT = 100.0
    # Cell creation buffer: cells are created when within this distance of the viewport.
    # Must be >= CACHE_EXTENT so cells cover the entire viewport_cache buffer.
    # = CACHE_EXTENT(100) + safety_margin(50) for sub-pixel rounding headroom.
    CREATION_BUFFER = 150.0
    # Cell destruction buffer: cells are destroyed when outside this distance.
    # Larger than CREATION_BUFFER to provide hysteresis (avoids create/destroy thrashing
    # when scrolling back and forth near the viewport edge).
    DESTRUCTION_BUFFER = 200.0

    # Z-index offsets for VirtualMatrix layers (relative to widget's base_z)
    CONTENT_LAYER_Z  = 1  # Main cell content layer
    CURSOR_OVERLAY_Z = 8  # Cursor highlight layer (above all ScrollView layers: SV uses +1..+5)
    DRAG_OVERLAY_Z   = 9  # Cell drag source/target decals (above the cursor band; Normal blend)
    # See-through for the drag decal. Applied as LAYER opacity over an opaque salmon
    # fill (not fill alpha) so the RT stays opaque — a semi-transparent fill would be
    # premultiplied over the transparent-black RT and composite to an invisible tint.
    DRAG_OVERLAY_OPACITY = 0.5

    # Zoom tracking for change detection in perform_layout
    @last_zoom_factor : Float64 = 1.0

    private def frame_height : Float64
      FRAME_HEIGHT_BASE * FontSizing.zoom_factor
    end

    # Inter-cell gap in device pixels. Public (like the sibling ruler_*/sticky_* geometry
    # helpers) because the cursor overlay must subtract it to size the cell-flash to the
    # cell — cells are laid out at pitch MINUS grid_spacing (update_visible_cells).
    def grid_spacing : Int32
      (GRID_SPACING_BASE * FontSizing.zoom_factor).round.to_i32
    end

    # Layers (reconciled to preserve layer state across DSL rebuilds)
    # OBJECT REFS — kept as plain ivars via reconcile_property (no Source-backing, no read sweep)
    reconcile_property content_layer : Layer?
    reconcile_property cursor_overlay_layer : Layer?
    reconcile_property cursor_overlay_widget : CursorOverlayWidget?
    reconcile_property drag_overlay_layer : Layer?
    reconcile_property drag_overlay_widget : DragOverlayWidget?

    # Ruler widgets (rendered on sticky layers for column/row labels + resize handles)
    getter col_ruler_widget : ColumnRulerWidget? = nil
    getter row_ruler_widget : RowRulerWidget? = nil
    getter corner_ruler_widget : CornerRulerWidget? = nil
    getter corner_row_strip_widget : CornerRowStripWidget? = nil

    # Ruler visibility (default on)
    reactive_property show_rulers : Bool = true, layout: true

    # ScrollView for scrollbar chrome (overlays content area)
    @content_scroll_view : ScrollView?

    # Reconciliation properties
    # scroll_offset is a Source-backed reactive_property (reconcile: true).
    # Getter auto-captures in to_primitives; setter notifies dependents.
    # The custom setter below OVERRIDES the macro's: scroll is a COMPOSITING input,
    # so setting it must call apply_scroll (composite + recenter), NOT mark_needs_layout.
    reactive_property scroll_offset : Vec2 = Vec2.zero, reconcile: true

    # scroll_offset is a COMPOSITING input: the setter notifies auto-captured readers (Source.set) AND
    # applies the scroll (apply_scroll = composite + recenter). NOT mark_needs_layout — scroll never re-layouts.
    def scroll_offset=(value : Vec2) : Nil
      return if scroll_offset == value
      @scroll_offset.set(value)
      apply_scroll
    end

    # Track last synced scroll offset for bi-directional sync with ScrollView
    # This allows detecting which side (VirtualMatrix or ScrollView) changed
    # NOT reconciled: after rebuild the ScrollView is fresh (offset=0), so we need
    # the push branch to fire and seed it with our reconciled scroll_offset.
    @last_synced_scroll_offset : Vec2 = Vec2.zero
    # Deferred scroll (5e2f3ee): scrollbar thumb drag fires sync_from_scroll_view per mouse
    # event (~125Hz). Running update_visible_cells on each backs the event loop up into a
    # multi-second freeze, so we only flag here and flush once per frame in pre_render_flush.
    @pending_scroll_update : Bool = false
    # Resize drag defers its expensive reflow/geometry/ruler work to pre_render_flush,
    # so a fast (~125 Hz) drag coalesces to ONE update per (~60 Hz) frame — mirrors
    # @pending_scroll_update. Set in on_mouse_move, drained in pre_render_flush.
    @pending_resize_update : Bool = false
    reactive_property cursor_rc : Tuple(Int32, Int32) = {0, 0}, reconcile: true

    # Public API: move cursor to a specific cell (e.g., after an external edit moved a row)
    def set_cursor(row : Int32, col : Int32)
      self.cursor_rc = {row, col}
      mark_needs_render
    end

    # Interactive column/row resize state
    reactive_property resize_axis : ResizeAxis = ResizeAxis::None, reconcile: true
    reactive_property resize_index : Int32 = 0, reconcile: true
    reactive_property resize_start_mouse : Float64 = 0.0, reconcile: true
    reactive_property resize_start_size : Float64 = 0.0, reconcile: true
    # Whole pixels the resized line's leading edge has moved since the content buffer was last
    # composited. The drag setters accumulate it (telescoping per-move integer deltas → exact),
    # and update_visible_cells consumes it once per frame to drive the content-layer blit-shift.
    @resize_pending_shift_px : Int32 = 0

    # Cursor highlight intensity. Positive = additive/brighten (dark themes),
    # negative = subtractive/darken (light themes). Magnitude = per-channel delta.
    @cursor_highlight_delta : Int32 = Theme.current.brightness_cursor_delta

    # Content layer background color (visible between cells)
    @content_background_color : Color? = nil # nil = follow Theme.current.grid_content_background live

    # Cursor flash state (managed via overlay layer with additive blend)
    @cursor_flash_timer_id : Int32? = nil
    @cursor_flash_on : Bool = true

    # Double-click detection
    DOUBLE_CLICK_THRESHOLD_MS = 300
    @last_click_time : Time::Instant = Time.instant - 1.hour
    @last_click_cell : Tuple(Int32, Int32) = {-1, -1}

    # Cell management (sparse - only visible cells exist)
    # NOT reconciled - cells are recreated fresh on rebuild to avoid bounds corruption
    @active_cells : Hash(Tuple(Int32, Int32), Widget) = {} of Tuple(Int32, Int32) => Widget

    # Cached visible indices (updated in perform_layout)
    @visible_rows : Array(Int32) = [] of Int32
    @visible_cols : Array(Int32) = [] of Int32

    # Viewport StickyMath outputs (for reposition_sticky_cells)
    @viewport_col_offset : Int32 = 0
    @viewport_col_positions : Hash(Int32, Int32) = {} of Int32 => Int32
    @viewport_col_shifting_index : Int32 = 0
    @viewport_row_offset : Int32 = 0
    @viewport_row_positions : Hash(Int32, Int32) = {} of Int32 => Int32
    @viewport_row_shifting_index : Int32 = 0

    # Visibility cache key to avoid redundant update_visible_cells work
    # Simplified: just visible indices (no scroll_offset rounding)
    @last_visible_key : Tuple(Array(Int32), Array(Int32), Int32?, Int32?)? = nil
    @force_cell_update : Bool = false
    @layer_widgets_need_sync : Bool = true

    # (Deferred scroll removed — sync_from_scroll_view now calls update_visible_cells
    # directly, same as on_mouse_wheel. The early-exit optimization makes this cheap.)

    # Instrumentation: count update_visible_cells calls (for performance testing)
    @@update_visible_cells_call_count : Int32 = 0

    def self.update_visible_cells_call_count : Int32
      @@update_visible_cells_call_count
    end

    def self.reset_update_visible_cells_counter
      @@update_visible_cells_call_count = 0
    end

    # perf-audit: total ROW-GEOMETRY entries rebuilt by the @cached_row_sizes rebuild in
    # update_visible_cells. Bumped by @rows every time that O(total rows) row-sizes array is
    # recomputed from nil — so a COLUMN resize (which invalidates ALL dimension caches, then
    # rebuilds row sizes) shows this scaling with TOTAL rows even though visible cells are constant.
    @@row_cache_rebuild_rows : Int32 = 0

    def self.row_cache_rebuild_rows : Int32
      @@row_cache_rebuild_rows
    end

    def self.reset_row_cache_rebuild_rows
      @@row_cache_rebuild_rows = 0
    end

    def self.increment_row_cache_rebuild_rows(n : Int32)
      @@row_cache_rebuild_rows += n
    end

    # Cell sizes (frame_height multiples), one entry per row/col.
    # Initialized from adapter.get_sizes, mutated by drag resize.
    # Protected for copy_state_from reconciliation.
    @row_heights : Array(Float64) = [] of Float64
    @col_widths : Array(Float64) = [] of Float64

    protected def col_widths : Array(Float64)
      @col_widths
    end

    protected def row_heights : Array(Float64)
      @row_heights
    end

    # === DIMENSION CACHES (27 variables, all cleared by invalidate_dimension_caches) ===
    # Built once per resize (O(n)), reused per-scroll (O(1) or O(log n)).
    # Adding a new cache variable? Add its nil-assignment to invalidate_dimension_caches too.

    # -- Group 1: Derived totals --
    @cached_total_width : Float64? = nil
    @cached_total_height : Float64? = nil

    # -- Group 2: Size & cumulative arrays (O(n) to build, O(log n) bsearch per scroll) --
    @cached_col_sizes : Array(Int32)? = nil
    @cached_row_sizes : Array(Int32)? = nil
    @cached_col_cumulative : Array(Int32)? = nil     # prefix sums in scroll order
    @cached_row_cumulative : Array(Int32)? = nil
    @cached_col_physical_cum : Array(Int32)? = nil   # prefix sums in physical order
    @cached_row_physical_cum : Array(Int32)? = nil
    @cached_col_scroll_order : Array(Int32)? = nil
    @cached_row_scroll_order : Array(Int32)? = nil
    @cached_sticky_row_count : Int32? = nil
    @cached_sticky_col_count : Int32? = nil

    # Shorthand for the lib's O(1) shifted-membership value (cached inverse permutation).
    alias ShiftedSet = Widgets::VirtualMatrix::StickyMath::ShiftedSet
    # Shorthand for the per-axis compound-disposition context (see StickyMath.compound_axis).
    alias AxisView = Widgets::VirtualMatrix::StickyMath::AxisView

    # -- Group 3: Viewport sticky results (keyed on {num_shifted, index_beyond}) --
    @last_col_sticky_key : Tuple(Int32, Int32?)? = nil
    @last_row_sticky_key : Tuple(Int32, Int32?)? = nil
    @last_col_sticky_result : Tuple(Int32, Hash(Int32, Int32), Int32, Array(Int32), ShiftedSet)? = nil
    @last_row_sticky_result : Tuple(Int32, Hash(Int32, Int32), Int32, Array(Int32), ShiftedSet)? = nil
    @cached_col_shifted : ShiftedSet? = nil
    @cached_row_shifted : ShiftedSet? = nil
    # Inverse of scroll_order (scroll_rank[physical] = its scroll-order position), built once
    # per resize so ShiftedSet membership is O(1).
    @cached_col_scroll_rank : Array(Int32)? = nil
    @cached_row_scroll_rank : Array(Int32)? = nil

    # -- Group 4: Creation/destruction region caches --
    @last_creation_col_key : Tuple(Int32, Int32?)? = nil
    @last_creation_row_key : Tuple(Int32, Int32?)? = nil
    @last_creation_col_result : Array(Int32)? = nil
    @last_creation_row_result : Array(Int32)? = nil
    @last_destruction_col_key : Tuple(Int32, Int32?)? = nil
    @last_destruction_row_key : Tuple(Int32, Int32?)? = nil
    @last_destruction_col_result : Array(Int32)? = nil
    @last_destruction_row_result : Array(Int32)? = nil

    # Scroll wheel sensitivity
    SCROLL_SPEED_BASE = 30.0

    private def scroll_speed : Float64
      SCROLL_SPEED_BASE * FontSizing.zoom_factor
    end

    def initialize(@rows : Int32, @cols : Int32, id : String? = nil)
      adapter = DefaultAdapter.new(@rows, @cols)
      @adapter = adapter
      @row_heights, @col_widths = adapter.get_sizes
      super(id: id)
      @focusable = true
      bind_adapter_invalidation(adapter)
    end

    # Constructor with adapter for data binding
    def initialize(
      adapter : Widgets::VirtualMatrix::MatrixAdapter,
      id : String? = nil,
      cursor_highlight_delta : Int32 = Theme.current.brightness_cursor_delta,
      content_background_color : Color? = nil
    )
      @adapter = adapter
      row_order, col_order = adapter.get_scrollorder
      @rows = row_order.size
      @cols = col_order.size
      @row_heights, @col_widths = adapter.get_sizes
      @cursor_highlight_delta = cursor_highlight_delta
      @content_background_color = content_background_color
      super(id: id)
      @focusable = true
      bind_adapter_invalidation(adapter)
    end

    # Override base class method (which always returns false)
    def focusable? : Bool
      true
    end

    # Suppress drag tracking when resize is active (resize takes priority over cell drag)
    def suppresses_drag? : Bool
      resize_axis != ResizeAxis::None
    end

    # VirtualMatrix is a focus scope — FocusCycler won't Tab into cell widgets
    def is_focus_scope? : Bool
      true
    end

    # Proxy focus: the cell widget that currently has delegated focus
    # VirtualMatrix stays focused (owns grid nav), but forwards events to this widget
    # OBJECT REF / transient proxy state — kept plain via reconcile_property (no Source-backing, no sweep)
    reconcile_property proxy_focused_widget : Widget? = nil
    # Row/col of the proxy-focused cell (for commit_proxy_edit)
    reconcile_property proxy_focused_rc : Tuple(Int32, Int32)? = nil

    # === THEME CONFIGURATION ===

    def cursor_highlight_delta : Int32
      @cursor_highlight_delta
    end

    def cursor_highlight_delta=(value : Int32)
      @cursor_highlight_delta = value
    end

    # Live theme: nil ivar → follow Theme.current; an explicit value overrides (snapshot-drop).
    def content_background_color : Color
      @content_background_color || Theme.current.grid_content_background
    end

    def content_background_color=(value : Color?)
      @content_background_color = value
    end

    # Pull-based layer background: the content layer clears to the LIVE content background so
    # a Theme.set recolors it without a rebuild. Other VM layers keep their cached color.
    def compute_background_for_layer(layer : Layer) : Color?
      layer == @content_layer ? content_background_color : nil
    end

    # === SIZE SETTERS/GETTERS ===

    # Set custom row height (in frame_height multiples)
    def row_height(row : Int32, height : Float64)
      @row_heights[row] = height
      @cached_total_height = nil  # Invalidate cache
      invalidate_dimension_caches
      @force_cell_update = true
      mark_needs_layout
    end

    # Set custom column width (in frame_height multiples)
    def col_width(col : Int32, width : Float64)
      @col_widths[col] = width
      @cached_total_width = nil  # Invalidate cache
      invalidate_dimension_caches
      @force_cell_update = true
      mark_needs_layout
    end

    # Lightweight drag setters: update size without mark_needs_layout.
    # Used during interactive resize drag for O(1) per-move instead of O(n) rebuild.
    # Caller must follow with update_visible_cells + mark_needs_render.
    protected def set_col_width_for_drag(col : Int32, width : Float64)
      old_px = col_width_pixels(col).to_i32
      @col_widths[col] = width
      @cached_total_width = nil
      invalidate_dimension_caches
      @force_cell_update = true
      @resize_pending_shift_px += col_width_pixels(col).to_i32 - old_px
    end

    protected def set_row_height_for_drag(row : Int32, height : Float64)
      old_px = row_height_pixels(row).to_i32
      @row_heights[row] = height
      @cached_total_height = nil
      invalidate_dimension_caches
      @force_cell_update = true
      @resize_pending_shift_px += row_height_pixels(row).to_i32 - old_px
    end

    # Get row height (in frame_height multiples)
    def get_row_height(row : Int32) : Float64
      @row_heights[row]
    end

    # Get column width (in frame_height multiples)
    def get_col_width(col : Int32) : Float64
      @col_widths[col]
    end

    # === STICKY HELPERS ===

    # Derive sticky count from scroll_order tail.
    # Elements at the end of scroll_order that form a contiguous set {0, 1, ..., N-1}
    # are considered sticky (they scroll out last and render at fixed positions).
    # scroll_order is the sole mechanism for stickiness — there is no separate sticky flag.
    private def derive_sticky_count(scroll_order : Array(Int32)) : Int32
      count = 0
      sticky_set = Set(Int32).new
      scroll_order.reverse_each do |idx|
        test_set = sticky_set.dup
        test_set.add(idx)
        if test_set == (0...test_set.size).to_set
          sticky_set = test_set
          count = test_set.size
        else
          break
        end
      end
      count
    end

    # Derive number of sticky rows from row scroll_order (cached to avoid repeated allocation)
    def sticky_row_count : Int32
      @cached_sticky_row_count ||= if adapter = @adapter
        row_order, _ = adapter.get_scrollorder
        scroll_order = @cached_row_scroll_order || row_order
        derive_sticky_count(scroll_order)
      else
        0
      end
    end

    # Derive number of sticky columns from col scroll_order (cached to avoid repeated allocation)
    def sticky_col_count : Int32
      @cached_sticky_col_count ||= if adapter = @adapter
        _, col_order = adapter.get_scrollorder
        scroll_order = @cached_col_scroll_order || col_order
        derive_sticky_count(scroll_order)
      else
        0
      end
    end

    # Calculate total pixel height of sticky rows
    def sticky_row_height_pixels : Float64
      count = sticky_row_count
      return 0.0 if count <= 0
      (0...count).sum { |r| row_height_pixels(r) }
    end

    # Calculate total pixel width of sticky columns
    def sticky_col_width_pixels : Float64
      count = sticky_col_count
      return 0.0 if count <= 0
      (0...count).sum { |c| col_width_pixels(c) }
    end

    # Ruler dimensions in pixels (0 if rulers hidden)
    def ruler_row_height_pixels : Float64
      show_rulers ? (RULER_ROW_HEIGHT * frame_height) : 0.0
    end

    def ruler_col_width_pixels : Float64
      show_rulers ? (RULER_COL_WIDTH * frame_height) : 0.0
    end

    # === COMPOUND/MERGED CELLS ===

    # Get bounding box for a cell
    # Non-merged cells return themselves as the bounding box
    def get_bounding_box(cell : Tuple(Int32, Int32)) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
      if adapter = @adapter
        adapter.cell_get_bounding_box(cell[0], cell[1])
      else
        {cell, cell}
      end
    end

    # Get top-left cell of merged region (static, ignores scroll state)
    def get_top_left_cell(cell : Tuple(Int32, Int32)) : Tuple(Int32, Int32)
      get_bounding_box(cell)[0]
    end

    # Check if cell is top-left of its merged region (should render widget)
    def is_handle_cell?(cell : Tuple(Int32, Int32)) : Bool
      cell == get_top_left_cell(cell)
    end

    # Dynamic handle cell: first VISIBLE cell of a merged region.
    # When the top-left scrolls out, the first visible row/col takes over.
    # Finds a merged region's first visible constituent via ShiftedSet (O(1) membership).
    # Returns nil if the merged region is entirely invisible.
    def dynamic_handle_cell(cell : Tuple(Int32, Int32),
                            shifted_rows : ShiftedSet,
                            shifted_cols : ShiftedSet) : Tuple(Int32, Int32)?
      bounding = get_bounding_box(cell)
      min_row = bounding[0][0]
      min_col = bounding[0][1]

      # First visible row/col at or after the bounding box start — O(shifted run)
      handle_row = Widgets::VirtualMatrix::StickyMath.first_visible_at_or_after(min_row, shifted_rows, @rows)
      handle_col = Widgets::VirtualMatrix::StickyMath.first_visible_at_or_after(min_col, shifted_cols, @cols)

      # -1 means no visible element at or after this index
      return nil if handle_row == -1 || handle_col == -1

      # Only valid if the handle is within the bounding box
      max_row = bounding[1][0]
      max_col = bounding[1][1]
      return nil if handle_row > max_row || handle_col > max_col

      {handle_row, handle_col}
    end

    # Check if cell is the dynamic handle of its merged region
    def is_dynamic_handle_cell?(cell : Tuple(Int32, Int32),
                                shifted_rows : ShiftedSet,
                                shifted_cols : ShiftedSet) : Bool
      cell == dynamic_handle_cell(cell, shifted_rows, shifted_cols)
    end

    # Get cell at a given row/col (returns top-left for merged cells)
    def cell_at_point(cell : Tuple(Int32, Int32)) : Tuple(Int32, Int32)
      get_top_left_cell(cell)
    end

    # Check if a cell is "cursored" (cursor is within its bounding box)
    def is_cell_cursored?(cell : Tuple(Int32, Int32)) : Bool
      bounding = get_bounding_box(cell)
      row_range = bounding[0][0]..bounding[1][0]
      col_range = bounding[0][1]..bounding[1][1]
      rc = cursor_rc
      row_range.includes?(rc[0]) && col_range.includes?(rc[1])
    end

    # === CELL ACCESSORS ===

    def active_cell_count : Int32
      @active_cells.size
    end

    # Expose active_cells for testing (read-only)
    def active_cells : Hash(Tuple(Int32, Int32), Widget)
      @active_cells
    end

    # Clear all widget_backend and background_backend for active cells.
    # Called by layer_renderer's handle_viewport_cache_scroll on full recenter (no overlap).
    # Without this, the fast-path (cached blit) would blit OLD content
    # rendered at OLD buffer_origin positions after the buffer recenters.
    def clear_all_widget_backends
      @active_cells.each do |_key, widget|
        widget.widget_backend = nil
        widget.background_backend = nil
      end
    end

    # Prepare for blit-shift recenter (overlap exists).
    # DON'T touch widget_backend or background_backend — overlap cells keep valid caches
    # and pass the fast path (cheap blit, no re-render). Background content (solid bg_color)
    # is position-independent, so old background stays valid after buffer shift.
    # Only force cell update so edge cells for the newly exposed strip get created.
    def prepare_backends_for_blit_shift(layer : Layer)
      @force_cell_update = true
    end

    def visible_cell_indices : NamedTuple(rows: Array(Int32), cols: Array(Int32))
      {rows: @visible_rows, cols: @visible_cols}
    end

    # Calculate screen position (absolute) for a cell - useful for testing
    # Returns the absolute position where a cell would appear on screen
    def cell_screen_position(row : Int32, col : Int32) : Vec2
      # Content area is the full bounds
      content_x = absolute_bounds.x
      content_y = absolute_bounds.y

      # Calculate cell position within content (before scroll)
      # Ruler offsets shift all cells right/down
      cell_x = ruler_col_width_pixels + (0...col).sum { |c| col_width_pixels(c) }
      cell_y = ruler_row_height_pixels + (0...row).sum { |r| row_height_pixels(r) }

      # Apply scroll offset
      screen_x = content_x + cell_x - scroll_offset.x
      screen_y = content_y + cell_y - scroll_offset.y

      Vec2.new(screen_x, screen_y)
    end

    # === ADAPTER METHODS ===

    # Bind invalidation callbacks so adapter can push changes to this matrix
    private def bind_adapter_invalidation(adapter)
      adapter._bind_invalidation(
        on_cell: ->(row : Int32, col : Int32) {
          @pending_cell_invalidations << {row, col}
          mark_needs_render
          nil
        },
        on_all: ->{
          @pending_invalidate_all = true
          # Clear proxy focus immediately — cell widgets will be destroyed during
          # flush_invalidate_all. Without this, @proxy_focused_widget points to a
          # dead widget between invalidation and next render.
          clear_proxy_focus
          mark_needs_layout
          nil
        }
      )
    end

    # === CURSOR AND NAVIGATION ===

    # Check if row is highlighted (cursor is in this row)
    def is_row_highlighted?(row : Int32) : Bool
      cursor_rc[0] == row
    end

    # Check if column is highlighted (cursor is in this column)
    def is_col_highlighted?(col : Int32) : Bool
      cursor_rc[1] == col
    end

    # === LAYER ACCESSORS ===

    def layer : Layer?
      @content_layer
    end

    # Auxiliary layers this matrix owns beyond its primary content layer
    # (@content_layer, returned by #layer): the cursor band + drag decal overlays.
    # Published for LayerRenderer#collect_layers (the each_owned_layer protocol) so
    # a new matrix overlay can't be silently missed by the render pass. (The
    # scrollbar/sticky layers belong to the inner @content_scroll_view child, not
    # this matrix, and are collected through the child recursion.)
    def each_owned_layer(& : Layer ->)
      @cursor_overlay_layer.try { |l| yield l }
      @drag_overlay_layer.try { |l| yield l }
    end

    # Pull-based layer bounds: content and cursor overlay use effective content size.
    # A shrink_to_content matrix has FIXED-width content, so during an ancestor
    # resize it clips to the ancestor's live content rectangle — it shrinks only
    # once the edge reaches it (not by the ancestor's whole delta), and the
    # intersection is shrink-only and never negative. A full-size matrix (the
    # main grid) reflows with the panel, so it keeps the delta-based clip.
    def compute_bounds_for_layer(layer : Layer) : Rect
      abs = absolute_bounds
      w, h = effective_content_size(bounds.width, bounds.height)
      Rect.new(abs.x, abs.y, w, h)
    end

    # content_layer / cursor_overlay_layer accessors are generated by reconcile_property.

    # Removed: sticky_col_header_layer, sticky_row_header_layer, sticky_corner_layer
    # Headers are now data cells rendered via adapter cell_paint with styling

    # Returns the ScrollView used for scrollbar chrome
    def content_scroll_view : ScrollView?
      @content_scroll_view
    end

    # === LAYOUT ===

    # When true, measure() returns the intrinsic size of all cells + rulers
    # instead of filling the parent's constraint. For embedded VMs in a
    # vstack / tree_node where VM shouldn't take over the whole panel.
    property shrink_to_content : Bool = false
    # Upper bound on VM height — pairs with shrink_to_content. When the
    # intrinsic content height exceeds this cap, VM sizes to the cap and
    # the vertical scrollbar becomes active.
    property max_height : Float64? = nil

    # When false, VM does NOT intercept cell-level mouse events: clicks
    # flow directly to child cell widgets (Checkbox, Button, etc.), and
    # no cursor-highlight overlay is drawn. Use for embedded summary /
    # listing tables where navigation and cell-cursor semantics aren't
    # wanted. Default true preserves the normal spreadsheet-style UX.
    property interactive_cells : Bool = true

    def measure(constraints : BoxConstraints) : Size
      if @shrink_to_content
        # Intrinsic size matches VM's own total_content_{width,height} so
        # the internal scroll_view's content_size equals the viewport_size
        # (no internal scrollbar needed). Mirrors col_width_pixels /
        # row_height_pixels which add grid_spacing per cell.
        fh = frame_height
        gs = grid_spacing
        intrinsic_h = ruler_row_height_pixels + @row_heights.sum { |h| gs + h * fh }
        intrinsic_w = ruler_col_width_pixels + @col_widths.sum { |w| gs + w * fh }
        # Reserve scrollbar-column width so the right-most cell isn't
        # clipped by the internal ScrollView's vertical scrollbar when
        # content overflows vertically. Cheap to always reserve it — the
        # scrollbar layer is inert when not needed.
        intrinsic_w += ScrollView::SCROLLBAR_WIDTH
        # Width: size to content, capped at the available constraint. When the
        # panel is narrower than the content the matrix CLIPS — columns keep
        # their natural, readable width and the right-most ones are cut off
        # (horizontal scrolling/scrollbar is disabled in this mode; see
        # horizontal_clip?). Scaling columns down to fit was tried and rejected:
        # it renders cells as unreadable slivers, and doing it in measure()
        # corrupted the authored @col_widths. @col_widths is never mutated here.
        width = constraints.max_width.finite? ? Math.max(0.0, Math.min(intrinsic_w, constraints.max_width)) : intrinsic_w
        # Height: cap at optional max_height AND the parent's constraint.
        max_h = @max_height
        capped_h = max_h ? Math.min(intrinsic_h, max_h) : intrinsic_h
        height = constraints.max_height.finite? ? Math.min(capped_h, constraints.max_height) : capped_h
        Size.new(width, height)
      else
        # Fill available space (legacy default).
        width = constraints.max_width.finite? ? constraints.max_width : 400.0
        height = constraints.max_height.finite? ? constraints.max_height : 300.0
        Size.new(width, height)
      end
    end

    # A virtual grid scrolls, so its content floor is the ruler/header + ONE data row — not the
    # greedy fill its measure returns. (A shrink_to_content VM already sizes to content, so its
    # measure-based default IS its min.) Mirrors row_height_pixels' per-row sizing.
    def min_intrinsic_height(width : Float64) : Float64
      return super if @shrink_to_content
      first_row = @rows > 0 ? grid_spacing + (@row_heights[0]? || DEFAULT_ROW_HEIGHT) * frame_height : 0.0
      ruler_row_height_pixels + first_row
    end

    # The WIDTH dual: a virtual grid scrolls, so its width floor is the ruler/header col + ONE data column
    # — not the greedy fill its measure returns. (A shrink_to_content VM sizes to content → measure IS its
    # min, so defer to super, mirroring the height guard.) No sticky-col reservation (mirrors the height
    # min's no-sticky-row) and no scrollbar reservation, keeping the dual symmetric.
    def min_intrinsic_width(height : Float64) : Float64
      return super if @shrink_to_content
      first_col = @cols > 0 ? grid_spacing + (@col_widths[0]? || DEFAULT_COLUMN_WIDTH) * frame_height : 0.0
      ruler_col_width_pixels + first_col
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      handle_zoom_change
      measured = measure(constraints)
      @bounds = Rect.new(position, measured)

      content_x = absolute_bounds.x
      content_y = absolute_bounds.y
      full_width = @bounds.width
      full_height = @bounds.height
      content_width, content_height = effective_content_size(full_width, full_height)
      base_z = parent_layer_z_index

      setup_content_layer(content_x, content_y, content_width, content_height, base_z)
      if @interactive_cells
        setup_cursor_overlay_layer(content_x, content_y, content_width, content_height, base_z)
        setup_drag_overlay_layer(content_x, content_y, content_width, content_height, base_z)
      end
      setup_scroll_view(full_width, full_height)
      sync_scroll_offsets
      @content_layer.not_nil!.scroll_offset = scroll_offset

      # Invalidate sticky layers so rulers re-render at current viewport bounds
      if sv = @content_scroll_view
        [sv.sticky_row_layer, sv.sticky_col_layer, sv.sticky_corner_layer].each do |layer|
          layer.try &.mark_needs_clear_and_render
        end
      end

      if show_rulers
        create_ruler_widgets(@content_scroll_view.not_nil!)
      end

      update_visible_cells(content_width, content_height)
      clamp_cursor
    end

    # Detect zoom change → scale scroll offset proportionally and invalidate all caches.
    private def handle_zoom_change
      current_zoom = FontSizing.zoom_factor
      return if @last_zoom_factor == current_zoom

      zoom_ratio = current_zoom / @last_zoom_factor
      @scroll_offset.set(Vec2.new(scroll_offset.x * zoom_ratio, scroll_offset.y * zoom_ratio))
      @last_zoom_factor = current_zoom
      invalidate_dimension_caches
      @cached_total_width = nil
      @cached_total_height = nil
      @force_cell_update = true

      # Destroy all active cells (sizes changed, need recreation at new dimensions)
      @active_cells.each do |_key, widget|
        if @proxy_focused_widget == widget
          commit_proxy_edit
          widget.deactivate_proxy_focus
          @proxy_focused_widget = nil
          @proxy_focused_rc = nil
        end
        widget.render_layer = nil
        widget.parent = nil
        @children.delete(widget)
      end
      @active_cells.clear
      @layer_widgets_need_sync = true

      # Clear layer backends to erase old pixels rendered at previous zoom's cell sizes
      @content_layer.try(&.mark_needs_clear_and_render)
      if sv = @content_scroll_view
        sv.sticky_row_layer.try(&.mark_needs_clear_and_render)
        sv.sticky_col_layer.try(&.mark_needs_clear_and_render)
        sv.sticky_corner_layer.try(&.mark_needs_clear_and_render)
      end
      # No buffer_origin pin — needs_clear above makes render_layer recompute it via
      # recenter_origin! next frame; a raw Vec2.zero write would have been clobbered anyway.
    end

    # Create or update the content layer (viewport-cached, scrollable cell content).
    private def setup_content_layer(x : Float64, y : Float64, w : Float64, h : Float64, base_z : Int32)
      content_bounds = Rect.new(x, y, w, h)
      {% if flag?(:DEBUG_BLIT) %}
        is_new = @content_layer.nil?
      {% end %}
      @content_layer ||= Layer.new(
        "matrix_content_#{id}",
        content_bounds,
        z_index: base_z + CONTENT_LAYER_Z,
        background_color: content_background_color, # getter (live); pull-based layer keeps it fresh
        owner_widget: self
      )
      {% if flag?(:DEBUG_BLIT) %}
        if is_new
          File.open("/tmp/blit_trace.log", "a") do |f|
            f.puts ">>> NEW CONTENT LAYER CREATED (scroll=#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)}) active_cells=#{@active_cells.size}"
          end
        end
      {% end %}
      @content_layer.not_nil!.z_index = base_z + CONTENT_LAYER_Z
      @content_layer.not_nil!.background_color = content_background_color # cached fallback; pull keeps it live
      @content_layer.not_nil!.viewport_cache = true
      @content_layer.not_nil!.tiled_cells = true # grid of tiling cells → eligible for direct-to-layer render
      @content_layer.not_nil!.cache_extent = CACHE_EXTENT
      @content_layer.not_nil!.scroll_offset = scroll_offset
    end

    # Create or update the cursor overlay layer (non-scrolling highlight bands).
    private def setup_cursor_overlay_layer(x : Float64, y : Float64, w : Float64, h : Float64, base_z : Int32)
      overlay_bounds = Rect.new(x, y, w, h)
      @cursor_overlay_layer ||= Layer.new(
        "cursor_overlay_#{id}",
        overlay_bounds,
        z_index: base_z + CURSOR_OVERLAY_Z,
        background_color: Color.new(0, 0, 0, 0),
        owner_widget: self
      )
      # CursorOverlayWidget is CachePolicy::Never and only paints its current highlight region, so on
      # a grow (e.g. a sibling section above collapsed → the matrix gained height) the newly-exposed
      # area keeps the old (smaller) band → the column cursor stops short of the last row. Declare
      # clear_on_grow; the renderer's size-change handler clears the layer on a grow — a generic
      # mechanism, not a per-widget guard.
      @cursor_overlay_layer.not_nil!.clear_on_grow = true
      @cursor_overlay_layer.not_nil!.z_index = base_z + CURSOR_OVERLAY_Z
      @cursor_overlay_layer.not_nil!.blend_mode = @cursor_highlight_delta >= 0 ? BlendMode::Additive : BlendMode::Subtractive
      @cursor_overlay_layer.not_nil!.skip_rebuild_clear = true

      # Create/register cursor overlay widget at layer-local origin (0,0)
      overlay_layer = @cursor_overlay_layer.not_nil!
      unless @cursor_overlay_widget
        cow = CursorOverlayWidget.new(self)
        cow.parent = self
        overlay_constraints = BoxConstraints.tight(Size.new(overlay_bounds.width, overlay_bounds.height))
        cow.layout(overlay_constraints, Vec2.zero)
        overlay_layer.widgets << cow
        @cursor_overlay_widget = cow
      else
        cow = @cursor_overlay_widget.not_nil!
        overlay_constraints = BoxConstraints.tight(Size.new(overlay_bounds.width, overlay_bounds.height))
        cow.layout(overlay_constraints, Vec2.zero)
      end
    end

    # Create or update the drag overlay layer — the cell drag source/target
    # decals. Kept separate from the cursor band overlay because it needs Normal
    # blend: the band layer flips to Subtractive in a light theme, which would
    # invert the fixed salmon decal into teal-green. Mirrors the cursor overlay
    # otherwise (non-scrolling, CachePolicy::Never widget, clear_on_grow).
    private def setup_drag_overlay_layer(x : Float64, y : Float64, w : Float64, h : Float64, base_z : Int32)
      overlay_bounds = Rect.new(x, y, w, h)
      @drag_overlay_layer ||= Layer.new(
        "drag_overlay_#{id}",
        overlay_bounds,
        z_index: base_z + DRAG_OVERLAY_Z,
        background_color: Color.new(0, 0, 0, 0),
        owner_widget: self
      )
      @drag_overlay_layer.not_nil!.clear_on_grow = true
      @drag_overlay_layer.not_nil!.z_index = base_z + DRAG_OVERLAY_Z
      @drag_overlay_layer.not_nil!.blend_mode = BlendMode::Normal
      @drag_overlay_layer.not_nil!.opacity = DRAG_OVERLAY_OPACITY
      @drag_overlay_layer.not_nil!.skip_rebuild_clear = true

      drag_layer = @drag_overlay_layer.not_nil!
      unless @drag_overlay_widget
        dow = DragOverlayWidget.new(self)
        dow.parent = self
        constraints = BoxConstraints.tight(Size.new(overlay_bounds.width, overlay_bounds.height))
        dow.layout(constraints, Vec2.zero)
        drag_layer.widgets << dow
        @drag_overlay_widget = dow
      else
        dow = @drag_overlay_widget.not_nil!
        constraints = BoxConstraints.tight(Size.new(overlay_bounds.width, overlay_bounds.height))
        dow.layout(constraints, Vec2.zero)
      end
    end

    # Create/configure ScrollView for scrollbar chrome and sticky layer support.
    private def setup_scroll_view(full_width : Float64, full_height : Float64)
      scroll_view = @content_scroll_view ||= ScrollView.new(ScrollDirection::Both, id: "#{id}_scrollview")
      scroll_view.parent = self
      @children << scroll_view unless @children.includes?(scroll_view)

      scroll_view.on_scroll_changed do |new_offset|
        sync_from_scroll_view(new_offset)
      end

      scroll_view.viewport_size = Size.new(full_width, full_height)
      # When clipping horizontally, pin the scroll content width to the viewport
      # so no horizontal scrollbar appears and the overflow is simply clipped.
      content_w = horizontal_clip? ? full_width : total_content_width
      scroll_view.content_size = Size.new(content_w, total_content_height)

      # Sticky layer config (include ruler space for ruler widgets)
      scroll_view.sticky_rows = sticky_row_count
      scroll_view.sticky_cols = sticky_col_count
      scroll_view.sticky_row_height = sticky_row_height_pixels + ruler_row_height_pixels
      scroll_view.sticky_col_width = sticky_col_width_pixels + ruler_col_width_pixels
      scroll_view.sticky_background_color = @content_background_color

      scroll_constraints = BoxConstraints.tight(Size.new(full_width, full_height))
      scroll_view.layout(scroll_constraints, Vec2.new(0.0, 0.0))
    end

    # Bi-directional scroll offset sync between VirtualMatrix and ScrollView.
    # Clamps to valid range, then pushes or pulls depending on which side changed.
    private def sync_scroll_offsets
      scroll_view = @content_scroll_view.not_nil!

      # Clamp scroll offset to valid range after resize
      clamped_x = scroll_offset.x.clamp(0.0, max_content_scroll_x)
      clamped_y = scroll_offset.y.clamp(0.0, max_content_scroll_y)
      if clamped_x != scroll_offset.x || clamped_y != scroll_offset.y
        @scroll_offset.set(Vec2.new(clamped_x, clamped_y))
      end

      if scroll_offset != @last_synced_scroll_offset
        # VirtualMatrix changed → push to ScrollView
        scroll_view.set_scroll_offset_for_sync(scroll_offset)
      elsif scroll_view.scroll_offset != @last_synced_scroll_offset
        # ScrollView changed (scrollbar interaction) → pull from ScrollView
        @scroll_offset.set(scroll_view.scroll_offset)
      end
      @last_synced_scroll_offset = scroll_offset
    end

    # Create ruler widgets on sticky layers (called from perform_layout)
    private def create_ruler_widgets(scroll_view : ScrollView)
      ruler_h = ruler_row_height_pixels
      ruler_w = ruler_col_width_pixels
      content_w = @content_layer.try(&.bounds.width) || bounds.width
      content_h = @content_layer.try(&.bounds.height) || bounds.height

      # Column ruler on sticky_row_layer
      if row_layer = scroll_view.sticky_row_layer
        unless @col_ruler_widget
          crw = ColumnRulerWidget.new(self)
          crw.parent = self
          constraints = BoxConstraints.tight(Size.new(content_w, ruler_h))
          crw.layout(constraints, Vec2.zero)
          row_layer.widgets << crw
          @col_ruler_widget = crw
        else
          crw = @col_ruler_widget.not_nil!
          constraints = BoxConstraints.tight(Size.new(content_w, ruler_h))
          crw.layout(constraints, Vec2.zero)
        end
      end

      # Row ruler on sticky_col_layer
      if col_layer = scroll_view.sticky_col_layer
        unless @row_ruler_widget
          rrw = RowRulerWidget.new(self)
          rrw.parent = self
          constraints = BoxConstraints.tight(Size.new(ruler_w, content_h))
          rrw.layout(constraints, Vec2.zero)
          col_layer.widgets << rrw
          @row_ruler_widget = rrw
        else
          rrw = @row_ruler_widget.not_nil!
          constraints = BoxConstraints.tight(Size.new(ruler_w, content_h))
          rrw.layout(constraints, Vec2.zero)
        end
      end

      # Corner ruler on sticky_corner_layer (covers ruler corner + sticky col headers)
      if corner_layer = scroll_view.sticky_corner_layer
        corner_w = ruler_w + sticky_col_width_pixels
        unless @corner_ruler_widget
          corner = CornerRulerWidget.new(self)
          corner.parent = self
          constraints = BoxConstraints.tight(Size.new(corner_w, ruler_h))
          corner.layout(constraints, Vec2.zero)
          corner_layer.widgets << corner
          @corner_ruler_widget = corner
        else
          corner = @corner_ruler_widget.not_nil!
          constraints = BoxConstraints.tight(Size.new(corner_w, ruler_h))
          corner.layout(constraints, Vec2.zero)
        end

        # Corner row strip for sticky row labels (below corner ruler)
        sticky_row_h = sticky_row_height_pixels
        unless @corner_row_strip_widget
          strip = CornerRowStripWidget.new(self)
          strip.parent = self
          constraints = BoxConstraints.tight(Size.new(ruler_w, sticky_row_h))
          strip.layout(constraints, Vec2.new(0.0, ruler_h))
          corner_layer.widgets << strip
          @corner_row_strip_widget = strip
        else
          strip = @corner_row_strip_widget.not_nil!
          constraints = BoxConstraints.tight(Size.new(ruler_w, sticky_row_h))
          strip.layout(constraints, Vec2.new(0.0, ruler_h))
        end
      end
    end

    # Re-add ruler widgets to sticky layers after widget lists are cleared.
    # Called from update_visible_cells and ensure_layer_widgets_synced.
    private def add_ruler_widgets_to_layers
      return unless show_rulers
      sv = @content_scroll_view
      return unless sv

      # render_layer routes each ruler's invalidation (the Dynamic node's on_dirty
      # scroll-auto-capture enqueue) to its STICKY layer — the rulers live on the sticky layers but their
      # parent is the matrix, so propagate_to_layer would otherwise mark the wrong layer. Re-set here (not
      # just at creation) so it tracks the current sticky layer across rebuilds.
      if crw = @col_ruler_widget
        sv.sticky_row_layer.try do |l|
          l.widgets << crw unless l.widgets.includes?(crw)
          crw.render_layer = l
        end
      end
      if rrw = @row_ruler_widget
        sv.sticky_col_layer.try do |l|
          l.widgets << rrw unless l.widgets.includes?(rrw)
          rrw.render_layer = l
        end
      end
      if corner = @corner_ruler_widget
        sv.sticky_corner_layer.try do |l|
          l.widgets << corner unless l.widgets.includes?(corner)
          corner.render_layer = l
        end
      end
      if strip = @corner_row_strip_widget
        sv.sticky_corner_layer.try do |l|
          l.widgets << strip unless l.widgets.includes?(strip)
          strip.render_layer = l
        end
      end
    end

    # Mark the ruler widgets dirty for a NON-scroll change (column/row resize — sizes aren't Sources, so
    # the Dynamic rulers' auto-capture doesn't cover them). Scroll is handled by auto-capture now. Marks
    # the sticky layers directly (belt-and-suspenders with the rulers' render_layer routing).
    private def mark_ruler_widgets_dirty
      return unless show_rulers
      # Column/row SIZES aren't Sources, so the Dynamic ruler nodes don't auto-
      # invalidate on a resize the way they do on a scroll (scroll_offset IS a
      # Source, auto-captured in to_primitives). invalidate_primitive_cache
      # touches each node — regenerating its primitives AND enqueuing it to its
      # (sticky) layer via on_dirty. Merely marking the layer (mark_needs_render)
      # would re-blit the STALE cached texture — the ruler-static resize bug.
      #
      # Only the RESIZED axis's rulers change — a column resize leaves every row size (the row ruler on
      # sticky_col_layer + the sticky-row corner strip) untouched, so re-generating them each drag frame
      # is wasted font work AND (with reposition_sticky_cells' per-layer clear) would needlessly wake
      # their layer. The corner column/row labels only reposition when a STICKY line is resized. Both
      # callers are the resize path, so resize_axis is always Col/Row (scroll auto-invalidates via the
      # scroll_offset Source, never through here) — the else asserts that (see the proof there).
      case resize_axis
      when ResizeAxis::Col
        @col_ruler_widget.try &.invalidate_primitive_cache
        @corner_ruler_widget.try &.invalidate_primitive_cache if resize_index < sticky_col_count
      when ResizeAxis::Row
        @row_ruler_widget.try &.invalidate_primitive_cache
        @corner_row_strip_widget.try &.invalidate_primitive_cache if resize_index < sticky_row_count
      else
        # Unreachable: the flush gate @pending_resize_update is set ONLY inside on_mouse_move's
        # `resize_axis != None` guard and is cleared before drag-end resets resize_axis; the drag-end
        # direct call also runs before that reset. So resize_axis is always Col/Row here — a None means
        # a future caller invoked this off the resize path, which must surface, not silently over-invalidate.
        raise "mark_ruler_widgets_dirty reached with resize_axis=#{resize_axis} (expected Col or Row)"
      end
    end

    # The canonical scroll application. Every scroll-changing path writes scroll_offset
    # then routes through here, so the application — composite (content layer) → optional ScrollView sync
    # → spatial recenter (update_visible_cells) → render + cross-layer marks — can never diverge between
    # paths (the duplicated inline blocks in wheel/snap/sync were the prior kludge). sync_to_sv=false for
    # the inbound sync_from_scroll_view path: the offset came FROM the ScrollView, so syncing back loops.
    private def apply_scroll(sync_to_sv : Bool = true) : Nil
      @last_synced_scroll_offset = scroll_offset
      if layer = @content_layer
        layer.scroll_offset = scroll_offset
      end
      if sync_to_sv && (sv = @content_scroll_view)
        sv.set_scroll_offset_for_sync(scroll_offset)
      end
      vp_w = @content_layer.try(&.bounds.width) || @bounds.width
      vp_h = @content_layer.try(&.bounds.height) || @bounds.height
      update_visible_cells(vp_w, vp_h) if vp_w > 0 && vp_h > 0
      mark_needs_render
      # Rulers (Dynamic) auto-capture scroll_offset → their nodes enqueue selectively via on_dirty, so
      # no mark_ruler_widgets_dirty on scroll. The cursor overlay is Never (flash animation, no node) →
      # still marked explicitly here.
      mark_cursor_overlay_dirty
    end

    # Sync scroll offset from ScrollView when the user scrolls via the scrollbar (thumb drag /
    # track). Called via ScrollView.on_scroll_changed — potentially on EVERY mouse-move event.
    # DEFERRED (5e2f3ee): apply only the cheap compositing offset now and flag the expensive
    # cell management for pre_render_flush, so a fast multi-event drag coalesces to ONE update
    # per frame (for the only scroll position the user sees) instead of backing the event loop
    # up into a multi-second freeze. The offset came FROM the ScrollView, so don't sync back.
    # Once-per-frame resize work, deferred from on_mouse_move via @pending_resize_update.
    # Geometry first (sticky/corner depend on the new sizes), then reflow the visible
    # cells, then invalidate the ruler nodes (sizes aren't Sources — see
    # mark_ruler_widgets_dirty). Coalesced so a fast drag does this ONCE per frame.
    private def flush_resize_update
      ruler_w = ruler_col_width_pixels
      ruler_h = ruler_row_height_pixels
      if crw = @corner_ruler_widget
        crw.layout(BoxConstraints.tight(Size.new(ruler_w + sticky_col_width_pixels, ruler_h)), Vec2.zero)
      end
      if strip = @corner_row_strip_widget
        strip.layout(BoxConstraints.tight(Size.new(ruler_w, sticky_row_height_pixels)), Vec2.new(0.0, ruler_h))
      end
      if sv = @content_scroll_view
        sv.sticky_row_height = sticky_row_height_pixels + ruler_row_height_pixels
        sv.sticky_col_width = sticky_col_width_pixels + ruler_col_width_pixels
        sv.update_sticky_layer_bounds
      end
      vp_w = @content_layer.try(&.bounds.width) || bounds.width
      vp_h = @content_layer.try(&.bounds.height) || bounds.height
      update_visible_cells(vp_w, vp_h) if vp_w > 0 && vp_h > 0
      mark_ruler_widgets_dirty
    end

    private def sync_from_scroll_view(new_offset : Vec2)
      return if scroll_offset == new_offset
      @scroll_offset.set(new_offset)
      @last_synced_scroll_offset = new_offset
      if layer = @content_layer
        layer.scroll_offset = new_offset # compositor shifts the cached content immediately
      end
      @pending_scroll_update = true      # cell create/destroy deferred to pre_render_flush
      mark_needs_render
      mark_cursor_overlay_dirty
    end

    # === DEFERRED SCROLL FLUSH ===

    # Called by layer_renderer before collecting widgets for rendering.
    # Flushes deferred scroll/invalidation updates so cells are created/destroyed once per frame,
    # not on every mouse event during scrollbar thumb drag.
    def pre_render_flush
      # Deferred scroll flush (5e2f3ee): sync_from_scroll_view only flagged the change and
      # shifted the compositor; run the expensive cell create/destroy here, once per frame —
      # not once per queued mouse event. Must run BEFORE the change-animation scan below so it
      # reads the up-to-date @visible_rows/@visible_cols.
      if @pending_scroll_update
        @pending_scroll_update = false
        vp_w = @content_layer.try(&.bounds.width) || bounds.width
        vp_h = @content_layer.try(&.bounds.height) || bounds.height
        update_visible_cells(vp_w, vp_h) if vp_w > 0 && vp_h > 0
      end

      # Deferred resize flush: a resize drag only flagged @pending_resize_update per
      # move; do the expensive geometry + reflow + ruler invalidation here, once per
      # frame. Must run before the change-animation scan below (which reads the
      # up-to-date @visible_rows/@visible_cols this refreshes).
      if @pending_resize_update
        @pending_resize_update = false
        flush_resize_update
      end

      # Change animation: call start_frame + scan visible cells for value changes
      if adapter = @adapter
        adapter.start_frame
        @visible_rows.each do |r|
          @visible_cols.each do |c|
            adapter.cell_read(r, c)
          end
        end
      end

      # Process push-based adapter invalidations first
      if @pending_invalidate_all
        @pending_invalidate_all = false
        @pending_cell_invalidations.clear
        flush_invalidate_all
        # Recreate cells immediately (layout may not run if only mark_needs_render)
        trigger_update_visible_cells
        # Refresh proxy focus: old cell widgets were destroyed, new ones created.
        # Without this, @proxy_focused_widget points to a dead widget.
        update_proxy_focus if focused?
      elsif !@pending_cell_invalidations.empty?
        flush_cell_invalidations
        # Recreate destroyed cells
        trigger_update_visible_cells
        update_proxy_focus if focused?
      end

    end

    # Full invalidation: re-read dimensions, destroy all active cells
    private def flush_invalidate_all
      if adapter = @adapter
        row_order, col_order = adapter.get_scrollorder
        @rows = row_order.size
        @cols = col_order.size
        @row_heights, @col_widths = adapter.get_sizes
      end

      # Invalidate dimension caches (row/col count may have changed)
      invalidate_dimension_caches

      # Destroy all active cells
      @active_cells.each do |_key, widget|
        if @proxy_focused_widget == widget
          commit_proxy_edit
          widget.deactivate_proxy_focus
          @proxy_focused_widget = nil
          @proxy_focused_rc = nil
        end
        widget.render_layer = nil
        widget.parent = nil
        @children.delete(widget)
      end
      @active_cells.clear

      clear_all_vm_layers_for_invalidate

      @force_cell_update = true
    end

    # Clear every VM-owned layer to erase pixels painted under a superseded adapter
    # state. ONE owner of the layer list — used by flush_invalidate_all (announced
    # structural changes) and by the reconcile adapter-swap rule in copy_state_from.
    # The cursor overlay is easy to overlook (CachePolicy::Never, "regenerates fresh")
    # — but the widget only paints its CURRENT highlight region; everything outside
    # stays untouched, so old pixels from a wider band persist as a ghost cursor
    # extending past the new data extent unless cleared here.
    # (handle_zoom_change still keeps its own near-copy of this list — without the
    # cursor overlay; routing it through here is a flagged follow-up.)
    private def clear_all_vm_layers_for_invalidate
      @content_layer.try(&.mark_needs_clear_and_render)
      @cursor_overlay_layer.try(&.mark_needs_clear_and_render)
      if sv = @content_scroll_view
        sv.sticky_row_layer.try(&.mark_needs_clear_and_render)
        sv.sticky_col_layer.try(&.mark_needs_clear_and_render)
        sv.sticky_corner_layer.try(&.mark_needs_clear_and_render)
      end
      @layer_widgets_need_sync = true
    end

    # Cell-level invalidation: destroy only the invalidated cells from @active_cells
    private def flush_cell_invalidations
      cells = @pending_cell_invalidations.dup
      @pending_cell_invalidations.clear

      any_destroyed = false
      cells.each do |key|
        if widget = @active_cells.delete(key)
          if @proxy_focused_widget == widget
            commit_proxy_edit
            widget.deactivate_proxy_focus
            @proxy_focused_widget = nil
            @proxy_focused_rc = nil
          end
          widget.render_layer = nil
          widget.parent = nil
          @children.delete(widget)
          any_destroyed = true
        end
      end

      @force_cell_update = true if any_destroyed
    end

    # Trigger update_visible_cells using current content layer dimensions
    private def trigger_update_visible_cells
      if layer = @content_layer
        if layer.bounds.width > 0 && layer.bounds.height > 0
          update_visible_cells(layer.bounds.width, layer.bounds.height)
        end
      end
    end

    # === CELL MANAGEMENT ===

    private def update_visible_cells(viewport_width : Float64, viewport_height : Float64)
      {% if flag?(:PERF_LOG) || flag?(:CURSOR_PERF) %}
        _uvc_start = Time.monotonic
      {% end %}
      # === VIEWPORT STICKY MATH with incremental cache ===
      # Strategy: cache cumulative array per-resize (O(n) once), bsearch per-scroll (O(log n)),
      # full sticky() recompute only when num_shifted or index_beyond changes (boundary crossing).

      # Build/use cached sizes arrays (avoid O(n) rebuild per scroll)
      col_sizes = @cached_col_sizes ||= (0...@cols).map { |c| col_width_pixels(c).to_i32 }
      row_sizes = @cached_row_sizes ||= begin
        # perf-audit: this O(total rows) rebuild fires on ANY dimension-cache invalidation, including
        # a COLUMN resize (invalidate_dimension_caches clears row sizes too) — visible cells constant.
        VirtualMatrix.increment_row_cache_rebuild_rows(@rows)
        (0...@rows).map { |r| row_height_pixels(r).to_i32 }
      end

      # Get scroll order from adapter (or default sequential), cache it
      unless @cached_col_scroll_order && @cached_row_scroll_order
        if adapter = @adapter
          row_order, col_order = adapter.get_scrollorder
          @cached_row_scroll_order ||= row_order
          @cached_col_scroll_order ||= col_order
        else
          @cached_row_scroll_order ||= (0...@rows).to_a
          @cached_col_scroll_order ||= (0...@cols).to_a
        end
      end
      col_scroll_order = @cached_col_scroll_order.not_nil!
      row_scroll_order = @cached_row_scroll_order.not_nil!

      # Inverse permutation (physical → scroll-order position) for O(1) shifted-membership.
      col_scroll_rank = @cached_col_scroll_rank ||= begin
        inv = Array(Int32).new(col_scroll_order.size, 0)
        col_scroll_order.each_with_index { |phys, i| inv[phys] = i }
        inv
      end
      row_scroll_rank = @cached_row_scroll_rank ||= begin
        inv = Array(Int32).new(row_scroll_order.size, 0)
        row_scroll_order.each_with_index { |phys, i| inv[phys] = i }
        inv
      end

      # Build/use cached cumulative arrays (O(n) once per resize, O(1) thereafter)
      col_cumulative = @cached_col_cumulative ||= col_scroll_order.map { |el| col_sizes[el] }.accumulate { |x, y| x + y }
      row_cumulative = @cached_row_cumulative ||= row_scroll_order.map { |el| row_sizes[el] }.accumulate { |x, y| x + y }
      # Physical cumulative in natural order for filtering creation/destruction regions
      col_physical_cum = @cached_col_physical_cum ||= col_sizes.accumulate(0) { |a, b| a + b }
      row_physical_cum = @cached_row_physical_cum ||= row_sizes.accumulate(0) { |a, b| a + b }

      # Use floor/ceil for correct visibility at sub-pixel offsets.
      # Subtract ruler offsets: StickyMath and col_physical_cum work in column-space
      # (no ruler), but scroll_offset is in content-space (includes ruler width/height).
      ruler_x = ruler_col_width_pixels.to_i32
      ruler_y = ruler_row_height_pixels.to_i32
      min_x = {(scroll_offset.x.floor.to_i32 - ruler_x), 0_i32}.max # snap-exempt: content-space visible-range
      max_x = {((scroll_offset.x + viewport_width).ceil.to_i32 - ruler_x), 0_i32}.max # snap-exempt: content-space visible-range
      min_y = {(scroll_offset.y.floor.to_i32 - ruler_y), 0_i32}.max # snap-exempt: content-space visible-range
      max_y = {((scroll_offset.y + viewport_height).ceil.to_i32 - ruler_y), 0_i32}.max # snap-exempt: content-space visible-range

      # O(log n) bsearch to determine boundary key
      col_num_shifted = col_cumulative.bsearch_index { |p| p >= min_x } || col_scroll_order.size
      col_index_beyond = col_cumulative.bsearch_index { |p| p > max_x }
      row_num_shifted = row_cumulative.bsearch_index { |p| p >= min_y } || row_scroll_order.size
      row_index_beyond = row_cumulative.bsearch_index { |p| p > max_y }

      col_sticky_key = {col_num_shifted, col_index_beyond}
      row_sticky_key = {row_num_shifted, row_index_beyond}

      # Full sticky_fast() only when boundary key changes (column/row shifts in or out)
      if @last_col_sticky_key == col_sticky_key && (cached = @last_col_sticky_result)
        col_offset, col_positions, col_shifting_index, visible_cols, col_shifted = cached
      else
        col_offset, col_positions, col_shifting_index, visible_cols, col_shifted = Widgets::VirtualMatrix::StickyMath.sticky_fast(
          col_sizes, col_scroll_order, col_scroll_rank, col_num_shifted, col_cumulative, col_physical_cum,
          min_x, max_x, sticky_col_count)
        @last_col_sticky_key = col_sticky_key
        @last_col_sticky_result = {col_offset, col_positions, col_shifting_index, visible_cols, col_shifted}
        @cached_col_shifted = col_shifted
      end

      if @last_row_sticky_key == row_sticky_key && (cached = @last_row_sticky_result)
        row_offset, row_positions, row_shifting_index, visible_rows, row_shifted = cached
      else
        row_offset, row_positions, row_shifting_index, visible_rows, row_shifted = Widgets::VirtualMatrix::StickyMath.sticky_fast(
          row_sizes, row_scroll_order, row_scroll_rank, row_num_shifted, row_cumulative, row_physical_cum,
          min_y, max_y, sticky_row_count)
        @last_row_sticky_key = row_sticky_key
        @last_row_sticky_result = {row_offset, row_positions, row_shifting_index, visible_rows, row_shifted}
        @cached_row_shifted = row_shifted
      end

      # Public API: only report cols/rows physically within viewport (sticky always included)
      @visible_cols = visible_cols.select { |c| c < sticky_col_count || (col_physical_cum[c] <= max_x && col_physical_cum[c + 1] > min_x) }
      @visible_rows = visible_rows.select { |r| r < sticky_row_count || (row_physical_cum[r] <= max_y && row_physical_cum[r + 1] > min_y) }

      # Store viewport StickyMath outputs for reposition_sticky_cells
      @viewport_col_offset = col_offset
      @viewport_col_positions = col_positions
      @viewport_col_shifting_index = col_shifting_index
      @viewport_row_offset = row_offset
      @viewport_row_positions = row_positions
      @viewport_row_shifting_index = row_shifting_index

      # Early-exit check: use exact visible indices for correctness
      # Placed BEFORE creation/destruction sticky calls to avoid O(n) work per scroll frame.
      # Include physical viewport boundary: last physical column/row whose left edge is
      # within the viewport. This detects when a new physical column enters from the right
      # edge even though the sticky cache key (scroll-order based) hasn't changed.
      # Without this, compound header cells at the right edge aren't created for ~3 scroll steps.
      last_phys_col = col_physical_cum.bsearch_index { |p| p > max_x }
      last_phys_row = row_physical_cum.bsearch_index { |p| p > max_y }
      visible_key = {visible_rows, visible_cols, last_phys_col, last_phys_row}
      # An ancestor collapse (e.g. the enclosing "Perspective" TreeNode section closing) zeros the
      # matrix's cell bounds DIRECTLY — without going through this matrix's perform_layout — so on
      # re-expand the visible-index key is UNCHANGED and the early-exit below would leave the cells at
      # 0×0, where the zero-size collect guard drops the whole body (only a sticky Rank column survives:
      # blank on SFML, whose culled RenderTexture didn't persist; retained headless). The early-exit's
      # premise (active cells are validly laid out) is then false, so re-run the creation loop, which
      # re-lays-out any zeroed cell. O(1) probe of one active cell; a normal scroll/resize is untouched.
      first = @active_cells.first?
      cells_zeroed = !first.nil? && (first[1].bounds.width <= 0.0 || first[1].bounds.height <= 0.0)
      exact_indices_changed = @last_visible_key != visible_key || @force_cell_update || cells_zeroed

      {% if flag?(:DEBUG_BLIT) %}
        # Log early-exit decisions
        File.open("/tmp/blit_trace.log", "a") do |f|
          cell_11_exists = @active_cells.has_key?({1, 1})
          f.puts "UVC: scroll=#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)} changed=#{exact_indices_changed} cell_11=#{cell_11_exists}"
        end
      {% end %}

      # Early exit if visible indices haven't changed
      unless exact_indices_changed
        {% if flag?(:PERF_LOG) %}
          _uvc_elapsed = (Time.monotonic - _uvc_start).total_milliseconds
          if _uvc_elapsed > 0.1
            File.open("/tmp/uvc_perf.txt", "a") { |f| f.puts "UVC EARLY-EXIT: #{_uvc_elapsed.round(2)}ms scroll=#{scroll_offset.x.round(0)},#{scroll_offset.y.round(0)} active=#{@active_cells.size} sync=#{@layer_widgets_need_sync}" }
          end
        {% end %}
        {% if flag?(:CURSOR_PERF) %}
          _uvc_elapsed = (Time.monotonic - _uvc_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "  UVC(early-exit): #{_uvc_elapsed.round(2)}ms active=#{@active_cells.size}" }
        {% end %}
        # Update visual states for cursor/highlight (lightweight, O(active_cells))
        if sticky_cells_can_use_blit_plan?
          compute_sticky_blit_plans
        else
          reposition_sticky_cells
        end
        # Bug 2 fix: Ensure layer.widgets is synced even on early-exit
        # After rebuild, new layer has empty widgets but active_cells may exist
        ensure_layer_widgets_synced
        return
      end

      # Update cache AFTER check
      @last_visible_key = visible_key
      @force_cell_update = false

      sticky_cols_val = sticky_col_count
      sticky_rows_val = sticky_row_count

      # Compute creation/destruction regions with hysteresis buffering.
      # Creation region (CREATION_BUFFER) ⊂ Destruction region (DESTRUCTION_BUFFER),
      # so cells are created before they become visible and only destroyed well past the edge.
      creation_cols = compute_region_cached(CREATION_BUFFER, viewport_width, scroll_offset.x,
        col_cumulative, col_physical_cum, col_scroll_rank, sticky_cols_val,
        @last_creation_col_key, @last_creation_col_result) { |k, r| @last_creation_col_key = k; @last_creation_col_result = r }
      creation_rows = compute_region_cached(CREATION_BUFFER, viewport_height, scroll_offset.y,
        row_cumulative, row_physical_cum, row_scroll_rank, sticky_rows_val,
        @last_creation_row_key, @last_creation_row_result) { |k, r| @last_creation_row_key = k; @last_creation_row_result = r }
      destruction_cols = compute_region_cached(DESTRUCTION_BUFFER, viewport_width, scroll_offset.x,
        col_cumulative, col_physical_cum, col_scroll_rank, sticky_cols_val,
        @last_destruction_col_key, @last_destruction_col_result) { |k, r| @last_destruction_col_key = k; @last_destruction_col_result = r }
      destruction_rows = compute_region_cached(DESTRUCTION_BUFFER, viewport_height, scroll_offset.y,
        row_cumulative, row_physical_cum, row_scroll_rank, sticky_rows_val,
        @last_destruction_row_key, @last_destruction_row_result) { |k, r| @last_destruction_row_key = k; @last_destruction_row_result = r }

      # Only manage cell widgets if we have an adapter AND indices changed
      # (Skip expensive cell creation/destruction if same cells are visible)
      if @adapter
        # Determine which cells should be created (using creation region)
        creation_cells = Set(Tuple(Int32, Int32)).new
        creation_rows.each do |row|
          creation_cols.each do |col|
            creation_cells << {row, col}
          end
        end

        # Determine which cells should be kept alive (using destruction region)
        keep_alive_cells = Set(Tuple(Int32, Int32)).new
        destruction_rows.each do |row|
          destruction_cols.each do |col|
            keep_alive_cells << {row, col}
          end
        end

        # Filter to only "handle" cells using dynamic handle (first visible cell of merged region).
        # For merged cells: when the top-left scrolls out, the first visible cell takes over.
        # This ensures compound cells remain visible as long as any part is in the viewport.
        # For NON-merged cells: always use cell itself as handle (dynamic handle only applies
        # to merged cells where the visible representative shifts as parts scroll out).
        # Bug 2h: dynamic_handle_cell was returning nil for non-merged cells in the creation
        # buffer but outside the viewport, preventing their creation → blank rows on cursor-up.
        handle_cells = Set(Tuple(Int32, Int32)).new
        sticky_rows_val = sticky_row_count
        sticky_cols_val = sticky_col_count
        creation_cells.each do |cell|
          bounding = get_bounding_box(cell)
          is_merged = bounding[0] != bounding[1]

          if is_merged
            # For sticky compound cells, always use the top-left as the permanent widget key.
            # The dynamic handle mechanism (which shifts the key as rows scroll out) causes
            # destroy+create cycles that produce visual snapping. Sticky cells don't need it
            # because they aren't subject to viewport_cache buffer limits.
            is_sticky = (bounding[0][0] < sticky_rows_val || bounding[0][1] < sticky_cols_val)
            if is_sticky
              topleft = bounding[0]
              next if handle_cells.includes?(topleft)

              min_row, min_col = bounding[0]
              max_row, max_col = bounding[1]
              rows_intersect = (min_row..max_row).any? { |r| creation_rows.includes?(r) }
              cols_intersect = (min_col..max_col).any? { |c| creation_cols.includes?(c) }
              handle_cells << topleft if rows_intersect && cols_intersect
            else
              # Content (non-sticky) merged cells: use dynamic handle
              handle = dynamic_handle_cell(cell, row_shifted, col_shifted)
              next unless handle  # Merged region entirely invisible
              next if handle_cells.includes?(handle)  # Already added

              min_row, min_col = bounding[0]
              max_row, max_col = bounding[1]
              rows_intersect = (min_row..max_row).any? { |r| creation_rows.includes?(r) }
              cols_intersect = (min_col..max_col).any? { |c| creation_cols.includes?(c) }
              handle_cells << handle if rows_intersect && cols_intersect
            end
          else
            # Non-merged cell: cell is its own handle, always include
            handle_cells << cell
          end
        end
        keep_alive_handles = Set(Tuple(Int32, Int32)).new
        keep_alive_cells.each do |cell|
          bounding = get_bounding_box(cell)
          if bounding[0] != bounding[1]
            # Merged cell: sticky compounds use top-left, content compounds use dynamic handle
            is_sticky = (bounding[0][0] < sticky_rows_val || bounding[0][1] < sticky_cols_val)
            if is_sticky
              keep_alive_handles << bounding[0]
            elsif is_dynamic_handle_cell?(cell, row_shifted, col_shifted)
              keep_alive_handles << cell
            end
          else
            # Non-merged cell: always its own handle
            keep_alive_handles << cell
          end
        end

        # Destroy cells that are outside the destruction buffer (larger hysteresis region)
        cells_to_remove = @active_cells.keys.reject { |key| keep_alive_handles.includes?(key) }
        cells_destroyed = cells_to_remove.size > 0
        {% if flag?(:DEBUG_BLIT) %}
          # Log when cells are created or destroyed
          new_cells_set = handle_cells.reject { |h| @active_cells.has_key?(h) }
          if cells_to_remove.size > 0 || new_cells_set.size > 0
            File.open("/tmp/blit_trace.log", "a") do |f|
              f.puts "CELL_CHANGE: scroll=#{scroll_offset}"
              f.puts "  creating=#{new_cells_set.to_a.sort}" if new_cells_set.size > 0
              f.puts "  destroying=#{cells_to_remove.to_a.sort}" if cells_to_remove.size > 0
            end
          end
          # Log active cells at scroll=0
          if scroll_offset.x < 1.0
            File.open("/tmp/blit_trace.log", "a") do |f|
              f.puts "ACTIVE_CELLS_AT_0: #{@active_cells.keys.to_a.sort}"
            end
          end
        {% end %}
        cells_to_remove.each do |key|
          if widget = @active_cells.delete(key)
            # Clear proxy focus if the destroyed cell had it
            if @proxy_focused_widget == widget
              commit_proxy_edit
              widget.deactivate_proxy_focus
              @proxy_focused_widget = nil
              @proxy_focused_rc = nil
            end
            widget.render_layer = nil
            widget.parent = nil
            @children.delete(widget)
          end
        end

        compound_visible_sizes, compound_clipped_pos = compute_compound_visible_sizes(
          handle_cells, visible_cols, visible_rows,
          col_sizes, row_sizes,
          col_offset, col_positions, col_shifting_index,
          row_offset, row_positions, row_shifting_index,
          row_shifted, col_shifted)

        # Create cells that are newly visible and are handle cells
        # Layout each cell inline when created (fixed content-space position)
        cells_created = false
        new_cells_count = 0
        # Track newly created cells for targeted rendering
        new_cells = [] of Widget
        adapter = @adapter.not_nil!
        handle_cells.each do |key|
          existing = @active_cells[key]?
          # Already present AND validly laid out → nothing to do. But a cell whose bounds were
          # zeroed by an ancestor collapse (TreeNode zeros its children on collapse) survives in
          # @active_cells at 0×0; collect_all_widgets_recursive's zero-size guard then drops it, so
          # it never re-renders → blank rows after collapse → expand → grow (healed only by a zoom,
          # which rebuilds every cell). Re-use the widget (its cached texture stays valid) and fall
          # through to re-run layout below, restoring its bounds.
          next if existing && existing.bounds.width > 0.0 && existing.bounds.height > 0.0

          row, col = key
          # Normalize to canonical top-left, so adapters always receive
          # the correct cell coordinates (not the dynamic handle).
          canonical = get_top_left_cell(key)
          cell = existing || adapter.cell_paint(canonical[0], canonical[1])

          unless existing
            cells_created = true
            new_cells_count += 1
            cell.parent = self
            @children << cell
            @active_cells[key] = cell
          end
          new_cells << cell  # Track for targeted rendering (new or re-laid-out)

          # Layout the NEW cell at its FIXED content-space position.
          # Use canonical (bounding-box top-left), not the dynamic-handle key:
          # for a merged cell, the dynamic handle migrates as scroll progresses
          # while the cell's content-space rect is anchored to its top-left.
          # Using key.row/col here would slide the cell off its cluster, leaving
          # cached pixels at the wrong content y after the next scroll cycle.
          x = ruler_col_width_pixels.to_i + col_physical_cum[canonical[1]]
          y = ruler_row_height_pixels.to_i + row_physical_cum[canonical[0]]
          bounding = get_bounding_box(key)

          # Use visible compound size if available (partial scroll shrinking)
          # Bug A fix: Content cells (non-sticky) use FIXED sizes in content space;
          # only sticky cells need viewport-relative sizing.
          is_content_cell = row >= sticky_row_count && col >= sticky_col_count
          if !is_content_cell && (compound_size = compound_visible_sizes[key]?)
            cell_width = compound_size[0]
            cell_height = compound_size[1]
            # Use clipped position for compound cells
            if clipped = compound_clipped_pos[key]?
              x = clipped[0].to_i32
              y = clipped[1].to_i32
            end
          else
            cell_width = calculate_merged_width(bounding, col_sizes)
            cell_height = calculate_merged_height(bounding, row_sizes)
          end
          cell_constraints = BoxConstraints.tight(Size.new(cell_width - grid_spacing, cell_height - grid_spacing))
          cell.layout(cell_constraints, Vec2.new(x.to_f64, y.to_f64))
          {% if flag?(:DEBUG_BLIT) %}
            if key == {1, 1}
              File.open("/tmp/blit_trace.log", "a") do |f|
                f.puts "CELL_LAYOUT(1,1): x=#{x} y=#{y} col_offset=#{creation_col_offset} col_positions[1]=#{creation_col_positions[1]?} scroll=#{scroll_offset}"
              end
            end
          {% end %}
        end

        # Re-layout existing content cells during resize drag.
        # set_col_width_for_drag / set_row_height_for_drag skip mark_needs_layout,
        # so existing cells keep stale bounds. Update them here (O(active_cells)).
        if resize_axis != ResizeAxis::None
          sticky_rows_val = sticky_row_count
          sticky_cols_val = sticky_col_count

          # Whole pixels the resized line's leading edge moved since the buffer was last composited
          # (accumulated by the drag setters; telescopes to an exact integer). Consumed once per frame.
          shift_delta = @resize_pending_shift_px
          @resize_pending_shift_px = 0

          # A content-layer blit-shift replaces the whole-layer clear for any COLUMN or ROW resize
          # (widen or shrink, data OR sticky line) with no compound cell straddling the boundary. A sticky
          # resize shifts the whole data area, which on the content layer is the same single-axis
          # translation (its sticky region holds no content cells — just background). The sticky-header
          # layers reflow via their own path. Any disqualifier flips this off and the layer clears as
          # before. (doc/plans/resize-blit-shift.md.)
          can_shift = shift_delta != 0 && !resize_axis.none?

          size_changed_cells = [] of Widget

          @active_cells.each do |key, widget|
            next if new_cells.includes?(widget) # Already laid out above
            row, col = key
            # Only content cells — sticky cells handled by reposition_sticky_cells
            next unless row >= sticky_rows_val && col >= sticky_cols_val

            bounding = get_bounding_box(key)

            # Skip cells entirely unaffected (left of resized col / above resized row)
            case resize_axis
            when ResizeAxis::Col
              next if bounding[1][1] < resize_index # max_col < resized col
            when ResizeAxis::Row
              next if bounding[1][0] < resize_index # max_row < resized row
            end

            # Cells whose span INCLUDES the resized line changed size → re-render.
            size_changed = case resize_axis
                           when ResizeAxis::Col
                             bounding[0][1] <= resize_index && resize_index <= bounding[1][1]
                           when ResizeAxis::Row
                             bounding[0][0] <= resize_index && resize_index <= bounding[1][0]
                           else false
                           end

            if can_shift && !size_changed
              # A line entirely PAST the resized one: it only MOVES (by shift_delta along the resize
              # axis). Translate its bounds WITHOUT invalidation — handle_content_resize_shift moves its
              # buffer pixels + slot stamp in lockstep, so re-rendering it would be wasted work (the point
              # of the shift). (layout()'s position-only path would dispose its background + needs_render.)
              if resize_axis.col?
                widget.shift_bounds(shift_delta.to_f64, 0.0)
              else
                widget.shift_bounds(0.0, shift_delta.to_f64)
              end
            else
              # The resized line (re-renders at its new size) or the clear-path fallback: re-lay-out to
              # the exact new geometry so a full clear+render is correct.
              x = ruler_col_width_pixels.to_i + col_physical_cum[col]
              y = ruler_row_height_pixels.to_i + row_physical_cum[row]
              cell_width = calculate_merged_width(bounding, col_sizes)
              cell_height = calculate_merged_height(bounding, row_sizes)
              cell_constraints = BoxConstraints.tight(Size.new(cell_width - grid_spacing, cell_height - grid_spacing))
              widget.layout(cell_constraints, Vec2.new(x.to_f64, y.to_f64))
            end

            if size_changed
              widget.invalidate_primitive_cache
              size_changed_cells << widget
            end
          end

          content = @content_layer
          if content && can_shift
            # Dispose the resized line's cached backends so the selective render repaints them fresh
            # (nil widget_backend → full render path); the surrounding columns are translated by the
            # buffer blit-shift in handle_content_resize_shift. Nulling background_backend forces a
            # fresh background capture (else a moved/re-rendered cell re-imprints a stale clipped edge).
            size_changed_cells.each do |cell|
              cell.widget_backend.try(&.dispose)
              cell.widget_backend = nil
              cell.background_backend.try(&.dispose)
              cell.background_backend = nil
            end
            if resize_axis.col?
              boundary_local = ruler_col_width_pixels.to_i + col_physical_cum[resize_index + 1]
              content.mark_needs_resize_shift(ResizeShift.new(ShiftAxis::Horizontal, boundary_local, shift_delta, grid_spacing))
            else
              boundary_local = ruler_row_height_pixels.to_i + row_physical_cum[resize_index + 1]
              content.mark_needs_resize_shift(ResizeShift.new(ShiftAxis::Vertical, boundary_local, shift_delta, grid_spacing))
            end
          else
            # Clear buffer (erases ghost pixels at old positions) and trigger full render.
            # Most cells hit the fast path (blit cached widget_backend) — only size-changed
            # cells do full re-render.
            content.try(&.mark_needs_clear_and_render)
          end
        end

        # Re-layout existing COMPOUND cells with updated visible sizes
        # Only sticky compound cells need re-layout because their visible portion changes with scroll.
        # Content compound cells have FIXED sizes in content space; buffer_origin handles viewport shift.
        if compound_visible_sizes.any?
          sticky_rows_val = sticky_row_count
          sticky_cols_val = sticky_col_count
          @active_cells.each do |key, widget|
            next unless compound_visible_sizes.has_key?(key)
            next if new_cells.includes?(widget)  # Already laid out above

            row, col = key
            # Bug A fix: Content cells have fixed sizes — only re-layout sticky compound cells
            next if row >= sticky_rows_val && col >= sticky_cols_val
            # Use absolute content positions from pre-computed cumulative arrays
            x = col_physical_cum[col]
            y = row_physical_cum[row]

            compound_size = compound_visible_sizes[key]
            cell_width = compound_size[0]
            cell_height = compound_size[1]
            if clipped = compound_clipped_pos[key]?
              x = clipped[0].to_i32
              y = clipped[1].to_i32
            end
            cell_constraints = BoxConstraints.tight(Size.new(cell_width - grid_spacing, cell_height - grid_spacing))
            widget.layout(cell_constraints, Vec2.new(x.to_f64, y.to_f64))
          end
        end
        # Update visual states for all cells

        # Reposition sticky cells to account for scroll offset
        # Sticky layers are non-viewport_cache, so cells need screen-space positions.
        # The blit-plan now runs during a resize too: the resized line's header (stale-size cached
        # texture) is routed to render_list by compute_sticky_blit_plans; every other sticky cell merely
        # moved → its cached texture is blitted at the new position, instead of a full sticky-layer clear
        # + re-render of every header. (reposition_sticky_cells stays the fallback when nothing blits.)
        if sticky_cells_can_use_blit_plan?
          compute_sticky_blit_plans
        else
          reposition_sticky_cells
        end

        # Sync cell widgets to appropriate layers and mark new cells for render
        if cells_created || cells_destroyed || @active_cells.any?
          sync_cells_to_layers(new_cells)

          if new_cells_count > 0
            @@update_visible_cells_call_count += 1
          end
          if @proxy_focused_widget.nil? && focused?
            update_proxy_focus
          end
        end
      end
      {% if flag?(:PERF_LOG) %}
        _uvc_elapsed = (Time.monotonic - _uvc_start).total_milliseconds
        if _uvc_elapsed > 0.1
          File.open("/tmp/uvc_perf.txt", "a") { |f| f.puts "UVC FULL: #{_uvc_elapsed.round(2)}ms scroll=#{scroll_offset.x.round(0)},#{scroll_offset.y.round(0)} active=#{@active_cells.size} new=#{new_cells_count || 0}" }
        end
      {% end %}
      {% if flag?(:CURSOR_PERF) %}
        _uvc_elapsed = (Time.monotonic - _uvc_start).total_milliseconds
        File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "  UVC(full): #{_uvc_elapsed.round(2)}ms active=#{@active_cells.size} new=#{new_cells_count || 0} destroyed=#{cells_to_remove.try(&.size) || 0}" }
      {% end %}
      # Cells enter and leave @children here, not via add_child/remove_child, and this runs from
      # pre_render_flush as well as from perform_layout — so the bottom-up recompute in Widget#layout
      # can miss a cell that appeared after this matrix was laid out. Re-close the dependency over the
      # current cell set: cell_paint is app-supplied, so the library cannot assume a cell never holds a
      # wrapping layout.
      refresh_subtree_layout_dependency
    end

    # Repopulate all layer widget lists from @active_cells, assigning each cell
    # to content/sticky layers by position, then optionally mark new_cells for render.
    # When render_all is true (deferred sync), marks ALL cells for render.
    private def sync_cells_to_layers(new_cells : Array(Widget)? = nil, render_all : Bool = false)
      content_layer = @content_layer
      return unless content_layer

      sv = @content_scroll_view
      sticky_row_layer = sv.try(&.sticky_row_layer)
      sticky_col_layer = sv.try(&.sticky_col_layer)
      sticky_corner_layer = sv.try(&.sticky_corner_layer)

      content_layer.widgets.clear
      sticky_row_layer.try(&.widgets.clear)
      sticky_col_layer.try(&.widgets.clear)
      sticky_corner_layer.try(&.widgets.clear)

      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count

      @active_cells.each do |key, widget|
        row, col = key
        layer = get_cell_layer(row, col, sticky_rows, sticky_cols,
                               content_layer, sticky_row_layer, sticky_col_layer, sticky_corner_layer)
        layer.try do |l|
          l.widgets << widget
          widget.render_layer = l
        end
      end
      add_ruler_widgets_to_layers
      @layer_widgets_need_sync = false

      # Mark cells for render: either new cells only (creation path) or all cells (deferred sync)
      cells_to_render = render_all ? @active_cells.values : (new_cells || [] of Widget)
      cells_to_render.each do |cell|
        key = @active_cells.key_for?(cell)
        next unless key
        row, col = key
        layer = get_cell_layer(row, col, sticky_rows, sticky_cols,
                               content_layer, sticky_row_layer, sticky_col_layer, sticky_corner_layer)
        layer.try(&.mark_needs_render(cell))
      end

      {% if flag?(:DEBUG_BLIT) %}
        if scroll_offset.x < 1.0
          File.open("/tmp/blit_trace.log", "a") do |f|
            content_count = content_layer.widgets.size
            f.puts "FINAL_STATE: scroll=#{scroll_offset} active=#{@active_cells.size} content_layer=#{content_count}"
            if cell_1_1 = @active_cells[{1, 1}]?
              f.puts "  CELL(1,1): bounds=#{cell_1_1.bounds} has_backend=#{!cell_1_1.widget_backend.nil?}"
            end
          end
        end
      {% end %}
    end

    # Bug 2 fix: Ensure layer.widgets matches @active_cells.
    # Called on early-exit path when no cells created/destroyed but layer may be fresh.
    private def ensure_layer_widgets_synced
      return unless @layer_widgets_need_sync
      return if @active_cells.empty?
      sync_cells_to_layers(render_all: true)
    end

    # Determine which layer a cell should be assigned to based on sticky configuration
    private def get_cell_layer(
      row : Int32,
      col : Int32,
      sticky_rows : Int32,
      sticky_cols : Int32,
      content_layer : Layer?,
      sticky_row_layer : Layer?,
      sticky_col_layer : Layer?,
      sticky_corner_layer : Layer?
    ) : Layer?
      is_sticky_row = row < sticky_rows
      is_sticky_col = col < sticky_cols

      if is_sticky_row && is_sticky_col
        # Corner cell - fixed position
        sticky_corner_layer || content_layer
      elsif is_sticky_row
        # Header row cell - scrolls X only
        sticky_row_layer || content_layer
      elsif is_sticky_col
        # Header column cell - scrolls Y only
        sticky_col_layer || content_layer
      else
        # Normal content cell - scrolls both X and Y
        content_layer
      end
    end

    # Variable size helpers (include grid spacing)
    private def col_width_pixels(col : Int32) : Float64
      grid_spacing + get_col_width(col) * frame_height
    end

    # Embedded shrink_to_content tables clip horizontally rather than scrolling
    # or scaling: columns keep their natural width, and when the panel is too
    # narrow the right-most columns are simply cut off (no horizontal scrollbar,
    # no horizontal scroll). The full data grid (shrink_to_content == false)
    # scrolls both ways as usual.
    private def horizontal_clip? : Bool
      @shrink_to_content
    end

    private def row_height_pixels(row : Int32) : Float64
      grid_spacing + get_row_height(row) * frame_height
    end

    # Calculate total width for a merged cell region
    # Compute visible indices in a buffered region around the scroll offset, with caching.
    # The cache key is {num_shifted, index_beyond} from bsearch — only recomputes when
    # a boundary element shifts in or out of the region.
    # Yields (key, result) to store in caller-specific cache instance variables.
    private def compute_region_cached(
        buffer : Float64, viewport_size : Float64, scroll_pos : Float64,
        cumulative : Array(Int32), physical_cum : Array(Int32),
        scroll_rank : Array(Int32), sticky_count : Int32,
        last_key : Tuple(Int32, Int32?)?, last_result : Array(Int32)?,
        & : Tuple(Int32, Int32?), Array(Int32) ->
    ) : Array(Int32)
      min_pos = (scroll_pos - buffer).floor.to_i32.clamp(0, Int32::MAX)
      max_pos = (scroll_pos + viewport_size + buffer).ceil.to_i32

      ns = cumulative.bsearch_index { |p| p >= min_pos } || scroll_rank.size
      ib = cumulative.bsearch_index { |p| p > max_pos }
      key = {ns, ib}

      if last_key == key && last_result
        return last_result
      end

      result = Widgets::VirtualMatrix::StickyMath.visible_indices_in_range(
        physical_cum, scroll_rank, ns, min_pos, max_pos, sticky_count)
      result = result.select { |i| i < sticky_count || (physical_cum[i] < max_pos && physical_cum[i + 1] > min_pos) }
      yield key, result
      result
    end

    private def calculate_merged_width(bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)), col_sizes : Array(Int32)) : Float64
      min_col = bounding[0][1]
      max_col = bounding[1][1]
      (min_col..max_col).sum { |c| col_sizes[c]? || col_width_pixels(c).to_i32 }.to_f64
    end

    # Calculate total height for a merged cell region
    private def calculate_merged_height(bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)), row_sizes : Array(Int32)) : Float64
      min_row = bounding[0][0]
      max_row = bounding[1][0]
      (min_row..max_row).sum { |r| row_sizes[r]? || row_height_pixels(r).to_i32 }.to_f64
    end

    # === Compute visible compound sizes using viewport StickyMath ===
    #
    # Compound (merged) cells span multiple rows/columns. When partially scrolled
    # off-screen, their visible size shrinks. This computes {width, height} for each
    # compound cell by summing the pixel sizes of its constituent columns/rows that
    # are currently visible, minus any clipping at the shifting edge.
    #
    # Returns: {compound_visible_sizes, compound_clipped_pos}
    private def compute_compound_visible_sizes(
        handle_cells : Set(Tuple(Int32, Int32)),
        visible_cols : Array(Int32), visible_rows : Array(Int32),
        col_sizes : Array(Int32), row_sizes : Array(Int32),
        col_offset : Int32, col_positions : Hash(Int32, Int32), col_shifting_index : Int32,
        row_offset : Int32, row_positions : Hash(Int32, Int32), row_shifting_index : Int32,
        row_shifted : ShiftedSet, col_shifted : ShiftedSet
    ) : {Hash(Tuple(Int32, Int32), {Float64, Float64}), Hash(Tuple(Int32, Int32), {Float64, Float64})}
      compound_visible_sizes = Hash(Tuple(Int32, Int32), {Float64, Float64}).new
      compound_clipped_pos = Hash(Tuple(Int32, Int32), {Float64, Float64}).new

      visible_col_set = visible_cols.to_set
      visible_row_set = visible_rows.to_set

      handle_cells.each do |handle_key|
        bounding = get_bounding_box(handle_key)
        next if bounding[0] == bounding[1]  # Skip non-merged

        handle = dynamic_handle_cell(handle_key, row_shifted, col_shifted)
        next unless handle

        w = 0.0
        h = 0.0

        # Accumulate width from visible columns in bounding box
        (bounding[0][1]..bounding[1][1]).each do |ci|
          next unless visible_col_set.includes?(ci)

          pos_x = (col_offset + (col_positions[ci]? || 0)).to_f64
          pos_clipped_x = pos_x
          if ci == col_shifting_index
            pos_clipped_x = {scroll_offset.x, pos_x}.max
          end

          w += col_sizes[ci].to_f64 + (pos_x - pos_clipped_x)

          if ci == handle[1]
            pos_clipped_y_for_handle = (row_offset + (row_positions[handle[0]]? || 0)).to_f64
            if handle[0] == row_shifting_index
              pos_clipped_y_for_handle = {scroll_offset.y, pos_clipped_y_for_handle}.max
            end
            compound_clipped_pos[handle_key] = {pos_clipped_x, pos_clipped_y_for_handle}
          end
        end

        # Accumulate height from visible rows in bounding box
        (bounding[0][0]..bounding[1][0]).each do |ri|
          next unless visible_row_set.includes?(ri)

          pos_y = (row_offset + (row_positions[ri]? || 0)).to_f64
          pos_clipped_y = pos_y
          if ri == row_shifting_index
            pos_clipped_y = {scroll_offset.y, pos_y}.max
          end

          h += row_sizes[ri].to_f64 + (pos_y - pos_clipped_y)
        end

        compound_visible_sizes[handle_key] = {w, h} if w > 0 && h > 0
      end

      {compound_visible_sizes, compound_clipped_pos}
    end

    # Total content dimensions (cached for performance)
    # Includes ruler offset since content cells are positioned at ruler_offset + col_cum
    private def total_content_width : Float64
      @cached_total_width ||= ruler_col_width_pixels + (0...@cols).sum { |c| col_width_pixels(c) }
    end

    private def total_content_height : Float64
      @cached_total_height ||= ruler_row_height_pixels + (0...@rows).sum { |r| row_height_pixels(r) }
    end

    # Compute content dimensions excluding scrollbar space.
    # Two-pass: one scrollbar appearing may trigger the other.
    private def effective_content_size(full_width : Float64, full_height : Float64) : Tuple(Float64, Float64)
      w = full_width
      h = full_height
      needs_vscroll = total_content_height > h
      # A horizontally clipping matrix (shrink_to_content) has no horizontal
      # scrollbar — it clips overflow. Reserving height for a scrollbar that
      # never appears made the matrix lose 16px of height (rows popping in/out)
      # whenever the panel width crossed the content-fits threshold.
      needs_hscroll = horizontal_clip? ? false : (total_content_width > w)
      if needs_vscroll
        w -= ScrollView::SCROLLBAR_WIDTH
        needs_hscroll = total_content_width > w unless needs_hscroll || horizontal_clip?
      end
      if needs_hscroll
        h -= ScrollView::SCROLLBAR_WIDTH
        needs_vscroll = total_content_height > h unless needs_vscroll
      end
      w -= ScrollView::SCROLLBAR_WIDTH if needs_vscroll && w == full_width
      h -= ScrollView::SCROLLBAR_WIDTH if needs_hscroll && h == full_height
      {w, h}
    end

    # Invalidate dimension caches (call when sizes change)
    private def invalidate_dimension_caches
      @cached_total_width = nil
      @cached_total_height = nil
      @cached_col_sizes = nil
      @cached_row_sizes = nil
      @cached_col_cumulative = nil
      @cached_row_cumulative = nil
      @cached_col_physical_cum = nil
      @cached_row_physical_cum = nil
      @cached_col_scroll_order = nil
      @cached_row_scroll_order = nil
      @last_col_sticky_key = nil
      @last_row_sticky_key = nil
      @last_col_sticky_result = nil
      @last_row_sticky_result = nil
      @cached_col_shifted = nil
      @cached_row_shifted = nil
      @cached_col_scroll_rank = nil
      @cached_row_scroll_rank = nil
      @last_creation_col_key = nil
      @last_creation_row_key = nil
      @last_creation_col_result = nil
      @last_creation_row_result = nil
      @last_destruction_col_key = nil
      @last_destruction_row_key = nil
      @last_destruction_col_result = nil
      @last_destruction_row_result = nil
      @cached_sticky_row_count = nil
      @cached_sticky_col_count = nil
      @last_visible_key = nil
    end

    private def max_content_scroll_y : Float64
      viewport_height = @content_layer.try(&.bounds.height) || @bounds.height
      (total_content_height - viewport_height).clamp(0.0, Float64::MAX)
    end

    private def max_content_scroll_x : Float64
      return 0.0 if horizontal_clip? # clip horizontally — never scroll sideways
      viewport_width = @content_layer.try(&.bounds.width) || @bounds.width
      (total_content_width - viewport_width).clamp(0.0, Float64::MAX)
    end

    # === LAYER OWNER NOTIFICATION HANDLERS ===

    # Get z_index from parent layer (for proper z-ordering)
    private def parent_layer_z_index : Int32
      widget = self.parent
      while widget
        if widget.responds_to?(:layer)
          if layer = widget.layer
            return layer.z_index
          end
        end
        widget = widget.parent
      end
      0
    end

    # on_ancestor_position_changed no longer needed (pull-based bounds)

    def on_ancestor_z_index_changed(base_z : Int32)
      @content_layer.try { |l| l.z_index = base_z + CONTENT_LAYER_Z }
      @cursor_overlay_layer.try { |l| l.z_index = base_z + CURSOR_OVERLAY_Z }
      @drag_overlay_layer.try { |l| l.z_index = base_z + DRAG_OVERLAY_Z }

      # Propagate to ScrollView child (for scrollbar layer z-index)
      @content_scroll_view.try(&.on_ancestor_z_index_changed(base_z + 2))

      # Mark layer for re-render
      @content_layer.try(&.mark_needs_layout)
    end

    # === RECONCILIATION ===

    # Reconciliation: transfer state from the old widget instance to this new one.
    #
    # Preserved across rebuilds:
    #   - @scroll_offset, @cursor_rc (via @[Reconcile] properties + clamping)
    #   - @col_widths, @row_heights (user's drag-resize state, if grid dims match)
    #   - @last_zoom_factor (prevents false zoom transitions)
    #   - Layer ownership (content_layer.owner_widget → self)
    #   - Adapter invalidation callbacks (re-bound to new instance)
    #
    # Invalidated on rebuild:
    #   - All dimension caches (sizes, cumulative arrays, sticky results)
    #   - Active cells (force_cell_update triggers fresh creation)
    #   - VM layer buffers: cleared on an adapter-instance swap, or via the pending
    #     flush on an announced (or contract-violating) structural change
    def copy_state_from(old_widget : Widget)
      auto_copy_reconcile_properties(old_widget)
      super

      if old = old_widget.as?(VirtualMatrix)
        # The content/cursor/drag layers' owner_widget is re-adopted generically by
        # auto_copy_reconcile_properties (a stale owner drops the layer from
        # Layer.active_layers → invisible, and breaks pull-based bounds). Here we only
        # re-bind the overlay WIDGETS' back-reference to this new matrix instance.
        {@cursor_overlay_widget, @drag_overlay_widget}.each do |ow|
          ow.try do |w|
            w.matrix = self
            w.parent = self
          end
        end

        # Fix: Preserve zoom tracking so perform_layout doesn't see false 1.0→1.0
        # transition (new instance defaults @last_zoom_factor = 1.0)
        @last_zoom_factor = old.@last_zoom_factor

        # Transfer pending invalidation FIRST (e.g. an announce that fired on the old
        # widget before reconciliation rebound the adapter callbacks) — the contract
        # check below must see it. Without the transfer, flush_invalidate_all never
        # runs → layers keep stale pixels.
        @pending_invalidate_all = true if old.@pending_invalidate_all
        @pending_cell_invalidations.concat(old.@pending_cell_invalidations)

        # SIZE-CARRY (UX state, not the clear invariant): user drag-resize survives a
        # rebuild only while the grid dimensions still match — identity-INDEPENDENT, so
        # fresh-adapter-per-build apps keep their resize state too. On a dims drift keep
        # the constructor's fresh get_sizes arrays instead: a carried short array would
        # raise IndexError in the scroll clamp below (see fit_custom_sizes' history note).
        if old.rows == @rows && old.cols == @cols
          @col_widths = old.col_widths
          @row_heights = old.row_heights
        end

        # CLEAR (the invariant: no retained buffer pixel outlives its painter).
        if !old.adapter.same?(@adapter)
          # A swapped-in adapter instance has no announce history — deliberate heuristic
          # default: clear everything painted under the old adapter. The sizes carried
          # above survive (no flush runs, so no get_sizes overwrite).
          clear_all_vm_layers_for_invalidate
        elsif (old.rows != @rows || old.cols != @cols) && !@pending_invalidate_all
          # Same instance, dims drifted, nothing announced: MatrixAdapter contract
          # violation. Structural changes (dims, sizes, merges, scroll order) must be
          # announced via invalidate_all! at mutation time, before requesting the
          # rebuild that shows them. NOTE: this canary sees DIMS-drifting violations
          # only — a same-dims structural change is invisible at reconcile time.
          msg = "MatrixAdapter contract violation: #{@adapter.class} changed structure " \
                "(#{old.rows}x#{old.cols} -> #{@rows}x#{@cols}) behind matrix " \
                "'#{id || "unnamed"}' without invalidate_all! — announce structural " \
                "changes before requesting the rebuild; see VIRTUAL_MATRIX_ARCHITECTURE.md " \
                "\"Push-Based Adapter Invalidation\""
          {% if flag?(:verify_bounds) %}
            raise msg
          {% else %}
            # Release: degrade = late announce, routed through the ONE owner — the
            # pending flush clears every VM layer and re-reads dims + sizes. Pair the
            # flag with mark_needs_layout exactly like the announce callback (on_all):
            # the flush only runs when the content layer renders, and this rebuild has
            # nothing else that reliably wakes it.
            STDERR.puts "[MATRIX_ADAPTER_CONTRACT] #{msg}"
            @pending_invalidate_all = true
            mark_needs_layout
          {% end %}
        end
        @cached_total_width = nil
        @cached_total_height = nil
        invalidate_dimension_caches
        @force_cell_update = true

        # Clamp cursor to new matrix size if needed
        rc = cursor_rc
        row = rc[0].clamp(0, {@rows - 1, 0}.max)
        col = rc[1].clamp(0, {@cols - 1, 0}.max)
        self.cursor_rc = {row, col}

        # Clamp scroll offset to new grid bounds (e.g. after switching to smaller adapter)
        @scroll_offset.set(Vec2.new(
          scroll_offset.x.clamp(0.0, max_content_scroll_x),
          scroll_offset.y.clamp(0.0, max_content_scroll_y)
        ))

        # Rebind adapter callbacks to this (new) widget instance
        if adapter = @adapter
          bind_adapter_invalidation(adapter)
        end

        # Tear down the migrated proxy-focus pointer. auto_copy_reconcile_properties
        # copied @proxy_focused_widget/@proxy_focused_rc from the old widget, but they point
        # at a cell of the OLD tree — @active_cells is recreated fresh (@force_cell_update
        # above), so the dead pointer can never match a live cell. Every clear-guard is
        # `if @proxy_focused_widget == <live cell>`, and the re-establish in update_visible_cells
        # is gated `if @proxy_focused_widget.nil?` — so a non-nil dead pointer is never replaced,
        # silently routing forwarded text/keys to the orphan (lost edits). clear_proxy_focus
        # commits the in-flight edit to the (just-rebound) adapter — matching the other proxy
        # teardown paths (flush_invalidate_all, flush_cell_invalidations, zoom) — stops the
        # orphan's blink timer, and nils the pointers so proxy re-derives onto the live cursor
        # cell on the next update_visible_cells.
        clear_proxy_focus

        # Transfer cursor flash: cancel old timer, restart on new instance if focused.
        # Without this, invalidate_all! → rebuild orphans the timer on the dead instance.
        old.stop_cursor_flash_for_transfer
        start_cursor_flash if focused?
      end
    end

    # Default adapter for the (rows, cols) constructor.
    # Returns Text cells with "row,col" content.
    private class DefaultAdapter
      include Widgets::VirtualMatrix::HeaderlessMatrixAdapter

      def initialize(@rows : Int32, @cols : Int32)
      end

      def row_count : Int32
        @rows
      end

      def col_count : Int32
        @cols
      end

      def cell_paint(row : Int32, col : Int32) : Widget
        Text.new("#{row},#{col}")
      end
    end

  end
end
