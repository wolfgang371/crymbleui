require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: MenuBar background should fill to right edge (no gap showing panel color)
#
# BUG: Small grey gap visible between last menu item and right edge of MenuBar
# Expected: MenuBar background color fills entire width (no panel color visible)
# Actual: Panel color (grey) shows through on right side
#
# This could be:
# 1. MenuBar not rendering background rect to full width
# 2. Menu items not accounting for full MenuBar width
# 3. Off-by-one pixel issue in background rect

class MenubarRightEdgeTestApp < CrymbleUI::App
  property root_widget : CrymbleUI::Widget?

  def build : CrymbleUI::Widget
    @root_widget.not_nil!
  end

  # Fix: Also set inherited @root so render_all_layers executes
  def root_widget=(widget : CrymbleUI::Widget)
    @root_widget = widget
    @root = widget
  end
end

describe "MenuBar right edge gap" do
  it "menubar background fills to right edge (no panel color showing)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenubarRightEdgeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

    menubar = CrymbleUI::MenuBar.new
    menu1 = CrymbleUI::Menu.new("File")
    menu2 = CrymbleUI::Menu.new("Edit")
    menubar.add_child(menu1)
    menubar.add_child(menu2)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Render
    renderer.render_frame(app)

    # Get colors
    menubar_bg = menubar.background_color
    panel_bg = panel.background_color


    # Check pixel at right edge of MenuBar (should be MenuBar color, not panel color)
    menubar_abs = menubar.absolute_bounds

    # Right edge of MenuBar area
    right_edge_x = (menubar_abs.x + menubar_abs.width - 1).to_i
    menubar_middle_y = (menubar_abs.y + menubar_abs.height / 2).to_i


    # Get panel layer backend for pixel testing
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Convert to layer-local coordinates
    layer_local_x = right_edge_x - panel_layer.bounds.x.to_i
    layer_local_y = menubar_middle_y - panel_layer.bounds.y.to_i
    pixel = backend.get_pixel(layer_local_x, layer_local_y)


    # BUG: This should be MenuBar background, not panel background
    pixel.should eq(menubar_bg)
    pixel.should_not eq(panel_bg)
  end

  it "menubar background fills right edge even with few menu items" do
    # Test with only 1 menu item to make the gap more obvious
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenubarRightEdgeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 400.0, 200.0)

    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")  # Only one menu
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Render
    renderer.render_frame(app)

    menubar_abs = menubar.absolute_bounds
    menubar_bg = menubar.background_color
    panel_bg = panel.background_color


    # Check multiple points along right edge
    right_edge_x = (menubar_abs.x + menubar_abs.width - 1).to_i
    middle_x = (menubar_abs.x + menubar_abs.width / 2).to_i
    menubar_middle_y = (menubar_abs.y + menubar_abs.height / 2).to_i

    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Convert to layer-local coordinates
    layer_right_x = right_edge_x - panel_layer.bounds.x.to_i
    layer_middle_x = middle_x - panel_layer.bounds.x.to_i
    layer_y = menubar_middle_y - panel_layer.bounds.y.to_i

    # Check right edge
    pixel_right = backend.get_pixel(layer_right_x, layer_y)

    # Check middle (should definitely be MenuBar background)
    pixel_middle = backend.get_pixel(layer_middle_x, layer_y)

    # BUG: Right edge should be MenuBar color, not panel color
    pixel_right.should eq(menubar_bg)
    pixel_right.should_not eq(panel_bg)
  end
end
