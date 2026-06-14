require "../core/types"
require "../core/scheduler"
require "../rendering/renderer"
require "../rendering/draw_primitive"
require "../rendering/layer_renderer"
require "../widgets/window_panel"
require "../widgets/popup"
require "./test_render_backend"
require "./test_shortcut_manager"

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
      getter shortcut_manager : TestShortcutManager

      # Tracking
      getter render_frame_count : Int32 = 0
      getter render_layer_count : Int32 = 0
      getter compositor_call_count : Int32 = 0
      getter compositor_skip_count : Int32 = 0
      getter backend_blit_count : Int32 = 0
      getter exceptions_caught : Int32 = 0  # Graceful degradation counter
      getter last_exception_message : String? = nil

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

      # Track all layer backends for primitive counting
      @layer_backends : Array(TestRenderBackend) = [] of TestRenderBackend
      getter layer_backends

      # Track all widget backends (for cached widget rendering)
      @widget_backends : Array(TestRenderBackend) = [] of TestRenderBackend
      getter widget_backends

      def initialize(width : Int32 = 800, height : Int32 = 600)
        @backend = TestRenderBackend.new(width, height)  # Window buffer
        @scheduler = Scheduler.new
        @shortcut_manager = TestShortcutManager.new

        # Set global scheduler for widgets (shortcut manager not set in headless mode)
        Widget.scheduler = @scheduler
        # Note: Widget.shortcut_manager not set - headless tests don't test keyboard shortcuts
      end

      # Reset all performance counters
      def reset_counters
        @render_frame_count = 0
        @render_layer_count = 0
        @compositor_call_count = 0
        @compositor_skip_count = 0
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

      # Render frames until rendering stabilizes (no more changes)
      # Useful for test setup - ensures initial state is settled before testing
      def settle_rendering(app : App, max_frames : Int32 = 10)
        max_frames.times do
          prev_primitive_count = primitive_count
          prev_clear_count = backend_clear_count

          render_frame(app)

          # If nothing changed, we're settled
          if primitive_count == prev_primitive_count && backend_clear_count == prev_clear_count
            break
          end
        end
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

        # Sync background color from app (app may override; nil = white default).
        @background_color = app.app_background_color || Color.new(255, 255, 255, 255)

        # Clear widget backends before each frame
        # Backends will re-register as widgets render, ensuring we only count active backends
        @widget_backends.clear

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

          # Re-detect hover after layout (restores hover state after rebuild)
          # Matches SFML renderer behavior
          app.redetect_hover if did_layout

          return unless root_widget = app.root

          # All layer logic handled by LayerRenderer
          # Include ghost and highlight layers if drag-and-drop is active
          render_all_layers(root_widget, app.drag_manager.ghost_layer, app.drag_manager.highlight_layer)

          # Clear render state after rendering (same as SFMLRenderer)
          # This marks widgets as Clean so cache optimization works correctly
          app.clear_render_state unless did_layout
        rescue exception
          handle_frame_exception(exception, app)
        end
      end

      # Handle exception during frame rendering (graceful degradation)
      private def handle_frame_exception(exception : Exception, app : App)
        @exceptions_caught += 1
        @last_exception_message = "#{exception.message}\n#{exception.backtrace?.try(&.first(5).join("\n"))}"
        app.reset_all_caches
        app.root.try(&.mark_needs_layout)
      end

      # Render primitives directly
      def render_primitives(primitives : Array(DrawPrimitive))
        primitives.each do |primitive|
          @total_primitives += 1
          @backend.execute_primitive(primitive)
        end
      end

      # === LayerRenderer Abstract Methods ===

      # Create test backend for layer
      def ensure_layer_backend(layer : Layer, width : Int32, height : Int32)
        backend = TestRenderBackend.new(width, height)
        layer.backend = backend
        layer.reset_first_render

        # Track backend for primitive counting
        @layer_backends << backend unless @layer_backends.includes?(backend)
      end

      # Create test backend for widget (per-widget texture)
      # NOTE: Uses transparent background (alpha=0) to match SFML RenderTexture behavior
      # This allows tests to detect size-mismatch bugs where uninitialized pixels leak through
      def create_widget_backend(width : Int32, height : Int32) : RenderBackend
        backend = TestRenderBackend.new(width, height, Color.new(0_u8, 0_u8, 0_u8, 0_u8))
        register_widget_backend(backend)
        backend
      end

      # Composite layer to window buffer
      def composite_layer_to_window(layer : Layer)
        return unless backend = layer.backend
        return unless backend.is_a?(TestRenderBackend)

        # Blit only the visible portion of layer buffer (clip to layer.bounds size)
        # Layer backend may be larger due to buffer expansion, but we only composite the visible area
        # Use ceil() to avoid clipping bottom/right edge when bounds are fractional
        clip_width = layer.bounds.width.ceil.to_i
        clip_height = layer.bounds.height.ceil.to_i

        if layer.viewport_cache
          # Viewport cache compositing: sliding viewport for scrolling layers
          composite_viewport_cache_layer(layer, backend, clip_width, clip_height)
        else
          # Standard compositing: blit layer to window at layer position
          backend.blit_to(@backend, layer.bounds.x.to_i, layer.bounds.y.to_i, clip_width, clip_height,
                          use_alpha_blend: true, opacity: layer.opacity, blend_mode: layer.blend_mode)
          @backend_blit_count += 1
        end

        # Draw borders for panels and popups if this layer belongs to them
        # Borders are NOT cached - drawn fresh each frame to avoid ghost borders during resize
        # This aligns headless renderer with SFML renderer behavior

        # Detect panel layers by ID (layer.id starts with "panel_")
        if layer.id.starts_with?("panel_")
          # Find the panel widget (parent of Chrome/Content widgets in layer)
          if chrome = layer.widgets.first?
            if panel = chrome.parent.as?(WindowPanel)
              draw_panel_border(panel)
            end
          end
        end

        # Detect popup layers by ID (layer.id starts with "popup_")
        if layer.id.starts_with?("popup_")
          # Find the popup widget (first widget in layer.widgets)
          if popup_widget = layer.widgets.first?
            if popup = popup_widget.as?(Popup)
              draw_popup_border(popup)
            end
          end
        end
      end

      # Draw panel border directly on window buffer (not cached in layer)
      # Draws border INSIDE bounds (unlike SFML which draws OUTSIDE with outline_thickness)
      private def draw_panel_border(panel : WindowPanel)
        border_rect = Rect.new(panel.x, panel.y, panel.width, panel.height)
        @backend.draw_rect(border_rect, panel.border_color)
      end

      # Draw popup border directly on window buffer (not cached in layer)
      # Draws border INSIDE bounds (unlike SFML which draws OUTSIDE with outline_thickness)
      private def draw_popup_border(popup : Popup)
        abs_bounds = popup.absolute_bounds
        border_rect = Rect.new(abs_bounds.x, abs_bounds.y, abs_bounds.width, abs_bounds.height)
        @backend.draw_rect(border_rect, popup.border_color)
      end

      # Composite viewport_cache layer - apply viewport offset (scroll_offset - buffer_origin)
      # MUST match SFML's composite_viewport_cache_layer to ensure tests catch same bugs
      private def composite_viewport_cache_layer(layer : Layer, backend : TestRenderBackend, viewport_width : Int32, viewport_height : Int32)
        dest_x = layer.bounds.x.to_i
        dest_y = layer.bounds.y.to_i

        # Viewport position within buffer = scroll_offset - buffer_origin (MATCHES SFML!)
        viewport_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
        viewport_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i

        # Clamp to valid buffer region
        buffer_width = backend.width
        buffer_height = backend.height
        viewport_x = viewport_x.clamp(0, [buffer_width - viewport_width, 0].max)
        viewport_y = viewport_y.clamp(0, [buffer_height - viewport_height, 0].max)

        # Blit from viewport position in buffer (NOT always 0,0)
        backend.blit_region_to(@backend, viewport_x, viewport_y, viewport_width, viewport_height,
                                dest_x, dest_y, use_alpha_blend: true, opacity: layer.opacity, blend_mode: layer.blend_mode)
        @backend_blit_count += 1
      end

      # Clear window buffer to background color
      def clear_window_background
        @backend.clear(@background_color)
      end

      # Instrumentation: Track compositor calls
      def increment_compositor_call_count
        @compositor_call_count += 1
      end

      # Instrumentation: Track compositor skips
      def increment_compositor_skip_count
        @compositor_skip_count += 1
      end

      # === Event Simulation Methods ===

      # Simulate mouse down event
      def mouse_down(x : Float64, y : Float64)
        return unless app = @app

        point = Vec2.new(x, y)
        app.handle_mouse_down(point)
      end

      # Simulate mouse move event
      def mouse_move(x : Float64, y : Float64)
        return unless app = @app

        point = Vec2.new(x, y)
        # Update hover (triggers on_mouse_enter/on_mouse_exit)
        app.update_hover(point)
        # Also handle dragging if mouse is down
        app.handle_mouse_move(point)
        # Update cursor when not dragging
        update_cursor(app, point) unless app.mouse_down?
      end

      # Simulate mouse up event
      def mouse_up(x : Float64, y : Float64)
        return unless app = @app

        point = Vec2.new(x, y)
        app.handle_mouse_up(point)
        # Update cursor immediately after mouse up (matches SFMLRenderer fix)
        update_cursor(app, point)
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
