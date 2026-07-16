require "./types"
require "./cached"
require "./scheduler"
require "./cache_policy"
require "./font"
require "./clipboard"
require "../rendering/draw_primitive"
require "../input/shortcut_manager"
require "../input/focus_manager"

module CrymbleUI
    enum MouseButton
        Left
        Right
        Middle
    end

    # Annotation for properties that should be automatically copied during reconciliation
    # Emitted by reactive_property(reconcile: true) and reconcile_property
    # The auto_copy_reconcile_properties method iterates all @[Reconcile] annotated vars
    annotation Reconcile
    end

    # Annotation for properties explicitly excluded from reconciliation.
    # Used with -Daudit_reconcile to ensure every ivar is classified.
    annotation NoReconcile
    end

    # Explicit focus navigation overrides
    # Allows overriding automatic spatial navigation for specific directions
    struct FocusOverride
        property up : String?     # Widget ID for Up arrow navigation
        property down : String?   # Widget ID for Down arrow navigation
        property left : String?   # Widget ID for Left arrow navigation
        property right : String?  # Widget ID for Right arrow navigation

        def initialize(
            @up : String? = nil,
            @down : String? = nil,
            @left : String? = nil,
            @right : String? = nil
        )
        end
    end

    # Widget invalidation state
    # Clean: no changes needed
    # NeedsRender: visual changes only (animations, colors) - selective render
    # NeedsLayout: structural changes (size, position, children) - full layout + render
    enum WidgetState
        Clean
        NeedsRender
        NeedsLayout
    end

    # Abstract base class for all widgets
    abstract class Widget
        # Global scheduler for all widgets
        @@scheduler : Scheduler?

        # Global shortcut manager for all widgets
        @@shortcut_manager : ShortcutManager?

        # Global focus manager for keyboard focus
        @@focus_manager : FocusManager?

        # Global app reference for triggering rebuilds
        @@app : App?

        # Global font for text measurement (set by renderer)
        @@font : Font?

        # Global clipboard (set by renderer; in-memory stub in specs)
        @@clipboard : Clipboard?

        # Render count instrumentation (for testing optimization)
        @@render_count : Int32 = 0
        @@cache_render_count : Int32 = 0

        # Layout count instrumentation (for testing optimization)
        @@layout_count : Int32 = 0

        # Measure count instrumentation (for testing VStack/HStack optimization)
        @@measure_count : Int32 = 0

        # absolute_bounds invocation instrumentation. absolute_bounds is UNCACHED and O(depth) (it
        # re-walks the parent chain on every call), so calling it once per widget over a whole subtree
        # is O(content·depth) — the shape of the resize regression a per-frame grow walk re-introduced
        # (the repaint marking walk). This counter guards the grow path against re-introducing an
        # O(content) absolute_bounds storm: a pure grow must call it O(1) in content size, not O(n).
        @@absolute_bounds_count : Int32 = 0

        # mark_needs_render PROPAGATION instrumentation. Each call walks the parent chain to a
        # layer + does a set-insert (propagate_to_layer) — the "method calls, set operations, layer
        # traversals" overhead that regressed live resize historically (be1ffa9) and is INVISIBLE to
        # primitive_count (a mark-storm over culled widgets renders nothing). This counter guards
        # the live-resize policy against re-introducing that propagation wall.
        @@mark_render_count : Int32 = 0

        # HOT-PATH instrumentation (perf audit). Bump via the explicit `Widget.` class qualifier
        # so a bare @@ from an instance method doesn't scatter into each subclass's own copy (see
        # increment_absolute_bounds_count).
        #
        # panel_walk_visits/popup_walk_visits: bumped once per REGISTRY ENTRY checked by
        # WindowPanel.all_in_tree/Popup.all_in_tree (window_panel.cr/popup.cr) — O(#panels)/O(#popups),
        # content-independent. Formerly bumped once per NODE VISITED by an O(total-widget) tree walk
        # (collect_panels_recursive/collect_popups_recursive, deleted); this counter guards against
        # that O(content) walk creeping back onto the per-frame path.
        @@panel_walk_visits : Int32 = 0
        @@popup_walk_visits : Int32 = 0
        # state_sweep_visits: STILL an O(total-widget) tree walk (clear_render_state_recursive, per
        # non-layout frame) — unscoped, unlike the two above. Guards against it regressing further,
        # not a claim it's already O(1). Scoping it is a separate, not-yet-started effort.
        @@state_sweep_visits : Int32 = 0

        # Text-measurement cache (text+size → visual Size). measure_text is a layout HOT PATH: every
        # Button/Text re-measures each layout pass, so a live panel resize fired hundreds of SFML
        # font queries per frame (~40ms, the resize-CPU cost). The result is deterministic per font,
        # so cache it; cleared on font change (font=). Bounded to cap growth from dynamic text.
        @@measure_text_cache = Hash(Tuple(String, Float64), Size).new

        # Control warnings for conflicts (duplicate IDs, duplicate shortcuts, etc.)
        # Can be disabled for tests
        @@enable_warnings : Bool = true

        # Set the global scheduler (called by renderer)
        def self.scheduler=(scheduler : Scheduler)
            @@scheduler = scheduler
        end

        # Get the global scheduler
        def self.scheduler : Scheduler
            @@scheduler || raise "Scheduler not initialized"
        end

        # Set the global shortcut manager (called by renderer)
        def self.shortcut_manager=(manager : ShortcutManager)
            @@shortcut_manager = manager
        end

        # Get the global shortcut manager
        def self.shortcut_manager : ShortcutManager
            @@shortcut_manager || raise "ShortcutManager not initialized"
        end

        # Set the global focus manager (called by renderer)
        def self.focus_manager=(manager : FocusManager)
            @@focus_manager = manager
        end

        # Get the global focus manager
        def self.focus_manager : FocusManager
            @@focus_manager || raise "FocusManager not initialized"
        end

        # Get the global focus manager (optional - may not be set in tests)
        def self.focus_manager? : FocusManager?
            @@focus_manager
        end

        # Set the global app (called by renderer)
        def self.app=(app : App)
            @@app = app
        end

        # Get the global app
        def self.app? : App?
            @@app
        end

        # Set the global font (called by renderer)
        def self.font=(font : Font)
            @@font = font
            @@measure_text_cache.clear # font changed → cached measurements are invalid
        end

        # Get the global font
        def self.font : Font?
            @@font
        end

        # Set the global clipboard (called by renderer)
        def self.clipboard=(clipboard : Clipboard)
            @@clipboard = clipboard
        end

        # Get the global clipboard
        def self.clipboard : Clipboard
            @@clipboard || raise "Clipboard not initialized"
        end

        # Enable/disable warnings (duplicate IDs, shortcut conflicts, etc.)
        # Useful for tests
        def self.enable_warnings=(value : Bool)
            @@enable_warnings = value
        end

        # Get current enable_warnings setting
        def self.enable_warnings : Bool
            @@enable_warnings
        end

        # Measure text dimensions using global font
        # This is a pure geometry query - no rendering required
        # Can be called during measure() phase
        # Returns the visual size of the text (width/height only, no offsets)
        # Use with draw_text() which automatically compensates for SFML local_bounds offsets
        def self.measure_text(text : String, size : Float64) : Size
            return Size.new(0.0, 0.0) unless font = @@font

            key = {text, size}
            if cached = @@measure_text_cache[key]?
                return cached
            end
            # Delegate to Font implementation (SFML or headless)
            result = font.measure_text(text, size)
            @@measure_text_cache.clear if @@measure_text_cache.size > 20_000 # bound dynamic-text growth
            @@measure_text_cache[key] = result
            result
        end

        # Instance method for convenience
        def measure_text(text : String, size : Float64) : Size
            Widget.measure_text(text, size)
        end

        # Render count instrumentation API (for testing)
        def self.render_count : Int32
            @@render_count
        end

        def self.cache_render_count : Int32
            @@cache_render_count
        end

        def self.reset_render_counts
            @@render_count = 0
            @@cache_render_count = 0
        end

        # Get layout count for testing
        def self.layout_count : Int32
            @@layout_count
        end

        # Reset layout count for testing
        def self.reset_layout_count
            @@layout_count = 0
        end

        # Increment layout count for instrumentation
        def self.increment_layout_count
            @@layout_count += 1
        end

        # Get measure count for testing
        def self.measure_count : Int32
            @@measure_count
        end

        # Reset measure count for testing
        def self.reset_measure_count
            @@measure_count = 0
        end

        # Increment measure count for instrumentation
        def self.increment_measure_count
            @@measure_count += 1
        end

        # Get absolute_bounds invocation count for testing
        def self.absolute_bounds_count : Int32
            @@absolute_bounds_count
        end

        # Reset absolute_bounds invocation count for testing
        def self.reset_absolute_bounds_count
            @@absolute_bounds_count = 0
        end

        # Increment absolute_bounds count for instrumentation. Called via the explicit `Widget.` class
        # qualifier (NOT a bare `@@` from the instance method): a bare class-var write from an instance
        # method targets the RUNTIME subclass's own copy (Crystal gives each subclass a separate copy),
        # so the counts would scatter across Button/VStack/… and Widget's would stay 0. Same idiom as
        # increment_measure_count.
        def self.increment_absolute_bounds_count
            @@absolute_bounds_count += 1
        end

        def self.mark_render_count : Int32
            @@mark_render_count
        end

        def self.reset_mark_render_count
            @@mark_render_count = 0
        end

        # --- HOT-PATH TREE-WALK counters (perf audit) --------------------------------------------
        # Same subclass-copy caveat as increment_absolute_bounds_count: always bump via `Widget.`.
        def self.panel_walk_visits : Int32
            @@panel_walk_visits
        end

        def self.reset_panel_walk_visits
            @@panel_walk_visits = 0
        end

        def self.increment_panel_walk_visits
            @@panel_walk_visits += 1
        end

        def self.popup_walk_visits : Int32
            @@popup_walk_visits
        end

        def self.reset_popup_walk_visits
            @@popup_walk_visits = 0
        end

        def self.increment_popup_walk_visits
            @@popup_walk_visits += 1
        end

        def self.state_sweep_visits : Int32
            @@state_sweep_visits
        end

        def self.reset_state_sweep_visits
            @@state_sweep_visits = 0
        end

        def self.increment_state_sweep_visits
            @@state_sweep_visits += 1
        end

        def self.increment_render_count
            @@render_count += 1
        end

        def self.increment_cache_render_count
            @@cache_render_count += 1
        end

        # Explicit ID for reconciliation
        # When nil, widgets are matched by position during rebuild (works if structure is stable)
        # Provide explicit IDs for dynamic lists or conditional widgets
        property id : String?

        # Generic user data - can store custom string attributes
        # Useful for attaching metadata (e.g., hover text, tooltips, shortcuts)
        # User can also subclass widgets and add typed properties instead
        property user_data : Hash(Symbol, String) = {} of Symbol => String

        # Parent widget (nil for root)
        property parent : Widget?

        # Children widgets
        getter children : Array(Widget)

        # Whether build() has been called (for auto-build on add_child)
        getter? built : Bool = false

        # Mark widget as built (called by add_child before triggering build)
        protected def mark_built
            @built = true
        end

        # Widget bounds after layout (parent-relative coordinates)
        property bounds : Rect

        # Layer ownership (overridden by widgets with their own layers: Window, WindowPanel, MenuBar, Popup, LayerBox)
        # Most widgets don't have their own layer - they render into parent's layer
        def layer : Layer?
            nil
        end

        # Calculate absolute window coordinates from parent-relative bounds
        # Traverses parent chain to convert relative position to absolute
        def absolute_bounds : Rect
            Widget.increment_absolute_bounds_count
            if parent = @parent
                parent_abs = parent.absolute_bounds
                Rect.new(
                    @bounds.x + parent_abs.x,
                    @bounds.y + parent_abs.y,
                    @bounds.width,
                    @bounds.height
                )
            else
                # Root widget has no parent - bounds are already absolute
                @bounds
            end
        end

        # Widget invalidation state (Clean, NeedsRender, NeedsLayout)
        property state : WidgetState

        # Explicit layer override for propagate_to_layer (set by VirtualMatrix for sticky cells)
        property render_layer : Layer?

        # Cached ancestry bounds validity (nil = uncached).
        # Valid when this widget and all ancestors have positive bounds.
        # Cleared on mark_needs_layout (upward propagation clears entire chain).
        @ancestry_bounds_valid : Bool? = nil

        # Enabled state - disabled widgets render but don't respond to clicks
        @enabled : Bool = true

        def enabled? : Bool
          @enabled
        end

        def enabled=(value : Bool)
          return if @enabled == value
          @enabled = value
          mark_needs_render
        end

        # Children can be positioned outside parent bounds (for Popup, etc.)
        # When true, hit_test will check children even if point is outside parent bounds
        property children_escape_bounds : Bool

        # Focus highlight state (for flashing animation when widget has keyboard focus)
        # Managed by FocusFlashController - widgets should not set this directly
        @focus_highlighted : Bool = false

        def focus_highlighted? : Bool
            @focus_highlighted
        end

        def focus_highlighted=(value : Bool)
            return if @focus_highlighted == value
            @focus_highlighted = value
            mark_needs_render
        end

        # Explicit focus navigation overrides
        # Allows overriding automatic spatial navigation for specific directions
        @focus_override : FocusOverride? = nil
        property focus_override : FocusOverride?

        # Cached primitive list (for primitive-based rendering)
        # Managed by base class - subclasses never touch this. Used by the Static cache policy; the
        # Dynamic policy uses @primitives_node.
        @cached_primitives : Array(DrawPrimitive)?

        # The Dynamic-policy primitive cache as a pull node. Its recompute is
        # to_primitives(@primitives_bounds), which AUTO-CAPTURES theme/zoom (Sources) it reads; content
        # and layout are signalled via touch() from mark_needs_render / mark_needs_layout. Lazily created
        # on first render.
        @primitives_node : Cached(Array(DrawPrimitive))? = nil
        @primitives_bounds : Rect = Rect.new(0.0, 0.0, 0.0, 0.0)

        # Per-widget render backend (for per-widget texture optimization)
        # Each widget maintains its own tiny RenderTexture for fast selective rendering
        # Managed by renderer - subclasses never touch this
        @widget_backend : RenderBackend?

        # Track if widget has rendered to layer at current bounds (for invariant h)
        # Prevents capturing own content as background
        @rendered_to_layer_at_current_bounds : Bool = false

        # Background backend (stores saved background from layer)
        # For SFML: small RenderTexture with layer background (GPU-based, fast)
        # For TestRenderBackend: pixel buffer with Array(Color) (CPU-based)
        # Captured once on first render, restored before each subsequent render
        # Managed by renderer - subclasses never touch this
        @background_backend : RenderBackend?


        # Layer position where widget was last rendered (for auto-detecting stale background).
        # Cleared when widget_backend is disposed (scroll exit, rebuild).
        @last_rendered_layer_position : Tuple(Int32, Int32)? = nil

        # Last constraints used for layout (for incremental layout optimization)
        # If current constraints match and widget is clean, layout can be skipped
        @last_constraints : BoxConstraints?

        # Zoom epoch at last layout (forces re-layout when zoom changes)
        @last_zoom_epoch : UInt64 = 0

        # Per-widget revision axes for the primitive cache.
        # content_rev bumps on mark_needs_render (visual change), layout_rev on mark_needs_layout
        # (size/structure). Summed with the global Theme.theme_rev + FontSizing.zoom_epoch they form
        # the validity key (see primitive_cache_rev) — replacing `needs_render? || nil`, which was
        # blind to theme/zoom swaps that issue no mark_needs_render.
        @content_rev : UInt64 = 0
        @layout_rev : UInt64 = 0

        # Pull/SlotBuffer (sparse, per-cell — no dense structure): the slot key for a
        # viewport_cache buffer = {content version, BUFFER position}. content_version is the cell's
        # primitives_version (the Cached node version for a Dynamic cell — auto-captures theme/zoom;
        # the content_rev+layout_rev residual otherwise). buffer_pos = content_pos − buffer_origin.
        # The buffer SKIPS a cell whose key is unchanged (it already holds its pixels);
        # the soundness invariant is that buffer_pos is moved IN LOCKSTEP with the pixels by every
        # buffer op (scroll blit-shift → shift_slot; reflow/clear → invalidate via disposed backend).
        @slot_rev : UInt64? = nil
        @slot_buffer_pos : Tuple(Int32, Int32)? = nil

        # Skip iff the buffer already holds this cell's current pixels at buffer_pos. The
        # version axis is the cell's node version (primitives_version) — auto-captures theme/zoom, so a
        # theme/zoom swap invalidates every slot. The geometric coherence (buffer_pos +
        # shift_slot/invalidate_slot lockstep) is the separate spatial axis, unchanged.
        def slot_fresh?(buffer_pos : Tuple(Int32, Int32)) : Bool
            @slot_rev == primitives_version && @slot_buffer_pos == buffer_pos
        end

        # Stamp the slot after a (re-)blit into the buffer at buffer_pos.
        def stamp_slot(buffer_pos : Tuple(Int32, Int32)) : Nil
            @slot_rev = primitives_version
            @slot_buffer_pos = buffer_pos
        end

        # Blit-shift lockstep: the cell's pixels were moved by (dx,dy) in the buffer — move its stamp too.
        def shift_slot(dx : Int32, dy : Int32) : Nil
            if bp = @slot_buffer_pos
                @slot_buffer_pos = {bp[0] + dx, bp[1] + dy}
            end
        end

        # Blit-shift: the cell's backend is still VALID but its pixels were NOT copied to the new buffer
        # position — invalidate the slot so it re-blits the cached backend (no re-render needed).
        def invalidate_slot : Nil
            @slot_buffer_pos = nil
        end

        # True iff the cached widget_backend texture still reflects the current version (position aside).
        def slot_rev_matches? : Bool
            @slot_rev == primitives_version
        end

        def initialize(@id : String? = nil)
            @parent = nil
            @children = [] of Widget
            @bounds = Rect.zero
            @state = WidgetState::NeedsLayout
            @children_escape_bounds = false
            @widget_backend = nil
            @background_backend = nil
            @render_layer = nil
        end

        # Path-based ID for hierarchical identification (ImGui-inspired)
        # Example: "window/toolbar/save_button"
        def path_id : String
            if @parent
                parent_path = @parent.not_nil!.path_id
                my_segment = @id || label || self.class.name.split("::").last
                "#{parent_path}/#{my_segment}"
            else
                @id || label || self.class.name.split("::").last
            end
        end

        # Label for display/identification (can be overridden)
        def label : String?
            nil
        end

        # Add child widget
        def add_child(child : Widget)
            # Warn if ID is already used by a sibling (unless warnings disabled)
            if child_id = child.id
                if @children.any? { |sibling| sibling.id == child_id }
                    if Widget.enable_warnings
                        STDERR.puts "WARNING: Duplicate widget ID '#{child_id}' among siblings of #{self.class.name}"
                        STDERR.puts "  This may cause issues with find() and reconciliation."
                    end
                end
            end

            child.parent = self
            @children << child

            # Auto-trigger build for composite widgets (only once)
            unless child.built?
                child.mark_built
                child.build
            end

            mark_needs_layout
        end

        # Remove child widget
        def remove_child(child : Widget)
            @children.delete(child)
            child.parent = nil
            mark_needs_layout
        end

        # Clear all children
        def clear_children
            @children.each { |child| child.parent = nil }
            @children.clear
            mark_needs_layout
        end

        # Mark widget as needing layout (structural change)
        # This implies rendering will also be needed
        def mark_needs_layout
            @state = WidgetState::NeedsLayout
            @layout_rev &+= 1             # bump layout axis
            @primitives_node.try(&.touch) # signal the pull node (layout is an intrinsic change)
            @ancestry_bounds_valid = nil  # Invalidate bounds cache (propagates up via parent chain)

            # Invalidate cached constraints (forces re-layout even if constraints unchanged)
            invalidate_last_constraints

            # Invalidate background backend - layout change means position/size changed
            # Background needs to be recaptured from new location
            # IMPORTANT: Use setter to properly reset rendered_to_layer flag
            self.background_backend = nil

            @parent.try &.mark_needs_layout

            # Propagate to containing layer ONLY if already laid out
            # Skip during initial build phase (bounds not set yet) - massive performance win
            # After first layout, layer propagation keeps rendering in sync with layout changes
            propagate_to_layer unless @bounds.width == 0.0 && @bounds.height == 0.0
        end

        # Mark widget as needing render (visual change only)
        # Does not trigger layout unless already needed
        def mark_needs_render
            @@mark_render_count &+= 1  # instrumentation: count the propagation (see @@mark_render_count)
            @content_rev &+= 1  # bump content axis (any visual change)
            @primitives_node.try(&.touch) # signal the pull node (content is an intrinsic change)
            # Don't downgrade from NeedsLayout to NeedsRender
            @state = WidgetState::NeedsRender if @state == WidgetState::Clean

            # Chrome/content split eliminates need for invalidate_children_backgrounds!
            # Chrome and content have non-overlapping bounds, so chrome re-render
            # cannot overwrite content. Content uses selective rendering (dirty widgets only).
            # This achieves O(1) performance instead of O(children) cascade.

            # Propagate to containing layer (replaces parent propagation for rendering)
            # Layer propagation handles the hierarchy - no need to propagate up parent chain
            propagate_to_layer
        end

        # Propagate state change to containing layer
        # Walks up parent chain to find a widget with a layer and marks it
        private def propagate_to_layer
            # Check explicit render_layer override (e.g., VirtualMatrix sticky cells)
            if rl = @render_layer
                if @state == WidgetState::NeedsLayout
                    rl.mark_needs_layout
                else
                    rl.mark_needs_render(self)
                end
                return
            end

            # First check if THIS widget has its own layer (WindowPanel, MenuBar, Popup, LayerBox)
            if layer = self.layer
                # This widget owns the layer - check if layout or just render is needed
                if @state == WidgetState::NeedsLayout
                    # Layout needed - mark layer for layout (disables viewport culling for new widgets)
                    layer.mark_needs_layout
                else
                    # Just render - mark widget dirty (selective rendering)
                    layer.mark_needs_render(self)
                end
                return
            end

            # Otherwise, walk up parent chain to find a widget with a layer (Window)
            current = self.parent
            while current
                # Check if parent widget has a layer
                if layer = current.layer
                    # Check if this widget needs layout or just render
                    if @state == WidgetState::NeedsLayout
                        # Layout needed - mark layer for layout (disables viewport culling)
                        layer.mark_needs_layout
                    else
                        # Just render - mark widget dirty (selective rendering)
                        layer.mark_needs_render(self)
                    end
                    return
                end
                current = current.parent
            end
        end

        # The node-driven layer-index enqueue. The widget's primitives node calls this
        # (via on_dirty) when it goes value-stale, putting this widget in its layer's selective-render
        # set. Reuses propagate_to_layer so the @state branch (selective render vs full-layout) is
        # honoured exactly as the push path does — they coexist idempotently with the push.
        protected def enqueue_dirty_to_layer : Nil
            propagate_to_layer
        end

        # Invalidate children's background backends recursively
        # Called when parent changes visually - children must re-capture backgrounds
        # This is an O(children) cascade which is correct behavior (uncommon case: ~5-10%)
        # Common case (leaf changes) remains O(1) selective rendering
        protected def invalidate_children_backgrounds
            @children.each do |child|
                # Invalidate child's background (forces re-capture on next render)
                child.background_backend = nil
                # CRITICAL: Mark child as needing render so it actually re-renders!
                # Without this, child keeps old content with invalid background → artifacts
                child.mark_needs_render
                # Recursively invalidate descendants
                child.invalidate_children_backgrounds
            end
        end

        # Widget property macros — two concerns, two macros:
        #
        #   reactive_property  — a reactive VALUE (the workhorse). A tracked Source(T): read it in
        #                        to_primitives and it auto-captures; a change re-renders.
        #   reconcile_property — non-reactive infrastructure that must survive a DSL rebuild (a managed
        #                        Layer/Widget ref). A plain ivar, carried across the rebuild — NOT a value.
        #
        # Usage:
        #   reactive_property text : String                              # render-reactive (read while painting)
        #   reactive_property padding : Float64 = 0.0, layout: true      # change also re-layouts
        #   reactive_property mode : Mode = Mode::None, reconcile: true   # value survives a rebuild
        #   reconcile_property content_layer : Layer?                    # carried object ref, not reactive

        # reactive_property: the unified reactive field. The field is a tracked Source(T) — the getter
        # reads it (so to_primitives AUTO-CAPTURES it → the primitives node depends on it), the setter
        # notifies (→ node stale → the on_dirty callback enqueues this widget). No manual mark: the value
        # edge can't be forgotten, and the equality gate suppresses no-op writes.
        #   layout: true    → the setter ALSO pokes the imperative layout pass (mark_needs_layout) — layout
        #                     is not a pull-node, so a layout-affecting change must trigger it explicitly.
        #   reconcile: true → @[Reconcile] + a PLAIN build-shadow (the @[Reconcile] copy compares it by ==;
        #                     a Source-typed shadow would compare by identity and never reconcile), so the
        #                     value survives a DSL rebuild.
        macro reactive_property(declaration, layout = false, reconcile = false)
            {% if declaration.is_a?(TypeDeclaration) %}
                {% if reconcile %}
                    @[::CrymbleUI::Reconcile]
                {% end %}
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : ::CrymbleUI::Source({{declaration.type}}) = ::CrymbleUI::Source({{declaration.type}}).new({{declaration.value}})
                    {% if reconcile %}
                        @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% end %}
                {% else %}
                    @{{declaration.var}} : ::CrymbleUI::Source({{declaration.type}})
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}.get
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}}.set(value)
                    {% if layout %}
                        mark_needs_layout
                    {% end %}
                end
            {% end %}
        end

        # reconcile_property: non-reactive carry-over for infrastructure that must survive a DSL rebuild
        # but is NOT a reactive value — a managed Layer/Widget ref (content_layer, cursor_overlay_widget,
        # proxy_focused_widget). A plain ivar (NOT a Source): Source-wrapping a managed object would be a
        # dishonest abstraction and buys no auto-capture (these are never read in to_primitives). The field
        # is carried from the old widget on rebuild via @[Reconcile] (see auto_copy_reconcile_properties).
        # When a default exists, a @_build_<name> shadow gates the copy (app-wins-if-changed); without a
        # default it is always carried. Reactive VALUES use reactive_property(reconcile: true) instead.
        macro reconcile_property(declaration)
            {% if declaration.is_a?(TypeDeclaration) %}
                @[::CrymbleUI::Reconcile]
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                {% else %}
                    @{{declaration.var}} : {{declaration.type}}
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}} = value
                end
            {% end %}
        end

        # theme_property: a theme-derived Color that resolves LIVE.
        # Stores nil by default → the getter falls back to Theme.current.<theme_key> at READ time, so
        # a Theme.set recolors the widget immediately (paired with theme_rev invalidating the cache).
        # An explicit value (constructor arg or setter) is stored and WINS. This is the Flutter/ImGui
        # idiom: read the theme role at render, an explicit override takes precedence.
        # IMPORTANT: to_primitives MUST read the getter (`name`), never the `@name` ivar — the ivar is
        # the nullable override store, not the resolved color.
        macro theme_property(name, theme_key)
            # Stores nil (follow theme), a concrete Color (sticky override), or a live ThemeColorRef
            # (a different theme key, resolved at read time — see Theme.ref).
            @{{name.id}} : ThemeColor? = nil

            def {{name.id}} : Color
                v = @{{name.id}}
                case v
                in ThemeColorRef then v.resolve
                in Color         then v
                in Nil           then Theme.current.{{theme_key.id}}
                end
            end

            def {{name.id}}=(value : ThemeColor?)
                @{{name.id}} = value
                mark_needs_render
            end
        end

        # Check if widget needs rendering. For a node-backed (Dynamic, rendered) widget
        # this is NODE-DERIVED — render is needed iff the primitives cache is stale (a Source.set or a
        # touch invalidated it). This is more precise than the @state flag (which a Source-backed setter
        # no longer sets) and is what blit_plan needs: "blit the cached texture, or re-render?". Static /
        # Never / not-yet-rendered widgets fall back to the @state flag.
        def needs_render? : Bool
            if node = @primitives_node
                !node.valid?
            else
                @state >= WidgetState::NeedsRender
            end
        end

        # Check if widget needs layout
        def needs_layout? : Bool
            @state == WidgetState::NeedsLayout
        end

        # Clear state to Clean (for testing purposes only)
        def clear_state_for_test
            @state = WidgetState::Clean
        end

        # Half-pixel slack for the "did I fill?" test below. Erring toward "filled" (< EPS below max ⇒
        # treat as filling ⇒ re-layout) is the SAFE direction: at worst we re-layout a body that would
        # have been stable; the unsafe direction (skipping a fill body) would leave it the wrong size.
        LAYOUT_FILL_EPS = 0.5

        # Does this widget's child arrangement depend on the incoming constraint's AVAILABLE space, beyond
        # just its own resulting size? A wrapping/packing layout (FlowLayout) does — it re-packs rows
        # against max_width, so a width change can change its layout even though its own size stayed a
        # sub-max "widest row". Such a widget must NOT take the can_skip_layout? relaxation branch (which
        # assumes a sub-max body is intrinsic and unaffected by more space); it skips only on identical
        # constraints. Default false. Override → true to opt out of relaxation.
        def layout_depends_on_available_space? : Bool
            false
        end

        # Check if layout can be skipped (incremental layout optimization).
        # Skips when the widget is clean, zoom is unchanged, and the new constraints can't change its
        # layout — either identical constraints, OR a RELAXATION the widget didn't use (its last size
        # still fits the new constraints and, in each axis whose max grew, it wasn't already filling the
        # old max). The relaxation case is what lets a floored panel's non-fill content skip a resize
        # grow (intrinsic body: size < max ⇒ a bigger max changes nothing); a fill body (size == max)
        # re-lays-out, since it grows into the new space.
        protected def can_skip_layout?(constraints : BoxConstraints) : Bool
            return false if needs_layout?
            return false if @last_zoom_epoch != FontSizing.zoom_epoch
            old = @last_constraints
            return false if old.nil?
            return true if old == constraints
            return false if layout_depends_on_available_space?

            sz = @bounds.size
            return false unless constraints.min_width <= sz.width <= constraints.max_width
            return false unless constraints.min_height <= sz.height <= constraints.max_height
            return false if constraints.max_width > old.max_width && sz.width >= old.max_width - LAYOUT_FILL_EPS
            return false if constraints.max_height > old.max_height && sz.height >= old.max_height - LAYOUT_FILL_EPS
            true
        end

        # Invalidate cached constraints (forces re-layout on next pass)
        protected def invalidate_last_constraints
            @last_constraints = nil
        end

        # Check if widget is a rendering leaf (draws its own content without relying on children)
        # Used by selective rendering to determine if widget area should be cleared before re-render
        # Default: true if no children (actual leaf)
        # Override in widgets that draw their own content even though they have children
        def rendering_leaf? : Bool
            children.empty?
        end

        # Override to clip children rendering to a specific rect
        # Used by containers like Popup, WindowPanel that need to prevent children overflow
        # Renderer will automatically push/pop clip around children rendering
        def clip_children : Rect?
            nil  # Default: no clipping
        end

        # Polymorphic rendering control methods
        # These allow widgets to control their rendering behavior without
        # requiring type checks in the renderer

        # Should this widget be skipped entirely during rendering?
        # Used by widgets that can be hidden/closed (e.g., WindowPanel when closed)
        def skip_render? : Bool
            false  # Default: render everything
        end

        # Hook called by layer renderer before collecting widgets for rendering.
        # Override to flush deferred state (e.g., VirtualMatrix defers cell updates
        # during scrollbar drag to avoid running expensive work on every mouse event).
        def pre_render_flush
        end

        # Get children in render order (for z-order sorting)
        # Override to customize rendering order (e.g., Window sorts panels by z-index)
        def sorted_children : Array(Widget)
            @children  # Default: normal order
        end

        # Get menubar child if this widget has one (for direct compositing)
        # Override in containers that have menubars (e.g., Window)
        def menubar_child : Widget?
            nil  # Default: no menubar
        end

        # Build widget tree (declarative approach)
        # Subclasses override this to create their UI
        def build : Widget
            self
        end

        # Measure widget size given constraints
        # Returns the size the widget wants to be
        abstract def measure(constraints : BoxConstraints) : Size

        # Smallest height at which this widget still renders acceptably, at the given width.
        # Its own chain (NOT BoxConstraints-clamped like measure) so an unbounded request can't be
        # turned finite mid-compose. Default = the natural measured height — correct for LEAVES,
        # which can't shrink below their content. A CONTAINER with a shrinkable descendant (e.g. a
        # fill VirtualMatrix) MUST override, composing children's min the way its measure/perform_layout
        # stacks them; otherwise this default measures the greedy fill and the floor is wrong.
        def min_intrinsic_height(width : Float64) : Float64
            h = measure(BoxConstraints.new(min_width: 0.0, max_width: width, min_height: 0.0, max_height: Float64::INFINITY)).height
            {% if flag?(:verify_bounds) %}
                if !@children.empty? && h > 100_000.0
                    STDERR.puts "[min_intrinsic_height] #{self.class.name} fell through to the greedy measure default (#{h.round(0)}) — a container with a shrinkable descendant needs an override"
                end
            {% end %}
            h
        end

        # The WIDTH dual of min_intrinsic_height: smallest width at which this widget still renders
        # acceptably, at the given height. Own chain (NOT BoxConstraints-clamped), default = the natural
        # measured width — correct for LEAVES. A CONTAINER with a width-shrinkable descendant (a fill
        # VirtualMatrix / ScrollView) MUST override, composing children's min the way measure/perform_layout
        # arranges them on the WIDTH axis; otherwise this greedy-measures the fill and the floor is wrong.
        def min_intrinsic_width(height : Float64) : Float64
            w = measure(BoxConstraints.new(min_width: 0.0, max_width: Float64::INFINITY, min_height: 0.0, max_height: height)).width
            {% if flag?(:verify_bounds) %}
                if !@children.empty? && w > 100_000.0
                    STDERR.puts "[min_intrinsic_width] #{self.class.name} fell through to the greedy measure default (#{w.round(0)}) — a container with a width-shrinkable descendant needs an override"
                end
            {% end %}
            w
        end

        # Layout widget and children at given position
        # Template method: handles skip check, then delegates to perform_layout
        def layout(constraints : BoxConstraints, position : Vec2)
            # Skip layout if constraints unchanged and widget is clean
            if can_skip_layout?(constraints)
                # Just update position, skip full layout
                old_pos = @bounds.position
                @bounds = Rect.new(position, @bounds.size)
                # Position changed → background_backend holds content from old location
                if old_pos.x != position.x || old_pos.y != position.y
                    self.background_backend = nil
                    mark_needs_render
                    # Pull-based: layer bounds auto-update via compute_bounds_for_layer
                end
                return
            end

            # Set state to Clean first (before perform_layout)
            @state = WidgetState::Clean

            # Remember old size for change detection
            old_width = @bounds.width
            old_height = @bounds.height

            # Delegate to subclass implementation
            perform_layout(constraints, position)

            # Invalidate primitive cache when size changes.
            # Cached primitives (e.g., fill_rect) use the old bounds dimensions and would
            # leave unfilled regions on the new, differently-sized widget_backend.
            if old_width != @bounds.width || old_height != @bounds.height
                mark_needs_render
            end

            # Verify bounds satisfaction: widget size must respect constraints.
            # Found by Z3 verification: Image, Expanded, TextInput violated this.
            {% if flag?(:verify_bounds) %}
              if constraints.max_width.finite? && @bounds.width > constraints.max_width + 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} width #{@bounds.width.round(1)} > max #{constraints.max_width.round(1)}"
              end
              if constraints.max_height.finite? && @bounds.height > constraints.max_height + 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} height #{@bounds.height.round(1)} > max #{constraints.max_height.round(1)}"
              end
              if @bounds.width < constraints.min_width - 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} width #{@bounds.width.round(1)} < min #{constraints.min_width.round(1)}"
              end
              if @bounds.height < constraints.min_height - 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} height #{@bounds.height.round(1)} < min #{constraints.min_height.round(1)}"
              end
            {% end %}

            # Save constraints and zoom epoch for next skip check
            @last_constraints = constraints
            @last_zoom_epoch = FontSizing.zoom_epoch
        end

        # Coherent reposition for a blit-shift: translate this widget's bounds by (dx, dy) WITHOUT
        # invalidating its cached primitives or background. The caller (a content-layer resize blit-
        # shift) has already translated the widget's composited pixels in the layer buffer and moved its
        # slot stamp in lockstep (shift_slot), so a re-render/re-blit would be redundant. Contrast
        # layout()'s position-only fast path, which disposes the background + marks needs_render — correct
        # only when NOTHING has moved the pixels for you. Because @bounds is parent-local, this shifts
        # absolute_bounds (and every descendant's) by the same delta.
        def shift_bounds(dx : Float64, dy : Float64) : Nil
            @bounds = Rect.new(Vec2.new(@bounds.x + dx, @bounds.y + dy), @bounds.size)
        end

        # Perform actual layout (implemented by subclasses)
        # Called by layout() after skip check passes
        # Subclasses must set @bounds and layout children
        abstract def perform_layout(constraints : BoxConstraints, position : Vec2)

        # Auto-copy all @[Reconcile] annotated properties from old widget
        # Called by copy_state_from - widgets can override copy_state_from for custom logic
        # Note: reconcile_property always adds @[Reconcile]; reactive_property adds it only with
        # `reconcile: true`. Fields with a @_build_<name> shadow are gated (app-wins-if-changed);
        # fields without one (a no-default reconcile_property object ref) are always carried.
        protected def auto_copy_reconcile_properties(old_widget : Widget)
            {% for ivar in @type.instance_vars %}
                {% if ivar.annotation(::CrymbleUI::Reconcile) %}
                    {% build_var = "_build_#{ivar.name}".id %}
                    {% has_build = @type.instance_vars.any? { |v| v.name == build_var } %}
                    {% if has_build %}
                        # Only reconcile if build value didn't change (app didn't change it)
                        if @{{build_var}} == old_widget.as({{@type}}).@{{build_var}}
                            assert_no_constructor_layer(@{{ivar.name}}, old_widget.as({{@type}}).@{{ivar.name}})
                            @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                            adopt_reconciled_layer(@{{ivar.name}}, old_widget)
                        end
                    {% else %}
                        # No build tracking (manual @[Reconcile]) — always reconcile
                        assert_no_constructor_layer(@{{ivar.name}}, old_widget.as({{@type}}).@{{ivar.name}})
                        @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                        adopt_reconciled_layer(@{{ivar.name}}, old_widget)
                    {% end %}
                {% end %}
            {% end %}
        end

        # A @[Reconcile]-carried Layer keeps the OLD (discarded) widget as its owner_widget.
        # Re-point it to this new instance, or Layer.active_layers' in_tree? walk (owner → root)
        # can't find it → the compositor silently drops the layer AND pull-based bounds go stale.
        # Generic on purpose: fires for EVERY reconciled Layer, so a widget that adds a new layer
        # never has to remember a manual per-layer re-sync (the drag-overlay-invisible-after-rebuild
        # bug this replaces). No-op for non-Layer reconciled properties.
        protected def adopt_reconciled_layer(value, old_widget : Widget) : Nil
            if value.is_a?(::CrymbleUI::Layer) && value.owner_widget == old_widget
                value.owner_widget = self
            end
        end

        # The reconcile-partner of adopt_reconciled_layer, and its INVARIANT guard.
        # A @[Reconcile] Layer must be created LAZILY in perform_layout (@x ||= Layer.new),
        # never in the constructor: a constructor-created layer is immediately displaced by
        # the carried one on the first reconcile and leaks into @@all_layers (its owner is the
        # live new instance, so in_tree? never reaps it). All own-layer widgets create lazily
        # (ScrollView, VirtualMatrix, WindowPanel, LayerBox, Popup) → `current` is nil here on
        # a fresh instance, so this asserts silently. A future widget that regresses to
        # constructor creation trips it LOUD. Called BEFORE the overwrite, so `current` is the
        # new instance's ivar and `incoming` the carried old one.
        # `current.same?(incoming)` keeps it false-positive-safe under the DOUBLE auto_copy of
        # override-then-super widgets (VirtualMatrix): pass 2 sees current == incoming == the
        # already-carried layer (adopt set it in pass 1). No-op for non-Layer properties.
        protected def assert_no_constructor_layer(current, incoming) : Nil
            assert(
                !current.is_a?(::CrymbleUI::Layer) || current.same?(incoming),
                "a @[Reconcile] Layer must be created lazily in perform_layout (@x ||= Layer.new), " \
                "not in the constructor — a constructor-created layer leaks into @@all_layers every reconcile"
            )
        end

        # Copy internal state from old widget during reconciliation
        # Override this in subclasses for custom logic (e.g., callback re-wiring)
        # Call auto_copy_reconcile_properties(old_widget) first, then add custom logic
        # Base implementation copies background_backend, constraints, focus, and all @[Reconcile] properties
        def copy_state_from(old_widget : Widget)
            # CRITICAL: Only preserve background_backend (clean layer background behind widget)
            # Do NOT copy widget_backend - it contains old rendered content!
            # If we copied widget_backend and rendered on top, we'd get double rendering
            # The widget_backend will be recreated fresh during rendering

            # Copy background_backend from old widget (if it exists)
            # Note: We can't check size here because layout hasn't happened yet
            # Size validation happens during rendering (invariant g will catch mismatches)
            if old_bg = old_widget.background_backend
                @background_backend = old_bg
                {% if flag?(:DEBUG_RENDER) %}
                    puts "[COPY_STATE] #{self.class.name.split("::").last}##{path_id} <- copied background (backend=#{old_bg.object_id}, size=#{old_bg.width}x#{old_bg.height})"
                {% end %}
            end

            # Copy cached constraints (enables layout skipping after rebuild)
            @last_constraints = old_widget.@last_constraints

            # Transfer focus if old widget had it (applies to all focusable widgets)
            # This ensures flash animation continues on the new widget after rebuild
            if old_widget.focused?
                Widget.focus_manager?.try &.transfer_focus(old_widget, self)
            end

            # Auto-copy all @[Reconcile] annotated properties. This also re-adopts every
            # reconciled Layer (adopt_reconciled_layer) so a carried layer never keeps the
            # old, discarded widget as its owner_widget.
            auto_copy_reconcile_properties(old_widget)

            # Backstop for a `layer` override whose backing field is NOT a @[Reconcile]
            # property (Window returns @root_layer, created fresh per instance). Idempotent
            # for the common case — @internal_layer et al. are already re-adopted above.
            if self.responds_to?(:layer) && (lyr = self.layer)
                lyr.owner_widget = self
            end
        end

        # === PRIMITIVE-BASED RENDERING (New Architecture) ===

        # Cache policy for primitive generation
        # Subclasses override this to declare their caching behavior
        # Default: Dynamic (cache primitives, invalidate on state change)
        def cache_policy : CachePolicy
            CachePolicy::Dynamic
        end

        # Generate primitives describing what to draw
        # Subclasses override this to use primitive rendering
        # Default: empty array (widget uses old render() path)
        # Base class handles all caching via get_primitives()
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            [] of DrawPrimitive
        end

        # The residual primitive-cache validity key: this widget's content_rev (visual changes) +
        # layout_rev (size). Both monotonic, so the wrapping &+ sum is a pure monotonic key (never
        # raising); a bump on either axis forces a regenerate. Theme/zoom are NOT summed here (see the
        # method body): a rendered Dynamic widget captures them via its Cached node version, a zoom bump
        # also moves layout_rev, and a theme switch reaches the residual via rebuild — so the global
        # theme_rev counter was deleted. This AUGMENTS the old `needs_render? || nil` key (blind to
        # theme/zoom swaps, which issue no mark_needs_render).
        def primitive_cache_rev : UInt64
            # The residual version for Static / Never / pre-first-render widgets only
            # (rendered Dynamic widgets use the node version). Theme/zoom dropped here: Dynamic widgets
            # auto-capture them via the Cached node; a zoom change also bumps layout_rev (relayout); and a
            # theme switch reaches the residual via rebuild. The global theme_rev counter is now deleted.
            @content_rev &+ @layout_rev
        end

        # The per-widget version the render-trigger aggregate folds. For a rendered
        # Dynamic widget this is the pull node's version (auto-captured theme/zoom + touch-driven local
        # rev) — so the trigger moves iff this widget's primitives WOULD change, correct-by-construction
        # and more precise than the global rev (only widgets that read theme move on a theme swap). For
        # Static (cached forever — currently unused by any widget), Never (re-rendered every frame,
        # triggered elsewhere — drag ghost, cursor overlay), and a not-yet-rendered Dynamic widget fall
        # back to the hand-rolled primitive_cache_rev — a DECIDED PERMANENT residual (reseating these
        # no-node cases onto Cached nodes is awkward + zero value). version() is CHEAP — re-folds, never recomputes.
        def primitives_version : UInt64
            if cache_policy == CachePolicy::Dynamic && (node = @primitives_node)
                node.version
            else
                primitive_cache_rev
            end
        end

        # Get primitives (may be cached)
        # Renderer calls this method - never call to_primitives directly
        # Base class manages caching based on cache_policy
        def get_primitives(bounds : Rect) : Array(DrawPrimitive)
            case cache_policy
            when CachePolicy::Never
                # Always generate fresh (menus, popups, animations)
                to_primitives(bounds)

            when CachePolicy::Dynamic
                # The cache is a pull node. Its recompute (to_primitives) auto-captures
                # the theme/zoom it reads; content/layout are signalled via touch() from
                # mark_needs_render / mark_needs_layout. The node memoizes and re-derives only on a real
                # change — correct-by-construction (a global edge the widget reads can't be forgotten).
                @primitives_bounds = bounds
                node = @primitives_node
                unless node
                    node = Cached(Array(DrawPrimitive)).new { to_primitives(@primitives_bounds) }
                    # When this node goes value-stale, enqueue THIS widget into its layer's
                    # selective-render index — the pull-side replacement for mark_needs_render's push
                    # (which still COEXISTS). Fires once per clean→stale edge.
                    node.on_dirty = -> { enqueue_dirty_to_layer }
                    @primitives_node = node
                end
                node.get

            when CachePolicy::Static
                # Cache primitives forever (window chrome, static content)
                @cached_primitives ||= to_primitives(bounds)
            else
                # This should never happen (all enum values covered)
                raise "Unknown cache policy: #{cache_policy}"
            end
        end

        # Invalidate primitive cache (called on state changes)
        def invalidate_primitive_cache
            @cached_primitives = nil
            @primitives_node.try(&.touch)
        end

        # Check if widget has valid cached primitives (for scroll optimization)
        # Returns true if primitives were generated and haven't been invalidated
        def has_valid_primitive_cache? : Bool
            if node = @primitives_node
                node.valid? # Dynamic policy: fresh iff the node's memoized value is current
            else
                !@cached_primitives.nil?
            end
        end

        # === END PRIMITIVE-BASED RENDERING ===

        # === PER-WIDGET TEXTURE BACKEND ===

        # Get widget's render backend (nil if not yet created)
        def widget_backend : RenderBackend?
            @widget_backend
        end

        # Set widget's render backend (managed by renderer)
        def widget_backend=(backend : RenderBackend?)
            @widget_backend = backend
            @last_rendered_layer_position = nil if backend.nil?
        end

        # Get background backend (nil if not yet captured)
        def background_backend : RenderBackend?
            @background_backend
        end

        # Set background backend (managed by renderer)
        def background_backend=(backend : RenderBackend?)
            @background_backend = backend
            # When background is invalidated (set to nil), reset the rendered flag
            # This allows re-capturing background at new position/size
            if backend.nil?
                @rendered_to_layer_at_current_bounds = false
            end
        end

        # Check if widget has rendered to layer at current bounds (for invariant h)
        def rendered_to_layer_at_current_bounds? : Bool
            @rendered_to_layer_at_current_bounds
        end

        # Mark that widget has rendered to layer (called by renderer after blit)
        def mark_rendered_to_layer!
            @rendered_to_layer_at_current_bounds = true
        end

        # Layer position where widget was last rendered (for centralized stale-background detection)
        def last_rendered_layer_position : Tuple(Int32, Int32)?
            @last_rendered_layer_position
        end

        def last_rendered_layer_position=(pos : Tuple(Int32, Int32)?)
            @last_rendered_layer_position = pos
        end

        # Check if this widget and all ancestors have positive bounds (cached).
        # Used by valid_layer_dimensions? to avoid O(depth) walk every frame.
        def ancestry_bounds_valid? : Bool
            if cached = @ancestry_bounds_valid
                return cached
            end
            valid = bounds.width > 0 && bounds.height > 0
            if valid && (p = @parent)
                valid = p.ancestry_bounds_valid?
            end
            @ancestry_bounds_valid = valid
            valid
        end

        # Recursively invalidate ancestry_bounds_valid cache on this widget and all descendants.
        # Called when a parent (e.g., TreeNode) collapses and zeros children bounds —
        # without this, cached `true` values persist and layer compositing continues
        # for child-owned layers (e.g., VirtualMatrix viewport_cache), causing ghost pixels.
        # Check if this widget is reachable from root via parent chain.
        # Used by reconciliation validator to detect orphaned widgets.
        # Zero bounds and invalidate all caches. Called when a widget becomes hidden
        # (e.g., TreeNode collapse). Ensures no stale cached state persists —
        # prevents ghost pixels, stale primitive caches, and stale ancestry_bounds.
        def zero_bounds!
            @bounds = Rect.zero
            invalidate_last_constraints
            @cached_primitives = nil
            @primitives_node.try(&.touch)
            self.background_backend = nil
            self.widget_backend = nil
            @ancestry_bounds_valid = nil
            # A vacated footprint releases the cached pixels of the WHOLE subtree, not just
            # this node. Otherwise a descendant keeps stale bounds + a cached widget_backend,
            # and a viewport_cache layer's visit-all-visible pass re-blits it next frame as a
            # ghost (it never traverses through this now-zeroed node to discover it's gone).
            # Recursing also frees the hidden subtree's GPU backends — a perf win, not a cost.
            @children.each(&.zero_bounds!)
        end

        def widget_in_tree?(root : Widget) : Bool
            current : Widget? = self
            while current
                return true if current == root
                current = current.parent
            end
            false
        end

        # === END PER-WIDGET TEXTURE BACKEND ===

        # Hit test - check if point is inside widget
        def hit_test(point : Vec2) : Widget?
            # If children can escape bounds, check them first even if point is outside parent
            if @children_escape_bounds
                @children.reverse_each do |child|
                    if hit = child.hit_test(point)
                        return hit
                    end
                end
            end

            # Check if point is in this widget's bounds (use absolute coordinates)
            return nil unless absolute_bounds.contains_point(point)

            # Check children (if we haven't already due to escape_bounds)
            unless @children_escape_bounds
                @children.reverse_each do |child|
                    if hit = child.hit_test(point)
                        return hit
                    end
                end
            end

            # Return self if no child was hit
            self
        end

        # Trigger click event (for testing)
        def trigger_click
            on_click
        end

        # Click event handler (override in subclasses)
        def on_click
            # Default: do nothing
        end

        # Whether this widget claimed the mouse_down for its own purpose
        # (e.g., resize), suppressing DragManager tracking.
        def suppresses_drag? : Bool
            false
        end

        # Right-click callback (set by caller, dispatched from on_mouse_down)
        property on_right_click_handler : Proc(Vec2, Nil)? = nil

        # Hover text shown in statusbar when mouse is over this widget
        property hover_text : String? = nil

        # Mouse event handlers (override in subclasses for drag support)
        def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
            # Bring containing panel to front if inside one
            bring_containing_panel_to_front
            if button == MouseButton::Right
                # Bubble up: find nearest ancestor with right-click handler
                current : Widget? = self
                while current
                    if handler = current.on_right_click_handler
                        handler.call(point)
                        break
                    end
                    current = current.parent
                end
            end
        end

        def on_mouse_move(point : Vec2)
            # Default: do nothing
        end

        def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
            # Default: do nothing
        end

        # Preferred cursor when hovering this widget (override in subclasses)
        # Return nil to use default Arrow cursor
        def preferred_cursor(point : Vec2) : CursorType?
            nil
        end

        def on_mouse_enter
            # Default: do nothing
        end

        def on_mouse_exit
            # Default: do nothing
        end

        # === FOCUS AND KEYBOARD INPUT ===

        # Check if widget can receive keyboard focus
        # Override in focusable widgets (TextInput, etc.)
        def focusable? : Bool
            false
        end

        # Called when widget gains keyboard focus
        def on_focus
            # Request scroll-into-view from any parent ScrollView
            request_scroll_into_view
        end

        # Request parent ScrollView (if any) to scroll this widget into view
        private def request_scroll_into_view
            current = @parent
            while current
                if current.responds_to?(:scroll_to_visible)
                    current.scroll_to_visible(self)
                    break
                end
                current = current.parent
            end
        end

        # Called when widget loses keyboard focus
        def on_blur
            # Default: do nothing
        end

        # Handle key down event
        # Returns true if event was handled
        def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
            false  # Not handled
        end

        # Handle text input (printable characters)
        def on_text_input(char : Char)
            # Default: do nothing
        end

        # Request keyboard focus for this widget
        def request_focus
            return unless focusable?
            Widget.focus_manager?.try &.focus(self)
        end

        # Release keyboard focus (if this widget has it)
        def release_focus
            if fm = Widget.focus_manager?
                fm.clear_focus if fm.focused?(self)
            end
        end

        # Check if this widget has keyboard focus
        def focused? : Bool
            Widget.focus_manager?.try(&.focused?(self)) || false
        end

        # === PROXY FOCUS ===
        #
        # Proxy focus lets a parent container (e.g. VirtualMatrix) delegate focus
        # visuals and keyboard events to a child widget without giving it real
        # FocusManager focus. The container stays focused (owns grid navigation)
        # but forwards events to the proxy-focused child.
        #
        # **Widget contract for cells/children:**
        # - `focusable?` → return true so the container knows this widget can
        #   accept proxy focus
        # - `activate_proxy_focus` / `deactivate_proxy_focus` → override for
        #   setup/teardown (e.g. TextInput starts/stops cursor blink)
        # - `effectively_focused?` → returns true when either real-focused or
        #   proxy-focused; use this for rendering decisions (cursor, highlight)
        # - `wants_arrow_keys?` → return true to consume arrow keys (TextInput
        #   FullEdit mode), return false to let the container handle grid nav
        #   (TextInput QuickEntry mode)
        #
        # **Event forwarding rules (in VirtualMatrix):**
        # - Enter, Escape, Backspace, Delete, Home, End → always forwarded
        # - Arrow keys → forwarded only if `wants_arrow_keys?` returns true
        # - Tab → not forwarded; the matrix consumes it to round-robin its cell
        #   cursor (spreadsheet semantics) and stays focused. A focus-scope grid
        #   that consumes Tab is a keyboard focus trap BY DESIGN — Ctrl+Tab
        #   (panel cycling) is the intended escape hatch, so don't "fix" the
        #   missing Tab-order leak.
        #   The complement (overlay cell-editors): a cell editor that opens an
        #   overlay and steals real focus (e.g. ComboBox's dropdown TextInput) is
        #   NOT a proxy, so this forwarding doesn't apply — instead it must commit
        #   and re-dispatch Tab back to its focus-scope ancestor itself (see
        #   ComboBox#wire_popup_tab_callback), so Tab never escapes the matrix.
        # - Text input → always forwarded
        #
        # **Default behavior:** The base Widget implementation works for simple
        # widgets — just sets `@proxy_focused` bool and calls `mark_needs_render`.
        # Only override for special behavior (e.g. TextInput cursor blink).

        # Whether this widget has proxy focus (parent container delegates focus visuals)
        property proxy_focused : Bool = false

        # True if widget has real focus OR proxy focus (use for rendering decisions)
        def effectively_focused? : Bool
          focused? || @proxy_focused
        end

        # True if this widget renders its own text caret when (effectively) focused,
        # so a container's cursor-cell flash would just compete with it. VirtualMatrix
        # suppresses its whole-cell flash on cursor cells that return true.
        def draws_edit_caret? : Bool
          false
        end

        # Called by parent container to activate proxy focus on this widget.
        # Override for setup (e.g. TextInput starts cursor blink).
        def activate_proxy_focus
          @proxy_focused = true
          mark_needs_render
        end

        # Called by parent container to deactivate proxy focus on this widget.
        # Override for teardown (e.g. TextInput stops cursor blink).
        def deactivate_proxy_focus
          @proxy_focused = false
          mark_needs_render
        end

        # Whether this widget defines a focus scope boundary.
        # FocusCycler won't recurse into children of focus scope widgets.
        def is_focus_scope? : Bool
          false
        end

        # Whether this widget currently wants to consume arrow keys.
        # Used by proxy focus containers to decide whether to forward arrows
        # or handle grid navigation.
        def wants_arrow_keys? : Bool
          false
        end

        # === END PROXY FOCUS ===

        # === END FOCUS AND KEYBOARD INPUT ===

        # Find and bring to front any WindowPanel ancestor
        private def bring_containing_panel_to_front
            current = @parent
            while current
                if current.is_a?(WindowPanel)
                    current.as(WindowPanel).bring_to_front
                    return
                end
                current = current.parent
            end
        end


        # Schedule a timer callback
        # delay: how long to wait before firing
        # repeating: if true, timer repeats every delay interval
        # Returns timer ID that can be used to cancel
        def schedule_timer(delay : Time::Span, repeating : Bool = false, &block : -> Nil) : Int32
            Widget.scheduler.schedule(delay, repeating, &block)
        end

        # Cancel a scheduled timer
        def cancel_timer(timer_id : Int32)
            Widget.scheduler.cancel(timer_id)
        end

        # Find widget by ID in this subtree
        def find_by_id(target_id : String) : Widget?
            return self if @id == target_id

            @children.each do |child|
                if found = child.find_by_id(target_id)
                    return found
                end
            end

            nil
        end

        # Find widget by path ID in this subtree
        def find_by_path(target_path : String) : Widget?
            return self if path_id == target_path

            @children.each do |child|
                if found = child.find_by_path(target_path)
                    return found
                end
            end

            nil
        end

        # Find all widgets matching predicate
        def find_all(&block : Widget -> Bool) : Array(Widget)
            results = [] of Widget
            results << self if yield self

            @children.each do |child|
                results.concat(child.find_all(&block))
            end

            results
        end

        # Find all WindowPanel widgets reachable from this subtree — an O(#panels × depth)
        # registry scan (WindowPanel.@@all_panels), not a tree walk. `self` is the root argument
        # (widget_in_tree? walks a candidate panel's parent chain looking for `self`).
        def find_all_panels : Array(WindowPanel)
            WindowPanel.all_in_tree(self)
        end

        # Find ancestor Window
        def find_window : Window?
            current = @parent
            while current
                return current.as(Window) if current.is_a?(Window)
                current = current.parent
            end
            nil
        end

        # Find the topmost (highest z_index) non-closed WindowPanel in this subtree
        def find_topmost_panel : WindowPanel?
            panels = find_all_panels.reject(&.closed)
            return nil if panels.empty?
            panels.max_by(&.z_index)
        end

        # Find all Popup widgets reachable from this subtree — an O(#popups × depth) registry
        # scan (Popup.@@all_popups), not a tree walk. Also finds Window overlay popups (added via
        # Window#add_overlay, which sets popup.parent = window directly rather than adding it to
        # @children) since widget_in_tree? follows the parent chain regardless of how it got set.
        def find_all_popups : Array(Popup)
            Popup.all_in_tree(self)
        end

        # === LAYER OWNER NOTIFICATION BROADCASTING ===
        # These methods broadcast notifications to all LayerOwner descendants.
        # Used by WindowPanel to notify ScrollView (and other layer owners) of
        # size/z-index changes without direct type coupling.
        # Position changes are handled by pull-based bounds (compute_bounds_for_layer).

        # Broadcast z-index change to all LayerOwner descendants
        protected def notify_layer_owners_z_index_changed(new_z : Int32)
          @children.each do |child|
            if child.responds_to?(:on_ancestor_z_index_changed)
              child.on_ancestor_z_index_changed(new_z)
            end
            child.notify_layer_owners_z_index_changed(new_z)
          end
        end

        # Clear render state recursively
        def clear_render_state_recursive
            Widget.increment_state_sweep_visits # perf-audit: bump once per node visited
            @state = WidgetState::Clean
            @children.each(&.clear_render_state_recursive)
        end

        # Reset all render-related caches (for graceful degradation recovery)
        # Clears: cached_primitives, widget_backend, background_backend
        # Used when exception occurs mid-frame and caches may be corrupted
        def reset_render_caches_recursive
            @cached_primitives = nil
            @primitives_node.try(&.touch)
            @widget_backend = nil
            @background_backend = nil
            @rendered_to_layer_at_current_bounds = false
            @children.each(&.reset_render_caches_recursive)
        end

        # Debug: print widget tree
        def dump_tree(indent : Int32 = 0)
            prefix = "  " * indent
            puts "#{prefix}#{self.class.name} (id: #{@id || "nil"}, path: #{path_id})"
            @children.each { |child| child.dump_tree(indent + 1) }
        end

        # Default inspect for readable spec output (can be overridden by subclasses)
        def inspect(io : IO)
            io << "#{self.class.name}(id=#{@id.inspect}, bounds=#{@bounds})"
        end
    end
end
