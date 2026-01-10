require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for WindowPanel border rendering
#
# BUG: WindowPanel has a border_color property but doesn't draw a border
# around the entire panel perimeter. Only the title bar bottom border is drawn.
#
# Expected: Panel should have border around all four edges (top, right, bottom, left)
# Actual: No border drawn around panel edges

# TestApp that builds correct window+panel structure
# This prevents rebuild() from destroying the panel during mouse_up
class PanelBorderTestApp < CrymbleUI::App
  getter panel : CrymbleUI::WindowPanel?
  getter window : CrymbleUI::Window?

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    window.add_child(panel)
    @window = window
    @panel = panel
    window
  end
end

describe "WindowPanel Border" do
  it "panel has border around entire perimeter" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelBorderTestApp.new
    app.rebuild  # Trigger initial build and set root
    panel = app.panel.not_nil!

    # Initial render
    renderer.render_frame(app)

    # Get WINDOW backend for pixel testing (composite-time borders appear here)
    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Panel border should be darker blue: Color.new(0, 80, 160, 255)
    border_color = panel.border_color
    layer_bg = CrymbleUI::Color.new(240, 240, 240, 255)

    # Check top edge (should have border)
    # Panel is at window position (100, 100), size (300, 200)
    # Top edge pixels in window coordinates should be border color
    top_left = window_backend.get_pixel(100, 100)  # Top-left corner
    top_middle = window_backend.get_pixel(250, 100)  # Top edge middle
    top_right = window_backend.get_pixel(399, 100)  # Top-right corner

    top_left.should eq(border_color)
    top_middle.should eq(border_color)
    top_right.should eq(border_color)

    # Check right edge (should have border)
    right_top = window_backend.get_pixel(399, 101)  # Right edge near top
    right_middle = window_backend.get_pixel(399, 200)  # Right edge middle
    right_bottom = window_backend.get_pixel(399, 298)  # Right edge near bottom

    right_top.should eq(border_color)
    right_middle.should eq(border_color)
    right_bottom.should eq(border_color)

    # Check bottom edge (should have border)
    bottom_left = window_backend.get_pixel(100, 299)  # Bottom-left corner
    bottom_middle = window_backend.get_pixel(250, 299)  # Bottom edge middle
    bottom_right = window_backend.get_pixel(399, 299)  # Bottom-right corner

    bottom_left.should eq(border_color)
    bottom_middle.should eq(border_color)
    bottom_right.should eq(border_color)

    # Check left edge (should have border)
    left_top = window_backend.get_pixel(100, 101)  # Left edge near top
    left_middle = window_backend.get_pixel(100, 200)  # Left edge middle
    left_bottom = window_backend.get_pixel(100, 298)  # Left edge near bottom

    left_top.should eq(border_color)
    left_middle.should eq(border_color)
    left_bottom.should eq(border_color)
  end

  it "panel border visible after resize" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelBorderTestApp.new
    app.rebuild  # Trigger initial build and set root
    panel = app.panel.not_nil!

    # Initial render
    renderer.render_frame(app)

    # Resize panel wider: drag right edge
    panel_right_edge = 100.0 + 300.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    renderer.mouse_move(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    renderer.mouse_up(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    # Get WINDOW backend for pixel testing
    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Panel should now be 400px wide
    panel.width.should eq(400.0)

    # Border should extend to new width (panel at x=100, new width=400, so right edge at x=499)
    border_color = panel.border_color

    # Check new right edge has border
    right_edge_x = 499
    right_middle = window_backend.get_pixel(right_edge_x, 200)
    right_middle.should eq(border_color)

    # Check new bottom-right corner has border (panel at y=100, height=200, so bottom at y=299)
    bottom_right = window_backend.get_pixel(right_edge_x, 299)
    bottom_right.should eq(border_color)
  end
end
