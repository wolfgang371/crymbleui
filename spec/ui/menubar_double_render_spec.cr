require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for detecting double-rendering in dropdown menus
#
# BUG: MenuItem children are added to popup's layer.widgets AND rendered
# recursively as Popup's children, causing 2x rendering (visible as "bold").
#
# Root cause: In popup.cr line 150:
#   @children.each { |child| layer.widgets << child }
#
# This causes each MenuItem to be rendered twice:
# 1. As recursive child when Popup is rendered (via render_widget_to_backend recursion)
# 2. As explicit layer.widgets entry (explicit render)
#
# Same issue in menubar.cr line 139 for panel menubars.
#
# To verify visually: Run examples/menubar_demo.cr and click any menu.
# The dropdown menu items will appear "bold" initially, then normal after hover.

describe "Menu Dropdown Double Rendering Detection" do
  it "popup layer.widgets should contain only popup, not its children (prevents double-rendering)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create menubar with menu containing 3 menu items
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")

    # Add 3 menu items to the menu
    item1 = CrymbleUI::MenuItem.new("New", "Ctrl+N")
    item2 = CrymbleUI::MenuItem.new("Open", "Ctrl+O")
    item3 = CrymbleUI::MenuItem.new("Save", "Ctrl+S")

    menu.add_child(item1)
    menu.add_child(item2)
    menu.add_child(item3)

    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window

    # Initial render (menu closed)
    renderer.render_frame(app)

    # Click menu to open dropdown
    menu_center_x = menu.absolute_bounds.x + menu.absolute_bounds.width / 2
    menu_center_y = menu.absolute_bounds.y + menu.absolute_bounds.height / 2
    renderer.mouse_down(menu_center_x, menu_center_y)
    renderer.mouse_up(menu_center_x, menu_center_y)

    # Find the popup that was created (now in overlays, not children)
    popup = window.overlays.find { |c| c.is_a?(CrymbleUI::Popup) }
    popup.should_not be_nil
    popup = popup.as(CrymbleUI::Popup)

    # Get popup layer
    popup_layer = popup.layer.not_nil!

    # BUG: layer.widgets contains popup AND its children (MenuItems)
    # This causes double-rendering:
    # - When popup is rendered, it recursively renders children
    # - Then children are rendered again as explicit layer.widgets entries
    #
    # Expected: layer.widgets = [popup]
    # Bug: layer.widgets = [popup, item1, item2, item3]

    popup_layer.widgets.should eq([popup])  # Should ONLY contain popup, not children
  end

  it "panel menubar layer.widgets should contain only menubar, not menu children" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with menubar (menubar uses panel's layer)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 400.0, 300.0)
    menubar = CrymbleUI::MenuBar.new

    menu1 = CrymbleUI::Menu.new("File")
    menu2 = CrymbleUI::Menu.new("Edit")
    menu3 = CrymbleUI::Menu.new("View")

    menubar.add_child(menu1)
    menubar.add_child(menu2)
    menubar.add_child(menu3)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # Get panel layer (menubar uses this layer)
    panel_layer = panel.layer.not_nil!

    # BUG: For panel menubar, layer.widgets contains menus as separate entries
    # This happens at menubar.cr line 139:
    #   @children.each { |child| layer.widgets << child }
    #
    # This causes double-rendering:
    # - When menubar is rendered (from layer.widgets), it recursively renders menu children
    # - Then menus are rendered again as explicit layer.widgets entries
    #
    # Expected: Menus should NOT be in layer.widgets (only rendered recursively)
    # Bug: layer.widgets contains both menubar AND menus

    # Check that menus are NOT in layer.widgets
    panel_layer.widgets.should_not contain(menu1)
    panel_layer.widgets.should_not contain(menu2)
    panel_layer.widgets.should_not contain(menu3)
  end
end
