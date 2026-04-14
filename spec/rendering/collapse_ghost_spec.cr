require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/layer_box"

# Regression test: when a widget's ancestor has zero bounds (e.g. TreeNode collapsed),
# its layer must NOT be composited to the window. Previously, stale textures from
# before collapse were still blitted, creating "ghost" content.

describe "Collapse Ghost - layer compositing skips zero-bounds ancestors" do
  it "does not composite layers whose owner has a zero-bounds ancestor" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Container that will be "collapsed" by zeroing its bounds
    container = TestWidget.new(id: "container", measured_size: CrymbleUI::Size.new(400.0, 300.0))

    # LayerBox inside container — has its own layer
    layer_box = CrymbleUI::LayerBox.new(0.0, 0.0, 200.0, 100.0, id: "ghost_layer")
    button = CrymbleUI::Button.new("Ghost")
    layer_box.add_child(button)
    container.add_child(layer_box)

    window.add_child(container)
    app.root_widget = window

    # Settle rendering — all layers composited
    renderer.settle_rendering(app)
    renderer.reset_counters

    # Render one normal frame — count blits
    renderer.render_frame(app)
    blits_before = renderer.backend_blit_count
    blits_before.should be > 0 # At minimum window layer + layer_box layer

    # Collapse container: zero its bounds (simulates TreeNode collapse)
    container.bounds = CrymbleUI::Rect.new(container.bounds.x, container.bounds.y, 0.0, 0.0)
    # Also zero the layer_box bounds to match what layout would do
    layer_box.bounds = CrymbleUI::Rect.new(layer_box.bounds.x, layer_box.bounds.y, 0.0, 0.0)
    layer_box.mark_needs_render

    renderer.reset_counters
    renderer.render_frame(app)
    blits_after = renderer.backend_blit_count

    # After collapse, the layer_box's layer should NOT be composited
    # So we should have fewer blits than before
    blits_after.should be < blits_before
  end
end
