require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# HARNESS FIX (harness-gap-is-a-bug): the SFML loop's "render this frame?" decision — the
# version-keyed PULL trigger — was welded inside the windowed run-loop, and TestRenderer.render_frame
# ALWAYS renders, so NO spec could ever exercise the trigger. This was the
# blocker for proving render-trigger completeness (and for ever deleting the dirty-walk backstop).
#
# This spec drives interactions through the REAL App event path (App.handle_*) and asserts the loop
# would render IFF the pull trigger moved — via a shared, headless seam (RenderTrigger) consulted by
# BOTH the SFML loop and TestRenderer#render_frame_if_needed. It is the facility every later
# completeness test (drag, resize, reflow, eviction) builds on.

private class RTMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    60
  end

  def col_count : Int32
    4
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

describe "RenderTrigger (the pull trigger as a spec-testable seam)" do
  it "renders IFF the pull trigger moved, driven through App.handle_*" do
    matrix = CrymbleUI::VirtualMatrix.new(RTMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app) # reach steady state AND baseline the trigger

    # IDLE: nothing changed → the pull trigger must NOT request a render.
    # (This is the exact case the old harness could never assert — render_frame always rendered.)
    renderer.render_frame_if_needed(app).should be_false

    # SCROLL through the real event path → the trigger must request a render.
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), CrymbleUI::Vec2.new(165.0, 100.0))
    renderer.render_frame_if_needed(app).should be_true

    # After draining the scroll to steady state, idle again → no render.
    renderer.settle_rendering(app)
    renderer.render_frame_if_needed(app).should be_false

    # THEME swap (a global input that issues no per-widget mark) → render.
    begin
      CrymbleUI::Theme.set(:dark)
      renderer.render_frame_if_needed(app).should be_true
    ensure
      CrymbleUI::Theme.set(:light)
    end
  end
end
