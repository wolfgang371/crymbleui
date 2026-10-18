require "../csfml3/lib" # LibCSFML::Event and its enums: DATA only - the input model events arrive in
require "../core/types"
require "../core/theme"
require "../core/input_log"
require "../core/widget"
require "../core/app"
require "./render_trigger"
require "./frame_work_log"
require "../core/scheduler"
require "../core/font_sizing"
require "../input/shortcut_manager"
require "../input/focus_manager"
require "../input/keyboard_dispatch"
require "../input/mouse_dispatch"
require "../input/event_batch"
require "../widgets/window_panel"
require "./draw_primitive"
require "./layer_renderer"

module CrymbleUI
  # The platform-neutral half of a renderer that owns a window: the loop's decisions, event dispatch, cursor
  # choice, the frame and the composite decisions. A platform (SFMLRenderer natively, WebRenderer in the web
  # flavour) supplies the hooks below - the window, its events, presenting a frame, the cursor and title, and
  # drawing a layer region or a border onto the window - so both platforms run the SAME decisions, not copies.
  #
  # Driving the loop. Natively SFMLRenderer#run blocks (it waits for events or the next timer). A host that owns
  # the frame clock (a browser's requestAnimationFrame) calls `start` once and then `tick` per frame: one
  # iteration with the waits taken out, built from the same pieces run is built from.
  abstract class WindowRenderer
    include LayerRenderer # Shared layer rendering logic

    property background_color : Color
    getter scheduler : Scheduler
    getter shortcut_manager : ShortcutManager
    getter focus_manager : FocusManager

    # Track window title to avoid setting every frame
    @current_title : String = ""

    # Track last mouse move time for event coalescing
    @last_mouse_move_time : Time::Instant = Time.instant

    # The cursor installed last; apply_cursor runs only when it changes
    @current_cursor : CursorType = CursorType::Arrow

    # The app `start` set up; `tick` drives it (the renderer holds it: on the web it is how the app stays
    # reachable between ticks).
    @app : App? = nil
    # The first tick renders whatever else it finds (run's local initializer does the same for run).
    @first_frame_pending = false
    # The ledgers close once: a host keeps calling tick after the window closed.
    @run_finished = false

    # App-level PULL render-trigger: render a frame iff the version-keyed aggregate moved since
    # the last render — the correct-by-construction replacement for the any_needs_render? dirty walk
    # (which can MISS a change nobody marked, e.g. a theme swap). Preserves the event-driven 0%-idle:
    # no versioned change → same aggregate → no frame. The decision itself lives in RenderTrigger, a
    # shared headless seam so a spec can exercise it (TestRenderer#render_frame_if_needed) — the loop's
    # pull decision is no longer un-testable. PRIMARY: the version-keyed aggregate; BACKSTOP: the dirty
    # walk, kept until the aggregate's completeness is spec+interactively proven (removing it = final
    # flag deletion).
    @render_trigger = RenderTrigger.new

    def initialize
      # Default background
      @background_color = Theme.current.app_background

      # Create scheduler for timers
      @scheduler = Scheduler.new
      Widget.scheduler = @scheduler

      # Create shortcut manager for keyboard shortcuts
      @shortcut_manager = ShortcutManager.new
      Widget.shortcut_manager = @shortcut_manager

      # Create focus manager for keyboard focus
      @focus_manager = FocusManager.new
      Widget.focus_manager = @focus_manager

      # Routes the keyboard events; kept out of this class so a spec can drive it headlessly.
      @keyboard = KeyboardDispatch.new(@focus_manager, @shortcut_manager)
      @mouse = MouseDispatch.new
      @flushed_after_frame = false # the last frame's end applied work still to be painted (App#finish_frame)

      # Per-frame work ledger (writes only when ENV["CRYMBLE_WORKLOG"] is set; otherwise a no-op).
      @work_log = FrameWorkLog.new
    end

    # === Platform hooks ===

    # Whether there is a window at all (false headless). Every "has a window" guard of the shared half asks
    # this - NOT window_open?: after quit inside a dispatch, the loop's tail still renders one frame on the
    # closed window, and that frame's end (App#finish_frame, reporting) must run.
    protected abstract def has_window? : Bool
    # Whether the window is still open: only the loop's condition asks this.
    protected abstract def window_open? : Bool
    protected abstract def window_size : Size
    # The next queued event, nil when the queue is empty. Never waits.
    protected abstract def poll_event : LibCSFML::Event?
    protected abstract def close_window : Nil
    # Show the frame just drawn. Timed as LayerRenderer.phase_display_ms (nothing else is).
    protected abstract def display_window : Nil
    # Platform work after a displayed frame (SFML: free what this frame released).
    protected abstract def after_display : Nil
    # Show what a frame that raised left drawn - a stale frame is better than a black hole. Contract: if showing
    # raises, the after_display work is skipped (the platform's state is unknown then).
    protected abstract def present_after_failure : Nil
    protected abstract def apply_window_title(title : String) : Nil
    protected abstract def apply_cursor(cursor : CursorType) : Nil
    # The window was resized to width x height (the platform keeps its drawing 1:1 with it).
    protected abstract def on_window_resized(width : Int32, height : Int32) : Nil
    # Draw one layer region onto the window (the region composite_region computed), with the layer's opacity
    # and blend mode.
    protected abstract def draw_layer_region(backend : RenderBackend, region : CompositeRegion, opacity : Float64,
                                             blend_mode : BlendMode) : Nil
    # Draw a 1px chrome border directly on the window (not cached in any layer).
    protected abstract def draw_border_rect(bounds : Rect, color : Color) : Nil
    # Draw window-direct primitives (already checked: no PushClip/PopClip among them).
    protected abstract def draw_primitives(primitives : Array(DrawPrimitive)) : Nil

    # Called at the top of every loop iteration (run's and tick's), before anything else: platform work that
    # has to land before this iteration's input and frame (the web: an image decode or a restored canvas
    # invalidates rendering). No-op natively.
    protected def before_iteration : Nil
    end

    # === Driving the loop ===

    # Run's prelude: the app is set up for this renderer. Run calls it; a host that drives `tick` calls it once.
    def start(app : App) : Nil
      # Set global app reference for widgets to trigger rebuilds
      Widget.app = app
      @app = app

      # Set up quit callback so app can request window close
      app.quit_callback = -> { close_window }

      # NOTE: Scheduler callback removed - it was marking root which invalidated ALL backgrounds!
      # Individual widgets (CPUMonitor, etc.) already call mark_needs_render themselves
      # Marking root caused invalidate_children_backgrounds to cascade to entire tree
      # Result: all widgets re-captured backgrounds every timer tick → garbage accumulation

      # Build initial widget tree (or rebuild if already built to register shortcuts)
      # First build happens in CrymbleUI.run before renderer exists (to get window dimensions)
      # This rebuild ensures shortcuts get registered now that ShortcutManager exists
      app.build_tree
      app.start # the app's on_start: its timers find the scheduler from here on

      # Register zoom change callback for cache invalidation
      # This ensures font reload and texture invalidation happen regardless of
      # whether zoom is changed via keyboard (Ctrl+/-/0) or direct API call
      FontSizing.on_zoom_change = -> { apply_zoom_change(app.root) }

      @first_frame_pending = true
    end

    # Whether the window is open (false headless and after the app quit).
    def open? : Bool
      has_window? && window_open?
    end

    # One iteration of the loop without its waits - for a host that owns the frame clock. Returns whether it
    # rendered a frame. The gate on input is the no-timer branch's (not while the input barrier is up, nor after
    # a frame whose end applied work still to be painted): a host frame paints the deferred work first and
    # takes the input at the next tick.
    def tick : Bool
      return false unless app = @app
      unless open?
        finish_run
        return false
      end
      before_iteration
      needs_redraw = @first_frame_pending
      @first_frame_pending = false
      event_count = 0
      unless app.input_waits_for_frame? || @flushed_after_frame
        drained, asked = drain_events(app)
        event_count += drained
        needs_redraw = true if asked
      end
      unless (verdict = fire_timers(app)).nil?
        needs_redraw = verdict
      end
      finish_iteration(app, needs_redraw, event_count)
    end

    # Drain the queued events through dispatch (EventBatch: a batch ends early at an event that raises the
    # input barrier). Returns how many were dispatched and whether one of them asked for a redraw.
    private def drain_events(app : App) : {Int32, Bool}
      needs_redraw = false
      count = EventBatch.drain(app, -> { poll_event }) do |event|
        needs_redraw = true if dispatch(event, app)
      end
      {count, needs_redraw}
    end

    # Run expired timers. nil when none fired; else whether to redraw - which the caller ASSIGNS (a timer's
    # verdict replaces what the events asked for: the loop's rule, kept as it is).
    private def fire_timers(app : App) : Bool?
      fired_count = @scheduler.run_expired_timers
      return nil unless fired_count > 0
      # Timers may have changed widget state (e.g., CPUMonitor marks itself)
      # Individual widgets mark their layers as dirty, so check layers not root
      # This is more precise than marking root (which invalidates all backgrounds!)
      needs_redraw = any_layer_needs_render?(app)
      # Also check overlay primitives (splash screen animation driven by timer)
      if !needs_redraw
        if has_window?
          size = window_size
          needs_redraw = !app.overlay_primitives(size.width, size.height).nil?
        end
      end
      # Composite-only request (e.g., cursor flash opacity toggle)
      if !needs_redraw
        needs_redraw = app.needs_composite_only?
      end
      needs_redraw
    end

    # The tail every loop iteration runs: a pending rebuild, else the pull; the barrier's and the flushed
    # frame's force; the frame. Returns whether it rendered.
    private def finish_iteration(app : App, needs_redraw : Bool, event_count : Int32) : Bool
      # Apply a pending rebuild — requested by an EVENT handler OR a TIMER callback that changed app
      # state. This runs every iteration, NOT only `if event_count > 0`: a timer-driven request_rebuild
      # (a live clock, polled data, a state-based animation) used to be dropped when idle and deferred to
      # the next input event — the "frozen until you move the mouse, then a rebuild on every move" class.
      # (Timer-driven mark_needs_render was already honored via any_layer_needs_render? above; only the
      # separate needs_rebuild? signal was gated on input.)
      if app.needs_rebuild?
        {% if flag?(:DEBUG_RENDER) %}
          puts "\n[REBUILD CHECK @ loop] needs_rebuild? = true (#{event_count} events)"
          app.root.try { |root| app.find_widgets_needing_layout(root) }
        {% end %}
        # App state changed - rebuild tree with reconciliation
        app.rebuild
        needs_redraw = true
      elsif !needs_redraw
        # Render needed (no rebuild) — decided by the aggregate-rev pull, which subsumes the old
        # root.needs_layout? / needs_render? dirty checks (layout_rev/content_rev are in the aggregate).
        needs_redraw = any_layer_needs_render?(app)
      end

      # The barrier is lifted only by a frame: without one, EventBatch would never drain again. Nor
      # may the loop idle after a frame whose end applied work that still has to be painted.
      needs_redraw = true if app.input_waits_for_frame? || @flushed_after_frame

      # Render once per frame with latest state (after processing all events)
      if needs_redraw
        render_frame(app) # stamps the aggregate it rendered at, so the next pull idles until it moves
        true
      else
        # Events processed but no redraw triggered - this is where we save CPU!
        false
      end
    end

    # After the loop: close the ledgers, once.
    private def finish_run : Nil
      return if @run_finished
      @run_finished = true
      @work_log.close # flush + close the frame ledger on exit
      InputLog.close  # ...and the keyboard trace, with its received-vs-accepted trailer
    end

    private def any_layer_needs_render?(app : App) : Bool
      @render_trigger.should_render?(app)
    end

    # === Events ===

    # Dispatch one polled event. Returns true if it requires a redraw.
    private def dispatch(event : LibCSFML::Event, app : App) : Bool
      @last_mouse_move_time = Time.instant if event.type == LibCSFML::EventType::MouseMoved
      handle_event(event, app) || event.type == LibCSFML::EventType::MouseButtonPressed ||
        event.type == LibCSFML::EventType::MouseButtonReleased ||
        event.type == LibCSFML::EventType::KeyPressed ||
        event.type == LibCSFML::EventType::Resized
    end

    # Handle a single event
    # Returns true if event requires redraw
    private def handle_event(event : LibCSFML::Event, app : App) : Bool
      handle_event_impl(event, app)
    rescue ex
      app.report_event_exception(ex)
      false
    end

    private def handle_event_impl(event : LibCSFML::Event, app : App) : Bool
      case event.type
      when LibCSFML::EventType::TextEntered, LibCSFML::EventType::KeyPressed, LibCSFML::EventType::KeyReleased,
           LibCSFML::EventType::FocusLost
        @keyboard.handle(event, app)
      when LibCSFML::EventType::MouseWheelScrolled
        # Everything below is read from the event and the keyboard's event-stream state, never from
        # the live devices: a queued wheel event belongs where and how it happened (KeyboardDispatch).
        # Ctrl+MouseWheel = zoom: a widget's own content (on_zoom_wheel), else the UI's font (App)
        if @keyboard.control?
          wheel = event.mouse_wheel_scroll
          app.handle_ctrl_wheel(wheel.delta.to_f64, Vec2.new(wheel.position.x.to_f64, wheel.position.y.to_f64))
          return true
        end

        # Dispatch wheel event to widgets, at the position the wheel turned
        wheel = event.mouse_wheel_scroll
        mouse_pos = Vec2.new(wheel.position.x.to_f64, wheel.position.y.to_f64)
        # Note: SFML delta is positive for scroll up, negative for scroll down
        # Check wheel axis - touchpad can generate horizontal scroll events
        delta = case wheel.wheel
                when LibCSFML::MouseWheel::Horizontal
                  Vec2.new(wheel.delta.to_f64, 0.0) # Horizontal scroll → X
                else
                  Vec2.new(0.0, wheel.delta.to_f64) # Vertical scroll → Y
                end
        # Shift turns the wheel horizontal
        app.handle_mouse_wheel(delta, mouse_pos, @keyboard.shift?)
        # Update hover after scroll - content under mouse has changed
        app.update_hover(mouse_pos)
        true # Redraw after scroll
      when LibCSFML::EventType::Closed
        # Let app handle close request (can save data, show dialogs, etc.)
        # App calls quit() when ready to actually close
        app.handle_close_request
        false
      when LibCSFML::EventType::MouseButtonPressed, LibCSFML::EventType::MouseButtonReleased,
           LibCSFML::EventType::MouseMoved
        # MouseDispatch: the path TestRenderer#deliver takes too. The cursor shape needs the window.
        redraw = @mouse.handle(event, app)
        if at = @mouse.cursor_point(event, app)
          redraw = update_cursor(app, at) || redraw
        end
        redraw
      when LibCSFML::EventType::Resized
        on_window_resized(event.size.size.x.to_i, event.size.size.y.to_i) if has_window?
        # Mark root as needing layout to trigger re-layout with new size
        app.root.try &.mark_needs_layout
        false # Caller handles redraw for resize events
      else
        false
      end
    end

    # Update cursor based on what's under the mouse
    # Returns true if cursor changed (needs redraw), false otherwise
    private def update_cursor(app : App, point : Vec2) : Bool
      return false unless has_window?

      # Ask app for cursor type (app has all the business logic)
      cursor_type = app.get_cursor_for_point(point)

      set_cursor(cursor_type)
    end

    # Set the window cursor (only if changed)
    # Returns true if cursor changed, false otherwise
    private def set_cursor(cursor_type : CursorType) : Bool
      return false if @current_cursor == cursor_type
      return false unless has_window?

      apply_cursor(cursor_type)
      @current_cursor = cursor_type
      true # Cursor changed
    end

    # === Compositing ===

    # Composite layer to window - the region composite_region computes (clip, sample, snap), the
    # viewport-cache sample included
    def composite_layer_to_window(layer : Layer, clip : Rect?)
      return unless has_window?
      return unless backend = layer.backend

      # Skip compositing if owner widget should not render (e.g., closed panels)
      if owner = layer.owner_widget
        return if owner.skip_render?
      end

      LayerRenderer.frame_composite_count += 1 # Instrumentation
      LayerRenderer.frame_viewport_cache_count += 1 if layer.viewport_cache # Instrumentation

      if region = composite_region(layer, clip, backend.width, backend.height)
        # TRACE: Log compositor state for debugging ScrollView-in-Panel issues
        if ENV["CRYMBLE_TRACE"]? == "1"
          File.open("/tmp/compositor_trace.log", "a") do |f|
            f.puts "COMPOSITE layer=#{layer.id} bounds=#{layer.bounds} viewport_cache=#{layer.viewport_cache} " \
                   "SAMPLE src=(#{region.src_x},#{region.src_y}) size=(#{region.width},#{region.height}) -> dest=(#{region.dest_x},#{region.dest_y})"
          end
        end
        draw_layer_region(backend, region, layer.opacity, layer.blend_mode)
      end

      # Draw the chrome border (e.g. a WindowPanel's) fresh each frame — NOT cached, so a
      # resize leaves no ghost border. Asked polymorphically (responds_to? :chrome_border),
      # not by sniffing the layer id + downcasting. A layer's owner_widget is the widget that
      # owns it, so this fires once for the panel's own layer and never for its children's.
      # (Popup borders are drawn by Popup#foreground_primitives, after its children.)
      if (owner = layer.owner_widget) && owner.responds_to?(:chrome_border)
        border = owner.chrome_border
        draw_border_rect(border[:bounds], border[:color])
      end
    end

    # Render a list of primitives directly to the window (App#overlay_primitives). A window-direct draw has no
    # clip stack, so a list with a clip is refused - before drawing any of it - for every platform alike.
    def render_primitives(primitives : Array(DrawPrimitive))
      return unless has_window?
      reject_window_direct_clips(primitives)
      draw_primitives(primitives)
    end

    # === Frame ===

    # Render a single frame
    def render_frame(app : App)
      return unless has_window? # Headless mode - no window to render to
      unless root = app.root
        end_frame(app) # nothing to paint, but the frame ends as every frame does
        return
      end

      # Sync background color from app (app may override; nil = theme default).
      @background_color = app.app_background_color || Theme.current.app_background

      # Sync window title from root widget (e.g. "MyApp — document.txt")
      apply_title(app)

      # NOTE: Tried reset_gl_states here for texture pooling fix - didn't help.
      # See docs/TEXTURE_POOLING_INVESTIGATION.md

      frame_start = LayerRenderer.profile_enabled ? Time.instant : nil
      did_layout = false # hoisted so the work-log record below (outside begin/rescue) can read it

      begin
        # Perform layout if needed (timed)
        layout_start = Time.instant
        window_size = self.window_size
        did_layout = app.prepare_layout(window_size)
        LayerRenderer.phase_layout_ms = (Time.instant - layout_start).total_milliseconds
        if frame_start
          LayerRenderer.record_profile("layout", LayerRenderer.phase_layout_ms)
        end

        # Invalidate layer cache after layout (layer set may have changed)
        invalidate_layer_cache if did_layout

        # Cheap-rebuild staleness: after a rebuild + layout (layer.widgets now repopulated), mark only
        # the layers whose content actually changed (replaces the old unconditional post-rebuild clear).
        # Guarded on did_layout: a rebuild always forces a full root re-layout (fresh ⇒ NeedsLayout).
        if app.rebuild_needs_assessment
          if did_layout && (r = app.root)
            assess_rebuild_staleness(r)
          end
          app.rebuild_needs_assessment = false
        end

        # Re-detect hover after layout (restores hover state after rebuild)
        app.redetect_hover if did_layout

        # Render all layers using shared LayerRenderer logic (timed)
        # Include ghost and highlight layers if drag-and-drop is active
        render_start = Time.instant
        render_all_layers(root, app.drag_manager.ghost_layer, app.drag_manager.highlight_layer)
        # Note: composite timing is set inside render_all_layers
        LayerRenderer.phase_render_ms = (Time.instant - render_start).total_milliseconds - LayerRenderer.phase_composite_ms

        # Clear render state after rendering
        app.clear_render_state unless did_layout

        # Render overlay primitives (splash screen, etc.) directly to window
        if overlay = app.overlay_primitives(window_size.width, window_size.height)
          render_primitives(overlay)
        end

        # Display (timed)
        display_start = Time.instant
        display_window
        LayerRenderer.phase_display_ms = (Time.instant - display_start).total_milliseconds

        # The platform's work after a displayed frame, outside the display timing (SFML: THE one drain
        # point for released RenderTextures - see SFMLRenderer#after_display).
        after_display

        # Cost of this frame, so InputLog can correlate each keystroke with the load at the moment
        # it arrived — the reporter's loss is load-dependent (clean when slow, clean with one Shape,
        # lossy with ten).
        frame_ms = LayerRenderer.phase_layout_ms + LayerRenderer.phase_render_ms +
                   LayerRenderer.phase_composite_ms + LayerRenderer.phase_display_ms
        @keyboard.last_frame_ms = frame_ms
        if InputLog.enabled?
          InputLog.record_frame(frame_ms, did_layout, false,
            LayerRenderer.rendered_layer_ids.any?(&.starts_with?("matrix_content")))
          InputLog.batch_begin # events arriving after this frame form a new batch
        end

        if ENV["CRYMBLE_PERF"]? == "1"
          total = LayerRenderer.phase_layout_ms + LayerRenderer.phase_render_ms + LayerRenderer.phase_composite_ms + LayerRenderer.phase_display_ms
          if total > 1.0  # Only log slow frames (>1ms)
            STDERR.puts "[PERF] total=#{total.round(1)}ms layout=#{LayerRenderer.phase_layout_ms.round(1)} render=#{LayerRenderer.phase_render_ms.round(1)} composite=#{LayerRenderer.phase_composite_ms.round(1)} display=#{LayerRenderer.phase_display_ms.round(1)} layers_rendered=#{LayerRenderer.frame_layers_needing_render} widgets=#{LayerRenderer.frame_widget_count} composites=#{LayerRenderer.frame_composite_count} ids=#{LayerRenderer.rendered_layer_ids.join(",")}"
          end
        end


        if frame_start
          LayerRenderer.record_profile("display", LayerRenderer.phase_display_ms)
        end

        if frame_start
          LayerRenderer.record_profile("render_frame", (Time.instant - frame_start).total_milliseconds)
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
      apply_title(app) # a failure run marks it, the frame that ends one clears it

      {% if flag?(:PERF_LOG) %}
        frame_ms = frame_start ? (Time.instant - frame_start).total_milliseconds : 0.0
        if frame_ms > 1.0 || LayerRenderer.frame_layers_needing_render > 0
          File.open("/tmp/perf_log.txt", "a") do |f|
            f.puts "FRAME: #{frame_ms.round(1)}ms layout=#{LayerRenderer.phase_layout_ms.round(1)}ms render=#{LayerRenderer.phase_render_ms.round(1)}ms composite=#{LayerRenderer.phase_composite_ms.round(1)}ms display=#{LayerRenderer.phase_display_ms.round(1)}ms layers_rendered=#{LayerRenderer.frame_layers_needing_render}/#{LayerRenderer.frame_layers_total} widgets=#{LayerRenderer.frame_widgets_iterated} prims=#{LayerRenderer.frame_primitive_count}"
          end
        end
      {% end %}

      # Per-frame work ledger (no-op unless CRYMBLE_WORKLOG is set) — record BEFORE the counters reset.
      @work_log.record(
        LayerRenderer.phase_layout_ms, LayerRenderer.phase_render_ms,
        LayerRenderer.phase_composite_ms, LayerRenderer.phase_display_ms,
        did_layout, app.mouse_down?)

      # Reset frame counters for next frame (always, even after exception)
      LayerRenderer.reset_frame_counters
      Widget.reset_layout_count

      Widget.increment_render_count
    end

    # The frame's end, the same in both renderers and reached by every frame: stamp the aggregate it
    # rendered at, THEN apply the structural work of widgets that did not paint (App#finish_frame) - its
    # marks must move the trigger after the stamp, and the loop must not idle before the frame that
    # paints them.
    #
    # A flush that raised is reported like an event's exception - the loop runs it outside the frame's
    # rescue - except the defects a frame never degrades over either.
    private def end_frame(app : App) : Nil
      @render_trigger.record(app)
      @flushed_after_frame = app.finish_frame
    rescue ex
      raise ex if ex.is_a?(RenderDefect)
      @flushed_after_frame = true # the others' work ran; paint it
      app.report_event_exception(ex)
    end

    # Handle exception during frame rendering (graceful degradation)
    private def handle_frame_exception(exception : Exception, app : App)
      STDERR.puts "[GRACEFUL_DEGRADATION] Frame exception: #{exception.message}"
      STDERR.puts "  #{exception.backtrace?.try(&.first(3).join("\n  "))}"
      note_frame_failure(exception)
      app.reset_all_caches
      app.root.try(&.mark_needs_layout)
      # CRITICAL: Always display the frame — a stale frame is better than a black hole
      present_after_failure
    end

    # The window shows title_to_apply - written only when it changed.
    private def apply_title(app : App) : Nil
      return unless title = title_to_apply(app)
      return if title == @current_title
      apply_window_title(title)
      @current_title = title
    end
  end
end
