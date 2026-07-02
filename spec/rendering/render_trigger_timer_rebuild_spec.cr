require "../spec_helper"
require "../../src/testing/test_renderer"

# Render-trigger completeness — the REBUILD signal (structural / timer-driven app-state change).
#
# render_trigger_completeness_spec covers the aggregate-pull axes (resize/text/scroll/theme). This file
# covers the OTHER render signal: App#needs_rebuild?. A repeating timer that changes app `state` (a live
# clock, polled data, an animation) requests a rebuild OFF the input path. The frame decision must honor
# it — the SFML main loop used to apply needs_rebuild? only `if event_count > 0`, so an idle timer-driven
# rebuild was silently dropped and deferred to the next input event (the "frozen until you move the mouse,
# then a rebuild on every move" class). render_frame_if_needed is the headless model of that decision.

private class TimerRebuildApp < CrymbleUI::App
  state tick : Int32 = 0

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("T", 400, 300)
    window.add_child(CrymbleUI::Text.new("tick #{@tick}"))
    window
  end
end

describe "Render-trigger completeness: timer-driven app-state rebuild" do
  it "a pending app-state rebuild (off the input path) requests a render — not silently dropped" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TimerRebuildApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # What a repeating timer callback does: change app state with no input event and no other dirtiness.
    app.tick = app.tick + 1
    app.needs_rebuild?.should be_true # precondition: the state change requested a rebuild

    # The frame decision MUST honor a pending rebuild even with no aggregate/layer change and no input.
    renderer.render_frame_if_needed(app).should be_true
  end
end
