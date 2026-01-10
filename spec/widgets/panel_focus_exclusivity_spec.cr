require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for panel focus/highlight exclusivity
# Issue: In panels_demo, clicking in content of multiple panels makes all of them highlighted
# Expected: Only one panel should be highlighted (light blue title) at a time

describe "Panel Focus Exclusivity" do
  it "only one panel highlighted at a time when clicking content" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create three panels with distinct positions
    panel1 = CrymbleUI::WindowPanel.new("Panel 1", 50.0, 50.0, 200.0, 150.0)
    panel2 = CrymbleUI::WindowPanel.new("Panel 2", 300.0, 50.0, 200.0, 150.0)
    panel3 = CrymbleUI::WindowPanel.new("Panel 3", 550.0, 50.0, 200.0, 150.0)

    # Add some content to panels so they have clickable content area
    button1 = CrymbleUI::Button.new("Button 1")
    button2 = CrymbleUI::Button.new("Button 2")
    button3 = CrymbleUI::Button.new("Button 3")

    panel1.add_child(button1)
    panel2.add_child(button2)
    panel3.add_child(button3)

    window.add_child(panel1)
    window.add_child(panel2)
    window.add_child(panel3)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Initially, no panel should be topmost (all panels exist, none are highlighted)
    # Note: First panel in z-order is topmost by default
    # For this test, we'll track which panel was clicked last

    # Click in content area of panel1 (on the button)
    # Button is in panel content, below title bar
    renderer.mouse_down(150.0, 120.0)  # Inside panel1 content area
    renderer.mouse_up(150.0, 120.0)
    renderer.render_frame(app)

    # Panel1 should now be topmost (brought to front)
    panel1.topmost?.should be_true
    panel2.topmost?.should be_false
    panel3.topmost?.should be_false

    # Click in content area of panel2 (on the button)
    renderer.mouse_down(400.0, 120.0)  # Inside panel2 content area
    renderer.mouse_up(400.0, 120.0)
    renderer.render_frame(app)

    # Panel2 should now be topmost, panel1 should NO LONGER be topmost
    panel1.topmost?.should be_false
    panel2.topmost?.should be_true
    panel3.topmost?.should be_false

    # Click in content area of panel3 (on the button)
    renderer.mouse_down(650.0, 120.0)  # Inside panel3 content area
    renderer.mouse_up(650.0, 120.0)
    renderer.render_frame(app)

    # Panel3 should now be topmost, panel2 should NO LONGER be topmost
    panel1.topmost?.should be_false
    panel2.topmost?.should be_false
    panel3.topmost?.should be_true
  end

  it "only one panel can be dragged at a time (exclusivity)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel1 = CrymbleUI::WindowPanel.new("Panel 1", 50.0, 50.0, 200.0, 150.0)
    panel2 = CrymbleUI::WindowPanel.new("Panel 2", 300.0, 50.0, 200.0, 150.0)

    window.add_child(panel1)
    window.add_child(panel2)
    app.root_widget = window

    renderer.render_frame(app)

    # Start dragging panel1
    renderer.mouse_down(150.0, 60.0)  # Title bar
    renderer.render_frame(app)

    panel1.topmost?.should be_true
    panel2.topmost?.should be_false

    # Even if we somehow click panel2, panel1 should remain the topmost one during drag
    # (This is more about ensuring state consistency)
    initial_panel1_x = panel1.x
    renderer.mouse_move(200.0, 60.0)  # Drag panel1
    renderer.render_frame(app)

    # Panel1 should have moved
    panel1.x.should be > initial_panel1_x

    # Panel1 should still be topmost
    panel1.topmost?.should be_true
    panel2.topmost?.should be_false
  end
end
