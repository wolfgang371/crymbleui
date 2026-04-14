require "./types"
require "./scheduler"
require "./cache_policy"
require "./font"
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
    # Used by render_property, layout_property, and reconcile_property macros
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

        # Render count instrumentation (for testing optimization)
        @@render_count : Int32 = 0
        @@cache_render_count : Int32 = 0

        # Layout count instrumentation (for testing optimization)
        @@layout_count : Int32 = 0

        # Measure count instrumentation (for testing VStack/HStack optimization)
        @@measure_count : Int32 = 0

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
        end

        # Get the global font
        def self.font : Font?
            @@font
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

            # Delegate to Font implementation (SFML or headless)
            font.measure_text(text, size)
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

        # Visibility - hidden widgets are skipped in layout/render/hit-test
        @visible : Bool = true

        def visible? : Bool
          @visible
        end

        def visible=(value : Bool)
          return if @visible == value
          @visible = value
          mark_needs_layout
        end

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
        # Managed by base class - subclasses never touch this
        @cached_primitives : Array(DrawPrimitive)?

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

        # Flag: widget exited viewport and needs fresh background on re-entry
        # WORKAROUND for SFML RenderTexture limitation:
        #   - When widget exits viewport, its region in layer texture still has old pixels
        #   - We CANNOT clear that region because: fill_rect draws to render target,
        #     but blit_region reads from TEXTURE which isn't updated until display()
        #   - Calling display() after fill_rect breaks rendering
        #   - So instead we track that this widget needs "fresh" background on re-entry
        #   - During capture, we fill with background_color instead of blit_region
        # This is the same pattern as layer.buffer_just_cleared (Bug 1 fix)
        # Set by ScrollView when widget exits, cleared after capture
        @needs_fresh_background : Bool = false

        # Layer position where widget was last rendered (for auto-detecting stale background).
        # Cleared when widget_backend is disposed (scroll exit, rebuild).
        @last_rendered_layer_position : Tuple(Int32, Int32)? = nil

        # Last constraints used for layout (for incremental layout optimization)
        # If current constraints match and widget is clean, layout can be skipped
        @last_constraints : BoxConstraints?

        # Zoom epoch at last layout (forces re-layout when zoom changes)
        @last_zoom_epoch : UInt64 = 0

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

        # Property macros for widget properties with automatic invalidation and optional reconciliation
        #
        # Invalidation behavior:
        #   layout_property   →  mark_needs_layout on setter (implies render)
        #   render_property   →  mark_needs_render on setter
        #   reconcile_property   →  no invalidation (just reconcile)
        #
        # Reconciliation behavior:
        #   - reconcile_property: ALWAYS adds @[Reconcile] annotation
        #   - layout_property/render_property: Only add @[Reconcile] if `reconcile = true` is passed
        #
        # Usage:
        #   render_property background_color : Color = Color::White              # No reconcile
        #   render_property hover_state : Bool = false, reconcile = true         # With reconcile
        #   layout_property padding : Float64 = 0.0                              # No reconcile
        #   layout_property scroll_offset : Vec2 = Vec2.zero, reconcile = true   # With reconcile
        #   reconcile_property interaction_mode : InteractionMode = InteractionMode::None  # Always reconciled

        # render_property: mark_needs_render on setter
        # reconcile: if true, preserve this value during widget reconciliation (default: false)
        # When reconciled, a shadow @_build_<name> tracks the build-time value.
        # During reconciliation, if build value changed, app's value wins over old state.
        macro render_property(declaration, reconcile = false)
            {% if declaration.is_a?(TypeDeclaration) %}
                {% if reconcile %}
                    @[::CrymbleUI::Reconcile]
                {% end %}
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% if reconcile %}
                        @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% end %}
                {% else %}
                    @{{declaration.var}} : {{declaration.type}}
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}} = value
                    mark_needs_render
                end
            {% end %}
        end

        # layout_property: mark_needs_layout on setter (implies render)
        # reconcile: if true, preserve this value during widget reconciliation (default: false)
        macro layout_property(declaration, reconcile = false)
            {% if declaration.is_a?(TypeDeclaration) %}
                {% if reconcile %}
                    @[::CrymbleUI::Reconcile]
                {% end %}
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% if reconcile %}
                        @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% end %}
                {% else %}
                    @{{declaration.var}} : {{declaration.type}}
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}} = value
                    mark_needs_layout
                end
            {% end %}
        end

        # reconcile_property: Auto-reconcile only, no invalidation on setter
        # Use for internal state that must survive rebuilds but doesn't directly affect rendering
        # Examples: interaction_mode, drag state, internal flags
        # When a default value exists, a shadow @_build_<name> tracks the build-time value
        # so reconciliation can detect when the app changed it (app wins over old state).
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

        # Check if widget needs rendering (either NeedsRender or NeedsLayout)
        def needs_render? : Bool
            @state >= WidgetState::NeedsRender
        end

        # Check if widget needs layout
        def needs_layout? : Bool
            @state == WidgetState::NeedsLayout
        end

        # Clear state to Clean (for testing purposes only)
        def clear_state_for_test
            @state = WidgetState::Clean
        end

        # Check if layout can be skipped (incremental layout optimization)
        # Returns true if widget is clean AND constraints match last layout AND zoom unchanged
        protected def can_skip_layout?(constraints : BoxConstraints) : Bool
            return false if needs_layout?
            return false if @last_constraints.nil?
            return false if @last_zoom_epoch != FontSizing.zoom_epoch
            @last_constraints == constraints
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

        # Perform actual layout (implemented by subclasses)
        # Called by layout() after skip check passes
        # Subclasses must set @bounds and layout children
        abstract def perform_layout(constraints : BoxConstraints, position : Vec2)

        # Auto-copy all @[Reconcile] annotated properties from old widget
        # Called by copy_state_from - widgets can override copy_state_from for custom logic
        # Note: Only reconcile_property always adds @[Reconcile]. For layout_property/render_property,
        # you must pass `reconcile = true` to get the annotation.
        protected def auto_copy_reconcile_properties(old_widget : Widget)
            {% for ivar in @type.instance_vars %}
                {% if ivar.annotation(::CrymbleUI::Reconcile) %}
                    {% build_var = "_build_#{ivar.name}".id %}
                    {% has_build = @type.instance_vars.any? { |v| v.name == build_var } %}
                    {% if has_build %}
                        # Only reconcile if build value didn't change (app didn't change it)
                        if @{{build_var}} == old_widget.as({{@type}}).@{{build_var}}
                            @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                        end
                    {% else %}
                        # No build tracking (manual @[Reconcile]) — always reconcile
                        @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                    {% end %}
                {% end %}
            {% end %}
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

            # Auto-copy all @[Reconcile] annotated properties
            auto_copy_reconcile_properties(old_widget)
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

        # Get primitives (may be cached)
        # Renderer calls this method - never call to_primitives directly
        # Base class manages caching based on cache_policy
        def get_primitives(bounds : Rect) : Array(DrawPrimitive)
            case cache_policy
            when CachePolicy::Never
                # Always generate fresh (menus, popups, animations)
                to_primitives(bounds)

            when CachePolicy::Dynamic
                # Cache primitives, invalidate on state change (buttons, text)
                should_regenerate = needs_render? || @cached_primitives.nil?

                if should_regenerate
                    @cached_primitives = to_primitives(bounds)
                end
                @cached_primitives.not_nil!

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
        end

        # Check if widget has valid cached primitives (for scroll optimization)
        # Returns true if primitives were generated and haven't been invalidated
        def has_valid_primitive_cache? : Bool
            !@cached_primitives.nil?
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

        # Check if widget needs fresh background (exited viewport, layer has stale content)
        def needs_fresh_background? : Bool
            @needs_fresh_background
        end

        # Set needs_fresh_background flag (set by ScrollView on exit, cleared by renderer after capture)
        def needs_fresh_background=(value : Bool)
            @needs_fresh_background = value
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
            self.background_backend = nil
            self.widget_backend = nil
            invalidate_ancestry_bounds_cache
        end

        def widget_in_tree?(root : Widget) : Bool
            current : Widget? = self
            while current
                return true if current == root
                current = current.parent
            end
            false
        end

        def invalidate_ancestry_bounds_cache
            @ancestry_bounds_valid = nil
            @children.each(&.invalidate_ancestry_bounds_cache)
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
        # - Tab → never forwarded (falls through to FocusManager)
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

        # Find all WindowPanel widgets in this subtree
        def find_all_panels : Array(WindowPanel)
            panels = [] of WindowPanel
            collect_panels_recursive(panels)
            panels
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

        # Recursively collect all WindowPanel widgets
        protected def collect_panels_recursive(panels : Array(WindowPanel))
            if self.is_a?(WindowPanel)
                panels << self.as(WindowPanel)
            end
            @children.each do |child|
                child.collect_panels_recursive(panels)
            end
        end

        # Find all Popup widgets in this subtree
        def find_all_popups : Array(Popup)
            popups = [] of Popup
            collect_popups_recursive(popups)
            popups
        end

        # Recursively collect all Popup widgets
        protected def collect_popups_recursive(popups : Array(Popup))
            if self.is_a?(Popup)
                popups << self.as(Popup)
            end
            @children.each do |child|
                child.collect_popups_recursive(popups)
            end
        end

        # === LAYER OWNER NOTIFICATION BROADCASTING ===
        # These methods broadcast notifications to all LayerOwner descendants.
        # Used by WindowPanel to notify ScrollView (and other layer owners) of
        # size/z-index changes without direct type coupling.
        # Position changes are handled by pull-based bounds (compute_bounds_for_layer).

        # Broadcast resize move to all LayerOwner descendants
        protected def notify_layer_owners_resize_move(dw : Float64, dh : Float64, dx : Float64 = 0.0, dy : Float64 = 0.0)
          @children.each do |child|
            if child.responds_to?(:on_ancestor_resize_move)
              child.on_ancestor_resize_move(dw, dh, dx, dy)
            end
            child.notify_layer_owners_resize_move(dw, dh, dx, dy)
          end
        end

        # Broadcast resize end to all LayerOwner descendants
        protected def notify_layer_owners_resize_end
          @children.each do |child|
            if child.responds_to?(:on_ancestor_resize_end)
              child.on_ancestor_resize_end
            end
            child.notify_layer_owners_resize_end
          end
        end

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
            @state = WidgetState::Clean
            @children.each(&.clear_render_state_recursive)
        end

        # Reset all render-related caches (for graceful degradation recovery)
        # Clears: cached_primitives, widget_backend, background_backend
        # Used when exception occurs mid-frame and caches may be corrupted
        def reset_render_caches_recursive
            @cached_primitives = nil
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
