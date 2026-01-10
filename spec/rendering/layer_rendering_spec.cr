require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for layer-based rendering pipeline (Phase 2)
# These tests verify that layers are rendered correctly to their textures
# and composited to the window in the correct order.

describe "Layer Rendering (Phase 2)" do
  describe "Phase 2.1: Single Layer Backend Management" do
    it "layer starts with no backend" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)
      layer.backend.should be_nil
    end

    it "calculates backend size with buffer (20% + 50px)" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)

      width, height = layer.calculate_backend_size(200.0, 150.0)

      # Expected: 200 + max(200*0.2, 50) = 200 + 50 = 250
      #           150 + max(150*0.2, 50) = 150 + 50 = 200
      width.should eq(250)
      height.should eq(200)
    end

    it "backend_needs_resize returns true when no backend exists" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)
      layer.backend_needs_resize?(200.0, 150.0).should be_true
    end

    it "backend_needs_resize returns false when size within buffer" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)

      # Create backend through renderer
      renderer = CrymbleUI::Testing::TestRenderer.new
      app = TestApp.new
      renderer.ensure_layer_backend(layer, 250, 200)

      # Size 220×160 is within buffer of 250×200
      layer.backend_needs_resize?(220.0, 160.0).should be_false
    end

    it "backend_needs_resize returns true when size exceeds buffer" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)

      # Create backend through renderer
      renderer = CrymbleUI::Testing::TestRenderer.new
      app = TestApp.new
      renderer.ensure_layer_backend(layer, 250, 200)

      # Size 400×300 exceeds buffer of 250×200
      layer.backend_needs_resize?(400.0, 300.0).should be_true
    end
  end

  describe "Phase 2.2: Multi-Layer Compositing" do
    it "Window.collect_all_layers returns layers sorted by z_index" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 5)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      menubar = CrymbleUI::MenuBar.new

      window.add_child(menubar)
      app.root_widget = window
      window.add_child(panel1)
      app.root_widget = window
      window.add_child(panel2)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      layers = window.collect_all_layers

      # Should be sorted: root(0) < panel2(2) < panel1(5) < menubar(1000)
      layers.size.should eq(4)
      layers[0].z_index.should eq(0)     # root
      layers[1].z_index.should eq(2)     # panel2
      layers[2].z_index.should eq(5)     # panel1
      layers[3].z_index.should eq(1000)  # menubar
    end

    it "layers have correct bounds for compositing" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)

      window.add_child(panel1)
      app.root_widget = window

      # Trigger layout via App
      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      layers = window.collect_all_layers

      # Root layer should cover full window
      root_layer = layers.find { |l| l.z_index == 0 }.not_nil!
      root_layer.bounds.width.should eq(800.0)
      root_layer.bounds.height.should eq(600.0)

      # Panel layer should be at panel position (no border expansion)
      panel_layer = layers.find { |l| l.z_index == 1 }.not_nil!
      panel_layer.bounds.x.should eq(100.0)
      panel_layer.bounds.y.should eq(100.0)
    end
  end

  describe "Phase 2.3: Selective Layer Rendering" do
    it "layer reports needs_render when state is NeedsRender" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero, z_index: 0)

      layer.state = CrymbleUI::WidgetState::NeedsRender
      layer.needs_render?.should be_true

      layer.state = CrymbleUI::WidgetState::Clean
      layer.clear_render_state  # Simulate that first render already happened
      layer.needs_render?.should be_false
    end

    it "mark_needs_render propagates to parent layer" do
      app = TestApp.new
      parent = CrymbleUI::Layer.new("parent", CrymbleUI::Rect.zero, z_index: 0)
      child = CrymbleUI::Layer.new("child", CrymbleUI::Rect.zero, z_index: 1)

      child.parent = parent
      parent.state = CrymbleUI::WidgetState::Clean
      child.state = CrymbleUI::WidgetState::Clean

      child.mark_needs_full_render

      child.needs_render?.should be_true
      parent.needs_render?.should be_true
    end

    it "clear_render_state marks layer as clean" do
      app = TestApp.new
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero, z_index: 0)

      layer.state = CrymbleUI::WidgetState::NeedsRender
      layer.clear_render_state

      layer.state.should eq(CrymbleUI::WidgetState::Clean)
      layer.needs_render?.should be_false
    end
  end
end
