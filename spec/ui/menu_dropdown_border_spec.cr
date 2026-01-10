require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for Menu dropdown (Popup) border rendering
#
# BUG: Menu dropdown (Popup widget) doesn't render border around the dropdown panel.
# Popup.to_primitives calls draw_rect() to draw border, but it may not be executing.
#
# Expected: Dropdown should have border around all four edges
# Actual: No border visible around dropdown

# TestApp that builds correct window structure for menu dropdown tests
class MenuDropdownTestApp < CrymbleUI::App
  getter panel : CrymbleUI::WindowPanel?
  getter menubar : CrymbleUI::MenuBar?
  getter menu : CrymbleUI::Menu?

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")

    # Add menu items
    item1 = CrymbleUI::MenuItem.new("New", "Ctrl+N") { }
    item2 = CrymbleUI::MenuItem.new("Open", "Ctrl+O") { }
    menu.add_child(item1)
    menu.add_child(item2)

    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)

    @panel = panel
    @menubar = menubar
    @menu = menu

    window
  end
end

# TestApp for multi-item dropdown test
class MultiItemMenuApp < CrymbleUI::App
  getter menu : CrymbleUI::Menu?

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("Edit")

    # Add many items to create larger dropdown
    5.times do |i|
      item = CrymbleUI::MenuItem.new("Item #{i}", "") { }
      menu.add_child(item)
    end

    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)
    @menu = menu
    window
  end
end

describe "Menu Dropdown Border" do
  it "dropdown has border around entire perimeter" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuDropdownTestApp.new
    app.rebuild  # Build the widget tree
    menu = app.menu.not_nil!

    # Initial render
    renderer.render_frame(app)

    # Click on "File" menu to open dropdown
    # Menu is at panel position (100, 100) + title bar height (30) = y=130
    # Menu x position is approximately 108 (panel x + content padding)
    menu_x = 120.0
    menu_y = 145.0  # Middle of menu button

    renderer.mouse_down(menu_x, menu_y)
    renderer.render_frame(app)
    renderer.mouse_up(menu_x, menu_y)
    renderer.render_frame(app)

    # Verify menu opened
    menu.open?.should be_true

    # Get the popup (dropdown) from window overlays (added when menu opens)
    window = app.root.as(CrymbleUI::Window)
    popup = window.overlays.find { |c| c.is_a?(CrymbleUI::Popup) }
    popup.should_not be_nil
    popup = popup.as(CrymbleUI::Popup)

    # Verify popup generates border primitive
    primitives = popup.to_primitives(popup.bounds)
    has_border = primitives.any? { |p| p.is_a?(CrymbleUI::DrawRect) }
    has_border.should be_true

    # Now check if border is VISIBLE in final composited window output
    # Get window backend (final composited output visible to user)
    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Popup position in window coordinates
    popup_abs = popup.absolute_bounds
    popup_x = popup_abs.x.to_i
    popup_y = popup_abs.y.to_i
    popup_width = popup_abs.width.to_i
    popup_height = popup_abs.height.to_i

    border_color = popup.border_color

    # Check if border pixels are visible in window buffer (top edge)
    top_left = window_backend.get_pixel(popup_x, popup_y)
    top_middle = window_backend.get_pixel(popup_x + (popup_width / 2).to_i, popup_y)
    top_right = window_backend.get_pixel(popup_x + popup_width - 1, popup_y)

    # BUG: These should be border_color but may be background or transparent
    top_left.should eq(border_color)
    top_middle.should eq(border_color)
    top_right.should eq(border_color)
  end

  it "dropdown border visible with multiple menu items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MultiItemMenuApp.new
    app.rebuild
    menu = app.menu.not_nil!

    # Initial render
    renderer.render_frame(app)

    # Click on "Edit" menu to open dropdown
    menu_x = 120.0
    menu_y = 145.0

    renderer.mouse_down(menu_x, menu_y)
    renderer.render_frame(app)
    renderer.mouse_up(menu_x, menu_y)
    renderer.render_frame(app)

    # Verify menu opened
    menu.open?.should be_true

    # Get the popup from window overlays
    window = app.root.as(CrymbleUI::Window)
    popup = window.overlays.find { |c| c.is_a?(CrymbleUI::Popup) }
    popup.should_not be_nil
    popup = popup.as(CrymbleUI::Popup)

    # Verify popup generates border primitive
    primitives = popup.to_primitives(popup.bounds)
    has_border = primitives.any? { |p| p.is_a?(CrymbleUI::DrawRect) }
    has_border.should be_true

    # Popup should be reasonably tall with 5 items
    popup.bounds.height.should be > 100

    # Check if border is VISIBLE in final composited window output
    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Popup position in window coordinates
    popup_abs = popup.absolute_bounds
    popup_x = popup_abs.x.to_i
    popup_y = popup_abs.y.to_i
    popup_width = popup_abs.width.to_i

    border_color = popup.border_color

    # Check if border is visible (all four corners)
    top_left = window_backend.get_pixel(popup_x, popup_y)
    top_right = window_backend.get_pixel(popup_x + popup_width - 1, popup_y)

    top_left.should eq(border_color)
    top_right.should eq(border_color)
  end
end
