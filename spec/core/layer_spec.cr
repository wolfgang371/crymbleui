require "../spec_helper"
require "../../src/core/layer"

describe CrymbleUI::Layer do
  describe "#initialize" do
    it "creates layer with basic properties" do
      bounds = CrymbleUI::Rect.new(10, 20, 100, 80)
      layer = CrymbleUI::Layer.new("test_layer", bounds, z_index: 5)

      layer.id.should eq("test_layer")
      layer.z_index.should eq(5)
      layer.bounds.should eq(bounds)
      layer.opacity.should eq(1.0)
      layer.blend_mode.should eq(CrymbleUI::BlendMode::Normal)
    end

    it "defaults to z_index 0" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.z_index.should eq(0)
    end

    it "starts with no backend" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.backend.should be_nil
    end

    it "starts with empty widgets array" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.widgets.should be_empty
    end

    it "starts with empty children array" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.children.should be_empty
    end

    it "starts with NeedsLayout state" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state.should eq(CrymbleUI::WidgetState::NeedsLayout)
    end
  end

  describe "properties" do
    it "allows setting opacity" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.opacity = 0.5
      layer.opacity.should eq(0.5)
    end

    it "allows setting blend_mode" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.blend_mode = CrymbleUI::BlendMode::Additive
      layer.blend_mode.should eq(CrymbleUI::BlendMode::Additive)
    end

    it "allows updating bounds" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      new_bounds = CrymbleUI::Rect.new(50, 60, 200, 150)
      layer.bounds = new_bounds
      layer.bounds.should eq(new_bounds)
    end
  end

  describe "#mark_needs_render" do
    it "marks layer state as NeedsRender" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state = CrymbleUI::WidgetState::Clean

      layer.mark_needs_full_render

      layer.state.should eq(CrymbleUI::WidgetState::NeedsRender)
    end
  end

  describe "#needs_render?" do
    it "returns true when state is NeedsRender" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state = CrymbleUI::WidgetState::NeedsRender
      layer.needs_render?.should be_true
    end

    it "returns true when state is NeedsLayout" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state = CrymbleUI::WidgetState::NeedsLayout
      layer.needs_render?.should be_true
    end

    it "returns false when state is Clean and not first render" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state = CrymbleUI::WidgetState::Clean
      layer.clear_render_state  # Simulate that first render already happened
      layer.needs_render?.should be_false
    end
  end

  describe "#clear_render_state" do
    it "marks layer as clean" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.zero)
      layer.state = CrymbleUI::WidgetState::NeedsRender

      layer.clear_render_state

      layer.state.should eq(CrymbleUI::WidgetState::Clean)
    end
  end
end

