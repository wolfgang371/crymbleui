require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/menubar"
require "../../src/widgets/statusbar"
require "../../src/testing/test_renderer"

# Maximizing a window panel must not cover the statusbar. panel_area_bounds
# already excludes the menubar (line 296 of window.cr) but the symmetric
# treatment for the statusbar was missing — maximized panels filled to the
# very bottom of the window, hiding the statusbar.
private class MaxApp < CrymbleUI::App
  property panel : CrymbleUI::WindowPanel? = nil

  def build : CrymbleUI::Widget
    win = CrymbleUI::Window.new("max-test", 800, 600)
    mb = CrymbleUI::MenuBar.new
    win.add_child(mb)
    sb = CrymbleUI::StatusBar.new("ready", id: "sb")
    win.add_child(sb)
    p = CrymbleUI::WindowPanel.new("Panel", x: 50.0, y: 50.0, width: 200.0, height: 100.0, id: "panel")
    @panel = p
    win.add_child(p)
    win
  end
end

describe "Maximized panel must not cover statusbar" do
  it "panel_area_bounds excludes statusbar height" do
    app = MaxApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    win = app.root.as(CrymbleUI::Window)
    sb = win.children.find { |c| c.is_a?(CrymbleUI::StatusBar) }.not_nil!
    panel_area = win.panel_area_bounds

    # Panel area's bottom edge must stop ABOVE the statusbar's top.
    panel_area_bottom = panel_area.y + panel_area.height
    sb_top = sb.bounds.y
    panel_area_bottom.should be <= sb_top
  end

  it "maximized panel doesn't overlap statusbar after maximize" do
    app = MaxApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    panel = app.as(MaxApp).panel.not_nil!
    panel.toggle_maximize
    renderer.settle_rendering(app)

    win = app.root.as(CrymbleUI::Window)
    sb = win.children.find { |c| c.is_a?(CrymbleUI::StatusBar) }.not_nil!
    panel_bottom = panel.bounds.y + panel.bounds.height
    sb_top = sb.bounds.y
    panel_bottom.should be <= sb_top
  end
end
