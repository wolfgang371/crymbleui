require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: Checkbox should grow with zoom
#
# BUG: Checkbox box size stays the same regardless of zoom level
# The implementation exists (effective_box_size uses FontSizing.calculate_size)
# but something is preventing it from working.
#
# Possible causes:
# 1. Layout not being invalidated on zoom change
# 2. Caching issue preventing re-measure
# 3. Something overriding the dynamic sizing

class CheckboxZoomTestApp < CrymbleUI::App
  property checkbox_text : String = "Test"
  property checkbox_checked : Bool = true
  property last_checkbox : CrymbleUI::Checkbox?

  def build : CrymbleUI::Widget
    checkbox = CrymbleUI::Checkbox.new(@checkbox_text, checked: @checkbox_checked) { }
    @last_checkbox = checkbox
    window = CrymbleUI::Window.new("Test", 400, 200)
    window.add_child(checkbox)
    window
  end
end

describe "Checkbox scaling with zoom" do
  it "effective_box_size increases with zoom" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 200)
    app = CheckboxZoomTestApp.new

    # Build and render at default zoom (100%)
    app.build_tree
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!
    size_at_100 = checkbox.effective_box_size

    # Zoom in 3 times to reach 150%
    3.times { CrymbleUI::FontSizing.zoom_in }
    CrymbleUI::FontSizing.zoom_factor.should be_close(1.5, 0.01)

    # Real app behavior: rebuild on zoom change
    app.rebuild
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!

    size_at_150 = checkbox.effective_box_size

    # Box size should be 1.5x larger
    size_at_150.should be > size_at_100
    (size_at_150 / size_at_100).should be_close(1.5, 0.1)
  end

  it "checkbox widget bounds grow with zoom" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 200)
    app = CheckboxZoomTestApp.new
    app.checkbox_text = "Test checkbox label"

    # Build and render at default zoom
    app.build_tree
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!
    width_at_100 = checkbox.bounds.width
    height_at_100 = checkbox.bounds.height

    # Zoom in 5 times to reach 200%
    5.times { CrymbleUI::FontSizing.zoom_in }
    CrymbleUI::FontSizing.zoom_factor.should be_close(2.0, 0.01)

    # Real app behavior: rebuild creates fresh widgets on zoom change
    app.rebuild
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!

    width_at_200 = checkbox.bounds.width
    height_at_200 = checkbox.bounds.height

    # Bounds should approximately double
    width_at_200.should be > width_at_100
    height_at_200.should be > height_at_100
    (width_at_200 / width_at_100).should be_close(2.0, 0.3)
    (height_at_200 / height_at_100).should be_close(2.0, 0.3)
  end

  it "checkbox checkmark renders larger at higher zoom" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 200)
    app = CheckboxZoomTestApp.new

    # Build and render at default zoom
    app.build_tree
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!

    # Get checkmark line primitives at 100%
    primitives_100 = checkbox.get_primitives(checkbox.bounds)
    lines_100 = primitives_100.select { |p| p.is_a?(CrymbleUI::DrawLine) }
    line_width_100 = lines_100.first.as(CrymbleUI::DrawLine).width

    # Zoom in 5 times to reach 200%
    5.times { CrymbleUI::FontSizing.zoom_in }

    # Real app behavior: rebuild creates fresh widgets on zoom change
    app.rebuild
    renderer.render_frame(app)
    checkbox = app.last_checkbox.not_nil!

    # Get checkmark line primitives at 200%
    primitives_200 = checkbox.get_primitives(checkbox.bounds)
    lines_200 = primitives_200.select { |p| p.is_a?(CrymbleUI::DrawLine) }
    line_width_200 = lines_200.first.as(CrymbleUI::DrawLine).width

    # Checkmark line thickness should approximately double
    line_width_200.should be > line_width_100
    (line_width_200 / line_width_100).should be_close(2.0, 0.3)
  end
end
