require "../spec_helper"
require "../../src/testing/test_renderer"

# Render-trigger completeness: PANEL DRAG — GREEN regression guard for Layer#position_rev.
#
# A panel drag moves the layer at the COMPOSITOR level while window_panel.cr deliberately skips
# mark_needs_render during drag ("O(1) drag, zero re-renders"). Before the fix the version-keyed pull
# trigger was BLIND to it (it repainted only via the SFML event-loop push). Now window_panel bumps
# Layer#position_rev at the drag mutation site and frame_aggregate_rev folds position_rev in, so a real
# drag moves the aggregate → render_frame_if_needed fires (a re-composite, still no widget re-render).
#
# This guards that coupling: driven through the real App event path (handle_mouse_down +
# handle_mouse_move), the pull decision must request a render for a drag. (Was committed RED at 5afb346;
# made GREEN by position_rev at 46c7de1.)
describe "Render-trigger completeness: panel drag" do
  it "a panel drag moves the pull trigger" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("X") { }
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    # Grab the title bar, then settle any down-effects (raise / focus) so the MOVE is isolated and
    # the trigger is baselined to the post-grab state.
    app.handle_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
    renderer.settle_rendering(app)

    x_before = panel.bounds.x

    # The drag MOVE — the gesture that must repaint.
    app.handle_mouse_move(CrymbleUI::Vec2.new(350.0, 115.0))

    # It is a real drag: the panel actually moved (guards against a no-op test).
    panel.bounds.x.should_not eq x_before

    # The pull trigger must request a render. RED today: the layer moved at the compositor level but
    # bumped no rev, so frame_aggregate_rev is unchanged → render_frame_if_needed is false.
    renderer.render_frame_if_needed(app).should be_true
  end
end
