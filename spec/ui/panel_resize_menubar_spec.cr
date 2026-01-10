require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for panel resize with menubar children
#
# BUG: When panel is resized (enlarged), menubar inside doesn't extend its width.
# The menubar only updates after another event (like clicking panel titlebar).
#
# Root cause: on_mouse_up after resize doesn't trigger layout_children,
# so menubar keeps its old width even though panel is larger.

describe "Panel Resize with MenuBar" do
  it "menubar extends immediately after panel resize (no extra click needed)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with menubar inside
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)
    initial_menubar_width = menubar.bounds.width
    initial_menubar_width.should eq(300.0)  # Initial width

    # Resize panel wider: 300px -> 400px
    panel_right_edge = 100.0 + 300.0  # x=100, width=300
    renderer.mouse_down(panel_right_edge, 150.0)  # Start resize on right edge
    renderer.render_frame(app)

    # Drag to extend panel by 100px
    renderer.mouse_move(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    # Mouse up to end resize
    renderer.mouse_up(panel_right_edge + 100.0, 150.0)
    renderer.render_frame(app)

    # MenuBar should span full panel width (edge-to-edge)
    panel.width.should eq(400.0)  # Panel did resize
    menubar.bounds.width.should eq(400.0)  # MenuBar = panel_width (edge-to-edge)
  end

  it "menubar position correct after panel resize from left edge" do
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

    # Resize from left edge (panel position changes)
    panel_left_edge = 100.0
    renderer.mouse_down(panel_left_edge, 150.0)
    renderer.render_frame(app)

    # Drag left edge inward (shrink) by 50px
    renderer.mouse_move(panel_left_edge + 50.0, 150.0)
    renderer.render_frame(app)

    renderer.mouse_up(panel_left_edge + 50.0, 150.0)
    renderer.render_frame(app)

    # Panel should be at x=150, width=250
    panel.x.should eq(150.0)
    panel.width.should eq(250.0)

    # MenuBar should span full panel width (edge-to-edge)
    menubar.bounds.width.should eq(250.0)  # MenuBar = panel_width (edge-to-edge)
  end
end
