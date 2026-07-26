require "../spec_helper"
require "../../src/testing/test_renderer"

# Headless twin for the retired slow_resize_autotest.
#
# The shipped fix guarded by NOTHING today: WindowPanel::Content overrides
# can_skip_layout? to ALWAYS return false (window_panel.cr:570). Content is a
# "self-positioning" widget — its parent lays it out with Vec2.zero and Content
# computes its OWN padded origin (CONTENT_PADDING, title_bar_height + CONTENT_PADDING)
# in perform_layout. If the base skip path ran, an identical-constraint re-layout
# would take widget.cr's skip branch (`@bounds = Rect.new(position, @bounds.size)`)
# and, because position is Vec2.zero, collapse Content's bounds to (0,0) — overlapping
# the Chrome (the "slow resize stops mid-drag" symptom fixed originally).
#
# We arm the base skip by resizing PAST the min-size clamp so two consecutive resize
# frames produce an IDENTICAL panel size — identical tight constraints on Content,
# with Content staying clean while only the chrome re-renders. We then assert Content's
# BOUNDS DISPOSITION directly (its position keeps the padded origin, never (0,0)).
# We deliberately do NOT rely on the sibling-overlap invariant raise: that check is
# first_render-gated (documented gap at layer_renderer.cr:683-687).
describe "WindowPanel resize skip-path (Content self-positioning)" do
  it "keeps Content at its padded origin across two identical-size resize frames" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel well above the min floor, so a shrink can reach (and pin at) the clamp.
    panel = CrymbleUI::WindowPanel.new("Preview", 100.0, 100.0, 400.0, 300.0, id: "resize_panel")
    panel.add_child(CrymbleUI::Text.new("Body"))
    window.add_child(panel)
    app.root_widget = window

    # Initial layout + settle so Content's @last_constraints is seeded at the START size.
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    # Content is the panel's second internal child (Chrome first, Content second).
    content = panel.children.last
    expected_x = CrymbleUI::WindowPanel::CONTENT_PADDING
    expected_y = panel.title_bar_height + CrymbleUI::WindowPanel::CONTENT_PADDING

    # Sanity: initial disposition is the padded origin (not (0,0)).
    content.bounds.x.should eq(expected_x)
    content.bounds.y.should eq(expected_y)

    # Begin a resize drag from the bottom-right corner handle.
    resize_x = panel.x + panel.width - 5.0
    resize_y = panel.y + panel.height - 5.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
    renderer.render_frame(app)
    panel.resizing?.should be_true

    # MOVE 1: drag far past the top-left so BOTH axes clamp to the panel's minimum.
    # This is the FIRST time Content sees the pinned (min) constraints → full layout,
    # arming @last_constraints = tight(min_w, min_h) and leaving Content clean.
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x, panel.y))
    renderer.render_frame(app)
    width_after_move1 = panel.width
    height_after_move1 = panel.height

    # MOVE 2: drag even further top-left. The panel is already pinned at the clamp, so
    # this produces the SAME panel size → IDENTICAL tight constraints on Content. This is
    # the frame that would take the base can_skip_layout? skip path (RED: Content → (0,0)).
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x - 100.0, panel.y - 100.0))
    renderer.render_frame(app)

    # The two moves really did produce an identical panel size (arming precondition).
    panel.width.should eq(width_after_move1)
    panel.height.should eq(height_after_move1)

    # KEY DISPOSITION ASSERTION: Content still sits at its padded origin, never (0,0).
    content.bounds.position.should_not eq(CrymbleUI::Vec2.zero)
    content.bounds.x.should eq(expected_x)
    content.bounds.y.should eq(expected_y)

    app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x - 100.0, panel.y - 100.0))
  end
end
