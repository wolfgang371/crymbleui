require "../spec_helper"

# Visual regression tests based on reported rendering failures
# These test VISIBLE behavior from a user perspective, not internal implementation

# The text strings a widget's primitives would DRAW. A widget that emits a background FillRect but
# DROPS its text (the "renders white/blank" bug class these tests exist for) still has size > 0 — so
# assert the actual text, not just "some primitive".
private def drawn_texts(prims)
  prims.select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText).text)
end

describe "Visual Rendering - User Perspective" do
  describe "Content visibility in panels" do
    it "renders button text visible inside panel (not white)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
      button = CrymbleUI::Button.new("Click Me") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Button should generate visible primitives (text + background)
      primitives = button.get_primitives(button.bounds)

      # Should have primitives (not empty = not white)
      primitives.size.should be > 0

      # Should include text primitive with actual text
      text_prims = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
      text_prims.size.should be > 0
      text_prims.first.as(CrymbleUI::DrawText).text.should eq("Click Me")
    end

    it "renders multiple widgets visible inside panel (not all white)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
      button1 = CrymbleUI::Button.new("Button 1") { }
      button2 = CrymbleUI::Button.new("Button 2") { }
      text = CrymbleUI::Text.new("Hello World")

      panel.add_child(button1)
      panel.add_child(button2)
      panel.add_child(text)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Each widget should render its ACTUAL text (not just "some primitive")
      drawn_texts(button1.get_primitives(button1.bounds)).should contain("Button 1")
      drawn_texts(button2.get_primitives(button2.bounds)).should contain("Button 2")
      drawn_texts(text.get_primitives(text.bounds)).should contain("Hello World")
    end

    it "renders content in window root layer (not white)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Root Button") { }
      text = CrymbleUI::Text.new("Root Text")

      window.add_child(button)
      window.add_child(text)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Content widgets in root should render their actual text
      drawn_texts(button.get_primitives(button.bounds)).should contain("Root Button")
      drawn_texts(text.get_primitives(text.bounds)).should contain("Root Text")
    end
  end

  describe "Panel drag visual behavior" do
    # Obsolete: "panel content stays aligned during drag" - bounds intentionally stale for O(1) performance

    it "panel chrome renders at correct position during drag (not clipped)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Drag panel
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
      panel.on_mouse_move(CrymbleUI::Vec2.new(250.0, 215.0))

      # With NEW architecture, Chrome widget has the chrome primitives (not panel itself)
      # Chrome is the first widget in panel layer
      panel_layer = panel.layer.not_nil!
      chrome = panel_layer.widgets[0]  # Chrome is first
      chrome.should be_a(CrymbleUI::WindowPanel::Chrome)

      # Chrome primitives should exist at new position
      chrome_primitives = chrome.get_primitives(chrome.bounds)
      chrome_primitives.size.should be > 0

      # Panel should be rendered at new position (200, 200)
      # Not clipped at old position (100, 100)
      panel.x.should eq(200.0)
      panel.y.should eq(200.0)
    end
  end

  describe "Panel highlight/active state" do
    it "only one panel shows active highlight at a time" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      panel3 = CrymbleUI::WindowPanel.new("P3", 600.0, 100.0, 200.0, 150.0, z_index: 3)

      window.add_child(panel1)
      window.add_child(panel2)
      window.add_child(panel3)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Click panel1 title bar
      panel1.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))

      # Only panel1 should have highest z_index (brought to front)
      max_z = [panel1.z_index, panel2.z_index, panel3.z_index].max
      panel1.z_index.should eq(max_z)

      # Other panels should have lower z_index
      panel2.z_index.should be < max_z
      panel3.z_index.should be < max_z
    end

    it "clicking content inside panel ALSO highlights that panel (not just chrome)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      button1 = CrymbleUI::Button.new("B1") { }

      panel1.add_child(button1)
      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      initial_z1 = panel1.z_index
      initial_z2 = panel2.z_index

      # panel2 is in front initially
      initial_z2.should be > initial_z1

      # Click button INSIDE panel1 content area (not chrome)
      button_center = CrymbleUI::Vec2.new(
        button1.bounds.x + button1.bounds.width / 2,
        button1.bounds.y + button1.bounds.height / 2
      )
      button1.on_mouse_down(button_center)

      # Panel1 should come to front (z_index increases above panel2)
      panel1.z_index.should be > initial_z2
    end

    it "switching between panels updates highlight correctly" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      button1 = CrymbleUI::Button.new("B1") { }
      button2 = CrymbleUI::Button.new("B2") { }

      panel1.add_child(button1)
      panel2.add_child(button2)
      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Click panel1 content
      button1_center = CrymbleUI::Vec2.new(
        button1.bounds.x + button1.bounds.width / 2,
        button1.bounds.y + button1.bounds.height / 2
      )
      button1.on_mouse_down(button1_center)

      z1_after_first_click = panel1.z_index
      z2_after_first_click = panel2.z_index

      # Panel1 in front
      z1_after_first_click.should be > z2_after_first_click

      # Click panel2 content
      button2_center = CrymbleUI::Vec2.new(
        button2.bounds.x + button2.bounds.width / 2,
        button2.bounds.y + button2.bounds.height / 2
      )
      button2.on_mouse_down(button2_center)

      # Panel2 should now be in front
      panel2.z_index.should be > panel1.z_index
    end
  end

  describe "Z-order behavior" do
    it "clicking panel content brings panel to front (same as clicking chrome)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      button = CrymbleUI::Button.new("Button") { }

      panel1.add_child(button)
      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Initial state: panel2 in front
      panel2.z_index.should be > panel1.z_index

      # Click button in panel1
      button_center = CrymbleUI::Vec2.new(
        button.bounds.x + button.bounds.width / 2,
        button.bounds.y + button.bounds.height / 2
      )
      button.on_mouse_down(button_center)

      # Panel1 should now be in front
      panel1.z_index.should be > panel2.z_index

      # Now click panel2 chrome (title bar)
      panel2.on_mouse_down(CrymbleUI::Vec2.new(400.0, 115.0))

      # Panel2 should be in front again
      panel2.z_index.should be > panel1.z_index

      # Both methods (content click and chrome click) should have same effect
    end
  end
end
