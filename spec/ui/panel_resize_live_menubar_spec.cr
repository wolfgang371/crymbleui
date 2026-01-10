require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for live menubar resizing during panel resize
#
# BUG: During panel resize (while dragging resize edge), menubar doesn't
# update its width. It only updates after mouse_up.
#
# Current behavior:
# - on_mouse_move during resize: Updates panel bounds, but NOT children layout
# - Comment says: "DON'T layout children during resize - too expensive at 60fps"
# - Children appear at old size until mouse_up
#
# Desired behavior:
# - Menubar should resize live during panel resize (not just after mouse_up)
# - User sees immediate visual feedback

describe "Panel Resize Live MenuBar Updates" do
  it "menubar background extends during resize drag (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with menubar
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Start resize on right edge
    panel_right_edge = 100.0 + 300.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    # Drag to resize panel by 100px (DURING resize, before mouse_up)
    renderer.mouse_move(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    # Panel bounds should be updated
    panel.width.should eq(400.0)

    # Check pixel at right edge of panel (menubar should extend there)
    # Get panel layer backend for pixel testing
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Check pixel near right edge of resized panel (in layer-local coords)
    # MenuBar is at y=30 (TITLE_BAR_HEIGHT), check background pixel
    menubar_y = 32  # Middle of menubar (height 28px)
    right_edge_x = 395  # Near right edge of 400px panel

    pixel = backend.get_pixel(right_edge_x, menubar_y)

    # Should be menubar background color (not panel background)
    # This proves menubar background extends to panel edge during resize
    pixel.should eq(menubar.background_color)
  end

  it "menubar background extends to new edge during left edge resize (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with menubar
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Start resize from left edge
    panel_left_edge = 100.0
    renderer.mouse_down(panel_left_edge, 150.0)
    renderer.render_frame(app)

    # Drag left edge inward by 50px (DURING resize - panel gets smaller)
    renderer.mouse_move(panel_left_edge + 50.0, 150.0)
    renderer.render_frame(app)

    # Panel should be at x=150, width=250
    panel.x.should eq(150.0)
    panel.width.should eq(250.0)

    # Check pixel at right edge of resized panel
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    menubar_y = 32
    right_edge_x = 245  # Near right edge of 250px panel

    pixel = backend.get_pixel(right_edge_x, menubar_y)

    # Should still be menubar background (extends to panel edge)
    pixel.should eq(menubar.background_color)
  end
end
