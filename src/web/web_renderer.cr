require "../csfml3/lib"
require "../rendering/window_renderer"
require "./js"
require "./web_backend"
require "./web_font"

module CrymbleUI
  # The web flavour's platform under WindowRenderer: the page's canvas is the window, the page's input queue its
  # events. The page drives the loop - `start` once, `tick` per animation frame (src/web/entry.cr) - so nothing
  # here waits.
  class WebRenderer < WindowRenderer
    getter window : WebBackend
    @open = true

    def initialize(width : Int32 = 800, height : Int32 = 600, title : String = "CrymbleUI Application")
      @window = WebBackend.window # the page sizes its canvas; the app's width/height do not apply in a tab
      super()
      Widget.font = WebFont.new
      Widget.clipboard = WebClipboard.new
      apply_window_title(title)
    end

    # === WindowRenderer hooks ===

    protected def has_window? : Bool
      true
    end

    protected def window_open? : Bool
      @open
    end

    protected def window_size : Size
      Size.new(@window.width.to_f64, @window.height.to_f64)
    end

    protected def poll_event : LibCSFML::Event?
      return nil unless LibCrymbleWeb.next_event(out type, out i0, out i1, out i2, out f, out mods)
      WebRenderer.event(LibCSFML::EventType.new(type), i0, i1, i2, f, mods)
    end

    protected def close_window : Nil
      @open = false
    end

    # The browser shows the canvas once the tick returns.
    protected def display_window : Nil
    end

    protected def after_display : Nil
    end

    protected def present_after_failure : Nil
    end

    protected def apply_window_title(title : String) : Nil
      LibCrymbleWeb.set_title(title.to_unsafe, title.bytesize)
    end

    protected def apply_cursor(cursor : CursorType) : Nil
      LibCrymbleWeb.set_cursor(cursor.value)
    end

    protected def on_window_resized(width : Int32, height : Int32) : Nil
      @window.resized
    end

    # An image decoded after it was first asked for, or a lost and restored canvas: the drawn pixels are stale
    # behind the tree's back, so everything renders again (zoom's response without the font reload).
    protected def before_iteration : Nil
      return if LibCrymbleWeb.invalidations == 0
      invalidate_all_rendering(@app.try(&.root))
    end

    protected def draw_layer_region(backend : RenderBackend, region : CompositeRegion, opacity : Float64,
                                    blend_mode : BlendMode) : Nil
      @window.composite(backend.as(WebBackend), region.src_x, region.src_y, region.width, region.height,
        region.dest_x, region.dest_y, opacity, blend_mode)
    end

    # A 1px chrome border as four edge rects (WebBackend#draw_rect), as SFMLRenderer draws it.
    protected def draw_border_rect(bounds : Rect, color : Color) : Nil
      @window.draw_rect(bounds, color)
    end

    # Window-direct primitives through the window's backend: the one web geometry (the one conformance compares).
    protected def draw_primitives(primitives : Array(DrawPrimitive)) : Nil
      primitives.each { |primitive| execute_primitive_on_widget_backend(primitive, @window) }
    end

    def create_layer_backend(width : Int32, height : Int32) : RenderBackend
      WebBackend.new(width, height)
    end

    def create_widget_backend(width : Int32, height : Int32) : RenderBackend
      WebBackend.new(width, height)
    end

    def clear_window_background
      @window.clear(@background_color)
    end

    protected def reload_font_for_zoom
      Widget.font = WebFont.new
    end

    # The LibCSFML::Event an input event from the page stands for. Slots by type: Resized w, h; TextEntered the
    # code point; Key* the key code (+ mods: bit 0 alt, 1 control, 2 shift, 3 system); MouseMoved x, y;
    # MouseButton* button, x, y; MouseWheelScrolled wheel, x, y and the delta in f.
    def self.event(type : LibCSFML::EventType, i0 : Int32, i1 : Int32, i2 : Int32, f : Float64, mods : Int32) : LibCSFML::Event
      event = LibCSFML::Event.new
      case type
      when .resized?
        event.size = LibCSFML::SizeEvent.new(type: type, size: LibCSFML::Vector2u.new(x: i0.to_u32, y: i1.to_u32))
      when .text_entered?
        event.text = LibCSFML::TextEvent.new(type: type, unicode: i0.to_u32)
      when .key_pressed?, .key_released?
        event.key = LibCSFML::KeyEvent.new(type: type, code: LibCSFML::KeyCode.new(i0), scancode: -1,
          alt: mods.bit(0) == 1, control: mods.bit(1) == 1, shift: mods.bit(2) == 1, system: mods.bit(3) == 1)
      when .mouse_moved?
        event.mouse_move = LibCSFML::MouseMoveEvent.new(type: type, position: LibCSFML::Vector2i.new(x: i0, y: i1))
      when .mouse_button_pressed?, .mouse_button_released?
        event.mouse_button = LibCSFML::MouseButtonEvent.new(type: type, button: LibCSFML::MouseButton.new(i0),
          position: LibCSFML::Vector2i.new(x: i1, y: i2))
      when .mouse_wheel_scrolled?
        event.mouse_wheel_scroll = LibCSFML::MouseWheelScrollEvent.new(type: type, wheel: LibCSFML::MouseWheel.new(i0),
          delta: f.to_f32, position: LibCSFML::Vector2i.new(x: i1, y: i2))
      else
        event.type = type
      end
      event
    end
  end

  # What an app's About shows for the backend this flavour was built with (see the native definition).
  def self.backend_notices : Array(String)
    [
      "crymble-ui web backend (HTML canvas), MIT license",
      "Crystal standard library, Apache 2.0 license",
      "Boehm-Demers-Weiser garbage collector, MIT-style license",
      "wasi-libc, browser_wasi_shim: MIT / Apache 2.0 licenses",
    ] + EmbeddedFont::ATTRIBUTION + ["Full list: NOTICES, next to this page"]
  end
end
