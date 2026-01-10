require "../spec_helper"

# TEST: MenuBar vertical padding placement
#
# BUG: Current implementation adds CONTENT_PADDING between title bar and MenuBar
# Expected: Padding should be BELOW MenuBar (between MenuBar and content), not above
# Actual: Padding is above MenuBar (between title bar and MenuBar)
#
# Correct layout:
# - Title bar: Y=0, height=30
# - MenuBar: Y=30 (flush with title bar), height=28
# - Content: Y=58+8=66 (MenuBar bottom + CONTENT_PADDING)
#
# Current WRONG layout:
# - Title bar: Y=0, height=30
# - MenuBar: Y=38 (title bar + 8px gap ✗)
# - Content: Y=66 (MenuBar bottom, no padding ✗)
#
# This test documents the current WRONG behavior and should FAIL.

describe "MenuBar vertical padding" do
  it "menubar is flush with title bar, padding is BELOW menubar" do
    # Setup: Window → WindowPanel → MenuBar → Button
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 100.0, 300.0, 250.0)

    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    button = CrymbleUI::Button.new("Click")

    panel.add_child(menubar)
    panel.add_child(button)
    window.add_child(panel)

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    # Check positions

    # PART 1: MenuBar should be flush with title bar (no gap above)
    # Expected MenuBar Y = panel.y + title_bar_height
    expected_menubar_y = 100.0 + panel.title_bar_height

    menubar_abs = menubar.absolute_bounds

    # BUG: This will FAIL - current Y = 138.0 (has 8px gap above)
    menubar_abs.y.should eq(expected_menubar_y)  # Should be 130.0, actually 138.0
  end

  it "content below menubar has vertical padding" do
    # PART 2: Content BELOW MenuBar should have CONTENT_PADDING gap
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 100.0, 300.0, 250.0)

    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    button = CrymbleUI::Button.new("Click")

    panel.add_child(menubar)
    panel.add_child(button)
    window.add_child(panel)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    menubar_abs = menubar.absolute_bounds
    button_abs = button.absolute_bounds


    # Expected: Button Y = MenuBar bottom + CONTENT_PADDING
    # If MenuBar is at Y=130, height=28, then MenuBar bottom = 158
    # Button should be at Y = 158 + 8 = 166
    expected_button_y = menubar_abs.y + menubar_abs.height + CrymbleUI::WindowPanel::CONTENT_PADDING

    # BUG: This will likely FAIL - current implementation doesn't add padding below MenuBar
    button_abs.y.should eq(expected_button_y)
  end

  it "panel without menubar still has vertical padding for content" do
    # This test verifies that panels WITHOUT MenuBar correctly use CONTENT_PADDING
    # This should PASS (documents correct behavior for comparison)

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 100.0, 300.0, 250.0)

    # Add a button (not a menubar) as content
    button = CrymbleUI::Button.new("Click me")
    panel.add_child(button)
    window.add_child(panel)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)


    # Content (button) should have CONTENT_PADDING below title bar
    # Button Y = panel.y + title_bar_height + CONTENT_PADDING
    expected_y = 100.0 + panel.title_bar_height + CrymbleUI::WindowPanel::CONTENT_PADDING

    button_abs = button.absolute_bounds
    button_abs.y.should eq(expected_y)  # This should PASS (138.0)
  end
end
