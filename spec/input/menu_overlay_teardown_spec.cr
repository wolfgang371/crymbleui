require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/menubar"
require "../../src/widgets/menu"

# Regression guards. close_all_menus and is_inside_popup_or_menu?
# are TWO DIFFERENT predicate sets — conflating them into one capability silently
# changes behaviour, and the rest of the suite does not cover these two cases:
#   1. A click on the MenuBar BACKGROUND (not a button) must CLOSE an open menu — the
#      menubar is NOT a "click-inside overlay surface". If it were, close_all_menus
#      would be skipped and the menu system would stay active.
#   2. ESC must NOT tear down a standalone Popup — only menus/menubars are dismissable.

private def fresh(width = 800, height = 600)
  renderer = CrymbleUI::Testing::TestRenderer.new(width, height)
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", width, height)
  {renderer, app, window}
end

describe "menu/overlay teardown" do
  it "closes an open menu when the MenuBar BACKGROUND is clicked" do
    renderer, app, window = fresh
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window
    renderer.render_frame(app)

    menu.on_click
    menu.open?.should be_true
    menubar.menu_system_active.should be_true

    # Click the bar background, far to the right of the "File" button (still on the bar,
    # not on the dropdown which hangs below the button on the left).
    app.handle_mouse_down(CrymbleUI::Vec2.new(700.0, 3.0))

    # menu_system_active is reset ONLY by close_all_menus (deactivate_menu_system), so it
    # is the discriminating assertion: if the bar were treated as a click-inside surface,
    # close_all_menus would be skipped and this would stay true.
    menubar.menu_system_active.should be_false
    menu.open?.should be_false
  end

  it "keeps the two overlay capabilities as DISTINCT sets (the whole point of cluster C)" do
    menu = CrymbleUI::Menu.new("File")
    menubar = CrymbleUI::MenuBar.new
    popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)

    # Dismissable = the teardown set: an outside-click / ESC closes these. {Menu, MenuBar}
    # — NEVER a Popup (so ESC leaves a standalone popup open).
    menu.is_a?(CrymbleUI::Dismissable).should be_true
    menubar.is_a?(CrymbleUI::Dismissable).should be_true
    popup.is_a?(CrymbleUI::Dismissable).should be_false

    # OverlaySurface = the click-inside set: a click inside these is not a dismiss gesture.
    # {Popup, Menu} — NEVER a MenuBar (so a menubar-background click DOES dismiss menus).
    popup.is_a?(CrymbleUI::OverlaySurface).should be_true
    menu.is_a?(CrymbleUI::OverlaySurface).should be_true
    menubar.is_a?(CrymbleUI::OverlaySurface).should be_false
  end
end
