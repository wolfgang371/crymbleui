require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"

# SFML autotest - the per-frame cost of the paths that RELEASE surfaces as they drop them (they used to drop them
# unreleased): a deep scroll through a sticky-header grid (buffer recenters, repositioned sticky cells), a zoom
# sweep (every texture on screen), tab switches (a hidden page's textures). One action per scheduler tick; the
# frames are timed by the renderer's own work log (CRYMBLE_WORKLOG, layout + render + composite ms per rendered
# frame), and this run writes each phase's time window, on the work log's clock, next to it.
#
# Run:  source setup.sh
#       crystal build --release spec/autotest/release_cost_autotest.cr -o /tmp/release_cost
#       DISPLAY=:0 timeout 120 /tmp/release_cost
# Then average the work log's rows (/tmp/release_cost.tsv) inside each window of /tmp/release_cost.log. Compare
# two builds (before / after a change) by those per-phase means; no absolute budget is implied.

class ReleaseCostApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Release cost", 1200, 800) do
      window_panel("P", x: 10.0, y: 10.0, width: 1100.0, height: 720.0, id: "panel") do
        tabs(id: "tabs") do
          tab("grid") do
            widget(CrymbleUI::VirtualMatrix.new(ConfigurableMatrixAdapter.new(2, 2, 3000, 30, 1, 1), id: "grid"))
          end
          tab("buttons") do
            vstack(spacing: 2.0) { 60.times { |i| button("Button #{i}") { } } }
          end
        end
      end
    end
  end
end

LOG = "/tmp/release_cost.log"
File.write(LOG, "")

def log(msg : String)
  File.open(LOG, "a") { |f| f.puts msg }
  puts msg
end

class CostDriver
  SCROLLS = 60
  ZOOMS   = 20
  TABS    = 30

  @step = 0
  @phase = ""
  @phase_start = 0.0

  def initialize(@app : ReleaseCostApp, @t0 : Time::Instant)
  end

  private def now_ms : Float64
    (Time.instant - @t0).total_milliseconds
  end

  private def enter(phase : String) : Nil
    return if phase == @phase
    log("PHASE\t#{@phase}\t#{@phase_start.round(1)}\t#{now_ms.round(1)}") unless @phase.empty?
    @phase = phase
    @phase_start = now_ms
  end

  private def find(id : String) : CrymbleUI::Widget
    @app.root.not_nil!.find_by_id(id).not_nil!
  end

  def step : Bool
    s = @step
    @step += 1
    case s
    when 0...SCROLLS
      enter("deep scroll")
      find("grid").as(CrymbleUI::VirtualMatrix).scroll_offset = CrymbleUI::Vec2.new(0.0, 900.0 * (s + 1))
    when SCROLLS...(SCROLLS + ZOOMS)
      enter("zoom sweep")
      (s - SCROLLS).even? ? CrymbleUI::FontSizing.zoom_in : CrymbleUI::FontSizing.zoom_out
    when (SCROLLS + ZOOMS)...(SCROLLS + ZOOMS + TABS)
      enter("tab switch")
      find("tabs").as(CrymbleUI::Tabs).active = (s - SCROLLS - ZOOMS).even? ? 1 : 0
    else
      enter("done")
      return false
    end
    true
  end
end

ENV["CRYMBLE_WORKLOG"] = "/tmp/release_cost.tsv"
app = ReleaseCostApp.new
app.build_tree
window_widget = app.root.not_nil!.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(width: window_widget.width, height: window_widget.height, title: window_widget.title)
driver = CostDriver.new(app, Time.instant) # the work log's clock starts in the renderer's constructor

CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 800_000_000)) do
  tick = uninitialized Proc(Nil)
  tick = -> do
    if driver.step
      CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 120_000_000)) { tick.call }
    else
      app.quit # closes the window: run returns and the work log is flushed and closed
    end
    nil
  end
  tick.call
end

renderer.run(app)
