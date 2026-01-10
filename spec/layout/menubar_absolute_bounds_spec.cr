require "../spec_helper"

describe "MenuBar absolute bounds in WindowPanel" do
  it "calculates correct absolute position for menu popup" do
    # Setup: Window → WindowPanel → MenuBar → Menu
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 100.0, 300.0, 250.0)

    # Create menubar with a menu (manually, without DSL)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    # Check bounds at each level

    # Expected absolute positions:
    # Window: (0, 0)
    # Panel: (50, 100) - uses @x, @y (absolute)
    # MenuBar: (0, TITLE_BAR_HEIGHT) relative to panel (flush with title bar)
    #        = (50, 100+30) = (50, 130) absolute
    # Menu: (0, 0) relative to menubar
    #     = (50, 130) absolute

    # Verify MenuBar absolute position
    menubar_abs = menubar.absolute_bounds
    menubar_abs.x.should eq(50.0)
    menubar_abs.y.should eq(130.0)  # panel.y (100) + TITLE_BAR_HEIGHT (30) - flush with title bar

    # Verify Menu absolute position
    menu_abs = menu.absolute_bounds
    menu_abs.x.should eq(50.0)
    menu_abs.y.should eq(130.0)  # Same as menubar (menu is at 0,0 within menubar)

    # If menu opens a popup, it should appear at:
    # x = menu_abs.x = 50
    # y = menu_abs.y + menu_abs.height = 130 + 28 = 158
    expected_popup_x = 50.0
    expected_popup_y = 130.0 + menu_abs.height


    # This is what Menu.layout does:
    # popup_widget.x = abs_bounds.x
    # popup_widget.y = abs_bounds.y + abs_bounds.height
    popup_x = menu_abs.x
    popup_y = menu_abs.y + menu_abs.height

    popup_x.should eq(expected_popup_x)
    popup_y.should eq(expected_popup_y)
  end

  it "calculates correct absolute position for second menu" do
    # Test with multiple menus to verify x offset works
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 100.0, 300.0, 250.0)

    menubar = CrymbleUI::MenuBar.new
    menu1 = CrymbleUI::Menu.new("File")
    menu2 = CrymbleUI::Menu.new("Edit")
    menubar.add_child(menu1)
    menubar.add_child(menu2)
    panel.add_child(menubar)
    window.add_child(panel)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)


    # Menu2 should be positioned after Menu1
    menu2_abs = menu2.absolute_bounds
    menu2_abs.x.should be > 50.0  # Should be offset by menu1.width
    menu2_abs.y.should eq(130.0)  # Same y as menu1
  end
end
