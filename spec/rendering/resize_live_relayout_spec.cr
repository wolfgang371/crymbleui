require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/expanded"

# during an interactive panel resize the FULL content must be laid out each frame, so
# filling/stretched content tracks the panel LIVE instead of freezing at its old size and
# snapping on mouse-up. Confirmed in SFML (matrix.height 216 frozen during → 476 after release).
# This is a pure LAYOUT signal (renderer-independent), so it reproduces headlessly.

describe "live re-layout during panel resize" do
  it "a filling VirtualMatrix tracks the panel height DURING a resize, not frozen until mouse-up" do
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 800)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 900, 800)
    panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 300.0, 320.0)
    vstack = CrymbleUI::VStack.new(spacing: 6.0)
    vstack.add_child(CrymbleUI::Button.new("Header") { })
    exp = CrymbleUI::Expanded.new(flex: 1)
    matrix = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 5, id: "vm")
    exp.add_child(matrix)
    vstack.add_child(exp)
    panel.add_child(vstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    initial_h = matrix.absolute_bounds.height
    initial_rows = matrix.visible_cell_indices[:rows].size

    # Start + sustain a bottom-edge resize that grows the panel by 260px (resizing, NOT scrolling:
    # scroll_offset stays 0, so growing the viewport must surface MORE rows at the bottom). The
    # resize marks needs-layout; the layout is coalesced into render_frame's prepare_layout.
    panel.on_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width / 2, panel.y + panel.height - 3.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(panel.x + panel.width / 2, 50.0 + 320.0 - 3.0 + 260.0))
    renderer.render_frame(app)

    during_h = matrix.absolute_bounds.height
    during_rows = matrix.visible_cell_indices[:rows].size
    # The matrix must grow with the panel DURING the resize (live), not stay frozen at initial_h.
    during_h.should be > initial_h + 200.0
    # And it must actually SURFACE NEW ROWS — more visible cells, not merely a taller bounds with
    # the same content (the honest "new widgets show up" check).
    during_rows.should be > initial_rows
  end
end
