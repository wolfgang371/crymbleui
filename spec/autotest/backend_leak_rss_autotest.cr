require "../../src/crymble-ui"

# SFML RSS WITNESS for the backend-release defect.
#
# Headless cannot see this defect at all: there a backend's payload is a Crystal array the GC
# reclaims on its own, so every release-path fix measures as a no-op. Under SFML the payload is a
# driver-side RenderTexture that the collector cannot see and `dispose` does not free — so the only
# instrument that can witness it is a real window plus the process's own resident-set size.
#
# Protocol = the tester's, mechanised: build N panels (each with a matrix, i.e. many per-widget
# surfaces), drop them all, rebuild empty, and sample RSS at the same point in each cycle. The
# verdict is ORDINAL and needs no absolute numbers: if the after-drop floor CLIMBS from cycle to
# cycle, backends are not being released.
#
# Run: source setup.sh
#      crystal build --release spec/autotest/backend_leak_rss_autotest.cr -o /tmp/backend_leak_rss
#      DISPLAY=:0 timeout 240 /tmp/backend_leak_rss ; cat /tmp/backend_leak_rss.log

PAGE_SIZE = 4096_i64

# Deterministic companion to RSS: how many native RenderTextures were CREATED. RSS alone is
# allocator/driver-noisy; this is exact. Once dispose really destroys, add the destroy counter
# and the two must converge.
class SF::RenderTexture
  @@probe_created = 0

  @@probe_destroyed = 0

  def self.probe_created
    @@probe_created
  end

  def self.probe_destroyed
    @@probe_destroyed
  end

  # Survivor attribution: every live texture remembers WHERE it was created, so the ones that are
  # never destroyed can be blamed on an exact call site instead of guessed at.
  @@probe_sites = {} of UInt64 => String

  def self.probe_sites
    @@probe_sites
  end

  def destroy! : Nil
    unless destroyed?
      @@probe_destroyed += 1
      @@probe_sites.delete(object_id)
    end
    previous_def
  end

  def initialize(width : Int, height : Int, settings : SF::ContextSettings? = nil)
    previous_def
    @@probe_created += 1
    frames = caller.reject { |f|
      f.includes?("csfml3/") || f.includes?("crsfml_backend.cr") || f.includes?("backend_leak_rss_autotest.cr")
    }.first(5)
    @@probe_sites[object_id] = frames.map { |f| f.split(" in ").first.sub(/.*crymbleui\//, "") }.join("  <-  ")
  end
end

def rss_mb : Float64
  # /proc/self/statm field 2 (index 1) is the resident set in PAGES.
  fields = File.read("/proc/self/statm").split
  (fields[1].to_i64 * PAGE_SIZE) / 1_048_576.0
end

class LeakCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@tint : UInt8)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 90.0
    h = constraints.max_height.finite? ? constraints.max_height : 22.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
        CrymbleUI::Color.new(40, @tint, 140, 255))
    end
  end
end

class LeakAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@tint : UInt8)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    LeakCell.new(@tint)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...40).to_a, (0...6).to_a}
  end
end

class LeakApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property panels = 0

  def build : CrymbleUI::Widget
    n = @panels
    window("Backend leak RSS witness", 1400, 900) do
      vstack do
        n.times do |i|
          window_panel("Panel #{i}", x: 20.0 + i * 12.0, y: 20.0 + i * 9.0,
            width: 620.0, height: 420.0, id: "p#{i}") do
            widget(CrymbleUI::VirtualMatrix.new(LeakAdapter.new((60 + i * 10).to_u8), id: "m#{i}"))
          end
        end
      end
    end
  end
end

LOG = "/tmp/backend_leak_rss.log"
File.write(LOG, "")

def log(msg : String)
  File.open(LOG, "a") { |f| f.puts msg }
  puts msg
end

