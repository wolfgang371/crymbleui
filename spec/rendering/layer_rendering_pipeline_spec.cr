require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for layer rendering pipeline
# These tests verify the RENDERING path, not just data structures
# Goal: Find why content is white even though primitives exist

describe "Layer Rendering Pipeline" do
  describe "Layer backend creation and sizing" do
    it "creates layer backend with correct size for root layer" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Button") { }
      window.add_child(button)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!

      # Create backend through renderer
      renderer = CrymbleUI::Testing::TestRenderer.new
      app = TestApp.new
      width, height = root_layer.calculate_backend_size(root_layer.bounds.width, root_layer.bounds.height)
      renderer.ensure_layer_backend(root_layer, width, height)

      # Backend should exist
      root_layer.backend.should_not be_nil

      # Backend size should match calculated size (with buffer)
      backend = root_layer.backend.not_nil!
      backend.width.should eq(width)
      backend.height.should eq(height)

      # Should be at least as big as content
      backend.width.should be >= root_layer.bounds.width.to_i
      backend.height.should be >= root_layer.bounds.height.to_i
    end

    it "creates layer backend with correct size for panel layer" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Create backend through renderer
      renderer = CrymbleUI::Testing::TestRenderer.new
      app = TestApp.new
      width, height = panel_layer.calculate_backend_size(panel_layer.bounds.width, panel_layer.bounds.height)
      renderer.ensure_layer_backend(panel_layer, width, height)

      # Backend should exist
      panel_layer.backend.should_not be_nil

      # Backend size should accommodate panel bounds (expanded for border)
      backend = panel_layer.backend.not_nil!

      # Should be at least as big as layer bounds
      backend.width.should be >= panel_layer.bounds.width.to_i
      backend.height.should be >= panel_layer.bounds.height.to_i
    end

    it "backend_needs_resize detects when panel is resized" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Create initial backend
      renderer = CrymbleUI::Testing::TestRenderer.new
      app = TestApp.new
      width, height = panel_layer.calculate_backend_size(panel_layer.bounds.width, panel_layer.bounds.height)
      renderer.ensure_layer_backend(panel_layer, width, height)

      initial_backend_width = panel_layer.backend.not_nil!.width

      # Resize panel significantly (beyond buffer)
      right_edge = CrymbleUI::Vec2.new(299.0, 150.0)
      panel.on_mouse_down(right_edge)
      panel.on_mouse_move(CrymbleUI::Vec2.new(449.0, 150.0))  # +150px width

      # Update layer bounds
      border_width = 2.0
      new_bounds = CrymbleUI::Rect.new(
        panel.x - border_width,
        panel.y - border_width,
        panel.width + border_width * 2,
        panel.height + border_width * 2
      )
      panel_layer.bounds = new_bounds

      # Backend should need resize (new size exceeds buffer)
      panel_layer.backend_needs_resize?(panel_layer.bounds.width, panel_layer.bounds.height).should be_true

      # Create new backend with new size
      new_width, new_height = panel_layer.calculate_backend_size(panel_layer.bounds.width, panel_layer.bounds.height)
      renderer.ensure_layer_backend(panel_layer, new_width, new_height)

      # Backend should be bigger now
      new_backend_width = panel_layer.backend.not_nil!.width
      new_backend_width.should be > initial_backend_width
    end
  end

  describe "Widget-to-layer assignment during layout" do
    it "assigns content widgets to root layer during window layout" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      button1 = CrymbleUI::Button.new("B1") { }
      button2 = CrymbleUI::Button.new("B2") { }
      text = CrymbleUI::Text.new("Text")

      window.add_child(button1)
      app.root_widget = window
      window.add_child(button2)
      app.root_widget = window
      window.add_child(text)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!

      # All content widgets should be in root layer
      root_layer.widgets.should contain(button1)
      root_layer.widgets.should contain(button2)
      root_layer.widgets.should contain(text)
      root_layer.widgets.size.should eq(3)
    end

    it "assigns panel chrome and content to panel layer during layout (NEW architecture)" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }
      text = CrymbleUI::Text.new("Text")

      panel.add_child(button)
      panel.add_child(text)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Panel layer should have Chrome + Content (NEW architecture)
      panel_layer.widgets.size.should eq(2)
      panel_layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      panel_layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)
      # Button and text are nested under Content (panel.add_child redirects to Content.add_child)
      content = panel_layer.widgets[1].as(CrymbleUI::WindowPanel::Content)
      content.children.should contain(button)
      content.children.should contain(text)
    end

    it "does NOT assign panels to root layer (they have own layers)" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }

      window.add_child(button)  # Content
      app.root_widget = window
      window.add_child(panel)   # Panel
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!

      # Root layer should only have button, NOT panel
      root_layer.widgets.size.should eq(1)
      root_layer.widgets.should contain(button)
      root_layer.widgets.should_not contain(panel)
    end

    it "clears and repopulates layer widgets on re-layout (no accumulation)" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Button") { }
      window.add_child(button)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      # First layout
      root_layer = window.root_layer.not_nil!
      first_size = root_layer.widgets.size

      # Second layout (simulate rebuild)

      # Should have same number of widgets, not doubled
      root_layer.widgets.size.should eq(first_size)
      root_layer.widgets.size.should eq(1)
    end
  end

  describe "Layer collection for rendering" do
    it "collects root layer from window" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Button") { }
      window.add_child(button)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      layers = window.collect_all_layers

      # Should include root layer
      layers.size.should be >= 1
      layers.should contain(window.root_layer.not_nil!)
    end

    it "collects panel layers from window" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0)

      window.add_child(panel1)
      app.root_widget = window
      window.add_child(panel2)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      layers = window.collect_all_layers

      # Should include root + 2 panel layers = 3 layers
      layers.size.should eq(3)
      layers.should contain(window.root_layer.not_nil!)
      layers.should contain(panel1.layer.not_nil!)
      layers.should contain(panel2.layer.not_nil!)
    end

    it "sorts layers by z-index for rendering order" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 10)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 5)
      panel3 = CrymbleUI::WindowPanel.new("P3", 600.0, 100.0, 200.0, 150.0, z_index: 15)

      window.add_child(panel1)
      app.root_widget = window
      window.add_child(panel2)
      app.root_widget = window
      window.add_child(panel3)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(900.0, 600.0))

      layers = window.collect_all_layers

      # Layers should be sorted by z-index (ascending)
      # root(0) < panel2(5) < panel1(10) < panel3(15)
      layers.size.should eq(4)
      layers[0].z_index.should be < layers[1].z_index
      layers[1].z_index.should be < layers[2].z_index
      layers[2].z_index.should be < layers[3].z_index

      # Specific order
      layers[0].should eq(window.root_layer.not_nil!)  # z=0
      layers[1].should eq(panel2.layer.not_nil!)        # z=5
      layers[2].should eq(panel1.layer.not_nil!)        # z=10
      layers[3].should eq(panel3.layer.not_nil!)        # z=15
    end
  end

  describe "Layer render state after layout" do
    it "marks layers as needing render after initial layout" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }

      panel.add_child(button)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!
      panel_layer = panel.layer.not_nil!

      # Layers start with NeedsLayout state, should need rendering
      root_layer.needs_render?.should be_true
      panel_layer.needs_render?.should be_true
    end

    it "marks layers as needing render when content changes" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Button") { }
      window.add_child(button)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!
      root_layer.clear_render_state

      # Change button appearance
      button.background_color = CrymbleUI::Color.new(255, 0, 0, 255)

      # Root layer should be marked as needing render
      root_layer.needs_render?.should be_true
    end

    it "does NOT mark unrelated layers when content changes" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button_in_panel = CrymbleUI::Button.new("Panel Button") { }
      button_in_root = CrymbleUI::Button.new("Root Button") { }

      panel.add_child(button_in_panel)
      window.add_child(button_in_root)
      app.root_widget = window
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      root_layer = window.root_layer.not_nil!
      panel_layer = panel.layer.not_nil!

      # Clear all render states
      root_layer.clear_render_state
      panel_layer.clear_render_state

      # Change button in panel
      button_in_panel.background_color = CrymbleUI::Color.new(255, 0, 0, 255)

      # Only panel layer should be marked, not root layer
      panel_layer.needs_render?.should be_true
      root_layer.needs_render?.should be_false
    end
  end

  describe "Layer bounds during panel movement" do
    it "updates layer bounds when panel is dragged" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Initial layer bounds (match panel bounds)
      initial_x = panel_layer.bounds.x
      initial_y = panel_layer.bounds.y

      # Drag panel
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
      panel.on_mouse_move(CrymbleUI::Vec2.new(250.0, 215.0))

      # Panel moved
      panel.x.should eq(200.0)
      panel.y.should eq(200.0)

      # Layer bounds should follow panel exactly (no border expansion)
      panel_layer.bounds.x.should eq(panel.x)
      panel_layer.bounds.y.should eq(panel.y)
    end
  end

  describe "Layer compositing position" do
    it "composites layer at correct position matching layer bounds" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }

      panel.add_child(button)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Layer composite position should match layer bounds
      # When renderer calls composite_layer_to_window(layer, window),
      # sprite.position should be (layer.bounds.x, layer.bounds.y)

      expected_x = panel.x  # 100.0
      expected_y = panel.y  # 100.0

      panel_layer.bounds.x.should eq(expected_x)
      panel_layer.bounds.y.should eq(expected_y)
    end

    it "updates composite position when panel moves" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)
      app.root_widget = window

      app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

      panel_layer = panel.layer.not_nil!

      # Initial position
      initial_composite_x = panel_layer.bounds.x
      initial_composite_y = panel_layer.bounds.y

      # Drag panel
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
      panel.on_mouse_move(CrymbleUI::Vec2.new(250.0, 215.0))

      # Panel moved to (200, 200)
      # Layer composite position should update to (200, 200) - no border offset
      expected_x = 200.0
      expected_y = 200.0

      panel_layer.bounds.x.should eq(expected_x)
      panel_layer.bounds.y.should eq(expected_y)
    end
  end
end
