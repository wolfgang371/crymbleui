require "../spec_helper"
require "../../src/testing/test_renderer"

# Render-trigger completeness battery.
#
# Each interaction the version-keyed PULL aggregate must OWN (so the dirty-walk backstop
# `|| Layer.any_needs_render?` can eventually be deleted) is driven through the REAL App event path
# (App.handle_*) and asserted to fire `render_frame_if_needed`. Conversely an idle no-op must NOT fire.
# Built on the RenderTrigger seam. Scroll / theme / idle are covered in render_trigger_spec; panel drag
# (the position axis) in render_trigger_drag_spec. This file adds the remaining aggregate-owned axes.
#
# (Structural add/remove is driven by App#needs_rebuild?, a separate render signal, not the aggregate —
# so it is intentionally NOT part of this aggregate-completeness battery.)

describe "Render-trigger completeness: panel resize (layout axis)" do
  it "a panel resize moves the pull trigger" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("X") { }
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    # Grab the RIGHT resize edge — within RESIZE_HANDLE_SIZE (8px) of x=300, mid-height so it's a pure
    # Right edge (not a corner). Then settle the down-effects so the MOVE is isolated and baselined.
    app.handle_mouse_down(CrymbleUI::Vec2.new(295.0, 175.0))
    renderer.settle_rendering(app)

    w_before = panel.width

    # Drag the edge outward — widens the panel.
    app.handle_mouse_move(CrymbleUI::Vec2.new(350.0, 175.0))

    # It is a real resize: the panel actually grew (guards against a no-op test).
    panel.width.should be > w_before

    # The pull trigger must request a render: a resize bumps the chrome's content_rev (and layout),
    # which frame_aggregate_rev folds in. (Regression guard for the layout axis of completeness.)
    renderer.render_frame_if_needed(app).should be_true
  end
end

describe "Render-trigger completeness: text edit (content axis)" do
  it "typing into a focused text input moves the pull trigger" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 150.0)
    input = CrymbleUI::TextInput.new(value: "ab", mode: CrymbleUI::TextInputMode::FullEdit)
    panel.add_child(input)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    # Focus the input through the real App click path, then settle the focus/cursor effects + baseline.
    click_on(app, input)
    renderer.settle_rendering(app)

    v_before = input.value

    # Type a character through the FocusManager (the real text-entry path).
    type_text("c")

    # It is a real edit: the value changed (guards against a no-op test).
    input.value.should_not eq v_before

    # The pull trigger must request a render: a value edit bumps content_rev → aggregate moves.
    renderer.render_frame_if_needed(app).should be_true
  end
end
