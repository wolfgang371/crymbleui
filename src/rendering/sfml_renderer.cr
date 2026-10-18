require "../csfml3/wrapper"
require "../core/types"
require "../core/widget"
require "../core/app"
require "../core/embedded_font"
require "./window_renderer"
require "./pixel_snap"
require "./sfml_font"
require "./sfml_clipboard"
require "./draw_primitive"
require "./crsfml_backend"
require "./render_debug"

module CrymbleUI
  # The third-party lines an app's About should show for the backend this flavour was built with (native: the
  # SFML libraries it links and the embedded font). Ask this instead of naming the backend, so the same About
  # is right in every flavour.
  def self.backend_notices : Array(String)
    ["CSFML (version #{SF::VERSION}, Zlib license)", "SFML (version #{SF::SFML_VERSION}, Zlib license)"] +
      EmbeddedFont::ATTRIBUTION
  end

  # SFML-based renderer for CrymbleUI applications: the native platform under WindowRenderer's shared half -
  # the window, its events and cursors, the font, and drawing layer regions onto the window.
  class SFMLRenderer < WindowRenderer
    getter window : SF::RenderWindow?

    # Default font for text rendering
    @default_font : SF::Font
    @font_path : String? # Store for font reloading on zoom

    # Texture cache for DrawImage primitives (keyed by file path).
    # BLESSED (instrument_tripwires_spec, guard (d)): this is a file-path->image
    # texture cache, NOT a glyph/font cache. The (d) tripwire only forbids a
    # class-var FONT map (the @@font_cache stale-glyph-atlas incident, fix 4a7b4a5);
    # this instance-var image cache is legitimate — do not "fix" it away.
    @texture_cache = Hash(String, SF::Texture).new

    # Cursors for different resize/interaction directions
    @cursor_arrow : SF::Cursor
    @cursor_text : SF::Cursor
    @cursor_size_horizontal : SF::Cursor
    @cursor_size_vertical : SF::Cursor
    @cursor_size_nwse : SF::Cursor
    @cursor_size_nesw : SF::Cursor

    # Target framerate for smooth rendering without lag
    TARGET_FPS = 60

    # The embedded font's attribution lives in EmbeddedFont (both flavours embed the same font). The old public
    # name stays for its callers (an app's About; font_invariants_spec); new code asks CrymbleUI.backend_notices.
    FONT_ATTRIBUTION = EmbeddedFont::ATTRIBUTION

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
                        SF::Font.from_memory(EmbeddedFont::BYTES.to_slice)
                      end

      # Create the window (skipped in headless mode, for testing)
      if headless
        @window = nil
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
      end

      # Scheduler, shortcut and focus managers, input dispatch, frame ledger (WindowRenderer)
      super()

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
    def create_layer_backend(width : Int32, height : Int32) : RenderBackend
      CrSFMLBackend.acquire(width, height, @default_font)
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
      clips = Hash(Widget, Rect?).new.compare_by_identity
      Layer.composite_order(root).each do |layer|
        next unless valid_layer_dimensions?(layer)
        next unless backend = layer.backend
        next unless backend.is_a?(CrSFMLBackend)
        if owner = layer.owner_widget
          next if owner.skip_render?
        end
        # The live compositor's region (composite_region: clip, viewport-cache sample, snap) - one instrument
        region = composite_region(layer, layer.owner_widget.try(&.ancestor_clip(clips)), backend.width, backend.height)
        next unless region
        sprite = SF::Sprite.new(backend.texture)
        sprite.texture_rect = SF.int_rect(region.src_x, region.src_y, region.width, region.height)
        sprite.position = SF.vector2f(region.dest_x.to_f32, region.dest_y.to_f32)
        rt.draw(sprite, blend_mode_to_render_states(layer.blend_mode))
      end
      rt.display
      rt.texture.copy_to_image
    end

    # === WindowRenderer hooks ===

    protected def has_window? : Bool
      !@window.nil?
    end

    protected def window_open? : Bool
      @window.not_nil!.open?
    end

    protected def window_size : Size
      window = @window.not_nil!
      Size.new(window.size.x.to_f64, window.size.y.to_f64)
    end

    protected def poll_event : LibCSFML::Event?
      @window.not_nil!.poll_event
    end

    protected def close_window : Nil
      @window.try &.close
    end

    protected def display_window : Nil
      @window.not_nil!.display
    end

    # THE one drain point for released RenderTextures. Deliberately here and nowhere else:
    # after display, no layer's RenderTexture is the active render target, so destroying FBOs
    # cannot disturb the GL state SFML tracks mid-frame (the corruption mode the old pooling
    # attempt hit). CrSFMLBackend#dispose only enqueues; this is what actually frees.
    protected def after_display : Nil
      CrSFMLBackend.drain_reaper
    end

    protected def present_after_failure : Nil
      begin
        @window.not_nil!.display
      rescue
        return # the reaper waits for the next good frame: after a display that raised, the GL state is unknown
      end
      # What the recovery released is freed here, in the state the success path drains in (after display) - a
      # frame that keeps raising would otherwise park the working set in the reaper again and again.
      CrSFMLBackend.drain_reaper
    end

    protected def apply_window_title(title : String) : Nil
      @window.not_nil!.title = title
    end

    # Convert the CursorType to the SFML cursor loaded for it and install it
    protected def apply_cursor(cursor : CursorType) : Nil
      sf_cursor = case cursor
                  when CursorType::Text
                    @cursor_text
                  when CursorType::SizeHorizontal
                    @cursor_size_horizontal
                  when CursorType::SizeVertical
                    @cursor_size_vertical
                  when CursorType::SizeNWSE
                    @cursor_size_nwse
                  when CursorType::SizeNESW
                    @cursor_size_nesw
                  else
                    @cursor_arrow
                  end
      @window.not_nil!.mouse_cursor = sf_cursor
    end

    protected def on_window_resized(width : Int32, height : Int32) : Nil
      window = @window.not_nil!
      # Reset view to prevent content scaling
      view = SF::View.new(SF.float_rect(0, 0, width.to_f32, height.to_f32))
      window.view = view

      # Force re-apply cursor after window resize
      # OS takes over cursor during resize, we must reclaim it
      window.mouse_cursor = @cursor_arrow
    end

    # Composite one layer region via sprite. Whole device pixels (composite_region snaps): a non-integer
    # position + texture_rect offset interpolates
    protected def draw_layer_region(backend : RenderBackend, region : CompositeRegion, opacity : Float64,
                                    blend_mode : BlendMode) : Nil
      return unless backend.is_a?(CrSFMLBackend)
      sprite = SF::Sprite.new(backend.texture)
      sprite.texture_rect = SF.int_rect(region.src_x, region.src_y, region.width, region.height)
      sprite.position = SF.vector2f(region.dest_x.to_f32, region.dest_y.to_f32)
      if opacity < 1.0
        sprite.color = SF::Color.new(255, 255, 255, (opacity * 255).to_u8)
      end
      @window.not_nil!.draw(sprite, blend_mode_to_render_states(blend_mode))
    end

    # Draw a 1px chrome border directly on the window (not cached in any layer).
    # 4 separate rectangles instead of outline_thickness, for pixel-perfect alignment.
    protected def draw_border_rect(bounds : Rect, color : Color) : Nil
      window = @window.not_nil!
      sf_color = to_sf_color(color)
      x = bounds.x.to_f32
      y = bounds.y.to_f32
      w = bounds.width.to_f32
      h = bounds.height.to_f32

      # Top edge
      top = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      top.position = SF.vector2f(x, y)
      top.fill_color = sf_color
      window.draw(top)

      # Bottom edge
      bottom = SF::RectangleShape.new(SF.vector2f(w, 1.0_f32))
      bottom.position = SF.vector2f(x, y + h - 1.0_f32)
      bottom.fill_color = sf_color
      window.draw(bottom)

      # Left edge
      left = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      left.position = SF.vector2f(x, y)
      left.fill_color = sf_color
      window.draw(left)

      # Right edge
      right = SF::RectangleShape.new(SF.vector2f(1.0_f32, h))
      right.position = SF.vector2f(x + w - 1.0_f32, y)
      right.fill_color = sf_color
      window.draw(right)
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

    # Clear window to background color
    def clear_window_background
      return unless window = @window
      window.clear(to_sf_color(@background_color))
    end

    # Run the application with event loop: the blocking desktop loop - it waits for events (no timers) or until
    # the next timer, then runs the iteration WindowRenderer#tick runs too.
    def run(app : App)
      # Set global app reference for widgets to trigger rebuilds
      Widget.app = app
      return unless window = @window # Headless mode - no window to run

      start(app)

      needs_redraw = true

      # Main loop - event coalescing for smooth interaction
      # Process the pending events first, then render once per frame. A batch ends early at an event
      # that raises the input barrier, so the events behind it see the state it deferred (EventBatch).
      while window.open?
        before_iteration
        # Check if there are scheduled timers
        next_wake = @scheduler.next_wake_time
        event_count = 0

        if next_wake
          # Timers scheduled - poll events with small sleeps until next timer
          remaining = next_wake
          while remaining > Time::Span.zero
            # Poll all pending events (coalescing - don't render per event)
            drained, asked = drain_events(app)
            event_count += drained
            needs_redraw = true if asked

            # If redraw needed, break immediately to render (don't wait for timer)
            # This makes clicks/resizes feel instant instead of delayed by up to 400ms
            # Also check if event callbacks dirtied any layers (e.g., hover callback
            # updating statusbar text via mark_needs_render → propagate_to_layer)
            if !needs_redraw && event_count > 0
              needs_redraw = any_layer_needs_render?(app)
            end
            # The input barrier also ends the wait: EventBatch stopped draining for it, and the events
            # still queued must not sit until the next timer.
            break if needs_redraw || app.input_waits_for_frame? || @flushed_after_frame

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

          # Run expired timers; their verdict replaces what the events asked for
          unless (verdict = fire_timers(app)).nil?
            needs_redraw = verdict
          end
        else
          # No timers - block until event (0% CPU when idle)
          # NOTE: SFML/X11 event polling overhead is ~5-6% CPU during mouse movement
          # (measured: event_wait + event_poll = ~1200ms CPU over 1900 mouse events in 20s)
          # This is unavoidable SFML/X11 windowing system overhead, not our application code.
          # Our actual event handling (cursor_update + event processing) is only ~1% CPU.
          # Not while the input barrier is up: the frame it waits for comes first (below), then the queue.
          unless app.input_waits_for_frame? || @flushed_after_frame
            if event = window.wait_event
              event_count += 1
              needs_redraw = true if dispatch(event, app)
            end

            # After first event, poll any remaining queued events (event coalescing)
            drained, asked = drain_events(app)
            event_count += drained
            needs_redraw = true if asked
          end
        end

        finish_iteration(app, needs_redraw, event_count)
        needs_redraw = false
      end

      finish_run
    end

    # === PRIMITIVE-BASED RENDERING (New Architecture) ===

    # Render a list of primitives to the current window (WindowRenderer#render_primitives refused clips)
    # This is the new rendering path - primitives are backend-agnostic data structures
    protected def draw_primitives(primitives : Array(DrawPrimitive)) : Nil
      window = @window.not_nil!
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
        # Snap to whole pixels (glyph-atlas blur guard) via PixelSnap — translation-
        # invariant, unlike the ties-even Float#round this previously used (the same
        # parity class as the cursor-cell text jitter).
        text.position = SF.vector2f(PixelSnap.snap(primitive.position.x).to_f32, PixelSnap.snap(primitive.position.y).to_f32)
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
      when PushClip, PopClip
        raise WindowDirectClipError.new(primitive) # the entry points check the whole list first

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
    # Backend-specific font reload on zoom — overrides the LayerRenderer hook,
    # invoked from the shared apply_zoom_change. The renderer-agnostic backend/layer
    # invalidation + re-layout now lives in LayerRenderer (shared with TestRenderer).
    protected def reload_font_for_zoom
      # Refresh the SFMLFont wrapper (cheap, just a Crystal-side adapter).
      # Downstream code may hold onto the wrapper and expect a new instance
      # after zoom change to invalidate its caches.
      Widget.font = SFMLFont.new(@default_font)
    end
  end
end
