require "./types"
require "./widget"
require "../rendering/render_backend"

module CrymbleUI
  # Entry in a blit-plan: describes one cached widget texture to blit onto a layer
  struct BlitEntry
    property source : RenderBackend
    property dest_x : Int32
    property dest_y : Int32
    property width : Int32
    property height : Int32

    def initialize(@source : RenderBackend, @dest_x : Int32, @dest_y : Int32)
      @width = source.width
      @height = source.height
    end
  end

  # Layer represents a render target with its own backend
  # Layers form a tree hierarchy and are composited by z-index
  #
  # Design principles:
  # - Each layer has content-sized backend (with buffer) for memory efficiency
  # - Absolute z-index determines rendering order (tree is for organization)
  # - Always dynamic rendering (re-render when contents change)
  # - Widgets own their layers (WindowPanel has @internal_layer)
  # - Backend is renderer-specific (SFML or test), assigned by renderer
  #
  # INVARIANT (siblings no-overlap):
  # - Sibling widgets within a layer MUST NOT have overlapping bounds
  # - This simplifies per-widget background memorization (no z-ordering conflicts)
  # - Future: will relax with explicit z-index for widget overlapping
  class Layer
    # Global registry of all layers (for efficient lookup without tree traversal)
    @@all_layers = Set(Layer).new

    # Identity
    property id : String
    property z_index : Int32

    # Spatial properties
    # bounds is pull-based: computed from owner_widget when available,
    # falls back to @cached_bounds for ownerless layers (drag ghost, initial creation)
    @cached_bounds : Rect
    property opacity : Float64 # 0.0 - 1.0
    property blend_mode : BlendMode

    # Pull-based bounds: ask owner widget for current bounds, fall back to cached
    def bounds : Rect
      if (owner = @owner_widget) && owner.responds_to?(:compute_bounds_for_layer)
        owner.compute_bounds_for_layer(self)
      else
        @cached_bounds
      end
    end

    # Setter: updates cached_bounds (used for drag ghost layer and initial creation)
    def bounds=(value : Rect)
      @cached_bounds = value
    end

    # Background color for buffer clearing (panel content area, over-allocated texture space)
    # Used instead of rendering full-panel background FillRect primitive
    # This prevents background from painting over cached children during selective rendering
    property background_color : Color

    # Rendering backend (assigned by renderer: CrSFMLBackend or TestRenderBackend)
    property backend : RenderBackend?

    # Track bounds from last render for change detection
    @last_rendered_bounds : Rect?

    # Baseline bounds captured at resize start for apply_resize_clip.
    # Prevents cumulative drift when last_rendered_bounds updates every frame.
    property resize_baseline : Rect?

    # Tree structure
    property parent : Layer?
    property children : Array(Layer)
    # Widgets directly in this layer (INVARIANT: siblings must not overlap)
    property widgets : Array(Widget)
    # Owner widget (e.g., WindowPanel that owns this layer)
    property owner_widget : Widget?

    # Blit-plan: when set, render_layer uses fast path (clear + blit cached textures)
    # instead of full widget render pipeline. Used for sticky layers on scroll.
    property blit_plan : Array(BlitEntry)? = nil
    # Widgets to render normally AFTER blit-plan blits (e.g., CachePolicy::Never rulers).
    # These are rendered through the full render_single_widget path after the blit-plan
    # handles data cells. This enables hybrid mode: blit cached cells + render fresh rulers.
    property blit_plan_render_widgets : Array(Widget)? = nil

    # State
    property state : WidgetState

    # Selective rendering: track which widgets are dirty
    getter dirty_widgets : Set(Widget)

    # Viewport cache support for efficient scrolling
    # When viewport_cache=true, the layer uses an oversized buffer:
    # - Buffer size = viewport + 2*cache_extent (extra pixels on each side)
    # - scroll_offset tracks viewport position in content space
    # - buffer_origin tracks which content coord is at buffer position (0,0)
    # - Enables O(1) scrolling (only render newly visible widgets, cached ones are blitted)
    @scroll_offset : Vec2 = Vec2.zero

    def scroll_offset : Vec2
      @scroll_offset
    end

    def scroll_offset=(value : Vec2)
      return if value == @scroll_offset
      @scroll_offset = value
      # Auto-mark viewport_cache layers for render when scroll changes,
      # so handle_viewport_cache_scroll runs and recenters buffer if needed.
      # Without this, scrollbar drag/wheel/arrow would set scroll_offset
      # without triggering buffer recenter — content appears stuck.
      if @viewport_cache
        if owner = @owner_widget
          mark_needs_render(owner)
        end
      end
    end

    # Skip clear on rebuild — for layers with CachePolicy::Never widgets that regenerate fresh.
    # Without this, app.rebuild clears ALL layers including overlays (expensive, unnecessary).
    property skip_rebuild_clear : Bool = false

    property viewport_cache : Bool = false
    property cache_extent : Float64 = 0.0     # Extra pixels to pre-render beyond viewport
    property buffer_origin : Vec2 = Vec2.zero # Content coord at buffer position (0,0)

    # Where inside the (oversized) buffer the visible viewport starts —
    # THE single source of truth for viewport-cache sampling, used by
    # the live compositor AND capture_composited_frame so they cannot
    # diverge (2026-06-05: the capture plain-blitted from (0,0) and
    # shifted every captured PNG of a viewport-cache layer by the cache
    # margin — the instrument was the bug, not the renderer).
    def viewport_sample_origin(buffer_width : Int32, buffer_height : Int32,
                               viewport_width : Int32, viewport_height : Int32) : {Int32, Int32}
      x = (@scroll_offset.x - @buffer_origin.x).to_i.clamp(0, {buffer_width - viewport_width, 0}.max)
      y = (@scroll_offset.y - @buffer_origin.y).to_i.clamp(0, {buffer_height - viewport_height, 0}.max)
      {x, y}
    end
    # Flag set during buffer recenter - widgets should fill with bg color, not capture from stale texture
    property buffer_just_cleared : Bool = false
    # Flag to force buffer clear on next render without NeedsLayout semantics.
    # Used by cursor overlay: old content must be erased (ghost bands) but
    # NeedsLayout is heavier than needed (forces sibling validation on first_render).
    property needs_clear : Bool = false

    def initialize(@id : String, @cached_bounds : Rect, @z_index : Int32 = 0, @background_color : Color = Color.new(0, 0, 0, 0), @owner_widget : Widget? = nil)
      @opacity = 1.0
      @blend_mode = BlendMode::Normal
      @parent = nil
      @children = [] of Layer
      @widgets = [] of Widget
      @backend = nil
      @state = WidgetState::NeedsLayout
      @dirty_widgets = Set(Widget).new

      # Register in global layer registry
      @@all_layers << self

      {% if flag?(:DEBUG_RENDER) %}
        puts "[LAYER CREATED: #{@id}, bg=#{@background_color}]"
      {% end %}
    end

    # Get all layers that are currently in the active widget tree
    # Filters out orphaned layers (from old widgets after rebuild)
    # O(k × d) where k = layers (~5-10), d = tree depth (~10-15)
    def self.active_layers(root : Widget) : Array(Layer)
      @@all_layers.select { |layer| layer.in_tree?(root) }.to_a
    end

    # Check if any layer in the registry needs rendering
    # More efficient than collecting all layers when we just need a boolean
    def self.any_needs_render?(root : Widget) : Bool
      @@all_layers.any? { |layer| layer.in_tree?(root) && layer.needs_render? }
    end

    # Remove layer from registry (called when layer is no longer needed)
    def unregister
      @@all_layers.delete(self)
    end

    # Clear all layers from registry (useful for tests)
    def self.clear_registry
      @@all_layers.clear
    end

    # Clean up orphaned layers from the registry
    # Called during app rebuild to prevent memory accumulation
    # An orphaned layer is one whose owner_widget is not in the active widget tree
    # This fixes the issue where rapid rebuilds cause @@all_layers to grow unboundedly
    def self.cleanup_orphaned_layers(root : Widget)
      # Collect orphaned layers (can't modify Set while iterating)
      orphaned = @@all_layers.reject { |layer| layer.in_tree?(root) }

      # Remove orphaned layers and dispose their backends
      orphaned.each do |layer|
        if backend = layer.backend
          backend.dispose # Release GPU memory
          layer.backend = nil
        end
        @@all_layers.delete(layer)

        {% if flag?(:DEBUG_RENDER) %}
          puts "[LAYER CLEANUP] Removed orphaned layer: #{layer.id}"
        {% end %}
      end

      {% if flag?(:DEBUG_RENDER) %}
        if !orphaned.empty?
          puts "[LAYER CLEANUP] Cleaned up #{orphaned.size} orphaned layers, #{@@all_layers.size} remain"
        end
      {% end %}
    end

    # Get current registry size (for debugging/metrics)
    def self.registry_size : Int32
      @@all_layers.size
    end

    # Remove orphaned widgets from all active layers.
    # After rebuild, reconciled layers may retain widgets from the old tree
    # (e.g., CursorOverlayWidget added to layer.widgets but not @[Reconcile]d).
    # New widgets get appended, old ones accumulate → stale rendering.
    def self.cleanup_orphaned_widgets(root : Widget)
      active_layers(root).each do |layer|
        original_size = layer.widgets.size
        layer.widgets.reject! do |widget|
          # Walk up parent chain — widget must be reachable from root
          current : Widget? = widget
          in_tree = false
          while current
            if current == root
              in_tree = true
              break
            end
            current = current.parent
          end
          !in_tree
        end
        {% if flag?(:DEBUG_RENDER) %}
          removed = original_size - layer.widgets.size
          if removed > 0
            puts "[WIDGET CLEANUP] Layer '#{layer.id}': removed #{removed} orphaned widgets (#{layer.widgets.size} remain)"
          end
        {% end %}
      end
    end

    # Check if this layer's owner widget is reachable from root
    # Returns true if layer is in the active widget tree
    def in_tree?(root : Widget) : Bool
      owner = @owner_widget
      return false unless owner

      # Walk up from owner to see if we reach root
      current : Widget? = owner
      while current
        return true if current == root
        current = current.parent
      end
      false
    end

    # Mark specific widget as needing re-render (selective rendering)
    # This is the SAFE default - only re-renders the specified widget
    # Rendering is confined to this layer - parent learns about changes during compositing
    def mark_needs_render(widget : Widget)
      @state = WidgetState::NeedsRender if @state == WidgetState::Clean
      @dirty_widgets << widget
      # NOTE: Do NOT propagate to parent layer - rendering is independent per layer
    end

    # Mark entire layer as needing full re-render
    # EXPENSIVE - use only when necessary (layout changes, etc.)
    # Full re-render stays within this layer - compositor handles layer changes
    def mark_needs_full_render
      {% if flag?(:DEBUG_RENDER) %}
        puts "[LAYER #{@id}] mark_needs_full_render called (clearing dirty_widgets)"
      {% end %}
      @state = WidgetState::NeedsRender if @state == WidgetState::Clean
      @dirty_widgets.clear # Empty set means "all dirty"
      # NOTE: Do NOT propagate to parent layer - rendering is independent per layer
    end

    # Mark layer as needing layout (structural change = full re-render)
    # Layout is confined to a single layer - does NOT propagate to parent layer
    def mark_needs_layout
      {% if flag?(:DEBUG_RENDER) %}
        puts "[LAYER #{@id}] mark_needs_layout called (clearing dirty_widgets for full re-render)"
      {% end %}
      @state = WidgetState::NeedsLayout
      @dirty_widgets.clear # Layout change = all widgets dirty (full re-render)
      # NOTE: Do NOT propagate to parent layer - layout is isolated per layer
    end

    # Mark layer for render with buffer clear (lighter than mark_needs_layout).
    # Clears the buffer to erase stale content (ghost bands) then renders all widgets.
    # Unlike mark_needs_layout: does NOT force sibling validation or disable viewport culling.
    def mark_needs_clear_and_render
      @state = WidgetState::NeedsRender if @state == WidgetState::Clean
      @dirty_widgets.clear # Empty set = render all widgets
      @needs_clear = true
    end

    # Check if layer needs rendering
    # A layer needs rendering if it's the first render OR has dirty state
    def needs_render? : Bool
      first_render? || @state == WidgetState::NeedsRender || @state == WidgetState::NeedsLayout
    end

    # Check if widget is dirty (needs re-rendering)
    # If dirty_widgets is empty, all widgets are dirty
    def widget_dirty?(widget : Widget) : Bool
      @dirty_widgets.empty? || @dirty_widgets.includes?(widget)
    end

    # Mark layer as clean (rendering complete)
    def clear_render_state
      @state = WidgetState::Clean
      @dirty_widgets.clear
      @needs_clear = false
      @last_rendered_bounds = bounds # Track bounds for change detection
    end

    # Check if bounds changed since last render
    def bounds_changed? : Bool
      @last_rendered_bounds != bounds
    end

    # Check if SIZE changed (not just position)
    def size_changed? : Bool
      last = @last_rendered_bounds
      return false if last.nil? # First render, not a "change"
      current = bounds
      last.width != current.width || last.height != current.height
    end

    # Check if current backend is large enough for current bounds
    def backend_fits_bounds? : Bool
      return false unless b = @backend
      b.width >= bounds.width.ceil.to_i && b.height >= bounds.height.ceil.to_i
    end

    # Get last rendered bounds (for debugging)
    def last_rendered_bounds : Rect?
      @last_rendered_bounds
    end

    # Check if this is the first render (never been rendered before)
    def first_render? : Bool
      @last_rendered_bounds.nil?
    end

    # Reset first_render flag (called when backend recreated)
    def reset_first_render
      @last_rendered_bounds = nil
    end

    # Restore first_render state (called when backend resized but content preserved)
    # Sets last_rendered_bounds to current bounds to indicate content exists
    def restore_first_render_state
      @last_rendered_bounds = bounds.dup
    end

    # Reset layer for recovery after exception (graceful degradation)
    # Clears: backend, dirty_widgets, last_rendered_bounds
    # Forces full re-render on next frame
    def reset_for_recovery
      @backend = nil
      @dirty_widgets.clear
      @last_rendered_bounds = nil
      @state = WidgetState::NeedsLayout
    end

    # Backend size calculation helpers for renderers
    # Returns desired backend size with over-allocation buffer (reduces reallocation during resize)
    def calculate_backend_size(content_width : Float64, content_height : Float64) : {Int32, Int32}
      buffer_factor = 0.2 # 20% over-allocation
      min_buffer = 50.0   # Minimum buffer in pixels

      width_buffer = [content_width * buffer_factor, min_buffer].max
      height_buffer = [content_height * buffer_factor, min_buffer].max

      backend_width = (content_width + width_buffer).to_i
      backend_height = (content_height + height_buffer).to_i

      {backend_width, backend_height}
    end

    # Calculate buffer size for viewport_cache layers including cache extent
    # Buffer = viewport + 2×cache_extent (margin on each side)
    def calculate_buffer_size_with_cache : {Int32, Int32}
      current = bounds
      width = (current.width + 2 * @cache_extent).ceil.to_i
      height = (current.height + 2 * @cache_extent).ceil.to_i
      {width, height}
    end

    # Check if backend needs recreation (size changed beyond buffer)
    def backend_needs_resize?(content_width : Float64, content_height : Float64) : Bool
      return true unless backend = @backend # No backend yet

      if @viewport_cache
        # For viewport_cache layers, compare required buffer size (includes cache extent)
        required_width, required_height = calculate_buffer_size_with_cache
        required_width > backend.width || required_height > backend.height
      else
        content_width > backend.width || content_height > backend.height
      end
    end

    # Coordinate wrapping (legacy, may not be used with viewport_cache approach)
    # Wraps coordinates to fit within texture bounds when viewport_cache mode is enabled
    # texture_width/height are the actual backend texture dimensions
    def wrap_coords(x : Float64, y : Float64, texture_width : Int32, texture_height : Int32) : {Int32, Int32}
      return {x.to_i, y.to_i} unless @viewport_cache

      # Use modulo for wrapping - Crystal handles negative numbers correctly
      wrapped_x = x.to_i % texture_width
      wrapped_y = y.to_i % texture_height

      {wrapped_x, wrapped_y}
    end

    # Get the viewport rectangle in content space
    # This represents what portion of the content is currently visible
    def viewport_rect : Rect
      current = bounds
      Rect.new(@scroll_offset.x, @scroll_offset.y, current.width, current.height)
    end

    # Check if a widget (by its bounds in content space) is visible in the viewport
    # include_cache: if true, considers widgets within cache_extent as visible (for pre-rendering)
    def widget_in_viewport?(widget_bounds : Rect, include_cache : Bool = false) : Bool
      viewport = viewport_rect

      if include_cache && @cache_extent > 0
        # Expand viewport by cache_extent on all sides
        expanded_viewport = Rect.new(
          viewport.x - @cache_extent,
          viewport.y - @cache_extent,
          viewport.width + @cache_extent * 2,
          viewport.height + @cache_extent * 2
        )
        rects_intersect?(widget_bounds, expanded_viewport)
      else
        rects_intersect?(widget_bounds, viewport)
      end
    end

    # Helper: check if two rectangles intersect
    private def rects_intersect?(a : Rect, b : Rect) : Bool
      !(a.x + a.width <= b.x ||  # a is left of b
        b.x + b.width <= a.x ||  # b is left of a
        a.y + a.height <= b.y || # a is above b
        b.y + b.height <= a.y)   # b is above a
    end

    # Concise inspect for readable spec output (prevents dumping widget arrays)
    def inspect(io : IO)
      io << "Layer(id=#{@id.inspect}, z=#{@z_index}, bounds=#{bounds}, widgets=#{@widgets.size})"
    end
  end
end
