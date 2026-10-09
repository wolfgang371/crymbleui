require "../core/types"
require "../core/scheduler"
require "../rendering/renderer"
require "../rendering/draw_primitive"
require "../rendering/layer_renderer"
require "../rendering/render_trigger"
require "./test_render_backend"
require "../rendering/pixel_snap"
require "../input/shortcut_manager"
require "../input/keyboard_dispatch"
require "../input/mouse_dispatch"
require "../input/event_batch"
require "../widgets/window"
require "./keys"
require "./test_clipboard"

module CrymbleUI
  module Testing
    # Full headless renderer for testing
    # Similar to Renderer interface but without SFML dependencies
    # Tracks all render operations for performance testing
    # Note: Does NOT implement Renderer module - headless testing has limitations
    class TestRenderer
      include LayerRenderer

      getter backend : TestRenderBackend  # Main window buffer
      getter scheduler : Scheduler
      getter shortcut_manager : ShortcutManager

      # Tracking
      getter render_frame_count : Int32 = 0
      getter compositor_call_count : Int32 = 0
      getter backend_blit_count : Int32 = 0
      getter exceptions_caught : Int32 = 0  # Graceful degradation counter
      getter last_exception_message : String? = nil

      # The same, across every renderer in the process (docs/GRACEFUL_DEGRADATION.md)
      class_getter frame_exceptions_swallowed : Int32 = 0
      class_getter last_frame_exception_message : String? = nil

      # Cursor tracking
      getter current_cursor : CursorType = CursorType::Arrow

      # Window background color (synced from app each frame)
      property background_color : Color = Color.new(255, 255, 255, 255)

      # Layout tracking (delegates to Widget class variable)
      def layout_count : Int32
        Widget.layout_count
      end

      @running : Bool = false
      @app : App?  # Store app for event simulation methods
      # The shared pull decision (same seam the SFML loop uses) — drives render_frame_if_needed.
      @render_trigger = RenderTrigger.new
      @mouse = MouseDispatch.new # the mouse path SFMLRenderer takes (mouse_down/move/up, deliver)
      @flushed_after_frame = false # the last frame's end applied work still to be painted (App#finish_frame)

      # Track all layer backends for primitive counting
      @layer_backends : Array(TestRenderBackend) = [] of TestRenderBackend
      getter layer_backends

      # Track all widget backends (for cached widget rendering)
      @widget_backends : Array(TestRenderBackend) = [] of TestRenderBackend
      getter widget_backends

      # Per-frame render disposition: widget object_id → :rendered | :blitted | :skipped. Populated by
      # record_widget_disposition (the shared render path's paint points), cleared each frame, so specs
      # can assert "this cell was painted, and how" instead of sampling pixels. A culled/absent widget
      # has no entry (nil) — exactly the grow-ghost signature.
      @frame_dispositions = {} of UInt64 => Symbol
      getter frame_dispositions

      # Override of the shared paint-point hook (no-op in the SFML renderer).
      protected def record_widget_disposition(widget : Widget, disposition : Symbol) : Nil
        @frame_dispositions[widget.object_id] = disposition
      end

      # How was this widget painted in the most recent frame? nil = not painted (culled/absent).
      def widget_disposition(widget : Widget) : Symbol?
        @frame_dispositions[widget.object_id]?
      end

      def initialize(width : Int32 = 800, height : Int32 = 600)
        @backend = TestRenderBackend.new(width, height)  # Window buffer
        @scheduler = Scheduler.new
        @shortcut_manager = ShortcutManager.new

        # Set global scheduler for widgets (shortcut manager not set in headless mode)
        Widget.scheduler = @scheduler
        # Give widgets a FocusManager so keyboard-driven tests (arrow nav, typed
        # input) work out of the box. SfmlRenderer sets one UNCONDITIONALLY; here it
        # is CONDITIONAL so it never clobbers an instance a suite spec_helper or a
        # spec already set + holds a reference to. crymbleui's spec_helper sets one
        # at load + clears focus per-test, so this is inert there; for consumers
        # whose suite does NOT pre-set one (e.g. embrace), this lazily provides a
        # shared fm — a gui spec that needs clean INITIAL focus should reset it.
        Widget.focus_manager = FocusManager.new unless Widget.focus_manager?
        # Same rule for the clipboard, and for the same reason: copy/cut/paste paths
        # reach `Widget.clipboard`, which RAISES when unset — so a consumer suite that
        # never installs one (embrace does not) would fail on the raise rather than on
        # the behaviour under test. CONDITIONAL so it cannot clobber the instance
        # crymbleui's own spec_helper installs and its specs hold references to.
        Widget.clipboard = TestClipboard.new unless Widget.clipboard?
        # The REAL ShortcutManager, not a stub. `register_shortcut` in the DSL returns early when
        # none is installed, so with the stub in place NO shortcut in a headless test was ever
        # registered — a dialog's Escape, a confirm box's Enter and every panel binding were
        # unreachable, and a spec could only assert that the code calling register_shortcut ran.
        # The manager is pure lookup over SF key enums and needs no window, so headless can have
        # the real thing; fire one with `Widget.shortcut_manager.trigger("Escape", panel)`.
        # CONDITIONAL for the same reason as the focus manager above: never clobber an instance a
        # suite's spec_helper installed and holds a reference to.
        Widget.shortcut_manager = @shortcut_manager unless Widget.shortcut_manager?

        # Baseline for the per-frame zoom-epoch check (see render_frame). Seed to the
        # current epoch so a fresh renderer only reacts to zoom changes during its life
        # (an initial layout already measures at the current zoom).
        @last_zoom_epoch = FontSizing.zoom_epoch
      end

      # Resize the window buffer — simulates an OS window resize. The next render_frame lays out
      # at the new size, while widget/layer backends created at the previous size are REUSED (they
      # live on the widgets, not here). This is what exposes a stale primitive cache: a fill_rect
      # cached at the old width re-rendered onto the grown widget_backend leaves a transparent
      # right-edge strip that composites as the window background — exactly the live symptom. The
      # two-separate-renderers pattern cannot show this (a fresh renderer first-renders at the new
      # size, so nothing is stale).
      def resize(width : Int32, height : Int32)
        @backend = TestRenderBackend.new(width, height)
      end

      # Reset all performance counters
      def reset_counters
        @render_frame_count = 0
        @compositor_call_count = 0
        @backend_blit_count = 0
        Widget.reset_layout_count
        @backend.reset_counters
        @layer_backends.each(&.reset_counters)
        @widget_backends.each(&.reset_counters)
      end

      # Get total primitive count across all layer AND widget backends
      # Widget backends are used for per-widget caching (Chrome, MenuBar, etc.)
      def primitive_count : Int32
        total = 0
        @layer_backends.each do |backend|
          total += backend.primitive_count
        end
        @widget_backends.each do |backend|
          total += backend.primitive_count
        end
        total
      end

      # Register a widget backend for tracking (called from layer_renderer)
      def register_widget_backend(backend : TestRenderBackend)
        @widget_backends << backend unless @widget_backends.includes?(backend)
      end

      # Get total clear count across all backends (window + layers)
      def backend_clear_count : Int32
        total = @backend.clear_count
        @layer_backends.each do |backend|
          total += backend.clear_count
        end
        total
      end

      # Count only layer backend clears (excludes window background clear)
      # Useful for testing that layers aren't re-rendering during drag
      def layer_backend_clear_count : Int32
        total = 0
        @layer_backends.each do |backend|
          total += backend.clear_count
        end
        total
      end

      # Render until the app is where the live loop would idle: after the first frame, only while SFML's
      # loop would render one - a pending rebuild, the input barrier, or a moved frame aggregate
      # (RenderTrigger, the pull decision it shares). The old test - "no new primitives and no new clears" -
      # counted the window's own background clear, which happens every frame, so it never held and every
      # settle rendered all max_frames frames; most of a GUI suite's compositing was those idle frames.
      # APPS RENDERED — an OPT-IN list of every app a TestRenderer rendered or delivered to while it is armed, so a
      # suite can release them between examples (release_rendered_apps). A discarded app is never released by
      # anything else: its widgets stay registered with the global zoom and theme Sources, and a grid's overlays
      # and rulers (layer-hosted) hold the grid, so every example's trees, layers and frame buffers would stay
      # reachable - the crymbleui suite reached the machine's memory limit that way. Off by default: an
      # always-on list would pin exactly what it exists to release.
      class_property rendered_apps : Array(App)? = nil

      # Put `app` on the list, once - while it is armed.
      def self.record_rendered(app : App) : Nil
        @@rendered_apps.try { |apps| apps << app unless apps.any?(&.same?(app)) }
      end

      # Release every app on the list (release_app), and empty it. The apps must be done with: their trees are
      # torn down.
      def self.release_rendered_apps : Nil
        return unless apps = @@rendered_apps
        apps.each { |app| release_app(app) }
        apps.clear
      end

      # Release a discarded app the way a rebuild releases a discarded tree: its layers (Layer#release - the
      # surface, and the widgets standing on them, which @children does not reach), its window's overlays, then
      # its root (Widget#dispose_subtree - pull nodes, links, backend references).
      def self.release_app(app : App) : Nil
        return unless root = app.root
        Layer.active_layers(root).each(&.release(nil))
        root.as?(Window).try { |window| window.overlays.each(&.dispose_subtree) }
        root.dispose_subtree
      end

      def settle_rendering(app : App, max_frames : Int32 = 10)
        max_frames.times do |i|
          break if i > 0 && !loop_would_render?(app)
          render_frame(app)
        end
      end

      # Render a frame ONLY if the pull trigger says to (the same decision the SFML loop makes via
      # RenderTrigger), and report whether it rendered. This is the seam that makes the loop's
      # "render this frame?" decision spec-testable: drive an interaction through App.handle_*, then
      # assert render_frame_if_needed — true when the change should repaint, false on an idle no-op.
      def render_frame_if_needed(app : App) : Bool
        # A pending rebuild is a render signal SEPARATE from the aggregate pull (should_render?): a
        # structural change or a timer-driven app-state change requests a rebuild off the input path. Honor
        # it here too — else the rebuild sits unprocessed until some unrelated aggregate change happens to
        # fire a frame. Mirrors the SFML main loop, which applies needs_rebuild? after timers, not only on
        # the event path.
        if loop_would_render?(app)
          render_frame(app)
          true
        else
          false
        end
      end

      # Whether SFML's run loop would render a frame now, without input: a pending rebuild (also a
      # non-blocking one, which lifts no barrier), the input barrier, or a moved frame aggregate. ONE
      # predicate for settle_rendering and render_frame_if_needed, so neither drifts from the loop.
      def loop_would_render?(app : App) : Bool
        app.needs_rebuild? || app.input_waits_for_frame? || @flushed_after_frame ||
          @render_trigger.should_render?(app)
      end

      # Check if running (for tests, always false since no event loop)
      def running? : Bool
        @running
      end

      # Render a single frame (for testing)
      # Can accept either App or Widget directly
      def render_frame(app : App)
        @render_frame_count += 1
        @app = app  # Store for event simulation methods
        TestRenderer.record_rendered(app)
        app.start # as SFMLRenderer#run does before its first frame (once; later frames find it started)

        # Mirror the SFML zoom response. In SFML a registered FontSizing.on_zoom_change
        # callback drops caches + forces re-layout the instant zoom changes; headless
        # has no persistent callback, so detect the epoch change per-frame and run the
        # SAME shared response. Without this, headless zoom bumped the epoch but never
        # re-laid-out — so zoom-dependent width bugs (e.g. an open dropdown) were
        # invisible to specs. Runs before layout so widths re-measure this frame.
        if @last_zoom_epoch != FontSizing.zoom_epoch
          @last_zoom_epoch = FontSizing.zoom_epoch
          apply_zoom_change(app.root)
        end

        # Sync background color from app (app may override; nil = white default).
        @background_color = app.app_background_color || Color.new(255, 255, 255, 255)

        # Clear widget backends before each frame
        # Backends will re-register as widgets render, ensuring we only count active backends
        @widget_backends.clear
        @frame_dispositions.clear

        begin
          # Process pending rebuild (matches SFML event loop behavior).
          # Without this, headless tests skip the reconciliation path,
          # hiding bugs that only manifest after widget tree rebuild.
          if app.needs_rebuild?
            app.rebuild
          end

          # Prepare layout (increments layout_count if layout happens)
          window_size = Size.new(@backend.width.to_f, @backend.height.to_f)
          did_layout = app.prepare_layout(window_size)

          # Invalidate layer cache after layout (layer set may have changed)
          invalidate_layer_cache if did_layout

          # Cheap-rebuild staleness: after a rebuild + layout (layer.widgets now repopulated), mark only
          # the layers whose content actually changed (replaces the old unconditional post-rebuild clear).
          # Guarded on did_layout: a rebuild always forces a full root re-layout (fresh ⇒ NeedsLayout).
          if app.rebuild_needs_assessment
            if did_layout && (root = app.root)
              assess_rebuild_staleness(root)
            end
            app.rebuild_needs_assessment = false
          end

          # Re-detect hover after layout (restores hover state after rebuild)
          # Matches SFML renderer behavior
          app.redetect_hover if did_layout

          if root_widget = app.root
            # All layer logic handled by LayerRenderer
            # Include ghost and highlight layers if drag-and-drop is active
            render_all_layers(root_widget, app.drag_manager.ghost_layer, app.drag_manager.highlight_layer)

            # Clear render state after rendering (same as SFMLRenderer)
            # This marks widgets as Clean so cache optimization works correctly
            app.clear_render_state unless did_layout
          end
        rescue exception
          # A post-release use is a DEFECT, never a transient frame hiccup, so it must not enter
          # graceful degradation: that path recovers by nil-ing every widget and layer backend, i.e.
          # it would abandon the whole GPU working set once per frame while hiding the very bug this
          # error exists to report. Let it out.
          raise exception if exception.is_a?(RenderDefect)
          handle_frame_exception(exception, app)
        else
          note_frame_completed
        end

        end_frame(app)
        report_frame_failure(app)
        @applied_title = title_to_apply(app)
      end

      # The window title the SFML renderer would show after this frame (title_to_apply, applied at the frame's tail)
      getter applied_title : String?

      # The frame's end, the same in both renderers and reached by every frame: stamp the aggregate it
      # rendered at, THEN apply the structural work of widgets that did not paint (App#finish_frame) - its
      # marks must move the trigger after the stamp, and the loop must not idle before the frame that
      # paints them. A flush that raised comes out of the frame: a spec never passes over it.
      private def end_frame(app : App) : Nil
        @render_trigger.record(app)
        @flushed_after_frame = app.finish_frame
      end

      # Handle exception during frame rendering (graceful degradation)
      private def handle_frame_exception(exception : Exception, app : App)
        @exceptions_caught += 1
        @last_exception_message = "#{exception.message}\n#{exception.backtrace?.try(&.first(5).join("\n"))}"
        @@frame_exceptions_swallowed += 1
        @@last_frame_exception_message = @last_exception_message
        note_frame_failure(exception)
        app.reset_all_caches
        app.root.try(&.mark_needs_layout)
      end

      # Render primitives directly
      def render_primitives(primitives : Array(DrawPrimitive))
        reject_window_direct_clips(primitives)
        primitives.each { |primitive| @backend.execute_primitive(primitive) }
      end

      # === LayerRenderer Abstract Methods ===

      # Create test backend for layer, tracked for primitive counting
      def create_layer_backend(width : Int32, height : Int32) : RenderBackend
        TestRenderBackend.new(width, height).tap { |backend| @layer_backends << backend }
      end

      # Create test backend for widget (per-widget texture)
      # NOTE: Uses transparent background (alpha=0) to match SFML RenderTexture behavior
      # This allows tests to detect size-mismatch bugs where uninitialized pixels leak through
      def create_widget_backend(width : Int32, height : Int32) : RenderBackend
        backend = TestRenderBackend.new(width, height, Color.new(0_u8, 0_u8, 0_u8, 0_u8))
        register_widget_backend(backend)
        backend
      end

      # Composite layer to window buffer - the SFML compositor's region (composite_region: clip, viewport-cache
      # sample, snap), so headless composite parity holds by construction
      def composite_layer_to_window(layer : Layer, clip : Rect?)
        return unless backend = layer.backend
        return unless backend.is_a?(TestRenderBackend)
        LayerRenderer.frame_composite_count += 1 # Instrumentation - counted as SFMLRenderer counts it
        LayerRenderer.frame_viewport_cache_count += 1 if layer.viewport_cache # Instrumentation - as SFMLRenderer

        if region = composite_region(layer, clip, backend.width, backend.height)
          backend.blit_region_to(@backend, region.src_x, region.src_y, region.width, region.height,
                                 region.dest_x, region.dest_y, use_alpha_blend: true, opacity: layer.opacity, blend_mode: layer.blend_mode)
          @backend_blit_count += 1
        end

        # Draw the chrome border (e.g. a WindowPanel's) fresh each frame — NOT cached, so a
        # resize leaves no ghost border. Asked polymorphically (responds_to? :chrome_border),
        # not by sniffing the layer id + downcasting; mirrors the SFML renderer. A layer's
        # owner_widget owns it, so this fires once for the panel's own layer, never its
        # children's. (Popup borders are drawn by Popup#foreground_primitives.)
        if (owner = layer.owner_widget) && owner.responds_to?(:chrome_border)
          draw_chrome_border(owner.chrome_border)
        end
      end

      # Draw a 1px chrome border directly on the window buffer (not cached in any layer).
      private def draw_chrome_border(border : NamedTuple(bounds: Rect, color: Color))
        @backend.draw_rect(border[:bounds], border[:color])
      end

      # Clear window buffer to background color
      def clear_window_background
        @backend.clear(@background_color)
      end

      # Instrumentation: Track compositor calls
      def increment_compositor_call_count
        @compositor_call_count += 1
      end


      # === Event Simulation Methods ===

      # The mouse, through MouseDispatch - the path SFMLRenderer's run loop takes (a press focuses what
      # it hits; a move drags while a button is down, else hovers) - then the cursor where it updates it.
      def mouse_down(x : Float64, y : Float64)
        return unless app = @app
        @mouse.press(app, Vec2.new(x, y))
      end

      def mouse_move(x : Float64, y : Float64)
        return unless app = @app
        point = Vec2.new(x, y)
        @mouse.move(app, point)
        update_cursor(app, point) if @mouse.cursor_after_move?(app)
      end

      def mouse_up(x : Float64, y : Float64)
        return unless app = @app
        point = Vec2.new(x, y)
        @mouse.release(app, point)
        update_cursor(app, point) # after every release, as MouseDispatch#cursor_point says
      end

      # Delivers keyboard and mouse events the way the SFML run loop does: dispatched through
      # KeyboardDispatch and MouseDispatch in batches that EventBatch delimits, one frame after each
      # batch, then settled. This is the path for anything that depends on how QUEUED input interleaves
      # with frames (a script typing, a click and typing arriving during a slow frame): key_down and
      # mouse_down render or not on their own, so a spec built on them cannot see a batch at all. Build
      # the events with Testing::Keys.
      def deliver(app : App, events : Array(LibCSFML::Event)) : Nil
        Widget.app = app # as SFMLRenderer#run does: widgets reach the app (and its input barrier) here
        TestRenderer.record_rendered(app)
        keyboard = KeyboardDispatch.new(Widget.focus_manager, Widget.shortcut_manager)
        queue = Deque(LibCSFML::Event).new(events)
        until queue.empty?
          EventBatch.drain(app, -> { queue.shift? }) do |event|
            if keyboard.keyboard_event?(event)
              keyboard.handle(event, app)
            elsif @mouse.mouse_event?(event)
              @mouse.handle(event, app)
              @mouse.cursor_point(event, app).try { |at| update_cursor(app, at) }
            else
              raise ArgumentError.new("deliver takes keyboard and mouse events, got #{event.type}")
            end
          end
          render_frame(app)
        end
        settle_rendering(app)
      end

      # Faithful headless key dispatch — same routing as SFMLRenderer (focused
      # widget first, then spatial focus navigation on a declined arrow), via the
      # shared FocusManager#dispatch_key. Use this (not bare handle_key_down) so
      # focus-escape bugs are observable headlessly. Renders a frame after.
      def key_down(key : SF::Keyboard::Key, control : Bool = false, shift : Bool = false, alt : Bool = false) : Bool
        return false unless app = @app
        return false unless root = app.root
        handled = Widget.focus_manager.dispatch_key(key, control, shift, alt, root)
        render_frame(app)
        handled
      end

      # Update cursor based on what's under the mouse (test instrumentation)
      private def update_cursor(app : App, point : Vec2)
        @current_cursor = app.get_cursor_for_point(point)
      end

      # Simulate drag sequence (down -> moves -> up)
      def simulate_drag(from_x : Float64, from_y : Float64, to_x : Float64, to_y : Float64, steps : Int32 = 10)
        return unless app = @app

        reset_counters

        # Mouse down
        mouse_down(from_x, from_y)
        render_frame(app)

        # Interpolate movement
        dx = (to_x - from_x) / steps
        dy = (to_y - from_y) / steps

        steps.times do |i|
          x = from_x + dx * (i + 1)
          y = from_y + dy * (i + 1)
          mouse_move(x, y)
          render_frame(app)
        end

        # Mouse up
        mouse_up(to_x, to_y)
        render_frame(app)
      end
    end
  end
end
