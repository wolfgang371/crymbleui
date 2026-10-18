require "../../src/crymble-ui"

# SFML AUTOTEST - WindowRenderer#tick through the real SFML window: the step a host that owns the frame clock
# (a browser) drives, one iteration per call, never waiting. Each check reads what a tick PRESENTED: the
# renderer below reads the back buffer inside display_window, just before the swap, so a pixel shows only
# what that tick rendered (reading the window afterwards would re-composite on its own and prove nothing).
#
# Run: source setup.sh
#      crystal build spec/autotest/tick_autotest.cr -o /tmp/tick_autotest
#      DISPLAY=:0 timeout 60 /tmp/tick_autotest      (exit 0: every check held)

lib LibCSFML
  fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
end

private BLUE  = CrymbleUI::Color.new(0, 0, 200, 255)
private RED   = CrymbleUI::Color.new(200, 0, 0, 255)
private GREEN = CrymbleUI::Color.new(0, 160, 0, 255)

# A block of the class's current colour.
class TickSwatch < CrymbleUI::Widget
  class_property color = BLUE

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(120.0, 60.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), TickSwatch.color).as(CrymbleUI::DrawPrimitive)]
  end
end

class TickApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Tick Autotest", 320, 200) do
      vstack { widget(TickSwatch.new(id: "swatch")) }
    end
  end
end

# Keeps the back buffer of each presented frame (read just before the swap); can hold the OS's events back.
class ProbeRenderer < CrymbleUI::SFMLRenderer
  property hold_events = false
  getter presents = 0
  getter last_image : SF::Image? = nil

  protected def poll_event : LibCSFML::Event?
    return nil if @hold_events
    super
  end

  protected def display_window : Nil
    window = self.window.not_nil!
    size = window.size
    texture = SF::Texture.new(size.x, size.y)
    LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
    @last_image = texture.copy_to_image
    @presents += 1
    super
  end

  # The colour the last presented frame shows at `at`.
  def presented_at(at : CrymbleUI::Vec2) : CrymbleUI::Color?
    @last_image.try do |image|
      px = image.get_pixel(at.x.to_i, at.y.to_i)
      CrymbleUI::Color.new(px.r, px.g, px.b, px.a)
    end
  end
end

failures = [] of String
check = ->(name : String, ok : Bool, detail : String) do
  puts "#{ok ? "ok  " : "FAIL"} #{name}: #{detail}"
  failures << name unless ok
end
near = ->(a : CrymbleUI::Color, b : CrymbleUI::Color) { (a.r.to_i - b.r).abs <= 2 && (a.g.to_i - b.g).abs <= 2 && (a.b.to_i - b.b).abs <= 2 }

app = TickApp.new
app.build_tree
root = app.root.as(CrymbleUI::Window)
renderer = ProbeRenderer.new(width: root.width, height: root.height, title: root.title)
renderer.hold_events = true
renderer.start(app)

# 0. The first tick after start renders, with no event at all, and presents the initial colour.
first = renderer.tick
at = app.find("swatch").not_nil!.viewport_bounds.center
shown = renderer.presented_at(at)
check.call("0 first tick renders without events", first && renderer.presents == 1 && !shown.nil? && near.call(shown.not_nil!, BLUE),
  "first tick rendered=#{first}, presents=#{renderer.presents}, shows #{shown}")

# 1. The OS's events released; once quiet, ticks render nothing.
renderer.hold_events = false
quiet = false
60.times do
  unless renderer.tick
    quiet = true
    break
  end
  sleep 10.milliseconds
end
idle = (1..5).map { renderer.tick }
check.call("1 quiet ticks render nothing", quiet && idle.none?, "quiet=#{quiet}, idle ticks rendered=#{idle}")

# 2. A state change between ticks: the next tick presents it, the ones after are idle again.
TickSwatch.color = RED
app.find("swatch").not_nil!.mark_needs_render
presents = renderer.presents
rendered = renderer.tick
after = (1..5).map { renderer.tick }
shown = renderer.presented_at(at).not_nil!
check.call("2 a change is presented by the next tick", rendered && renderer.presents == presents + 1 &&
  near.call(shown, RED) && after.none?, "rendered=#{rendered} presents +#{renderer.presents - presents} shows #{shown} after=#{after}")

# 3. A timer: ticks before it is due present nothing; the first tick after presents its change.
due = Time.instant + 150.milliseconds
CrymbleUI::Widget.scheduler.schedule(150.milliseconds) do
  TickSwatch.color = GREEN
  app.request_rebuild
end
presents = renderer.presents
early = [] of Bool
while Time.instant < due - 30.milliseconds
  early << renderer.tick
  sleep 10.milliseconds
end
sleep 50.milliseconds
late = renderer.tick
shown = renderer.presented_at(at).not_nil!
check.call("3 a timer is fired by the first tick after it is due", early.none? && renderer.presents == presents + 1 &&
  late && near.call(shown, GREEN), "early=#{early.size} ticks (any rendered: #{early.any?}), late rendered=#{late}, shows #{shown}")

# 4. Quit: the window closes, a later tick renders nothing and does not raise.
app.quit
closed = !renderer.open?
later = begin
  renderer.tick
rescue ex
  check.call("4 tick after quit", false, "raised #{ex.message}")
  true
end
check.call("4 quit closes; a later tick renders nothing", closed && !later, "open?=#{!closed} later tick rendered=#{later}")

puts failures.empty? ? "VERDICT: PASS" : "VERDICT: FAIL (#{failures.join(", ")})"
exit failures.empty? ? 0 : 1
