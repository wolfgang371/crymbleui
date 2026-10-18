require "../spec_helper"
require "../../src/rendering/window_renderer"
require "../../src/testing/keys"

# WindowRenderer is the platform-neutral half of a renderer that owns a window: the loop's decisions, event
# dispatch, cursor choice, the frame and the composite decisions. A platform supplies hooks; this spec supplies
# scripted ones over a TestRenderBackend window, so the shared half runs through REAL LibCSFML events in the
# headless suite - the SFML autotests drive App directly and never reach dispatch.

private class ScriptedWindowRenderer < CrymbleUI::WindowRenderer
  getter calls = [] of String
  getter window : CrymbleUI::Testing::TestRenderBackend
  getter events = Deque(LibCSFML::Event).new
  property open = true
  property invalidate_before_iteration = false

  def initialize(width : Int32, height : Int32)
    @window = CrymbleUI::Testing::TestRenderBackend.new(width, height)
    super()
  end

  def push(event : LibCSFML::Event) : Nil
    @events << event
  end

  def count(prefix : String) : Int32
    @calls.count(&.starts_with?(prefix))
  end

  protected def has_window? : Bool
    true
  end

  protected def window_open? : Bool
    @open
  end

  protected def window_size : CrymbleUI::Size
    CrymbleUI::Size.new(@window.width.to_f64, @window.height.to_f64)
  end

  protected def poll_event : LibCSFML::Event?
    @calls << "poll"
    @events.shift?
  end

  protected def close_window : Nil
    @calls << "close"
    @open = false
  end

  protected def display_window : Nil
    @calls << "display"
  end

  protected def after_display : Nil
    @calls << "after_display"
  end

  protected def present_after_failure : Nil
    @calls << "present_after_failure"
  end

  protected def apply_window_title(title : String) : Nil
    @calls << "title #{title}"
  end

  protected def apply_cursor(cursor : CrymbleUI::CursorType) : Nil
    @calls << "cursor #{cursor}"
  end

  protected def on_window_resized(width : Int32, height : Int32) : Nil
    @calls << "resized #{width}x#{height}"
  end

  protected def before_iteration : Nil
    return unless @invalidate_before_iteration
    @invalidate_before_iteration = false
    invalidate_all_rendering(@app.try(&.root))
  end

  protected def draw_primitives(primitives : Array(CrymbleUI::DrawPrimitive)) : Nil
    @window.execute_primitives(primitives)
  end

  protected def draw_layer_region(backend : CrymbleUI::RenderBackend, region : CrymbleUI::LayerRenderer::CompositeRegion,
                                  opacity : Float64, blend_mode : CrymbleUI::BlendMode) : Nil
    @calls << "layer"
    backend.as(CrymbleUI::Testing::TestRenderBackend).blit_region_to(@window, region.src_x, region.src_y,
      region.width, region.height, region.dest_x, region.dest_y, use_alpha_blend: true, opacity: opacity,
      blend_mode: blend_mode)
  end

  protected def draw_border_rect(bounds : CrymbleUI::Rect, color : CrymbleUI::Color) : Nil
    @calls << "border"
  end

  def create_layer_backend(width : Int32, height : Int32) : CrymbleUI::RenderBackend
    CrymbleUI::Testing::TestRenderBackend.new(width, height, CrymbleUI::Color.new(0, 0, 0, 0))
  end

  def create_widget_backend(width : Int32, height : Int32) : CrymbleUI::RenderBackend
    CrymbleUI::Testing::TestRenderBackend.new(width, height, CrymbleUI::Color.new(0, 0, 0, 0))
  end

  def clear_window_background
    @window.clear(@background_color)
  end
end

# Paints a swatch; raises in the frame after `armed` is set (once) - a frame that fails, as an app's widget can.
private class RaiseOnce < CrymbleUI::Widget
  class_property armed = false
  # Structural work held for the next input (App#register_input_flush): applied by the frame's end.
  class_property flush_pending = false

  def flush_before_input : Bool
    return false unless RaiseOnce.flush_pending
    RaiseOnce.flush_pending = false
    mark_needs_render
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(40.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    if RaiseOnce.armed
      RaiseOnce.armed = false
      raise "a widget failed to paint"
    end
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
      CrymbleUI::Color.new(9, 9, 9, 255)).as(CrymbleUI::DrawPrimitive)]
  end
