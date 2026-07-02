require "../../src/crymble-ui"

# SFML autotest for the timer-driven-rebuild loop fix (the headless model is
# spec/rendering/render_trigger_timer_rebuild_spec.cr; this exercises the REAL main loop, which no headless
# spec can). A repeating timer flips app `state` every 500ms with NO input. The counter must advance on its
# own. Before the loop fix a timer-driven request_rebuild was dropped when idle (rebuilds were applied only
# on the event path) → the counter froze until you moved the mouse, then jumped. After the fix it advances
# steadily while idle.
#
# Run:  source setup.sh && crystal build --release spec/autotest/timer_rebuild_autotest.cr -o /tmp/timer_rebuild_autotest
#       DISPLAY=:0 /tmp/timer_rebuild_autotest
# Watch 'ticks' WITHOUT touching the mouse — it should climb ~2/sec. Move the pointer off the window
# entirely; it must keep climbing.
class TimerRebuildAutotest < CrymbleUI::App
  state ticks : Int32 = 0
  @clock : Int32? = nil

  def build : CrymbleUI::Widget
    ensure_clock
    window("Timer Rebuild Autotest", 640, 260) do
      vstack(spacing: 10.0) do
        text("Idle timer-driven rebuild test", font_scale: 3, color: CrymbleUI::Color.new(0, 100, 180, 255))
        text("This counter must advance with NO mouse/keyboard input:", font_scale: -1)
        text("ticks = #{@ticks}", font_scale: 6, color: CrymbleUI::Color.new(0, 120, 215, 255))
        text("(before the loop fix it froze until you moved the mouse, then jumped)", font_scale: -2)
      end
    end
  end

  # Start the one repeating clock as soon as the scheduler exists (it does by the loop's rebuild of the
  # tree). @clock guards against re-scheduling on every rebuild.
  private def ensure_clock
    return if @clock
    return unless scheduler_ready?
    @clock = CrymbleUI::Widget.scheduler.schedule(500.milliseconds, repeating: true) do
      self.ticks += 1
    end
  end

  private def scheduler_ready? : Bool
    CrymbleUI::Widget.scheduler
    true
  rescue
    false
  end
end

puts "Timer-rebuild autotest: watch 'ticks' advance WITHOUT any input (it froze before the loop fix)."
CrymbleUI.run(TimerRebuildAutotest.new)
