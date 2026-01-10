require "../spec_helper"
require "../../src/input/focus_flash_controller"

# Helper to create a focusable test widget
class FlashTestWidget < CrymbleUI::Widget
  property render_called : Int32 = 0

  def initialize(id : String)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)
  end

  def focusable? : Bool
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 30.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100.0, 30.0)
  end

  def mark_needs_render
    @render_called += 1
    super
  end
end

describe CrymbleUI::FocusFlashController do
  describe "#start_flash" do
    it "sets focus_highlighted to true initially (immediate visual feedback)" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)

      widget.focus_highlighted?.should be_true
    end

    it "schedules a repeating timer" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)

      controller.timer_running?.should be_true
    end
  end

  describe "#stop_flash" do
    it "sets focus_highlighted to false" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)
      widget.focus_highlighted = true  # Simulate toggle
      controller.stop_flash(widget)

      widget.focus_highlighted?.should be_false
    end

    it "cancels the timer" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)
      controller.stop_flash(widget)

      controller.timer_running?.should be_false
    end

    it "does nothing for non-current widget" do
      controller = CrymbleUI::FocusFlashController.new
      widget1 = FlashTestWidget.new("test1")
      widget2 = FlashTestWidget.new("test2")

      controller.start_flash(widget1)
      controller.stop_flash(widget2)  # Different widget

      controller.timer_running?.should be_true  # Timer still running
    end
  end

  describe "#toggle_flash" do
    it "toggles focus_highlighted from true to false (first toggle)" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)  # Starts true
      controller.toggle_flash         # true -> false

      widget.focus_highlighted?.should be_false
    end

    it "toggles focus_highlighted back to true (second toggle)" do
      controller = CrymbleUI::FocusFlashController.new
      widget = FlashTestWidget.new("test")

      controller.start_flash(widget)  # Starts true
      controller.toggle_flash         # true -> false
      controller.toggle_flash         # false -> true

      widget.focus_highlighted?.should be_true
    end
  end

  describe "switching widgets" do
    it "stops flash on old widget when starting new" do
      controller = CrymbleUI::FocusFlashController.new
      widget1 = FlashTestWidget.new("test1")
      widget2 = FlashTestWidget.new("test2")

      controller.start_flash(widget1)  # widget1 starts highlighted

      controller.start_flash(widget2)  # Switch to widget2

      widget1.focus_highlighted?.should be_false  # Old widget reset
      widget2.focus_highlighted?.should be_true   # New widget starts highlighted
    end
  end

  describe "flash period" do
    it "has 300ms half-period (0.6s full cycle)" do
      CrymbleUI::FocusFlashController::FLASH_HALF_MS.should eq(300)
    end
  end
end
