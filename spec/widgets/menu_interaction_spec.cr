require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for menu interaction behaviors
# Issue (b): Hover-to-open between neighboring menus after clicking one
# Issue (c): MenuItem hover highlighting clearing on mouse exit

describe "Menu Interaction" do
  describe "Issue (b): Hover-to-open between neighboring menus" do
    it "MenuBar preserves menu_system_active state across rebuilds" do
      # Create old menubar with menu system active
      old_menubar = CrymbleUI::MenuBar.new
      old_menubar.activate_menu_system
      old_menubar.menu_system_active.should be_true

      # Create new menubar (simulating rebuild)
      new_menubar = CrymbleUI::MenuBar.new
      new_menubar.menu_system_active.should be_false  # Not active yet

      # Copy state from old to new (what reconciliation does)
      new_menubar.copy_state_from(old_menubar)

      # State should be preserved
      new_menubar.menu_system_active.should be_true
    end

    it "does not auto-open menus on hover if menu system is not active" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new

      menu1 = CrymbleUI::Menu.new("File")
      menu2 = CrymbleUI::Menu.new("Edit")

      menubar.add_child(menu1)
      menubar.add_child(menu2)
      window.add_child(menubar)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Hover over menu without clicking first
      menu1.on_mouse_enter

      # Menu should NOT open (menu system not active)
      menu1.open?.should be_false
      menubar.menu_system_active.should be_false
    end

    it "deactivates menu system when all menus are closed" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new

      menu1 = CrymbleUI::Menu.new("File")
      menubar.add_child(menu1)
      window.add_child(menubar)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Click to open menu (activates system)
      menu1.on_click
      menubar.menu_system_active.should be_true

      # Click again to close menu (should deactivate system)
      menu1.on_click
      menu1.open?.should be_false
      menubar.menu_system_active.should be_false
    end
  end

  describe "Menu closing behavior" do
    it "closes menu when non-checkable item is clicked" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("File")

      # Regular non-checkable item
      item = CrymbleUI::MenuItem.new("Save")
      menu.add_child(item)

      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Open menu
      menu.on_click
      menu.open?.should be_true

      # Click the menu item (non-checkable)
      item.on_click

      # Menu should close
      menu.open?.should be_false
    end

    it "keeps menu open when checkable item is clicked" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("View")

      # Checkable item
      item = CrymbleUI::MenuItem.new("Show Toolbar", checkable: true)
      menu.add_child(item)

      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Open menu
      menu.on_click
      menu.open?.should be_true

      # Click the checkable menu item
      item.on_click

      # Menu should stay open
      menu.open?.should be_true
    end
  end

  describe "Issue (c): MenuItem hover highlighting clearing" do
    it "clears MenuItem highlighting when mouse exits (pixel test)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new

      # Create menu with item using specific colors
      # MenuItem doesn't have background_color - it's transparent when not hovered
      # The "background" is the Popup's background_color
      popup_bg = CrymbleUI::Color.new(255, 255, 255, 255)
      item_hover = CrymbleUI::Color.new(100, 150, 250, 255)

      menu = CrymbleUI::Menu.new("File")
      item = CrymbleUI::MenuItem.new("New",
        hover_color: item_hover
      )
      menu.add_child(item)
      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Open the menu
      menu.on_click
      renderer.render_frame(app)

      # Get popup layer for pixel testing
      popups = window.find_all_popups
      popups.size.should eq(1)
      popup = popups.first
      popup_layer = popup.layer.not_nil!
      backend = popup_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

      # Get pixel in center of menu item
      item_center_x = (item.bounds.x + item.bounds.width / 2).to_i
      item_center_y = (item.bounds.y + item.bounds.height / 2).to_i

      # Before hover - should be popup background color (item is transparent)
      pixel_before = backend.get_pixel(item_center_x, item_center_y)
      pixel_before.should eq(popup_bg)

      # Simulate hover
      item.on_mouse_enter
      renderer.render_frame(app)

      # During hover - should be hover color
      pixel_hover = backend.get_pixel(item_center_x, item_center_y)
      pixel_hover.should eq(item_hover)

      # Simulate mouse exit
      item.on_mouse_exit
      renderer.render_frame(app)

      # After exit - should return to popup background color (item is transparent again)
      pixel_after = backend.get_pixel(item_center_x, item_center_y)
      pixel_after.should eq(popup_bg)
    end

    it "marks MenuItem as needing render on mouse exit" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("File")
      item = CrymbleUI::MenuItem.new("New")

      menu.add_child(item)
      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Open menu to create popup
      menu.on_click

      # Find popup layer
      popups = window.find_all_popups
      popups.size.should eq(1)
      popup = popups.first
      popup_layer = popup.layer.not_nil!
      # Render the item so its pull-node + layer-enqueue (on_dirty) exist. Reactive
      # re-render is edge-triggered on the captured `hovered`, so each hover change
      # needs the node freshly valid first (the old code marked unconditionally).
      item.get_primitives(item.bounds)
      popup_layer.clear_render_state

      # Hover over item
      item.on_mouse_enter
      popup_layer.needs_render?.should be_true

      item.get_primitives(item.bounds) # re-render so the exit produces a fresh stale edge
      popup_layer.clear_render_state

      # Mouse exit should mark layer for render
      item.on_mouse_exit
      popup_layer.needs_render?.should be_true
      popup_layer.dirty_widgets.should contain(item)
    end
  end
end
