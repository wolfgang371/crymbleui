require "../../src/crymble-ui"

# SFML AUTOTEST - controls for SFMLRenderer#run, the blocking desktop loop built on WindowRenderer's pieces.
# One control per process (run blocks and owns process-wide state):
#   a  no timers; the first frame quits -> run must return (it must not block for good before a frame)
#   b  a 0.3 s timer changes the swatch, no input -> the change is presented within 1 s (the timer branch's
#      fired-timers verdict renders it)
# What these do NOT prove: that the first frame comes before any OS event - X11 delivers Resized/FocusGained on
# map, which ends run's first wait anyway. The loop's rules are pinned by spec/rendering/window_renderer_spec.cr.
#
# Run: source setup.sh
#      crystal build spec/autotest/run_loop_autotest.cr -o /tmp/run_loop_autotest
#      DISPLAY=:0 timeout 10 /tmp/run_loop_autotest a && DISPLAY=:0 timeout 10 /tmp/run_loop_autotest b

lib LibCSFML
  fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
end

class LoopSwatch < CrymbleUI::Widget
  class_property color = CrymbleUI::Color.new(0, 0, 200, 255)

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(120.0, 60.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), LoopSwatch.color).as(CrymbleUI::DrawPrimitive)]
  end
end

class LoopApp < CrymbleUI::App
  property quit_on_first_frame = false
  getter frames = 0

  def build : CrymbleUI::Widget
    window("Run Loop Autotest", 320, 200) do
      vstack { widget(LoopSwatch.new(id: "swatch")) }
    end
  end

  def finish_frame : Bool
    @frames += 1
    quit if @quit_on_first_frame
    super
  end
end

# Notes the swatch colour of every presented frame (back buffer, just before the swap).
class LoopRenderer < CrymbleUI::SFMLRenderer
  property on_present : Proc(CrymbleUI::Color, Nil)? = nil

  protected def display_window : Nil
    if (callback = @on_present) && (app = @app) && (swatch = app.find("swatch"))
      window = self.window.not_nil!
      size = window.size
      texture = SF::Texture.new(size.x, size.y)
      LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
      at = swatch.viewport_bounds.center
      px = texture.copy_to_image.get_pixel(at.x.to_i, at.y.to_i)
      callback.call(CrymbleUI::Color.new(px.r, px.g, px.b, px.a))
    end
    super
  end
end

mode = ARGV.first? || "a"
app = LoopApp.new
app.build_tree
root = app.root.as(CrymbleUI::Window)
renderer = LoopRenderer.new(width: root.width, height: root.height, title: root.title)

case mode
when "a"
  app.quit_on_first_frame = true
  renderer.run(app)
  ok = app.frames >= 1
  puts "#{ok ? "ok  " : "FAIL"} a: run returned after its first frame (frames=#{app.frames})"
  puts ok ? "VERDICT: PASS" : "VERDICT: FAIL"
  exit ok ? 0 : 1
when "b"
  red = CrymbleUI::Color.new(200, 0, 0, 255)
  started = Time.instant
  shown_after : Time::Span? = nil
  renderer.on_present = ->(c : CrymbleUI::Color) do
    if shown_after.nil? && (c.r.to_i - red.r).abs <= 2 && c.g < 3 && c.b < 3
      shown_after = Time.instant - started
      app.quit
    end
    nil
  end
  CrymbleUI::Widget.scheduler.schedule(300.milliseconds) do
    LoopSwatch.color = red
    app.find("swatch").not_nil!.mark_needs_render
  end
  CrymbleUI::Widget.scheduler.schedule(3.seconds) { app.quit } # give up
  renderer.run(app)
  took = shown_after
  ok = !took.nil? && took.not_nil! < 1.second
  puts "#{ok ? "ok  " : "FAIL"} b: a timer's change without input was presented after #{took.try(&.total_milliseconds.round) || "never"} ms"
  puts ok ? "VERDICT: PASS" : "VERDICT: FAIL"
  exit ok ? 0 : 1
else
  abort "mode a or b"
end
