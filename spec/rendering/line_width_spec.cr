require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for line width rendering
#
# BUG: DrawLine primitives have width property, but it's not passed through
# the rendering pipeline to backends. SFML backend hardcodes line_width = 1.0
#
# Root causes:
# 1. layer_renderer.cr:300 doesn't pass primitive.width to backend.draw_line
# 2. crsfml_backend.cr:53 draw_line signature doesn't accept width parameter
# 3. test_render_backend.cr draw_line signature doesn't accept width parameter
#
# Result: All checkmarks render as 1px wide instead of 3px

describe "Line Width Rendering" do
  it "draw_line accepts and uses width parameter" do
    backend = CrymbleUI::Testing::TestRenderBackend.new(100, 100)

    # Draw a line with width 3.0
    backend.draw_line(10.0, 10.0, 50.0, 10.0, CrymbleUI::Color.new(0, 0, 0, 255), 3.0)

    # Backend should have received the width parameter
    # (This will fail until we add width parameter to signature)
  end

  it "checkbox checkmark renders with dynamic thickness" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new

    checkbox = CrymbleUI::Checkbox.new("Test", checked: true) { }

    window = CrymbleUI::Window.new("Test", 200, 100)
    window.add_child(checkbox)
    app.root_widget = window

    renderer.render_frame(app)

    # Get checkbox primitives
    primitives = checkbox.get_primitives(checkbox.bounds)

    # Find DrawLine primitives (checkmark strokes)
    lines = primitives.select { |p| p.is_a?(CrymbleUI::DrawLine) }
    lines.size.should eq(2)  # Two strokes for checkmark

    # Both lines should have dynamic width based on box size
    expected_thickness = checkbox.checkmark_line_thickness
    lines.each do |line|
      line.as(CrymbleUI::DrawLine).width.should eq(expected_thickness)
    end
  end

  it "menu item checkmark renders with dynamic thickness" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new

    # Create a checked menu item
    menu_item = CrymbleUI::MenuItem.new("Test", checked: true) { }

    window = CrymbleUI::Window.new("Test", 200, 100)
    window.add_child(menu_item)
    app.root_widget = window

    renderer.render_frame(app)

    # Get menu item primitives
    primitives = menu_item.get_primitives(menu_item.bounds)

    # Find DrawLine primitives (checkmark strokes)
    lines = primitives.select { |p| p.is_a?(CrymbleUI::DrawLine) }
    lines.size.should eq(2)  # Two strokes for checkmark

    # Both lines should have dynamic width based on font size
    expected_thickness = menu_item.checkmark_line_thickness
    lines.each do |line|
      line.as(CrymbleUI::DrawLine).width.should eq(expected_thickness)
    end
  end
end