describe "Window layer integration" do
  describe "root layer creation" do
    it "creates root layer on initialization" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      root = window.root_layer
      root.should_not be_nil
      root.not_nil!.id.should contain("window_content")
      root.not_nil!.z_index.should eq(0)
    end

    it "updates root layer bounds during layout" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

      window.layout(constraints, CrymbleUI::Vec2.zero)

      root = window.root_layer.not_nil!
      root.bounds.width.should eq(800.0)
      root.bounds.height.should eq(600.0)
    end
  end

  describe "#collect_all_layers" do
    it "returns root layer for window with no panels" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      layers.size.should eq(1)
      layers[0].should eq(window.root_layer)
    end

    it "sorts layers by z-index" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      # Should be sorted (ascending z-index)
      layers.size.times do |i|
        next if i == 0
        layers[i].z_index.should be >= layers[i - 1].z_index
      end
    end
  end

  describe "root layer widget population" do
    it "adds non-panel widgets to root layer during layout" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      text = CrymbleUI::Text.new("Hello")
      button = CrymbleUI::Button.new("Click") { }

      window.add_child(text)
      window.add_child(button)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root = window.root_layer.not_nil!
      root.widgets.should contain(text)
      root.widgets.should contain(button)
    end
  end

  describe "WindowPanel layer integration" do
    it "creates its internal layer lazily on first layout" do
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0, z_index: 5)
      panel.layer.should be_nil # lazy: no layer until laid out (mirrors ScrollView/VirtualMatrix)

      panel.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0)), CrymbleUI::Vec2.new(100.0, 100.0))

      layer = panel.layer
      layer.should_not be_nil
      layer.not_nil!.z_index.should eq(5)
    end

    it "updates layer bounds during layout (equal to panel bounds)" do
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))

      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      layer = panel.layer.not_nil!
      # Layer bounds now equal panel bounds (border drawn during composite, not cached)
      layer.bounds.x.should eq(100.0)
      layer.bounds.y.should eq(100.0)
      layer.bounds.width.should eq(200.0)
      layer.bounds.height.should eq(150.0)
    end

    it "syncs layer z_index with panel z_index during layout" do
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0, z_index: 3)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))

      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      panel.layer.not_nil!.z_index.should eq(3)

      # After bring_to_front, layer z_index should sync
      panel.bring_to_front
      panel.layer.not_nil!.z_index.should eq(panel.z_index)
    end

    it "populates layer with chrome first, then content (NEW architecture)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layer = panel.layer.not_nil!
      # Chrome should be first (for chrome rendering)
      layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      # Content should be second
      layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)
      # Panel itself is NOT in layer.widgets (chrome/content architecture)
      layer.widgets.size.should eq(2)
    end

    it "includes panel layers in window.collect_all_layers" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 5)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)

      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      # Should have root layer + 2 panel layers
      layers.size.should eq(3)

      # Should be sorted by z_index (root=0, panel2=2, panel1=5)
      layers[0].z_index.should eq(0)  # root
      layers[1].z_index.should eq(2)  # panel2
      layers[2].z_index.should eq(5)  # panel1
    end
  end

  describe "MenuBar layer integration" do
    it "does not create layer on initialization (created conditionally in layout)" do
      menubar = CrymbleUI::MenuBar.new

      # Layer is nil until layout() determines parent context
      layer = menubar.layer
      layer.should be_nil
    end

    it "creates layer for Window menubar (needs high z-index)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      window.add_child(menubar)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      menubar.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Window menubar should have its own layer (high z-index above panels)
      layer = menubar.layer
      layer.should_not be_nil
      layer.not_nil!.z_index.should eq(1000)
      layer.not_nil!.bounds.width.should eq(800.0)
    end

    it "does not create layer for Panel menubar (uses panel layer)" do
      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 300.0, 200.0)
      menubar = CrymbleUI::MenuBar.new
      panel.add_child(menubar)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0))
      menubar.layout(constraints, CrymbleUI::Vec2.new(0.0, 30.0))

      # Panel menubar should NOT have its own layer
      menubar.layer.should be_nil
    end

    it "populates layer with menubar (menus are children, not layer widgets)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu1 = CrymbleUI::Menu.new("File")

      menubar.add_child(menu1)
      window.add_child(menubar)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layer = menubar.layer.not_nil!
      # MenuBar should be the only widget in its layer
      layer.widgets[0].should eq(menubar)
      layer.widgets.size.should eq(1)
      # Menu is a child of MenuBar, not a layer widget
      menubar.children.should contain(menu1)
    end

    it "includes menubar layer in window.collect_all_layers" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 5)

      window.add_child(menubar)
      window.add_child(panel1)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      # Should have root layer + panel layer + menubar layer
      layers.size.should eq(3)

      # Should be sorted by z_index (root=0, panel1=5, menubar=1000)
      layers[0].z_index.should eq(0)     # root
      layers[1].z_index.should eq(5)     # panel1
      layers[2].z_index.should eq(1000)  # menubar
    end

    it "z_index ensures menubar renders on top" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 999)

      window.add_child(menubar)
      window.add_child(panel1)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      # MenuBar layer should be last (highest z_index)
      menubar_layer = menubar.layer.not_nil!
      menubar_layer.z_index.should be > panel1.layer.not_nil!.z_index
    end
  end

  describe "Popup layer integration" do
    it "creates its internal layer lazily on first layout" do
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0)
      popup.layer.should be_nil # lazy: no layer until laid out

      popup.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0)), CrymbleUI::Vec2.new(100.0, 50.0))

      layer = popup.layer
      layer.should_not be_nil
      layer.not_nil!.z_index.should eq(1000)  # Default z_index for popups
    end

    it "respects custom z_index from initialization" do
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0, z_index: 1500)
      popup.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0)), CrymbleUI::Vec2.new(100.0, 50.0))

      layer = popup.layer.not_nil!
      layer.z_index.should eq(1500)
    end

    it "updates layer bounds during layout" do
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      position = CrymbleUI::Vec2.new(100.0, 50.0)

      popup.layout(constraints, position)

      layer = popup.layer.not_nil!
      # Layer bounds expanded by 1px on all sides for border
      layer.bounds.x.should eq(99.0)
      layer.bounds.y.should eq(49.0)
      layer.bounds.width.should eq(202.0)
      layer.bounds.height.should eq(102.0)
    end

    it "populates layer with popup only (not children, to prevent double-rendering)" do
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0)
      menu_item = CrymbleUI::MenuItem.new("Open") { }

      popup.add_child(menu_item)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      popup.layout(constraints, CrymbleUI::Vec2.zero)

      layer = popup.layer.not_nil!
      # Popup should be in layer.widgets for background rendering
      layer.widgets[0].should eq(popup)
      # Children should NOT be in layer.widgets (they're rendered recursively)
      layer.widgets.should_not contain(menu_item)
      layer.widgets.size.should eq(1)  # Only popup, not children
    end

    it "includes popup layers in window.collect_all_layers" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0, z_index: 1200)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 5)

      # Add popup directly to window (not via Menu, since Menu manages popups dynamically)
      window.add_child(popup)
      window.add_child(panel1)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      layers = window.collect_all_layers

      # Should have root layer + panel layer + popup layer
      layers.size.should eq(3)

      # Should be sorted by z_index (root=0, panel1=5, popup=1200)
      layers[0].z_index.should eq(0)     # root
      layers[1].z_index.should eq(5)     # panel1
      layers[2].z_index.should eq(1200)  # popup
    end
  end
end
