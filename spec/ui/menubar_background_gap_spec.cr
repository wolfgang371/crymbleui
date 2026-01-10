require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for MenuBar background gap issue
#
# BUG: MenuBar background doesn't extend to full panel width.
# There's a gap between the last menu item and the panel edge that shows
# layer background color instead of menubar background color.
#
# Expected: MenuBar background fills entire width (edge-to-edge)
# Actual: Gap at right edge shows layer background

describe "MenuBar Background Gap" do
  it "menubar background fills full width (no gap at right edge)" do
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

    # Get panel layer backend for pixel testing
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Check MenuBar spans full panel width
    menubar.bounds.width.should eq(300.0)  # Full panel width

    # Check pixel at right edge of panel (should be menubar background, not layer background)
    # MenuBar is at y=30 (TITLE_BAR_HEIGHT), height=28px
    menubar_y = 32  # Middle of menubar
    right_edge_x = 295  # Near right edge of 300px panel

    pixel = backend.get_pixel(right_edge_x, menubar_y)
    layer_bg = CrymbleUI::Color.new(240, 240, 240, 255)

    # Should be menubar background, NOT layer background (gap)
    pixel.should eq(menubar.background_color)
    pixel.should_not eq(layer_bg)
  end

  it "menubar background fills full width after panel resize" do
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

    # Resize panel wider: 300px -> 400px
    panel_right_edge = 100.0 + 300.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    renderer.mouse_move(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    renderer.mouse_up(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    # Get panel layer backend
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # MenuBar should now be 400px wide
    menubar.bounds.width.should eq(400.0)

    # Check pixel at right edge of resized panel
    menubar_y = 32
    right_edge_x = 395  # Near right edge of 400px panel

    pixel = backend.get_pixel(right_edge_x, menubar_y)
    layer_bg = CrymbleUI::Color.new(240, 240, 240, 255)

    # Should be menubar background, NOT layer background (gap)
    pixel.should eq(menubar.background_color)
    pixel.should_not eq(layer_bg)
  end
end
