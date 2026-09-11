require "../spec_helper"
require "../../src/testing/test_renderer"

# The checkbox's box is drawn by PrimitiveBuilder#draw_check_glyph as four FILLED rects
# placed INSIDE the box bounds — deliberately, because SFML's centred outline_thickness
# put the outer half outside the widget and a scissor edge then ate it.
#
# Both probe values are DERIVED, not hardcoded: the row is the widget's vertical centre
# (box_y is `(height - box) / 2`, so the centre is inside the box for any metric), and the
# colour comes from the widget. The focus assertion is load-bearing — the widget actually
# draws `box_color.highlight(...)` when focus-highlighted, so without it a focus change
# would fail this as a colour mismatch that reads like "the border got clipped again",
# which is the misdiagnosis this spec exists to prevent.
describe "Checkbox border rendering" do
  it "draws the box's LEFT edge inside widget bounds, not clipped away" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # A vstack, to avoid the single-child special case.
    vstack = CrymbleUI::VStack.new
    checkbox = CrymbleUI::Checkbox.new("Test checkbox", checked: false)
    vstack.add_child(checkbox)
    window.add_child(vstack)
    app.root_widget = window

    renderer.render_frame(app)

    bounds = checkbox.absolute_bounds
    # box_x is 0 in widget-local coords, so the left edge column IS the widget's left edge.
    left_edge_x = bounds.x.to_i
    # box_y is vertically centred, so the widget's centre row is always inside the box.
    centre_y = (bounds.y + bounds.height / 2.0).to_i

    # The widget draws `actual_box_color`, which is box_color.highlight(...) when
    # focus-highlighted. Pin the precondition so a failure names its real cause.
    checkbox.focus_highlighted?.should be_false
    renderer.backend.get_pixel(left_edge_x, centre_y).should eq(checkbox.box_color)
  end
end
