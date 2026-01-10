require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: MenuBar width should update DURING panel resize drag (live resize)
#
# BUG: MenuBar width doesn't extend during panel resize drag
# Expected: MenuBar grows/shrinks in real-time as panel edge is dragged
# Actual: MenuBar stays at old width during drag, only updates on mouse up
#
# This is a visual bug - the MenuBar background rectangle doesn't extend
# to fill the new panel width while dragging, leaving a grey gap on the right.

class MenubarLiveResizeTestApp < CrymbleUI::App
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

describe "MenuBar live resize during drag" do
  it "menubar width extends during panel right-edge resize drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenubarLiveResizeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Start resizing panel from right edge
    panel_right_edge = panel.x + panel.width
    edge_y = panel.y + panel.height / 2
    renderer.mouse_down(panel_right_edge, edge_y)
    renderer.render_frame(app)

    # Drag right edge outward by 100px (panel width: 300 → 400)
    renderer.mouse_move(panel_right_edge + 100.0, edge_y)
    renderer.render_frame(app)

    # Verify MenuBar width matches panel width during drag (live resize)
    menubar.bounds.width.should eq(panel.width)

    # Also check that MenuBar background fills to right edge during drag
    menubar_abs = menubar.absolute_bounds
    backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Verify MenuBar background fills to right edge (check pixel, avoiding 1px border)
    panel_right_x = (panel.x + panel.width - 2).to_i
    menubar_y = (menubar_abs.y + menubar_abs.height / 2).to_i
    pixel = backend.get_pixel(panel_right_x, menubar_y)
    menubar_bg = menubar.background_color
    pixel.should eq(menubar_bg)
  end

  it "menubar width shrinks during panel left-edge resize drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenubarLiveResizeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("Edit")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Start resizing panel from left edge (shrinking panel)
    panel_left_edge = panel.x
    edge_y = panel.y + panel.height / 2
    renderer.mouse_down(panel_left_edge, edge_y)
    renderer.render_frame(app)

    # Drag left edge inward by 50px (panel width: 300 → 250)
    renderer.mouse_move(panel_left_edge + 50.0, edge_y)
    renderer.render_frame(app)

    # Verify MenuBar width shrinks to match panel width during drag
    menubar.bounds.width.should eq(panel.width)
  end
end