end

private class RecordingApp < CrymbleUI::App
  getter log = [] of String
  property title = "first"
  property with_panel = false
  # An overlay with a clip: a window-direct draw refuses it with a RenderDefect, which a frame never degrades over.
  property clip_in_overlay = false

  def overlay_primitives(window_width : Float64, window_height : Float64) : Array(CrymbleUI::DrawPrimitive)?
    return nil unless @clip_in_overlay
    [CrymbleUI::PushClip.new(CrymbleUI::Rect.new(0.0, 0.0, 5.0, 5.0)).as(CrymbleUI::DrawPrimitive)]
  end

  def build : CrymbleUI::Widget
    app = self
    window(@title, 300, 200) do
      vstack do
        text_input(id: "field", placeholder: "type")
        widget(RaiseOnce.new(id: "raiser"))
        if app.with_panel
          window_panel("Panel", id: "panel", x: 20.0, y: 20.0, width: 120.0, height: 80.0) do
            text("inside")
          end
        end
      end
    end
  end

  def handle_close_request
    @log << "close_request"
  end

  def handle_mouse_wheel(delta : CrymbleUI::Vec2, point : CrymbleUI::Vec2, shift : Bool = false)
    @log << "wheel #{delta.x},#{delta.y} shift=#{shift}"
  end

  def handle_ctrl_wheel(steps : Float64, point : CrymbleUI::Vec2) : Nil
    @log << "ctrl_wheel #{steps}"
  end
end

private def event_resized(w : UInt32, h : UInt32) : LibCSFML::Event
  e = LibCSFML::Event.new
  e.size = LibCSFML::SizeEvent.new(type: LibCSFML::EventType::Resized, size: LibCSFML::Vector2u.new(x: w, y: h))
  e
end

private def event_closed : LibCSFML::Event
  e = LibCSFML::Event.new
  e.type = LibCSFML::EventType::Closed
  e
end

private def event_wheel(delta : Float32, horizontal = false) : LibCSFML::Event
  e = LibCSFML::Event.new
  wheel = horizontal ? LibCSFML::MouseWheel::Horizontal : LibCSFML::MouseWheel::Vertical
  e.mouse_wheel_scroll = LibCSFML::MouseWheelScrollEvent.new(type: LibCSFML::EventType::MouseWheelScrolled,
    wheel: wheel, delta: delta, position: LibCSFML::Vector2i.new(x: 50, y: 50))
  e
end

private def started(app : RecordingApp = RecordingApp.new) : {ScriptedWindowRenderer, RecordingApp}
  renderer = ScriptedWindowRenderer.new(300, 200)
  renderer.start(app)
  {renderer, app}
end

# Tick until a tick renders nothing (bounded): the frames a start or an event leads to are over.
private def settle(renderer : ScriptedWindowRenderer) : Nil
  60.times { return unless renderer.tick }
  raise "the renderer never went quiet"
end

