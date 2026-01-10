require "../spec_helper"
require "../../src/input/focus_manager"
require "../../src/input/focus_flash_controller"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"

# Test that clicking on a focusable widget starts the flash animation
# User bug report: Arrow navigation starts flash, but clicking doesn't
describe "Focus click-to-flash" do
  describe "simulated click flow" do
    it "starts flash when focus() is called on focusable widget" do
      # Create fresh FocusManager for isolated test
      fm = CrymbleUI::FocusManager.new

      # Create a focusable widget (button)
      button = CrymbleUI::Button.new("Test") { }
      button.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Verify button is focusable
      button.focusable?.should be_true

      # Simulate what SFMLRenderer.handle_mouse_down does:
      # After hit_test returns widget, it calls focus_manager.focus(widget)
      fm.focus(button)

      # Verify focus was set
      fm.focused_widget.should eq(button)

      # Check that focus_highlighted starts as true (immediate visual feedback)
      # The flash controller schedules a timer to toggle this every 300ms
      button.focus_highlighted?.should be_true
    end

    it "schedules timer when widget is focused" do
      # Create fresh FocusManager with its own flash controller
      fm = CrymbleUI::FocusManager.new

      button = CrymbleUI::Button.new("Test") { }
      button.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Focus should schedule flash timer via flash_controller.start_flash()
      fm.focus(button)

      # The scheduler should have at least one timer now
      CrymbleUI::Widget.scheduler.not_nil!.has_timers?.should be_true
    end
  end

  describe "full click simulation with hit_test" do
    it "focuses button when clicked within bounds" do
      fm = CrymbleUI::FocusManager.new

      # Create a simple widget tree: VStack with button
      root = CrymbleUI::VStack.new
      button = CrymbleUI::Button.new("Clickable") { }
      root.add_child(button)

      # Layout at known position
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      root.layout(constraints, CrymbleUI::Vec2.zero)

      # Get button's center position for click
      button_bounds = button.absolute_bounds
      click_x = button_bounds.x + button_bounds.width / 2
      click_y = button_bounds.y + button_bounds.height / 2
      click_point = CrymbleUI::Vec2.new(click_x, click_y)

      # Simulate what SFMLRenderer.handle_mouse_down does:
      # 1. Call hit_test to find widget under click
      hit_widget = root.hit_test(click_point)

      # 2. If focusable, focus it
      hit_widget.should_not be_nil
      hit_widget.should eq(button)

      if hit_widget && hit_widget.focusable?
        fm.focus(hit_widget)
      end

      # Verify button got focus and flash started
      fm.focused_widget.should eq(button)
      button.focus_highlighted?.should be_true  # Flash starts highlighted (immediate feedback)
    end

    it "hit_test returns button (not parent) for nested widget" do
      # Create nested structure: VStack -> HStack -> Button
      vstack = CrymbleUI::VStack.new
      hstack = CrymbleUI::HStack.new
      button = CrymbleUI::Button.new("Nested") { }

      hstack.add_child(button)
      vstack.add_child(hstack)

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      vstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Click at button center
      button_bounds = button.absolute_bounds
      click_point = CrymbleUI::Vec2.new(
        button_bounds.x + button_bounds.width / 2,
        button_bounds.y + button_bounds.height / 2
      )

      hit_widget = vstack.hit_test(click_point)

      # Should return the button, not VStack or HStack
      hit_widget.should eq(button)
    end
  end

  describe "rebuild scenario (focus loss bug)" do
    it "preserves focus on widget after rebuild" do
      fm = CrymbleUI::FocusManager.new
      scheduler = CrymbleUI::Widget.scheduler.not_nil!

      # Setup: button that we will focus
      button1 = CrymbleUI::Button.new("Old", id: "btn") { }
      button1.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Focus button1
      fm.focus(button1)
      fm.focused_widget.should eq(button1)

      # Simulate what happens during rebuild: new button with same id
      button2 = CrymbleUI::Button.new("New", id: "btn") { }
      button2.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Transfer focus from old to new (what copy_state_from should do for focusables)
      fm.transfer_focus(button1, button2)

      # Focus should now be on button2
      fm.focused_widget.should eq(button2)

      # And flash should still be running (timer was scheduled on focus)
      scheduler.has_timers?.should be_true
    end

    it "Widget.copy_state_from should transfer focus if widget was focused" do
      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm  # Set global so widgets can access

      old_button = CrymbleUI::Button.new("Old", id: "btn") { }
      old_button.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Focus old button
      fm.focus(old_button)
      fm.focused_widget.should eq(old_button)

      # Create new button and copy state
      new_button = CrymbleUI::Button.new("New", id: "btn") { }
      new_button.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)
      new_button.copy_state_from(old_button)

      # BUG: This will fail because Widget.copy_state_from doesn't transfer focus
      # Focus should have been transferred to new_button
      fm.focused_widget.should eq(new_button)
    end
  end

  describe "WindowPanel scenario (panels_demo reproduction)" do
    it "hit_test returns button inside panel content" do
      # Create structure similar to panels_demo: Window -> WindowPanel -> Button
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click Me") { }

      panel.add_child(button)
      window.add_child(panel)

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Get button's absolute bounds
      button_bounds = button.absolute_bounds

      # Click at button center
      click_point = CrymbleUI::Vec2.new(
        button_bounds.x + button_bounds.width / 2,
        button_bounds.y + button_bounds.height / 2
      )

      # hit_test from window should return the button
      hit_widget = window.hit_test(click_point)

      # If this fails, the click is being intercepted by panel chrome/content
      hit_widget.should eq(button)
    end

    it "button inside panel is focusable via simulated click" do
      fm = CrymbleUI::FocusManager.new

      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click Me") { }

      panel.add_child(button)
      window.add_child(panel)

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Simulate click at button center
      button_bounds = button.absolute_bounds
      click_point = CrymbleUI::Vec2.new(
        button_bounds.x + button_bounds.width / 2,
        button_bounds.y + button_bounds.height / 2
      )

      # Replicate SFMLRenderer.handle_mouse_down logic:
      if hit_widget = window.hit_test(click_point)
        if hit_widget.focusable?
          fm.focus(hit_widget)
        end
      end

      # Button should have focus
      fm.focused_widget.should eq(button)
    end
  end
end
