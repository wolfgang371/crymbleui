require "../spec_helper"
require "../../src/testing/test_renderer"

# Test that checkbox borders are fully visible (not clipped)
# Issue: Checkbox box starts at widget-local x=0.0, and draw_rect with 1.0px stroke
# draws centered on edges, so left edge extends to x=-0.5 (clipped outside widget bounds)
describe "Checkbox Border Rendering" do
  it "renders complete border without left edge clipping" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # Create vstack with checkbox to avoid single-child special case
    vstack = CrymbleUI::VStack.new
    checkbox = CrymbleUI::Checkbox.new("Test checkbox", checked: false)
    vstack.add_child(checkbox)
    window.add_child(vstack)

    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Checkbox widget is at x=CONTENT_PADDING (8.0) in window
    # Checkbox box is at widget-local x=0.0
    # Border is drawn as 4 filled rectangles INSIDE widget bounds (not centered on edges)
    # Left edge is at widget-local x=0.0, which is absolute x=8.0
    # Border should be fully visible without clipping

    # Get checkbox absolute position
    checkbox_abs_x = checkbox.absolute_bounds.x.to_i  # Should be 8
    checkbox_abs_y = checkbox.absolute_bounds.y.to_i  # Should be 8

    window_backend = renderer.backend

    # Check pixel AT the left edge of checkbox widget bounds
    # With filled rectangles, border is drawn INSIDE bounds at x=0 (widget-local) = x=8 (absolute)
    pixel_at_left_edge = window_backend.get_pixel(checkbox_abs_x, checkbox_abs_y + 8)

    # Border color from checkbox.cr (box_color default)
    border_color = CrymbleUI::Color.new(100, 100, 100, 255)

    # Border should be visible at the widget boundary (no clipping)
    pixel_at_left_edge.should eq(border_color)
  end
end
