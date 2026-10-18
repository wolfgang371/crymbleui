# Tutorial 30: Fitted - a clock that follows the window
# ====================================================
# A clock whose digits grow and shrink with the window: `fitted { }` shows its one child scaled to
# the space it is given, and no widget inside knows about it. The text is rasterised at its final
# size (crisp at any size), and a click lands where it is drawn.
#
# Key concepts:
# - `fitted { text(now) }` - no font_scale: the box decides the size. The child is laid out at its
#   natural size and drawn scaled by the largest factor that fits, keeping its proportions; what
#   is left over (above and below a wide clock) shows what lies behind.
# - In a vstack or hstack, `expanded(fill_area: true) { fitted { } }` gives it all the remaining
#   space AND centres it there. A plain `expanded` fills only the stack's own axis: the fitted
#   then takes just the width its image needs, at the start of the row.
# - Keep the text's length constant (`%H:%M:%S`): a string that changes width changes the factor,
#   and the image would wobble every tick.
# - Nothing that owns a layer may be inside a fitted (scroll_view, window_panel, layer /
#   aligned_layer, popup): it raises, naming the widget and what to do. Dropdowns opened from
#   inside open at their natural size.
#
# Run with: shards build tutorial-30 && ./bin/tutorial-30
# Test with: crystal spec spec/tutorials/tutorial_30_spec.cr

require "../src/crymble-ui"

class ClockApp < CrymbleUI::App
  state now : String = ""

  # Where the time comes from - the spec hands in a clock it moves itself.
  def initialize(@clock : -> Time = -> { Time.local })
    super()
    @now = tick
  end

  def on_start
    every(1.second) { self.now = tick }
  end

  def build : CrymbleUI::Widget
    window("Tutorial 30: Fitted", 360, 160) do
      vstack(spacing: 4.0) do
        text("Resize the window - the clock follows it", id: "hint")
        expanded(fill_area: true) do
          fitted(id: "clock_box") do
            text(now, id: "clock")
          end
        end
      end
    end
  end

  private def tick : String
    @clock.call.to_s("%H:%M:%S")
  end
end

# The spec requires this file and drives the app headless, so it must not open a window.
{% unless @top_level.has_constant?("Spec") %}
  CrymbleUI.run(ClockApp.new)
{% end %}
