require "../csfml3/wrapper"
require "../core/types"
require "../core/widget"
require "../core/app"
require "../core/scheduler"
require "../core/font_sizing"
require "../input/shortcut_manager"
require "../input/focus_manager"
require "../widgets/window_panel"
require "../widgets/popup"
require "./sfml_paint_context"
require "./sfml_font"
require "./sfml_clipboard"
require "./draw_primitive"
require "./layer_renderer"
require "./crsfml_backend"
require "./render_debug"

module CrymbleUI
  # SFML-based renderer for CrymbleUI applications
  class SFMLRenderer
    include LayerRenderer # Shared layer rendering logic

    getter window : SF::RenderWindow?
    getter paint_context : SFMLPaintContext?
    property background_color : Color
    getter scheduler : Scheduler
    getter shortcut_manager : ShortcutManager
    getter focus_manager : FocusManager

    # Default font for text rendering
    @default_font : SF::Font
    @font_path : String? # Store for font reloading on zoom

    # Track window title to avoid setting every frame
    @current_title : String = ""

    # Texture cache for DrawImage primitives (keyed by file path)
    @texture_cache = Hash(String, SF::Texture).new

    # Track last mouse move time for event coalescing
    @last_mouse_move_time : Time::Instant = Time.instant

    # Cursor caching to avoid expensive hit tests
    @last_cursor_panel : WindowPanel? = nil
    @last_cursor_update_point : Vec2 = Vec2.new(0.0, 0.0)

    # Cursors for different resize/interaction directions
    @cursor_arrow : SF::Cursor
    @cursor_text : SF::Cursor
    @cursor_size_horizontal : SF::Cursor
    @cursor_size_vertical : SF::Cursor
    @cursor_size_nwse : SF::Cursor
    @cursor_size_nesw : SF::Cursor
    @current_cursor : SF::Cursor::Type = SF::Cursor::Arrow

    # Instrumentation: CPU% tracking (like CPUMonitor)
    @@last_cpu_time : UInt64 = 0_u64
    @@last_wall_time : Time::Instant = Time.instant

    @@last_frame_time : Time::Instant = Time.instant

    CLOCK_TICKS_PER_SEC = 100.0 # USER_HZ on most Linux systems

    def self.read_cpu_time : UInt64
      {% if flag?(:linux) %}
        stat = File.read("/proc/self/stat")
        fields = stat.split
        utime = fields[13].to_u64
        stime = fields[14].to_u64
        utime + stime
      {% else %}
        0_u64
      {% end %}
    rescue
      0_u64
    end

    def self.calculate_cpu_percent : Float64
      current_cpu = read_cpu_time
      current_wall = Time.instant
      cpu_delta = current_cpu - @@last_cpu_time
      wall_delta = (current_wall - @@last_wall_time).total_seconds
      @@last_cpu_time = current_cpu
      @@last_wall_time = current_wall
      return 0.0 if wall_delta <= 0
      (cpu_delta.to_f / CLOCK_TICKS_PER_SEC / wall_delta) * 100.0
    end

    def self.frame_delta_ms : Float64
      current = Time.instant
      delta = (current - @@last_frame_time).total_milliseconds
      @@last_frame_time = current
      delta
    end

    # Target framerate for smooth rendering without lag
    TARGET_FPS = 60

    # Embed font at compile time for self-contained binary.
    #
    # ⚠️  WINDOWS GLYPH GARBLING — see docs/WINDOWS_SFML_GL_SYNC_BUG.md
    # On Windows, SFML 3.0.0 + system GL drivers do not synchronize glyph
    # atlas uploads with subsequent reads, causing random characters to
    # render with the wrong glyph (stochastic across process launches).
    # The fix is an out-of-tree patch to SFML's Texture.cpp adding
    # glFinish() after every glTexImage2D / glTexSubImage2D. Without it,
    # text rendering on Windows is non-deterministic. The patched
    # sfml-graphics-s.lib MUST be used for Windows builds.
    EMBEDDED_FONT = {{ read_file(__DIR__+"/../../resources/Cousine-Regular.ttf") }}

    def initialize(
      width : Int32 = 800,
      height : Int32 = 600,
      title : String = "CrymbleUI Application",
      font_path : String? = nil,
      headless : Bool = false,
    )
      # Load font from memory (embedded at compile time) or from file if provided
      @font_path = font_path # Store for reloading on zoom
      @default_font = if font_path
                        SF::Font.from_file(font_path)
                      else
                        SF::Font.from_memory(EMBEDDED_FONT.to_slice)
                      end

      # Create window and paint context (skip if headless mode for testing)
      if headless
        @window = nil
        @paint_context = nil
      else
        @window = SF::RenderWindow.new(
          SF::VideoMode.new(width.to_u32, height.to_u32),
          title
        )
        @window.not_nil!.vertical_sync_enabled = false # otherwise there is always a lag between mouse cursor and e.g. dragged panels
        # On Windows, SFML's framerate limiter uses Sleep() with 15.6ms
        # default granularity, causing severe input lag and dropped events.
        # crymble-ui's own event loop already gates rendering via wait_event
        # and needs_redraw, so the SFML limiter is redundant on Windows.
        # See SFML issues #1962, #2191.
        {% if flag?(:win32) %}
          @window.not_nil!.framerate_limit = 0
        {% else %}
          @window.not_nil!.framerate_limit = TARGET_FPS
        {% end %}
        @paint_context = SFMLPaintContext.new(@window.not_nil!, @default_font)
      end

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

      # Set global font for text measurement (wrap in SFMLFont)
      Widget.font = SFMLFont.new(@default_font)

      # Set global clipboard to the platform (SFML) clipboard
      Widget.clipboard = SFMLClipboard.new

      # Initialize cursors
      @cursor_arrow = SF::Cursor.new
      @cursor_arrow.load_from_system(SF::Cursor::Arrow)

      @cursor_text = SF::Cursor.new
      @cursor_text.load_from_system(SF::Cursor::Text)

      @cursor_size_horizontal = SF::Cursor.new
      @cursor_size_horizontal.load_from_system(SF::Cursor::SizeHorizontal)

      @cursor_size_vertical = SF::Cursor.new
      @cursor_size_vertical.load_from_system(SF::Cursor::SizeVertical)

      # Diagonal cursors: try Linux-specific first, fall back to cross-platform, then arrow
      @cursor_size_nwse = SF::Cursor.new
      unless @cursor_size_nwse.load_from_system(SF::Cursor::SizeTopLeft) ||
             @cursor_size_nwse.load_from_system(SF::Cursor::SizeTopLeftBottomRight)
        @cursor_size_nwse.load_from_system(SF::Cursor::Arrow)
      end

      @cursor_size_nesw = SF::Cursor.new
      unless @cursor_size_nesw.load_from_system(SF::Cursor::SizeBottomLeft) ||
             @cursor_size_nesw.load_from_system(SF::Cursor::SizeBottomLeftTopRight)
        @cursor_size_nesw.load_from_system(SF::Cursor::Arrow)
      end
    end

    # === LayerRenderer Abstract Method Implementations ===

    # Create SFML backend for layer
    def ensure_layer_backend(layer : Layer, width : Int32, height : Int32)
      backend = CrSFMLBackend.acquire(width, height, @default_font)
      layer.backend = backend
      # Force first_render on next render (blank backend)
      layer.reset_first_render
    end

    # Create SFML backend for widget (per-widget texture)
    def create_widget_backend(width : Int32, height : Int32) : RenderBackend
      CrSFMLBackend.acquire(width, height, @default_font)
    end

    # Capture the composited frame to an image (for testing/debugging).
    # Composites all active layers to a temporary RenderTexture using the same
    # blend modes and clipping as the window compositor, then returns the image.
    def capture_composited_frame(app : App) : SF::Image
      window = @window.not_nil!
      w = window.size.x.to_i
      h = window.size.y.to_i
      rt = SF::RenderTexture.new(w.to_u32, h.to_u32)
      rt.clear(SF::Color.new(200, 200, 200, 255))
      root = app.root
      unless root
        rt.display
        return rt.texture.copy_to_image
      end
      layers = Layer.active_layers(root).sort_by(&.z_index)
      layers.each do |layer|
        next unless valid_layer_dimensions?(layer)
        next unless backend = layer.backend
        next unless backend.is_a?(CrSFMLBackend)
        if owner = layer.owner_widget
          next if owner.skip_render?
        end
        clip_w = layer.bounds.width.ceil.to_i
        clip_h = layer.bounds.height.ceil.to_i
        sfml_backend = backend.as(CrSFMLBackend)
        sprite = SF::Sprite.new(sfml_backend.texture)
        # Viewport-cache layers paint at +cache-margin inside their
        # oversized buffer — sample like the live compositor does
        # (Layer#viewport_sample_origin), or the capture shifts their
        # content by the cache margin.
        src_x, src_y = layer.viewport_cache ? layer.viewport_sample_origin(sfml_backend.width, sfml_backend.height, clip_w, clip_h) : {0, 0}
        sprite.texture_rect = SF.int_rect(src_x, src_y, clip_w, clip_h)
        sprite.position = SF.vector2f(layer.bounds.x.round(:ties_away).to_f32, layer.bounds.y.round(:ties_away).to_f32)
        rt.draw(sprite, blend_mode_to_render_states(layer.blend_mode))
      end
      rt.display
      rt.texture.copy_to_image
    end

    # Composite layer to window via sprite
    def composite_layer_to_window(layer : Layer)
      return unless window = @window
      return unless backend = layer.backend
      return unless backend.is_a?(CrSFMLBackend)

      # Skip compositing if owner widget should not render (e.g., closed panels)
      if owner = layer.owner_widget
        return if owner.skip_render?
      end

      LayerRenderer.frame_composite_count += 1 # Instrumentation

      # Clip sprite to visible layer bounds (texture may be larger due to buffer expansion)
      # Use ceil() to avoid clipping bottom/right edge when bounds are fractional
      clip_width = layer.bounds.width.ceil.to_i
      clip_height = layer.bounds.height.ceil.to_i

      # Clip to ancestor panel bounds — layers must not extend beyond their panel
      if panel_bounds = find_ancestor_panel_bounds(layer)
        panel_right = panel_bounds.x + panel_bounds.width
        panel_bottom = panel_bounds.y + panel_bounds.height
        if layer.bounds.x + clip_width > panel_right
          clip_width = Math.max(0, (panel_right - layer.bounds.x).ceil.to_i)
        end
        if layer.bounds.y + clip_height > panel_bottom
          clip_height = Math.max(0, (panel_bottom - layer.bounds.y).ceil.to_i)
        end
      end

      # TRACE: Log compositor state for debugging ScrollView-in-Panel issues
      if ENV["CRYMBLE_TRACE"]? == "1"
        File.open("/tmp/compositor_trace.log", "a") do |f|
          f.puts "COMPOSITE layer=#{layer.id} bounds=(#{layer.bounds.x.round(1)},#{layer.bounds.y.round(1)},#{layer.bounds.width.round(1)},#{layer.bounds.height.round(1)}) clip=(#{clip_width},#{clip_height}) viewport_cache=#{layer.viewport_cache}"
        end
      end

      if layer.viewport_cache
        # Viewport cache compositing: sliding viewport for scrolling layers
        composite_viewport_cache_layer(window, layer, backend, clip_width, clip_height)
      else
        # Standard compositing: simple sprite blit
        sprite = SF::Sprite.new(backend.texture)
        sprite.texture_rect = SF.int_rect(0, 0, clip_width, clip_height)
        sprite.position = SF.vector2f(layer.bounds.x.round(:ties_away).to_f32, layer.bounds.y.round(:ties_away).to_f32)

        # Apply layer opacity (0.0-1.0) during compositing
        if layer.opacity < 1.0
          alpha = (layer.opacity * 255).to_u8
          sprite.color = SF::Color.new(255, 255, 255, alpha)
        end

        window.draw(sprite, blend_mode_to_render_states(layer.blend_mode))
      end

      # Draw borders for panels and popups if this layer belongs to them
      # Borders are NOT cached - drawn fresh each frame to avoid ghost borders during resize

      # Detect panel layers by ID (layer.id starts with "panel_")
      if layer.id.starts_with?("panel_")
        # Find the panel widget (parent of Chrome/Content widgets in layer)
        if chrome = layer.widgets.first?
          if panel = chrome.parent.as?(WindowPanel)
            draw_panel_border(window, panel)
          end
        end
      end

      # Detect popup layers by ID (layer.id starts with "popup_")
      if layer.id.starts_with?("popup_")
        # Find the popup widget (first widget in layer.widgets)
        if popup_widget = layer.widgets.first?
          if popup = popup_widget.as?(Popup)
            draw_popup_border(window, popup)
          end
        end
      end
    end

    # Find ancestor WindowPanel bounds for compositor clipping.
    # Returns nil for root/overlay layers (no panel ancestor).
    private def find_ancestor_panel_bounds(layer : Layer) : Rect?
      widget = layer.owner_widget
      while widget
        if widget.is_a?(WindowPanel)
          return widget.compute_bounds_for_layer(widget.layer.not_nil!)
        end
        widget = widget.parent
      end
      nil
    end

    # Draw panel border directly on window (not cached in layer)
    # Draw as 4 separate rectangles instead of outline_thickness for pixel-perfect alignment
    private def draw_panel_border(window : SF::RenderWindow, panel : WindowPanel)
      border_color = to_sf_color(panel.border_color)
      x = panel.x.to_f32
      y = panel.y.to_f32
      w = panel.width.to_f32
      h = panel.height.to_f32

      # Top edge
      top = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      top.position = SF.vector2f(x, y)
      top.fill_color = border_color
      window.draw(top)

      # Bottom edge
      bottom = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      bottom.position = SF.vector2f(x, y + h - 1.0_f32)
      bottom.fill_color = border_color
      window.draw(bottom)

      # Left edge
      left = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      left.position = SF.vector2f(x, y)
      left.fill_color = border_color
      window.draw(left)

      # Right edge
      right = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      right.position = SF.vector2f(x + w - 1.0_f32, y)
      right.fill_color = border_color
      window.draw(right)
    end

    # Draw popup border directly on window (not cached in layer)
    # Draw as 4 separate rectangles for pixel-perfect alignment
    private def draw_popup_border(window : SF::RenderWindow, popup : Popup)
      border_color = to_sf_color(popup.border_color)
      abs_bounds = popup.absolute_bounds
      x = abs_bounds.x.to_f32
      y = abs_bounds.y.to_f32
      w = abs_bounds.width.to_f32
      h = abs_bounds.height.to_f32

      # Top edge
      top = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      top.position = SF.vector2f(x, y)
      top.fill_color = border_color
      window.draw(top)

      # Bottom edge
      bottom = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      bottom.position = SF.vector2f(x, y + h - 1.0_f32)
      bottom.fill_color = border_color
      window.draw(bottom)

      # Left edge
      left = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      left.position = SF.vector2f(x, y)
      left.fill_color = border_color
      window.draw(left)

      # Right edge
      right = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      right.position = SF.vector2f(x + w - 1.0_f32, y)
      right.fill_color = border_color
      window.draw(right)
    end

    # Composite viewport_cache layer: content is at buffer-relative positions
    # Use scroll_offset and buffer_origin to determine viewport window
    private def composite_viewport_cache_layer(window : SF::RenderWindow, layer : Layer, backend : CrSFMLBackend, viewport_width : Int32, viewport_height : Int32)
      LayerRenderer.frame_viewport_cache_count += 1 # Instrumentation

      dest_x = layer.bounds.x.round(:ties_away).to_f32
      dest_y = layer.bounds.y.round(:ties_away).to_f32

      # Clip to ancestor panel bounds — layers must not extend beyond their panel
      if panel_bounds = find_ancestor_panel_bounds(layer)
        panel_right = panel_bounds.x + panel_bounds.width
        panel_bottom = panel_bounds.y + panel_bounds.height
        if dest_x + viewport_width > panel_right
          viewport_width = Math.max(0, (panel_right - dest_x).ceil.to_i)
        end
        if dest_y + viewport_height > panel_bottom
          viewport_height = Math.max(0, (panel_bottom - dest_y).ceil.to_i)
        end
      end

      # Calculate opacity color
      sprite_color = if layer.opacity < 1.0
                       alpha = (layer.opacity * 255).to_u8
                       SF::Color.new(255, 255, 255, alpha)
                     else
                       SF::Color::White
                     end

      # Viewport position within buffer — shared math (Layer#viewport_sample_origin)
      viewport_x, viewport_y = layer.viewport_sample_origin(backend.width, backend.height, viewport_width, viewport_height)

      # TRACE: Log viewport cache compositor details with calculated sample position
      if ENV["CRYMBLE_TRACE"]? == "1"
        File.open("/tmp/compositor_trace.log", "a") do |f|
          f.puts "  VIEWPORT_CACHE layer=#{layer.id}"
          f.puts "    dest=(#{dest_x.round(1)},#{dest_y.round(1)}) viewport_size=(#{viewport_width},#{viewport_height})"
          f.puts "    scroll=(#{layer.scroll_offset.x.round(1)},#{layer.scroll_offset.y.round(1)}) buffer_origin=(#{layer.buffer_origin.x.round(1)},#{layer.buffer_origin.y.round(1)})"
          f.puts "    backend_size=(#{backend.width},#{backend.height})"
          f.puts "    SAMPLE src=(#{viewport_x},#{viewport_y}) size=(#{viewport_width},#{viewport_height}) -> dest=(#{dest_x.round(1)},#{dest_y.round(1)})"
        end
      end

      # Blit the viewport region from buffer to window
      sprite = SF::Sprite.new(backend.texture)
      sprite.texture_rect = SF.int_rect(viewport_x, viewport_y, viewport_width, viewport_height)
      # Round position to integers to avoid sub-pixel ghosting artifacts
      # (non-integer positions + texture_rect offset causes interpolation issues)
      sprite.position = SF.vector2f(dest_x, dest_y)
      sprite.color = sprite_color
      window.draw(sprite, blend_mode_to_render_states(layer.blend_mode))
    end

    # Map CrymbleUI::BlendMode to SFML RenderStates for layer compositing
    private def blend_mode_to_render_states(mode : BlendMode) : SF::RenderStates
      case mode
      when BlendMode::Additive    then SF::RenderStates.new(SF::BlendAdd)
      when BlendMode::Subtractive then SF::RenderStates.new(SF::BlendSubtract)
      when BlendMode::Multiply    then SF::RenderStates.new(SF::BlendMultiply)
      else                          SF::RenderStates::Default # BlendAlpha (normal)
      end
    end

    # Check if any layer needs rendering (for timer-triggered redraws)
    # Uses Layer registry for efficient O(k × d) lookup instead of tree traversal
    private def any_layer_needs_render?(app : App) : Bool
      return false unless root = app.root
      Layer.any_needs_render?(root)
    end

    # Clear window to background color
    def clear_window_background
      return unless window = @window
      window.clear(to_sf_color(@background_color))
    end

    # Run the application with event loop
    def run(app : App)
      # Set global app reference for widgets to trigger rebuilds
      Widget.app = app
      return unless window = @window # Headless mode - no window to run

      # Set up quit callback so app can request window close
      app.quit_callback = -> { window.close }

      # NOTE: Scheduler callback removed - it was marking root which invalidated ALL backgrounds!
      # Individual widgets (CPUMonitor, etc.) already call mark_needs_render themselves
      # Marking root caused invalidate_children_backgrounds to cascade to entire tree
      # Result: all widgets re-captured backgrounds every timer tick → garbage accumulation

      # Build initial widget tree (or rebuild if already built to register shortcuts)
      # First build happens in CrymbleUI.run before renderer exists (to get window dimensions)
      # This rebuild ensures shortcuts get registered now that ShortcutManager exists
      app.build_tree

      # Register zoom change callback for cache invalidation
      # This ensures font reload and texture invalidation happen regardless of
      # whether zoom is changed via keyboard (Ctrl+/-/0) or direct API call
      FontSizing.on_zoom_change = -> {
        reload_font
        invalidate_all_widget_backends(app.root)
        invalidate_all_layer_backends(app.root)
        # Force layout state on all layers to trigger full re-render
        # This ensures viewport_cache buffer_origin is recalculated
        if root = app.root
          Layer.active_layers(root).each(&.mark_needs_layout)
        end
      }

      needs_redraw = true

      # Main loop - event coalescing for smooth interaction
      # Process ALL pending events first, then render once per frame
      while window.open?
        # Check if there are scheduled timers
        next_wake = @scheduler.next_wake_time
        event_count = 0

        if next_wake
          # Timers scheduled - poll events with small sleeps until next timer
          remaining = next_wake
          while remaining > Time::Span.zero
            # Poll all pending events (coalescing - don't render per event)
            while event = window.poll_event
              event_count += 1
              if event.type == SF::Event::MouseMoved
                @last_mouse_move_time = Time.instant
              end
              redraw = handle_event(event, app)
              if redraw || event.type == SF::Event::MouseButtonPressed ||
                 event.type == SF::Event::MouseButtonReleased ||
                 event.type == SF::Event::KeyPressed ||
                 event.type == SF::Event::Resized
                needs_redraw = true
              end
            end

            # If redraw needed, break immediately to render (don't wait for timer)
            # This makes clicks/resizes feel instant instead of delayed by up to 400ms
            # Also check if event callbacks dirtied any layers (e.g., hover callback
            # updating statusbar text via mark_needs_render → propagate_to_layer)
            if !needs_redraw && event_count > 0
              needs_redraw = any_layer_needs_render?(app)
            end
            break if needs_redraw

            # During active drag, use short sleep to stay responsive without 100% CPU busy-wait
            # Mouse events arrive at ~125Hz (8ms intervals), so 2ms sleep is responsive enough
            # Without this sleep, we'd busy-poll at 100% CPU between mouse events
            time_since_last_move = Time.instant - @last_mouse_move_time
            drag_sleep = app.mouse_down? && time_since_last_move < 100.milliseconds

            # Sleep in chunks (max 50ms) to stay responsive, or 2ms during drag
            sleep_time = drag_sleep ? 2.milliseconds : (remaining < 50.milliseconds ? remaining : 50.milliseconds)
            sleep(sleep_time)

            # Check remaining time
            remaining = @scheduler.next_wake_time || Time::Span.zero
          end

          # Run expired timers
          fired_count = @scheduler.run_expired_timers
          if fired_count > 0
            # Timers may have changed widget state (e.g., CPUMonitor marks itself)
            # Individual widgets mark their layers as dirty, so check layers not root
            # This is more precise than marking root (which invalidates all backgrounds!)
            needs_redraw = any_layer_needs_render?(app)
            # Also check overlay primitives (splash screen animation driven by timer)
            if !needs_redraw
              if w = @window
                needs_redraw = !app.overlay_primitives(w.size.x.to_f64, w.size.y.to_f64).nil?
              end
            end
            # Composite-only request (e.g., cursor flash opacity toggle)
            if !needs_redraw
              needs_redraw = app.needs_composite_only?
            end
          end
        else
          # No timers - block until event (0% CPU when idle)
          # NOTE: SFML/X11 event polling overhead is ~5-6% CPU during mouse movement
          # (measured: event_wait + event_poll = ~1200ms CPU over 1900 mouse events in 20s)
          # This is unavoidable SFML/X11 windowing system overhead, not our application code.
          # Our actual event handling (cursor_update + event processing) is only ~1% CPU.
          if event = window.wait_event
            event_count += 1
            redraw = handle_event(event, app)
            if redraw || event.type == SF::Event::MouseButtonPressed ||
               event.type == SF::Event::MouseButtonReleased ||
               event.type == SF::Event::KeyPressed ||
               event.type == SF::Event::Resized
              needs_redraw = true
            end
          end

          # After first event, poll any remaining queued events (event coalescing)
          while event = window.poll_event
            event_count += 1
            redraw = handle_event(event, app)
            if redraw || event.type == SF::Event::MouseButtonPressed ||
               event.type == SF::Event::MouseButtonReleased ||
               event.type == SF::Event::KeyPressed ||
               event.type == SF::Event::Resized
              needs_redraw = true
            end
          end
        end

        # Check if any event triggered a rebuild request or render need
        if event_count > 0
          if app.needs_rebuild?
            {% if flag?(:DEBUG_RENDER) %}
              puts "\n[REBUILD CHECK @ event_loop] needs_rebuild? = true (#{event_count} events)"
              app.root.try { |root| app.find_widgets_needing_layout(root) }
            {% end %}
            # App state changed - rebuild tree with reconciliation
            app.rebuild
            needs_redraw = true
          elsif app.root.try(&.needs_layout?) || app.root.try(&.needs_render?) || any_layer_needs_render?(app)
            # Layout or render needed (no rebuild)
            needs_redraw = true
          end
        end

        # Render once per frame with latest state (after processing all events)
        if needs_redraw
          render_frame(app)
          needs_redraw = false
        elsif event_count > 0
          # Events processed but no redraw triggered - this is where we save CPU!
        end
      end
    end

    # Handle a single event
    # Returns true if event requires redraw
    private def handle_event(event : LibCSFML::Event, app : App) : Bool
      handle_event_impl(event, app)
    rescue ex
      if handler = app.on_event_exception
        handler.call(ex.message.to_s)
      else
        STDERR.puts "Unhandled exception in handle_event: #{ex.inspect_with_backtrace}"
      end
      false
    end

    private def handle_event_impl(event : LibCSFML::Event, app : App) : Bool
      case event.type
      when SF::Event::TextEntered
        # Check for Ctrl++ / Ctrl+- for zoom (works on all keyboard layouts)
        char = event.text.unicode.chr
        if SF::Keyboard.key_pressed?(SF::Keyboard::LControl) || SF::Keyboard.key_pressed?(SF::Keyboard::RControl)
          case char
          when '+', '='
            handle_zoom_in(app)
            return true
          when '-'
            handle_zoom_out(app)
            return true
          end
          # Filter ALL text when Ctrl is pressed (Ctrl+key combos shouldn't insert text)
          # This prevents Ctrl+0 from inserting '0', Ctrl+S from inserting 's', etc.
          return true
        end
        # Dispatch text input to focused widget
        # Filter control characters (< 32) except for specific cases
        # Also filter DEL (127)
        if char.ord >= 32 && char.ord != 127
          @focus_manager.handle_text_input(char)
        end
        true # Redraw for text input
      when SF::Event::MouseWheelScrolled
        # Ctrl+MouseWheel = zoom in/out
        if SF::Keyboard.key_pressed?(SF::Keyboard::LControl) || SF::Keyboard.key_pressed?(SF::Keyboard::RControl)
          if event.mouse_wheel_scroll.delta > 0
            handle_zoom_in(app)
          elsif event.mouse_wheel_scroll.delta < 0
            handle_zoom_out(app)
          end
          return true
        end

        # Dispatch wheel event to widgets
        # Get current mouse position from window
        if window = @window
          sfml_pos = SF::Mouse.get_position(window)
          mouse_pos = Vec2.new(sfml_pos.x.to_f64, sfml_pos.y.to_f64)
          # Note: SFML delta is positive for scroll up, negative for scroll down
          # Check wheel axis - touchpad can generate horizontal scroll events
          delta = case event.mouse_wheel_scroll.wheel
                  when SF::Mouse::Wheel::HorizontalWheel
                    Vec2.new(event.mouse_wheel_scroll.delta.to_f64, 0.0) # Horizontal scroll → X
                  else
                    Vec2.new(0.0, event.mouse_wheel_scroll.delta.to_f64) # Vertical scroll → Y
                  end
          # Detect shift key for horizontal scrolling
          shift = SF::Keyboard.key_pressed?(SF::Keyboard::LShift) || SF::Keyboard.key_pressed?(SF::Keyboard::RShift)
          app.handle_mouse_wheel(delta, mouse_pos, shift)
          # Update hover after scroll - content under mouse has changed
          app.update_hover(mouse_pos)
        end
        true # Redraw after scroll
      when SF::Event::KeyPressed
        key = event.key
        # Global zoom shortcuts - numpad +/- and Ctrl+0 for reset
        # Note: Regular keyboard +/- is handled via TextEntered for keyboard layout compatibility
        if key.control
          case key.code
          when SF::Keyboard::Add # numpad +
            handle_zoom_in(app)
            return true
          when SF::Keyboard::Subtract # numpad -
            handle_zoom_out(app)
            return true
          when SF::Keyboard::Num0, SF::Keyboard::Numpad0 # 0 = reset zoom
            handle_zoom_reset(app)
            return true
          when SF::Keyboard::M # Ctrl+M = toggle maximize on topmost panel
            if !key.alt && !key.shift
              if panel = app.root.try(&.find_topmost_panel)
                panel.toggle_maximize
              end
              return true
            end
          when SF::Keyboard::Tab # Ctrl+Tab / Ctrl+Shift+Tab = cycle panels
            if root = app.root
              @focus_manager.cycle_panel(forward: !key.shift, root: root)
            end
            return true
          when SF::Keyboard::D # Ctrl+Shift+D = dump render state (dev diagnostic)
            if key.shift
              if root = app.root
                RenderDebug.dump(root)
                puts "[render dump] /tmp/render_dump/ — #{Layer.active_layers(root).size} layers (PNG per layer + report.txt)"
              end
              return true
            end
          end
        end

        # ESC key: panel shortcuts first (dialog close), then app-level (drags, menus)
        if key.code == SF::Keyboard::Escape
          active_panel = app.root.try(&.find_topmost_panel)
          if active_panel && @shortcut_manager.handle_key_event(event.key, active_panel)
            return true
          end
          if app.handle_escape
            return true
          end
        end

        # Tab/Shift+Tab: the focused widget gets first dibs (a focus scope like
        # VirtualMatrix round-robins its cell cursor and stays focused); only
        # if it declines do we cycle focus to the next/previous widget.
        if key.code == SF::Keyboard::Tab
          if root = app.root
            @focus_manager.handle_tab_key(key.shift, root)
          end
          return true
        end

        # For Enter/Space, check topmost panel shortcuts first
        # (dialog confirm/cancel takes priority over widget focus)
        if key.code == SF::Keyboard::Enter || key.code == SF::Keyboard::Space
          active_panel = app.root.try(&.find_topmost_panel)
          if active_panel && @shortcut_manager.handle_key_event(event.key, active_panel)
            return true
          end
        end

        # Try focused widget (for navigation keys like arrows, backspace)
        handled = @focus_manager.handle_key_down(key.code, key.control, key.shift, key.alt)

        # If not handled by focused widget, try focus navigation
        # Skip when Alt is pressed — Alt+arrows go to shortcuts (e.g., history navigation)
        unless handled || key.alt
          case key.code
          when SF::Keyboard::Up, SF::Keyboard::Down, SF::Keyboard::Left, SF::Keyboard::Right
            if root = app.root
              direction = case key.code
                          when SF::Keyboard::Up    then :up
                          when SF::Keyboard::Down  then :down
                          when SF::Keyboard::Left  then :left
                          when SF::Keyboard::Right then :right
                          else                          :up # shouldn't happen
                          end
              @focus_manager.navigate(direction, root: root)
              handled = true
            end
          when SF::Keyboard::Enter, SF::Keyboard::Space
            # Activate focused widget (button click, checkbox toggle)
            key_sym = key.code == SF::Keyboard::Enter ? :enter : :space
            @focus_manager.handle_activation_key(key_sym)
            handled = true
          end
        end

        # If still not handled, try keyboard shortcuts
        unless handled
          active_panel = app.root.try(&.find_topmost_panel)
          @shortcut_manager.handle_key_event(event.key, active_panel)
        end
        true # Redraw for key events
      when SF::Event::Closed
        # Let app handle close request (can save data, show dialogs, etc.)
        # App calls quit() when ready to actually close
        app.handle_close_request
        false
      when SF::Event::MouseButtonPressed
        handle_mouse_down(app, event.mouse_button.position.x.to_f64, event.mouse_button.position.y.to_f64, map_mouse_button(event.mouse_button.button))
        false # Caller handles redraw for button events
      when SF::Event::MouseButtonReleased
        handle_mouse_up(app, event.mouse_button.position.x.to_f64, event.mouse_button.position.y.to_f64, map_mouse_button(event.mouse_button.button))
        false # Caller handles redraw for button events
      when SF::Event::MouseMoved
        handle_mouse_move(app, event.mouse_move.position.x.to_f64, event.mouse_move.position.y.to_f64)
      when SF::Event::Resized
        if window = @window
          # Reset view to prevent content scaling
          view = SF::View.new(SF.float_rect(0, 0, event.size.size.x.to_f32, event.size.size.y.to_f32))
          window.view = view

          # Force re-apply cursor after window resize
          # OS takes over cursor during resize, we must reclaim it
          window.mouse_cursor = @cursor_arrow
        end
        # Mark root as needing layout to trigger re-layout with new size
        app.root.try &.mark_needs_layout
        false # Caller handles redraw for resize events
      else
        false
      end
    end

    # Handle mouse down events
    private def handle_mouse_down(app : App, x : Float64, y : Float64, button : MouseButton = MouseButton::Left)
      point = Vec2.new(x, y)

      # Set focus on click - only focus focusable widgets
      # Don't clear focus when clicking non-focusable elements (like scrollbars)
      # This allows TextInput to keep focus while interacting with scrollbars
      if root = app.root
        if widget = root.hit_test(point)
          if widget.focusable?
            @focus_manager.focus(widget)
          end
          # Non-focusable widgets: keep current focus unchanged
        else
          # Click outside all widgets: clear focus
          @focus_manager.clear_focus
        end
      end

      app.handle_mouse_down(point, button)
    end

    # Handle mouse move events (for dragging, hover, and cursor updates)
    private def handle_mouse_move(app : App, x : Float64, y : Float64)
      point = Vec2.new(x, y)

      # Handle dragging if mouse is down
      if app.mouse_down?
        # Let app handle drag logic
        return app.handle_mouse_move(point)
      else
        # Update hover state (app manages which widget is hovered)
        needs_redraw = app.update_hover(point)

        # Update cursor based on what's under the mouse
        # Only redraw if cursor visually changed
        cursor_changed = update_cursor(app, point)

        return needs_redraw || cursor_changed
      end
    end

    # Handle mouse up events
    private def handle_mouse_up(app : App, x : Float64, y : Float64, button : MouseButton = MouseButton::Left)
      point = Vec2.new(x, y)
      app.handle_mouse_up(point, button)
      # Update cursor immediately after mouse up (fixes sticky resize cursor bug)
      update_cursor(app, point)
    end

    # Update cursor based on what's under the mouse
    # Returns true if cursor changed (needs redraw), false otherwise
    private def update_cursor(app : App, point : Vec2) : Bool
      return false unless window = @window

      # Ask app for cursor type (app has all the business logic)
      cursor_type = app.get_cursor_for_point(point)

      # Convert to SFML cursor type and set
      set_cursor(cursor_type)
    end

    # Map SFML mouse button to CrymbleUI MouseButton
    private def map_mouse_button(button : LibCSFML::MouseButton) : MouseButton
      case button
      when LibCSFML::MouseButton::Right  then MouseButton::Right
      when LibCSFML::MouseButton::Middle then MouseButton::Middle
      else                                    MouseButton::Left
      end
    end

    # Set the window cursor (only if changed)
    # Returns true if cursor changed, false otherwise
    private def set_cursor(cursor_type : CursorType) : Bool
      # Convert CursorType to SF::Cursor::Type
      sf_cursor_type = case cursor_type
                       when CursorType::Text
                         SF::Cursor::Text
                       when CursorType::SizeHorizontal
                         SF::Cursor::SizeHorizontal
                       when CursorType::SizeVertical
                         SF::Cursor::SizeVertical
                       when CursorType::SizeNWSE
                         SF::Cursor::SizeTopLeftBottomRight
                       when CursorType::SizeNESW
                         SF::Cursor::SizeBottomLeftTopRight
                       when CursorType::SizeAll
                         SF::Cursor::SizeAll
                       else
                         SF::Cursor::Arrow
                       end

      return false if @current_cursor == sf_cursor_type
      return false unless window = @window

      cursor = case sf_cursor_type
               when SF::Cursor::Text
                 @cursor_text
               when SF::Cursor::SizeHorizontal
                 @cursor_size_horizontal
               when SF::Cursor::SizeVertical
                 @cursor_size_vertical
               when SF::Cursor::SizeTopLeftBottomRight
                 @cursor_size_nwse
               when SF::Cursor::SizeBottomLeftTopRight
                 @cursor_size_nesw
               else
                 @cursor_arrow
               end

      window.mouse_cursor = cursor
      @current_cursor = sf_cursor_type
      true # Cursor changed
    end

    # Render a single frame
    def render_frame(app : App)
      return unless window = @window # Headless mode - no window to render to
      return unless root = app.root

      # Sync background color from app (app may override; nil = theme default).
      @background_color = app.app_background_color || Theme.current.app_background

      # Sync window title from root widget (e.g. "MyApp — document.txt")
      if root.is_a?(Window)
        new_title = root.as(Window).title
        if new_title != @current_title
          window.title = new_title
          @current_title = new_title
        end
      end

      # NOTE: Tried reset_gl_states here for texture pooling fix - didn't help.
      # See docs/TEXTURE_POOLING_INVESTIGATION.md

      frame_start = LayerRenderer.profile_enabled ? Time.instant : nil

      begin
        # Perform layout if needed (timed)
        layout_start = Time.instant
        window_size = Size.new(window.size.x.to_f64, window.size.y.to_f64)
        did_layout = app.prepare_layout(window_size)
        LayerRenderer.phase_layout_ms = (Time.instant - layout_start).total_milliseconds
        if frame_start
          LayerRenderer.record_profile("layout", LayerRenderer.phase_layout_ms)
        end

        # Invalidate layer cache after layout (layer set may have changed)
        invalidate_layer_cache if did_layout

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
          overlay.each { |p| execute_primitive(p, window) }
        end

        # Display (timed)
        display_start = Time.instant
        window.display
        LayerRenderer.phase_display_ms = (Time.instant - display_start).total_milliseconds

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
        handle_frame_exception(exception, app, window)
      end

      {% if flag?(:PERF_LOG) %}
        frame_ms = frame_start ? (Time.instant - frame_start).total_milliseconds : 0.0
        if frame_ms > 1.0 || LayerRenderer.frame_layers_needing_render > 0
          File.open("/tmp/perf_log.txt", "a") do |f|
            f.puts "FRAME: #{frame_ms.round(1)}ms layout=#{LayerRenderer.phase_layout_ms.round(1)}ms render=#{LayerRenderer.phase_render_ms.round(1)}ms composite=#{LayerRenderer.phase_composite_ms.round(1)}ms display=#{LayerRenderer.phase_display_ms.round(1)}ms layers_rendered=#{LayerRenderer.frame_layers_needing_render}/#{LayerRenderer.frame_layers_total} widgets=#{LayerRenderer.frame_widgets_iterated} prims=#{LayerRenderer.frame_primitive_count}"
          end
        end
      {% end %}

      # Reset frame counters for next frame (always, even after exception)
      LayerRenderer.reset_frame_counters
      Widget.reset_layout_count

      Widget.increment_render_count
    end

    # Handle exception during frame rendering (graceful degradation)
    private def handle_frame_exception(exception : Exception, app : App, window : SF::RenderWindow)
      STDERR.puts "[GRACEFUL_DEGRADATION] Frame exception: #{exception.message}"
      STDERR.puts "  #{exception.backtrace?.try(&.first(3).join("\n  "))}"
      app.reset_all_caches
      app.root.try(&.mark_needs_layout)
      # CRITICAL: Always display the frame — a stale frame is better than a black hole
      begin
        window.display
      rescue
      end
    end

    # === PRIMITIVE-BASED RENDERING (New Architecture) ===

    # Render a list of primitives to the current window
    # This is the new rendering path - primitives are backend-agnostic data structures
    def render_primitives(primitives : Array(DrawPrimitive))
      return unless window = @window
      primitives.each { |primitive| execute_primitive(primitive, window) }
    end

    # Execute a single primitive on the given render target
    # Dispatches to specific handler based on primitive type
    private def execute_primitive(primitive : DrawPrimitive, target : SF::RenderTarget)
      case primitive
      when FillRect
        # Fill rectangle with solid color
        rect = SF::RectangleShape.new(SF.vector2f(primitive.bounds.width, primitive.bounds.height))
        rect.position = SF.vector2f(primitive.bounds.x, primitive.bounds.y)
        rect.fill_color = to_sf_color(primitive.color)
        target.draw(rect)
      when DrawText
        # Draw text at position
        text = SF::Text.new(primitive.text, @default_font, primitive.size.round.to_u32)
        # Round to integers to avoid GPU bilinear interpolation blur on glyph atlas
        # (see commit 20a683b — fractional coords cause washed-out text)
        text.position = SF.vector2f(primitive.position.x.round.to_f32, primitive.position.y.round.to_f32)
        text.fill_color = to_sf_color(primitive.color)
        target.draw(text)
      when DrawLine
        # Draw line as a rotated rectangle to support width
        # (SF::Lines doesn't support line width)
        dx = primitive.to.x - primitive.from.x
        dy = primitive.to.y - primitive.from.y
        length = Math.sqrt(dx * dx + dy * dy)
        angle = Math.atan2(dy, dx) * 180.0 / Math::PI

        shape = SF::RectangleShape.new(SF.vector2f(length.to_f32, primitive.width.to_f32))
        shape.position = SF.vector2f(primitive.from.x.to_f32, (primitive.from.y - primitive.width / 2.0).to_f32)
        shape.rotation = angle.to_f32
        shape.fill_color = to_sf_color(primitive.color)
        target.draw(shape)
      when DrawCircle
        # Draw circle (filled or outline)
        circle = SF::CircleShape.new(primitive.radius.to_f32)
        circle.position = SF.vector2f(
          primitive.center.x - primitive.radius,
          primitive.center.y - primitive.radius
        )
        if primitive.fill
          circle.fill_color = to_sf_color(primitive.color)
        else
          circle.fill_color = SF::Color::Transparent
          circle.outline_color = to_sf_color(primitive.color)
          circle.outline_thickness = 1.0
        end
        target.draw(circle)
      when DrawRect
        # Draw rectangle outline
        rect = SF::RectangleShape.new(SF.vector2f(primitive.bounds.width, primitive.bounds.height))
        rect.position = SF.vector2f(primitive.bounds.x, primitive.bounds.y)
        rect.fill_color = SF::Color::Transparent
        rect.outline_color = to_sf_color(primitive.color)
        rect.outline_thickness = primitive.width
        target.draw(rect)
      when PushClip
        # Push clipping rectangle (only works with SFMLPaintContext currently)
        # For direct window rendering, clipping needs special handling
        # TODO: Implement clipping for primitives rendered directly to window

      when PopClip
        # Pop clipping rectangle
        # TODO: Implement clipping for primitives rendered directly to window

      when FillTriangle
        # Fill triangle with 3 vertices
        shape = SF::ConvexShape.new(3)
        shape.set_point(0, SF.vector2f(primitive.p1.x.to_f32, primitive.p1.y.to_f32))
        shape.set_point(1, SF.vector2f(primitive.p2.x.to_f32, primitive.p2.y.to_f32))
        shape.set_point(2, SF.vector2f(primitive.p3.x.to_f32, primitive.p3.y.to_f32))
        shape.fill_color = to_sf_color(primitive.color)
        target.draw(shape)
      when DrawImage
        texture = load_cached_texture(primitive.source)
        if texture
          sprite = SF::Sprite.new(texture)
          sprite.position = SF.vector2f(primitive.bounds.x.to_f32, primitive.bounds.y.to_f32)
          tex_size = texture.size
          if tex_size.x > 0 && tex_size.y > 0
            sprite.scale = SF.vector2f(
              (primitive.bounds.width / tex_size.x).to_f32,
              (primitive.bounds.height / tex_size.y).to_f32
            )
          end
          sprite.color = to_sf_color(primitive.color)
          target.draw(sprite)
        end
      end
    end

    # === END PRIMITIVE-BASED RENDERING ===

    # Load texture, caching for reuse by ImageSource#key. Uses compile-time-embedded
    # bytes when present (CWD-independent); otherwise reads the key as a disk path.
    private def load_cached_texture(source : ImageSource) : SF::Texture?
      @texture_cache[source.key]? || begin
        texture = if data = source.bytes
                    SF::Texture.from_memory(data)
                  else
                    SF::Texture.from_file(source.key)
                  end
        texture.smooth = true
        @texture_cache[source.key] = texture
        texture
      rescue ex
        STDERR.puts "Failed to load texture '#{source.key}': #{ex.message}"
        nil
      end
    end

    # Convert CrymbleUI Color to SFML Color
    private def to_sf_color(color : Color) : SF::Color
      SF::Color.new(color.r, color.g, color.b, color.a)
    end

    # === GLOBAL ZOOM HANDLING ===

    # === FONT RELOAD ON ZOOM ===
    #
    # IMPORTANT: do NOT recreate SF::Font on zoom change. SFML's Font keeps
    # an independent glyph atlas (Page) per character size in m_pages, so a
    # single Font instance correctly serves all zoom levels — recreating it
    # is pure waste.
    #
    # Note: the historical "fresh font per zoom" workaround was originally
    # added because of the Windows random-glyph-garbling bug. That was a
    # red herring: the real cause was missing GPU sync after texture
    # uploads in upstream SFML, which we fix out-of-tree (see
    # docs/WINDOWS_SFML_GL_SYNC_BUG.md and the patch alongside the lib at
    # locallib/sfml3/lib/win32/sfml-graphics-windows-glsync.patch).
    private def reload_font
      # Refresh the SFMLFont wrapper (cheap, just a Crystal-side adapter).
      # Downstream code may hold onto the wrapper and expect a new instance
      # after zoom change to invalidate its caches.
      Widget.font = SFMLFont.new(@default_font)

      # Recreate paint context with the existing font so any per-frame
      # state tied to it gets reset.
      if window = @window
        @paint_context = SFMLPaintContext.new(window, @default_font)
      end
    end

    # Invalidate all widget backends to clear corrupted textures
    # Font reload clears glyph cache, but widget textures may still have corrupted pixels
    private def invalidate_all_widget_backends(widget : Widget?)
      return unless widget
      widget.widget_backend = nil
      widget.background_backend = nil
      widget.children.each { |c| invalidate_all_widget_backends(c) }

      # Also invalidate overlays (popups, tooltips, modals) - they're not in children
      if widget.is_a?(Window)
        widget.overlays.each { |o| invalidate_all_widget_backends(o) }
      end
    end

    # Invalidate all layer backends (called on zoom to clear cached rendered text)
    private def invalidate_all_layer_backends(root : Widget?)
      return unless root
      Layer.active_layers(root).each do |layer|
        layer.backend = nil
        layer.reset_first_render # Force full re-render
      end
    end

    # Handle zoom in (Ctrl++ or Ctrl+MouseWheel up)
    # Cache invalidation is handled by FontSizing.on_zoom_change callback
    private def handle_zoom_in(app : App)
      if FontSizing.zoom_in
        app.root.try &.mark_needs_layout
      end
    end

    # Handle zoom out (Ctrl+- or Ctrl+MouseWheel down)
    # Cache invalidation is handled by FontSizing.on_zoom_change callback
    private def handle_zoom_out(app : App)
      if FontSizing.zoom_out
        app.root.try &.mark_needs_layout
      end
    end

    # Handle zoom reset (Ctrl+0)
    # Cache invalidation is handled by FontSizing.on_zoom_change callback
    private def handle_zoom_reset(app : App)
      FontSizing.reset_zoom
      app.root.try &.mark_needs_layout
    end
  end
end