class Driver
  PANELS = 16

  @step = 0
  @floors = [] of Float64
  @peaks = [] of Float64
  @pending_peak = false
  @baseline = 0.0
  @survivors = [] of Int32
  getter? failed = false

  def initialize(@app : LeakApp)
  end

  # One action per scheduler tick, so every state change is separated by rendered frames.
  # build -> drop -> SAMPLE, three times; the sample always lands after the empty rebuild
  # has actually rendered.
  def step : Bool
    case @step
    when 0
      @baseline = rss_mb
      log("baseline            : %8.1f MB  (textures created so far: %d)" % [@baseline, SF::RenderTexture.probe_created])
    when 1, 4, 7, 10, 13
      @app.panels = PANELS
      @app.request_rebuild
      @pending_peak = true
    when 2, 5, 8, 11, 14
      if @pending_peak
        p = rss_mb
        @peaks << p
        log("   peak (%2d panels) : %8.1f MB" % [PANELS, p])
        @pending_peak = false
      end
      @app.panels = 0
      @app.request_rebuild
    when 3, 6, 9, 12, 15
      f = rss_mb
      @floors << f
      @survivors << (SF::RenderTexture.probe_created - SF::RenderTexture.probe_destroyed)
      prev = @floors.size == 1 ? @baseline : @floors[-2]
      log("after cycle %d drop  : %8.1f MB   (delta %+7.1f)  textures created %d / destroyed %d" % [@floors.size, f, f - prev, SF::RenderTexture.probe_created, SF::RenderTexture.probe_destroyed])
    else
      log("")
      log("peaks  = #{@peaks.map(&.round(1))}")
      log("floors = #{@floors.map(&.round(1))}")
      if @peaks.size > 0 && @floors.size > 0
        log("RETURNED after drop, cycle 1: %.1f MB of the %.1f MB the panels cost" % [
          @peaks[0] - @floors[0], @peaks[0] - @baseline])
      end
      log("")
      log("SURVIVING textures by creation site (created #{SF::RenderTexture.probe_created}, destroyed #{SF::RenderTexture.probe_destroyed}):")
      tally = Hash(String, Int32).new(0)
      SF::RenderTexture.probe_sites.each_value { |s| tally[s] += 1 }
      tally.to_a.sort_by { |(_, n)| -n }.first(6).each do |(s, n)|
        log("  %5d survivors:" % n)
        s.split("  <-  ").each { |f| log("            #{f}") }
      end
      climb = @floors.size >= 2 ? (@floors[-1] - @floors[0]) : 0.0
      log("CLIMB across cycles = %+.1f MB" % climb)

      # VERDICT on the deterministic counter, not on RSS. RSS is driver-dependent: on some drivers
      # texture memory is not resident in the process at all, so a real leak of hundreds of
      # textures can show as a nearly flat RSS. Created-minus-destroyed is exact everywhere.
      #
      # Threshold-free and ordinal: the survivor count must not GROW from cycle to cycle. A steady
      # survivor count is correct — the live window legitimately holds its own layer surface — while
      # a count that climbs every cycle is precisely the defect, whatever its absolute value.
      log("survivors after each cycle = #{@survivors}")
      growth = @survivors.size >= 2 ? (@survivors[-1] - @survivors[0]) : 0
      if growth > 0
        log("VERDICT: FAIL — #{growth} more textures stranded after cycle #{@survivors.size} than " \
            "after cycle 1 (#{(growth / (@survivors.size - 1)).round} per open/close cycle). Every " \
            "one is driver memory the collector cannot reclaim.")
        @failed = true
      else
        log("VERDICT: PASS — the stranded-texture count does not grow across cycles " \
            "(#{SF::RenderTexture.probe_created} created, #{SF::RenderTexture.probe_destroyed} destroyed).")
      end
      return false
    end
    @step += 1
    true
  end
end

app = LeakApp.new
app.build_tree
root = app.root
raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)
window_widget = root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(
  width: window_widget.width,
  height: window_widget.height,
  title: window_widget.title
)

driver = Driver.new(app)
scheduled = false
app_ref = app

# Drive the protocol from the scheduler so every step lands between rendered frames.
CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 600_000_000)) do
  tick = uninitialized Proc(Nil)
  tick = -> do
    if driver.step
      CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 400_000_000)) { tick.call }
    else
      exit(driver.failed? ? 1 : 0)
    end
    nil
  end
  tick.call
end

renderer.run(app)