describe CrymbleUI::WindowRenderer do
  describe "tick" do
    it "renders the first frame after start without any event" do
      renderer, _ = started
      renderer.tick.should be_true
    end

    it "renders nothing once quiet, and polls every idle tick" do
      renderer, _ = started
      settle(renderer)
      polls = renderer.count("poll")
      5.times { renderer.tick.should be_false }
      renderer.count("poll").should be > polls
    end

    # (The input barrier itself stops EventBatch from polling - EventBatch's rule. What tick adds is the
    # flushed frame: after a frame whose end applied deferred work, that work is painted before input.)
    it "takes no input after a frame whose end applied deferred work, and paints that work first" do
      renderer, app = started
      settle(renderer)
      raiser = app.find("raiser").not_nil!
      RaiseOnce.flush_pending = true
      app.register_input_flush(raiser)
      raiser.mark_needs_render
      renderer.tick.should be_true # its end flushed the work
      polls = renderer.count("poll")
      renderer.tick.should be_true # paints what the flush changed...
      renderer.count("poll").should eq polls # ...before taking any input
    end

    it "ASSIGNS a fired timer's verdict: a key the app ignores plus a no-op timer render nothing" do
      renderer, _ = started
      settle(renderer)
      CrymbleUI::Widget.scheduler.schedule(Time::Span.zero) { }
      renderer.push(CrymbleUI::Testing::Keys.pressed(LibCSFML::KeyCode::F13))
      renderer.tick.should be_false # dispatch forced a redraw; the timer's pull (nothing moved) overwrote it
    end

    it "renders after an invalidation raised before the iteration, with no event or timer" do
      renderer, _ = started
      settle(renderer)
      renderer.invalidate_before_iteration = true
      renderer.tick.should be_true
    end

    it "stops after the window closed: later ticks render nothing and do not raise" do
      renderer, app = started
      settle(renderer)
      app.quit
      renderer.open?.should be_false
      3.times { renderer.tick.should be_false }
    end
  end

  describe "dispatch" do
    it "Resized: calls the platform hook, lays the root out again and renders" do
      renderer, app = started
      settle(renderer)
      renderer.push(event_resized(320, 240))
      renderer.tick.should be_true
      renderer.calls.should contain "resized 320x240"
    end

    it "Closed: asks the app, renders nothing for it" do
      renderer, app = started
      settle(renderer)
      renderer.push(event_closed)
      renderer.tick.should be_false
      app.log.should eq ["close_request"]
    end

    it "wheel: vertical goes to Y, horizontal to X" do
      renderer, app = started
      settle(renderer)
      renderer.push(event_wheel(1.5_f32))
      renderer.push(event_wheel(-2.0_f32, horizontal: true))
      renderer.tick
      app.log.should eq ["wheel 0.0,1.5 shift=false", "wheel -2.0,0.0 shift=false"]
    end

    it "wheel: Shift is passed on, Ctrl zooms instead" do
      renderer, app = started
      settle(renderer)
      renderer.push(CrymbleUI::Testing::Keys.pressed(LibCSFML::KeyCode::LShift, shift: true))
      renderer.push(event_wheel(1.0_f32))
      renderer.push(CrymbleUI::Testing::Keys.released(LibCSFML::KeyCode::LShift))
      renderer.push(CrymbleUI::Testing::Keys.pressed(LibCSFML::KeyCode::LControl, control: true))
      renderer.push(event_wheel(1.0_f32))
      renderer.tick
      app.log.should eq ["wheel 0.0,1.0 shift=true", "ctrl_wheel 1.0"]
    end

    it "installs a cursor only when it changes" do
      renderer, app = started
      settle(renderer)
      field = app.find("field").not_nil!.viewport_bounds.center
      renderer.push(CrymbleUI::Testing::Keys.move_to(field.x.to_i, field.y.to_i))
      renderer.push(CrymbleUI::Testing::Keys.move_to(field.x.to_i + 1, field.y.to_i))
      renderer.tick
      renderer.count("cursor").should eq 1
      renderer.calls.should contain "cursor Text"
    end
  end

  describe "frame" do
    it "applies the window title only when it changes" do
      renderer, app = started
      settle(renderer)
      renderer.count("title").should eq 1
      app.title = "second"
      app.request_rebuild
      settle(renderer)
      renderer.calls.select(&.starts_with?("title")).should eq ["title first", "title second"]
    end

    it "presents every rendered frame through display_window, then after_display" do
      renderer, _ = started
      renderer.tick
      renderer.calls.index("display").not_nil!.should be < renderer.calls.index("after_display").not_nil!
    end

    it "lets a RenderDefect out of the frame instead of degrading over it" do
      renderer, app = started
      settle(renderer)
      app.clip_in_overlay = true
      app.find("raiser").not_nil!.mark_needs_render
      expect_raises(CrymbleUI::WindowDirectClipError) { renderer.tick }
      renderer.count("present_after_failure").should eq 0
    end

    it "presents a frame that raised through present_after_failure" do
      renderer, app = started
      settle(renderer)
      RaiseOnce.armed = true
      app.find("raiser").not_nil!.mark_needs_render
      renderer.tick
      renderer.count("present_after_failure").should eq 1
    end
  end

  describe "composite" do
    # (A closed panel's layer never gets here: LayerRenderer's composite loop skips owners that skip_render?.
    # The same check inside composite_layer_to_window is a guard no tree reaches - measured, kept as moved.)
    it "draws an open panel's chrome border through the platform's border hook" do
      app = RecordingApp.new
      app.with_panel = true
      renderer, _ = started(app)
      renderer.tick.should be_true
      renderer.count("border").should be > 0
    end
  end
end
