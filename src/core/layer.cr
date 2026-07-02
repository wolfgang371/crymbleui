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

    # Background color for buffer clearing (panel content area, over-allocated texture space).
    # Used instead of rendering full-panel background FillRect primitive; prevents the background
    # from painting over cached children during selective rendering.
    # PULL-BASED (snapshot-drop, mirrors `bounds`): a theme-derived layer background would go
    # stale on a Theme.set, so the layer asks its owner for the live color via
    # compute_background_for_layer (nil = no theme override → use @cached_background_color). Ownerless
    # layers and non-theme owners use the cached value as before.
    @cached_background_color : Color

    def background_color : Color
      if (owner = @owner_widget) && owner.responds_to?(:compute_background_for_layer)
        owner.compute_background_for_layer(self) || @cached_background_color
      else
        @cached_background_color
      end
    end

    def background_color=(value : Color)
      @cached_background_color = value
    end

    # Rendering backend (assigned by renderer: CrSFMLBackend or TestRenderBackend)
    property backend : RenderBackend?

    # Track bounds from last render for change detection
    @last_rendered_bounds : Rect?

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

    # App-level pull: monotonic version of the scroll input, summed into frame_aggregate_rev so
    # a scroll (which the compositor must re-sample) moves the aggregate and triggers a frame.
    @scroll_rev : UInt64 = 0
    getter scroll_rev : UInt64

    # Monotonic version of the layer's COMPOSITE position. A panel drag moves the layer at the
    # compositor level without re-rendering any widget (window_panel.cr: "No mark_needs_render needed
    # during drag" — O(1) drag), so without this the version-keyed pull trigger is blind to the move
    # (it only repainted via the SFML event-loop push). Summed into frame_aggregate_rev and bumped at
    # the mutation site, exactly like scroll_rev. A drag thus re-composites (no widget re-render).
    @position_rev : UInt64 = 0
    getter position_rev : UInt64

    def bump_position_rev : Nil
      @position_rev &+= 1
    end

    # Monotonic version of buffer-CLEAR events (mark_needs_clear_and_render — reflow / sticky
    # reposition / zoom). A clear bumps no widget/scroll/position rev, so without this it is invisible to
    # frame_aggregate_rev and only the any_needs_render? backstop catches it. Summed into the aggregate so
    # a clear moves the trigger directly — the prerequisite for deleting that backstop.
    @clear_rev : UInt64 = 0
    getter clear_rev : UInt64

    def scroll_offset=(value : Vec2)
      return if value == @scroll_offset
      @scroll_offset = value
      @scroll_rev &+= 1
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
    getter buffer_origin : Vec2 = Vec2.zero   # Content coord at buffer position (0,0)

    # The whole-valued backstop: render subtracts buffer_origin.to_i (truncate-first), the composite
    # truncates scroll-buffer_origin (subtract-first) — they agree only for a whole origin, else a 1px seam.
    # PRODUCTION has no public buffer_origin writer: every write funnels through recenter_origin! (the one
    # writer), which is the only caller of this backstop besides the test seam below.
    private def write_buffer_origin(value : Vec2)
      {% if flag?(:verify_bounds) %}
        if @viewport_cache && (value.x != value.x.round || value.y != value.y.round)
          raise "buffer_origin must be whole-valued for viewport_cache layer '#{@id}' (got #{value})"
        end
      {% end %}
      @buffer_origin = value
    end

    # Test-only seam (mirrors ScrollView#set_scroll_offset_for_test): set an arbitrary origin to exercise
    # the reader/clamp in isolation. Keeps the whole-valued backstop; production never calls this.
    def set_buffer_origin_for_test(value : Vec2)
      write_buffer_origin(value)
    end

    # Composite-seam invariant: a viewport_cache composite must NEVER clamp — the origin is
    # whole+fitting by construction. The renderers pass the sample they will actually blit from; if it
    # differs from the unclamped (scroll-origin), the invariant broke → fail loudly. Checks THIS composite's
    # actual (post-clip) sample, so a legitimately clipped viewport (which only relaxes the clamp) can't
    # false-raise. Extracted so SFMLRenderer and TestRenderer share ONE check, not two copies.
    def assert_composite_fits!(sample_x : Int32, sample_y : Int32) : Nil
      {% if flag?(:verify_bounds) %}
        if @viewport_cache &&
           (sample_x != (@scroll_offset.x - @buffer_origin.x).to_i ||
           sample_y != (@scroll_offset.y - @buffer_origin.y).to_i)
          raise "composite clamped viewport_cache layer '#{@id}' — buffer_origin invariant broken " \
                "(scroll=#{@scroll_offset} origin=#{@buffer_origin})"
        end
      {% end %}
    end
    # Opt a NON-matrix layer into -Dcache_validation immediate-mode validation.
    # The validator auto-covers viewport_cache content layers; non-matrix overlay/window-direct
    # layers (combo popups, menus, buttons) are blind to it. A non-scrolling layer has scroll_offset=0
    # so the immediate path positions correctly — set this to true (ideally with synthetic-color
    # widgets, which don't AA-jitter) to validate keying-migration coherency on non-matrix widgets.
    property cv_validate : Bool = false

    # Where inside the (oversized) buffer the visible viewport starts —
    # THE single source of truth for viewport-cache sampling, used by
    # the live compositor AND capture_composited_frame so they cannot
    # diverge (2026-06-05: the capture plain-blitted from (0,0) and
    # shifted every captured PNG of a viewport-cache layer by the cache
    # margin — the instrument was the bug, not the renderer).
    def viewport_sample_origin(buffer_width : Int32, buffer_height : Int32,
                               viewport_width : Int32, viewport_height : Int32) : {Int32, Int32}
      # The clamp is a defensive memory-safety bound on the texture read. This method is PURE (no raise):
      # it is also the fit PROBE (`viewport_fits_buffer?` derives from it), so it must be able to observe a
      # clamp without failing. The invariant "a viewport_cache composite never clamps" is asserted at the
      # WRITER (`recenter_origin!`) and at the composite seam (both renderers) under -Dverify_bounds.
      x = (@scroll_offset.x - @buffer_origin.x).to_i.clamp(0, {buffer_width - viewport_width, 0}.max)
      y = (@scroll_offset.y - @buffer_origin.y).to_i.clamp(0, {buffer_height - viewport_height, 0}.max)
      {x, y}
    end

    # The sole writer of buffer_origin for a viewport_cache layer. Returns an ALWAYS-WHOLE origin,
    # positioned so the viewport fits the buffer at it — per axis `(scroll - origin).to_i ∈ [0, buffer -
    # ceil(viewport)]` — so `viewport_sample_origin` (the one reader) never clamps and render/composite,
    # which truncate the origin differently, agree. Preserves the cache_extent quantization grid away from
    # capacity (the scroll round-trip "19px shift" guard); clamps to whole bounds near capacity; and at zero
    # margin (empty integer range) uses floor(scroll) — the sub-pixel-best whole origin, tear-free.
    def compute_buffer_origin(buffer_width : Int32, buffer_height : Int32) : Vec2
      Vec2.new(
        compute_buffer_origin_axis(@scroll_offset.x, buffer_width, bounds.width),
        compute_buffer_origin_axis(@scroll_offset.y, buffer_height, bounds.height)
      )
    end

    private def compute_buffer_origin_axis(scroll : Float64, buffer : Int32, viewport : Float64) : Float64
      ce = @cache_extent
      return scroll.floor if ce <= 0.0
      q = (((scroll - ce) / ce).round * ce).round # quantized ideal, whole even for a fractional cache_extent
      vw = viewport.ceil.to_i
      lo = (scroll - (buffer - vw)).ceil # smallest whole origin with (scroll-origin) <= buffer-vw
      hi = scroll.floor                  # largest whole origin with (scroll-origin) >= 0
      lo <= hi ? q.clamp(lo, hi) : hi    # empty range (zero margin) -> floor(scroll)
    end

    # Does the viewport fit the buffer at the LIVE buffer_origin — i.e. will the one reader
    # (`viewport_sample_origin`) return WITHOUT clamping? Derived from the reader so the predicate cannot
    # drift from the composite. One-directional: the live composite may pass a smaller ancestor-clipped
    # viewport, which only relaxes the clamp, so a `true` here never yields a shift (a `false` in the
    # clipped band is at worst a harmless extra recenter).
    def viewport_fits_buffer?(buffer_width : Int32, buffer_height : Int32) : Bool
      vw = bounds.width.ceil.to_i
      vh = bounds.height.ceil.to_i
      sample = viewport_sample_origin(buffer_width, buffer_height, vw, vh)
      unclamped = { (@scroll_offset.x - @buffer_origin.x).to_i, (@scroll_offset.y - @buffer_origin.y).to_i }
      sample == unclamped
    end

    # The one production writer of buffer_origin: compute (or accept a pre-computed) whole+fitting
    # origin and set it, asserting the fit at the source under -Dverify_bounds. All viewport_cache
    # recenter/first-render sites funnel through this. The blit-shift path already computes the origin for
    # its overlap math, so it passes it in to avoid recomputing (compute_buffer_origin is pure). Returns the
    # new origin (the recenter blit-shift needs it as a value).
    def recenter_origin!(buffer_width : Int32, buffer_height : Int32, origin : Vec2? = nil) : Vec2
      origin ||= compute_buffer_origin(buffer_width, buffer_height)
      write_buffer_origin(origin)
      {% if flag?(:verify_bounds) %}
        raise "recenter_origin! produced a non-fitting origin for '#{@id}' " \
              "(scroll=#{@scroll_offset} origin=#{origin} buffer=#{buffer_width}x#{buffer_height})" \
          unless viewport_fits_buffer?(buffer_width, buffer_height)
      {% end %}
      origin
    end
    # Flag set during buffer recenter - widgets should fill with bg color, not capture from stale texture
    property buffer_just_cleared : Bool = false
    # Flag to force buffer clear on next render without NeedsLayout semantics.
    # Used by cursor overlay: old content must be erased (ghost bands) but
    # NeedsLayout is heavier than needed (forces sibling validation on first_render).
    property needs_clear : Bool = false

    def initialize(@id : String, @cached_bounds : Rect, @z_index : Int32 = 0, background_color : Color = Color.new(0, 0, 0, 0), @owner_widget : Widget? = nil)
      @cached_background_color = background_color
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
        puts "[LAYER CREATED: #{@id}, bg=#{@cached_background_color}]"
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

    # App-level pull render-trigger: a version-keyed aggregate over all in-tree layers. The SFML
    # loop renders a frame iff this moved since the last render — the correct-by-construction
    # replacement for any_needs_render? (which can MISS a change nobody marked). Captures every input
    # under versioning: content/theme/zoom/layout (each widget's primitive_cache_rev), structure (a +1
    # per widget, so add/remove moves it), scroll (scroll_rev), layer composite position (position_rev,
    # so a panel drag re-composites). O(rendered widgets) — bounded by the
    # viewport for virtual content. The event-driven 0%-idle behaviour is preserved: no change → same
    # aggregate → no frame.
    def self.frame_aggregate_rev(root : Widget) : UInt64
      agg = 0_u64
      @@all_layers.each do |layer|
        next unless layer.in_tree?(root)
        agg &+= layer.scroll_rev
        agg &+= layer.position_rev
        agg &+= layer.clear_rev
        layer.widgets.each { |w| agg = sum_widget_revs(w, agg) }
      end
      agg
    end

    private def self.sum_widget_revs(w : Widget, agg : UInt64) : UInt64
      agg &+= w.primitives_version # the pull node's version for Dynamic widgets (residual rev otherwise)
      agg &+= 1_u64 # structure: count each widget so an add/remove moves the aggregate
      w.children.each { |c| agg = sum_widget_revs(c, agg) }
      agg
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
      @clear_rev &+= 1 # make the clear visible to frame_aggregate_rev
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

    # True iff the bounds GREW (not merely changed) since the last render — a grown layer's
    # newly-exposed area holds prior/uninitialized pixels.
    def grew? : Bool
      last = @last_rendered_bounds
      return false if last.nil?
      bounds.width > last.width || bounds.height > last.height
    end

    # A layer whose widgets are CachePolicy::Never partial-painters (e.g. a cursor highlight band)
    # sets this; the renderer's size-change handler then clears the whole layer on a grow, because
    # the newly-exposed area would otherwise keep stale pixels the partial painter never overwrites.
    # Declarative + generic — replaces a per-widget mark_needs_clear_and_render guard.
    property clear_on_grow : Bool = false

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
        # Resize only when the viewport is dimensionally too BIG for the buffer — NOT when the 2×cache_extent
        # margin is merely sub-ideal (which reallocated + re-blit the whole buffer every grow-frame — the
        # ScrollView resize storm), and NOT when the viewport merely moved (a scroll — that is the recenter's
        # blit-shift job, not a resize). A grow that still fits keeps the buffer; the recenter re-positions
        # buffer_origin (clamped so the viewport fits — see compute_buffer_origin) to avoid a shifted composite.
        bounds.width > backend.width || bounds.height > backend.height
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
