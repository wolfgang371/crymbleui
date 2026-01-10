require "../spec_helper"
require "../../src/input/focus_navigator"
require "../../src/input/focus_cycler"
require "../../src/input/focus_flash_controller"

# Test widget for focus navigation
class NavTestWidget < CrymbleUI::Widget
  property clicked : Bool = false

  def initialize(id : String, x : Float64, y : Float64, @is_focusable : Bool = true)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(x, y, 100.0, 30.0)
  end

  def focusable? : Bool
    @is_focusable
  end

  def absolute_bounds : CrymbleUI::Rect
    @bounds
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 30.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100.0, 30.0)
  end

  def trigger_click
    @clicked = true
  end
end

# Container widget for testing
class NavContainerWidget < CrymbleUI::Widget
  def initialize(id : String? = nil)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(0.0, 0.0, 500.0, 500.0)
  end

  def add_test_child(child : CrymbleUI::Widget)
    add_child(child)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(500.0, 500.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 500.0, 500.0)
  end
end

describe CrymbleUI::FocusManager do
  describe "#cycle_focus" do
    it "focuses first widget when no current focus (Tab)" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      btn1 = NavTestWidget.new("btn1", 0.0, 0.0)
      btn2 = NavTestWidget.new("btn2", 0.0, 50.0)
      root.add_test_child(btn1)
      root.add_test_child(btn2)

      fm.cycle_focus(forward: true, root: root)

      fm.focused_widget.should eq(btn1)
    end

    it "moves to next widget on Tab" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      btn1 = NavTestWidget.new("btn1", 0.0, 0.0)
      btn2 = NavTestWidget.new("btn2", 0.0, 50.0)
      root.add_test_child(btn1)
      root.add_test_child(btn2)

      fm.focus(btn1)
      fm.cycle_focus(forward: true, root: root)

      fm.focused_widget.should eq(btn2)
    end

    it "moves to previous widget on Shift+Tab" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      btn1 = NavTestWidget.new("btn1", 0.0, 0.0)
      btn2 = NavTestWidget.new("btn2", 0.0, 50.0)
      root.add_test_child(btn1)
      root.add_test_child(btn2)

      fm.focus(btn2)
      fm.cycle_focus(forward: false, root: root)

      fm.focused_widget.should eq(btn1)
    end

    it "wraps around at end" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      btn1 = NavTestWidget.new("btn1", 0.0, 0.0)
      btn2 = NavTestWidget.new("btn2", 0.0, 50.0)
      root.add_test_child(btn1)
      root.add_test_child(btn2)

      fm.focus(btn2)
      fm.cycle_focus(forward: true, root: root)

      fm.focused_widget.should eq(btn1)
    end
  end

  describe "#navigate" do
    it "navigates down to widget below" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      top = NavTestWidget.new("top", 100.0, 50.0)
      bottom = NavTestWidget.new("bottom", 100.0, 100.0)
      root.add_test_child(top)
      root.add_test_child(bottom)

      fm.focus(top)
      fm.navigate(:down, root: root)

      fm.focused_widget.should eq(bottom)
    end

    it "navigates up to widget above" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      top = NavTestWidget.new("top", 100.0, 50.0)
      bottom = NavTestWidget.new("bottom", 100.0, 100.0)
      root.add_test_child(top)
      root.add_test_child(bottom)

      fm.focus(bottom)
      fm.navigate(:up, root: root)

      fm.focused_widget.should eq(top)
    end

    it "navigates right to widget on right" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      left = NavTestWidget.new("left", 50.0, 100.0)
      right = NavTestWidget.new("right", 200.0, 100.0)
      root.add_test_child(left)
      root.add_test_child(right)

      fm.focus(left)
      fm.navigate(:right, root: root)

      fm.focused_widget.should eq(right)
    end

    it "navigates left to widget on left" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      left = NavTestWidget.new("left", 50.0, 100.0)
      right = NavTestWidget.new("right", 200.0, 100.0)
      root.add_test_child(left)
      root.add_test_child(right)

      fm.focus(right)
      fm.navigate(:left, root: root)

      fm.focused_widget.should eq(left)
    end

    it "does nothing when no widget in direction" do
      fm = CrymbleUI::FocusManager.new

      root = NavContainerWidget.new("root")
      only = NavTestWidget.new("only", 100.0, 100.0)
      root.add_test_child(only)

      fm.focus(only)
      fm.navigate(:up, root: root)

      fm.focused_widget.should eq(only)  # Still focused on same widget
    end
  end

  describe "#handle_activation_key" do
    it "triggers click on focused button (Enter)" do
      fm = CrymbleUI::FocusManager.new

      btn = NavTestWidget.new("btn", 0.0, 0.0)
      fm.focus(btn)

      fm.handle_activation_key(:enter)

      btn.clicked.should be_true
    end

    it "triggers click on focused button (Space)" do
      fm = CrymbleUI::FocusManager.new

      btn = NavTestWidget.new("btn", 0.0, 0.0)
      fm.focus(btn)

      fm.handle_activation_key(:space)

      btn.clicked.should be_true
    end

    it "does nothing when no widget focused" do
      fm = CrymbleUI::FocusManager.new

      # Should not raise
      fm.handle_activation_key(:enter)
    end
  end
end
