require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Companion to the cursor-flash render-trigger regression: does the TEXT-INPUT CARET blink have the
# same bug (a timer-driven toggle that moves no rev the purely-version-keyed render trigger sees)?
#
# It should NOT — the caret is built on `reactive_property cursor_visible`, toggled via `.set`, and
# read in to_primitives, so it auto-captures and bumps the node version (unlike the cursor overlay's
# plain property + direct-render). This test proves that: firing the caret blink timer wakes the loop.
class CaretBlinkApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 400, 200) do
      widget(CrymbleUI::TextInput.new(value: "hello", id: "ti")) # FullEdit default → caret blinks when focused
    end
  end
end

describe "TextInput caret blink render trigger" do
  it "a caret blink toggle wakes the render loop (reactive cursor_visible, not the overlay bug)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 200)
    app = CaretBlinkApp.new
    app.build_tree

    ti = app.find("ti").as(CrymbleUI::TextInput)
    ti.request_focus # on_focus → caret shown + blink timer running
    renderer.settle_rendering(app)

    ti.effectively_focused?.should be_true # precondition: to_primitives reads cursor_visible (else vacuous)

    # IDLE baseline: the blink timer is only PENDING → the loop must not render.
    renderer.render_frame_if_needed(app).should be_false

    # Fire the repeating caret blink (530ms toggle of the reactive cursor_visible). It must move the
    # pull trigger — if it didn't, the caret would have the same aliased-blink bug as the cursor overlay.
    CrymbleUI::Widget.scheduler.run_expired_timers(Time.instant + 1.second)
    renderer.render_frame_if_needed(app).should be_true
  end
end
