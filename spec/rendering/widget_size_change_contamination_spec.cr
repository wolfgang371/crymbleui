require "../spec_helper"
require "../../src/testing/test_renderer"

# Widget that only fills TOP HALF of its bounds - bottom half shows background
class PartialBox < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  render_property color : CrymbleUI::Color
  layout_property fixed_width : Float64
  layout_property fixed_height : Float64

  def initialize(@color : CrymbleUI::Color, @fixed_width : Float64, @fixed_height : Float64, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@fixed_width, @fixed_height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    @state = CrymbleUI::WidgetState::Clean
    mark_needs_render
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    half = (bounds.height / 2).to_i.to_f64
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, half), @color) }
  end
end

# App that rebuilds with different box height (triggers reconcile path)
class GrowingBoxApp < CrymbleUI::App
  property box_height : Float64 = 20.0

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 400, 300)
    panel = CrymbleUI::WindowPanel.new("Panel", 70.0, 70.0, 150.0, 100.0, id: "panel")
    panel.add_child(PartialBox.new(CrymbleUI::Color.new(0_u8, 0_u8, 255_u8, 255_u8), 80.0, @box_height, id: "box"))
    window.add_child(panel)
    window
  end
end

# Bug: When widget size changes via rebuild, reconcile copies old background_backend
# (wrong size) to new widget. Blitting smaller background to larger widget_backend
# leaves uninitialized rows → transparent pixels.
describe "Reconcile size mismatch" do
  it "should not leave transparent pixels when widget grows via rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = GrowingBoxApp.new

    # Initial render with 20px box
    app.build_tree
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    # Rebuild with 22px box (reconcile copies 20px background to 22px widget)
    app.box_height = 22.0
    app.rebuild
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    # Check layer pixel in grown area (row 20 of 22px widget)
    panel = app.root.not_nil!.find_by_id("panel").as(CrymbleUI::WindowPanel)
    layer_backend = panel.layer.not_nil!.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Box at layer-local (8, 38), grown area at widget row 20 → layer y = 38 + 20 = 58
    pixel = layer_backend.get_pixel(18, 58)
    pixel.should_not be_nil
    pixel.not_nil!.a.should eq(255), "Layer has transparent pixel at (18, 58) - reconcile size mismatch bug!"
  end
end
