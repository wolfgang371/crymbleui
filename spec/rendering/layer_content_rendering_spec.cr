require "../spec_helper"

# Tests for layer content rendering
# These tests verify that widgets are correctly added to layers and rendered
#
# PROBLEM: After state propagation fix, panel chromes render but content is white
# ROOT CAUSE: Widgets may not be in layer.widgets array, or rendering is broken

describe "Layer Content Rendering" do
  describe "Layer widget population" do
    it "populates root layer with window content widgets" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Click") { }
      text = CrymbleUI::Text.new("Hello")

      window.add_child(button)
      window.add_child(text)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!

      # Root layer should contain both widgets
      root_layer.widgets.size.should eq(2)
      root_layer.widgets.should contain(button)
      root_layer.widgets.should contain(text)
    end

    it "populates panel layer with Chrome and Content (NEW architecture)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Panel layer has Chrome + Content (not panel itself, not button)
      panel_layer.widgets.size.should eq(2)
      panel_layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      panel_layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)
      # Button is child of Content, not in layer.widgets
    end

    it "panel children are nested in Content widget (NEW architecture)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      btn1 = CrymbleUI::Button.new("B1") { }
      btn2 = CrymbleUI::Button.new("B2") { }
      text = CrymbleUI::Text.new("Hello")

      panel.add_child(btn1)
      panel.add_child(btn2)
      panel.add_child(text)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Panel layer has Chrome + Content only (size = 2)
      panel_layer.widgets.size.should eq(2)
      panel_layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      panel_layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)

      # User-added children are nested under Content (panel.add_child redirects to Content.add_child)
      # panel.children contains [Chrome, Content], NOT user widgets
      content = panel_layer.widgets[1].as(CrymbleUI::WindowPanel::Content)
      content.children.should contain(btn1)
      content.children.should contain(btn2)
      content.children.should contain(text)
    end

    it "does NOT add panels to root layer (they have own layers)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      window.add_child(button)  # Regular widget
      window.add_child(panel)   # Panel widget

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!

      # Root layer should only have button, NOT panel (panel has own layer)
      root_layer.widgets.size.should eq(1)
      root_layer.widgets.should contain(button)
      root_layer.widgets.should_not contain(panel)
    end

    it "clears and repopulates layer widgets on re-layout" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      btn1 = CrymbleUI::Button.new("B1") { }

      panel.add_child(btn1)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      initial_size = panel_layer.widgets.size

      # Re-layout (happens during rebuild)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Should have same number of widgets (not doubled)
      panel_layer.widgets.size.should eq(initial_size)
    end
  end

  describe "Layer bounds and texture sizing" do
    it "sets root layer bounds to window size" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!

      root_layer.bounds.x.should eq(0.0)
      root_layer.bounds.y.should eq(0.0)
      root_layer.bounds.width.should eq(800.0)
      root_layer.bounds.height.should eq(600.0)
    end

    it "sets panel layer bounds to match panel bounds" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Layer bounds now match panel bounds exactly (border drawn during composite, not cached)
      panel_layer.bounds.x.should eq(100.0)
      panel_layer.bounds.y.should eq(100.0)
      panel_layer.bounds.width.should eq(200.0)
      panel_layer.bounds.height.should eq(150.0)
    end

    it "updates panel layer bounds when panel moves" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Simulate drag
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))  # Title bar
      panel.on_mouse_move(CrymbleUI::Vec2.new(200.0, 165.0))  # Drag 50px right/down

      # Panel position should have changed
      panel.x.should eq(150.0)
      panel.y.should eq(150.0)

      # Layer bounds should follow panel exactly (no border expansion)
      panel_layer.bounds.x.should eq(150.0)
      panel_layer.bounds.y.should eq(150.0)
    end
  end

  describe "Bring to front behavior" do
    it "brings panel to front when clicking inside content area" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      button1 = CrymbleUI::Button.new("B1") { }

      panel1.add_child(button1)
      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      initial_z2 = panel2.z_index

      # Click button inside panel1 content area
      # Use absolute_bounds since hit testing works in window coordinates
      abs_bounds = button1.absolute_bounds
      button_center = CrymbleUI::Vec2.new(
        abs_bounds.x + abs_bounds.width / 2,
        abs_bounds.y + abs_bounds.height / 2
      )

      # Simulate click through window hit testing
      hit = window.hit_test(button_center)
      hit.should eq(button1)

      # Simulate click on button (which should trigger parent panel's bring_to_front)
      button1.on_mouse_down(button_center)

      # Panel1 z_index should increase above panel2
      panel1.z_index.should be > initial_z2
    end

    it "hit testing finds button inside panel content area" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Click in button area (inside panel content, below title bar)
      # Use absolute_bounds since hit testing works in window coordinates
      abs_bounds = button.absolute_bounds
      button_center = CrymbleUI::Vec2.new(
        abs_bounds.x + abs_bounds.width / 2,
        abs_bounds.y + abs_bounds.height / 2
      )

      hit = window.hit_test(button_center)

      # Should find the button, not the panel
      hit.should eq(button)
    end
  end
end

  describe "Layer initial render state" do
    it "marks layers as needing render after initial layout" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!
      panel_layer = panel.layer.not_nil!

      # After layout, layers should need rendering (initial state is NeedsLayout)
      root_layer.needs_render?.should be_true
      panel_layer.needs_render?.should be_true
    end
  end
