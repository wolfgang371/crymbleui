require "../../src/crymble-ui"

# SFML autotest for the timer-driven-rebuild loop fix (the headless model is
# spec/rendering/render_trigger_timer_rebuild_spec.cr; this exercises the REAL main loop, which no headless
# spec can). A repeating timer flips app `state` every 500ms with NO input. The counter must advance on its
# own. Before the loop fix a timer-driven request_rebuild was dropped when idle (rebuilds were applied only
# on the event path) → the counter froze until you moved the mouse, then jumped. After the fix it advances
# steadily while idle.
#
# Self-verifying: after 1.6 s without input it checks that every value the timer counted to (1, 2, 3) was
# PAINTED - each frame notes the counter text the rebuilt tree shows - prints a VERDICT and exits 0/1. Frames
# from X11's own startup events cannot satisfy it: they paint "ticks = 0". Keep the pointer off the window.
#
# Run:  source setup.sh && crystal build spec/autotest/timer_rebuild_autotest.cr -o /tmp/timer_rebuild_autotest
#       DISPLAY=:0 timeout 20 /tmp/timer_rebuild_autotest      (exit 0: the counter advanced on its own)
class TimerRebuildAutotest < CrymbleUI::App
  state ticks : Int32 = 0
  getter painted = Set(String).new
  getter verdict : Bool? = nil

  def on_start
    every(500.milliseconds) { self.ticks += 1 }
    after(1600.milliseconds) do
      # Three rebuilds were requested by now; each has to have reached the screen without any input.
      @verdict = (1..3).all? { |n| @painted.includes?("ticks = #{n}") }
      puts "ticks=#{@ticks} painted=#{@painted.to_a.sort}"
      quit
    end
  end

  def finish_frame : Bool
    find("counter").try { |w| @painted << w.as(CrymbleUI::Text).text }
    super
  end

  def build : CrymbleUI::Widget
    window("Timer Rebuild Autotest", 640, 260) do
      vstack(spacing: 10.0) do
        text("Idle timer-driven rebuild test", font_scale: 3, color: CrymbleUI::Color.new(0, 100, 180, 255))
        text("This counter must advance with NO mouse/keyboard input:", font_scale: -1)
        text("ticks = #{@ticks}", id: "counter", font_scale: 6, color: CrymbleUI::Color.new(0, 120, 215, 255))
        text("(before the loop fix it froze until you moved the mouse, then jumped)", font_scale: -2)
      end
    end
  end
end

app = TimerRebuildAutotest.new
CrymbleUI.run(app)
ok = app.verdict == true
puts ok ? "VERDICT: PASS - the timer-driven rebuilds were painted without input" : "VERDICT: FAIL - the counter froze (or the check never ran)"
exit ok ? 0 : 1
