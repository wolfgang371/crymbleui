require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Regression: a cursor-flash TOGGLE must wake the render loop.
#
# The render trigger is purely version-keyed (the dirty-walk backstop was removed), so a change
# repaints only if it moves frame_aggregate_rev. The flash is TIMER-driven — there is no input event
# to force a redraw — so its dirty-mark MUST move the aggregate. When it only did mark_needs_render
# (which moves no rev), the flash never woke the loop and the cursor repainted only when some other
# timer moved the aggregate, aliasing the 400ms blink into irregular on/off durations. The fix is
# mark_cursor_overlay_dirty -> mark_needs_clear_and_render (bumps clear_rev, which the aggregate sums).
class CursorFlashRenderApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      widget(CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "flash_grid"))
    end
  end
end

describe "VirtualMatrix cursor-flash render trigger" do
  it "a flash toggle wakes the render loop (moves the version-keyed pull trigger)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = CursorFlashRenderApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("flash_grid").as(CrymbleUI::VirtualMatrix)
    matrix.set_cursor_from_cell({1, 2}) # activate the cursor overlay + start the flash timer
    renderer.settle_rendering(app)       # drain that move and re-baseline the trigger

    # Guard against a vacuous test: the overlay layer must actually exist, else the mark below no-ops.
    matrix.@cursor_overlay_layer.should_not be_nil

    # IDLE baseline: nothing changed, the flash timer is only PENDING → the loop must not render.
    renderer.render_frame_if_needed(app).should be_false

    # Fire the repeating cursor-flash timer (a 400ms toggle) by advancing well past its wake — this
    # runs the toggle callback, the exact idle path the user hits. It MUST move the pull trigger.
    CrymbleUI::Widget.scheduler.run_expired_timers(Time.instant + 1.second)
    renderer.render_frame_if_needed(app).should be_true
  end

  # The fix point in isolation, with the clearest failure message.
  it "mark_cursor_overlay_dirty moves the render aggregate" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = CursorFlashRenderApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("flash_grid").as(CrymbleUI::VirtualMatrix)
    renderer.render_frame_if_needed(app).should be_false # idle baseline

    matrix.mark_cursor_overlay_dirty
    renderer.render_frame_if_needed(app).should be_true
  end
end
