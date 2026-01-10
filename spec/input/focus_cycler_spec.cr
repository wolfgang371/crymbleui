require "../spec_helper"
require "../../src/input/focus_cycler"

# Helper to create a focusable test widget with specific bounds
class FocusableCyclerTestWidget < CrymbleUI::Widget
  def initialize(id : String, x : Float64, y : Float64, width : Float64 = 100.0, height : Float64 = 30.0, @is_focusable : Bool = true)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(x, y, width, height)
  end

  def focusable? : Bool
    @is_focusable
  end

  def absolute_bounds : CrymbleUI::Rect
    @bounds
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@bounds.width, @bounds.height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, @bounds.width, @bounds.height)
  end
end

# Container widget for testing tree traversal
class ContainerTestWidget < CrymbleUI::Widget
  def initialize(id : String? = nil)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(0.0, 0.0, 500.0, 500.0)
  end

  def add_test_child(child : CrymbleUI::Widget)
    add_child(child)
  end

  def focusable? : Bool
    false
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(500.0, 500.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 500.0, 500.0)
  end
end

describe CrymbleUI::FocusCycler do
  describe "#collect_focusable_widgets" do
    it "collects focusable widgets from tree" do
      cycler = CrymbleUI::FocusCycler.new

      root = ContainerTestWidget.new("root")
      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      root.add_test_child(btn1)
      root.add_test_child(btn2)

      focusables = cycler.collect_focusable_widgets(root)

      focusables.size.should eq(2)
      focusables.should contain(btn1)
      focusables.should contain(btn2)
    end

    it "excludes non-focusable widgets" do
      cycler = CrymbleUI::FocusCycler.new

      root = ContainerTestWidget.new("root")
      focusable = FocusableCyclerTestWidget.new("focusable", 0.0, 0.0, is_focusable: true)
      non_focusable = FocusableCyclerTestWidget.new("non_focusable", 0.0, 50.0, is_focusable: false)
      root.add_test_child(focusable)
      root.add_test_child(non_focusable)

      focusables = cycler.collect_focusable_widgets(root)

      focusables.size.should eq(1)
      focusables[0].should eq(focusable)
    end

    it "collects from nested containers" do
      cycler = CrymbleUI::FocusCycler.new

      root = ContainerTestWidget.new("root")
      container = ContainerTestWidget.new("container")
      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)

      root.add_test_child(container)
      container.add_test_child(btn1)
      container.add_test_child(btn2)

      focusables = cycler.collect_focusable_widgets(root)

      focusables.size.should eq(2)
    end

    it "sorts by reading order (top-to-bottom, left-to-right)" do
      cycler = CrymbleUI::FocusCycler.new

      root = ContainerTestWidget.new("root")
      # Add in wrong order, should be sorted by position
      bottom_right = FocusableCyclerTestWidget.new("br", 200.0, 100.0)
      top_left = FocusableCyclerTestWidget.new("tl", 0.0, 0.0)
      top_right = FocusableCyclerTestWidget.new("tr", 200.0, 0.0)
      bottom_left = FocusableCyclerTestWidget.new("bl", 0.0, 100.0)

      root.add_test_child(bottom_right)
      root.add_test_child(top_left)
      root.add_test_child(top_right)
      root.add_test_child(bottom_left)

      focusables = cycler.collect_focusable_widgets(root)

      # Should be sorted: top_left (y=0,x=0), top_right (y=0,x=200), bottom_left (y=100,x=0), bottom_right (y=100,x=200)
      focusables[0].should eq(top_left)
      focusables[1].should eq(top_right)
      focusables[2].should eq(bottom_left)
      focusables[3].should eq(bottom_right)
    end

    it "returns empty array for tree with no focusable widgets" do
      cycler = CrymbleUI::FocusCycler.new

      root = ContainerTestWidget.new("root")
      non_focusable = FocusableCyclerTestWidget.new("nf", 0.0, 0.0, is_focusable: false)
      root.add_test_child(non_focusable)

      focusables = cycler.collect_focusable_widgets(root)

      focusables.should be_empty
    end
  end

  describe "#find_next" do
    it "returns first widget when current is nil" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      focusables = [btn1, btn2]

      result = cycler.find_next(nil, focusables, forward: true)
      result.should eq(btn1)
    end

    it "returns next widget when going forward" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      btn3 = FocusableCyclerTestWidget.new("btn3", 0.0, 100.0)
      focusables = [btn1, btn2, btn3]

      result = cycler.find_next(btn1, focusables, forward: true)
      result.should eq(btn2)
    end

    it "returns previous widget when going backward" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      btn3 = FocusableCyclerTestWidget.new("btn3", 0.0, 100.0)
      focusables = [btn1, btn2, btn3]

      result = cycler.find_next(btn2, focusables, forward: false)
      result.should eq(btn1)
    end

    it "wraps around to first when at end (forward)" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      focusables = [btn1, btn2]

      result = cycler.find_next(btn2, focusables, forward: true)
      result.should eq(btn1)
    end

    it "wraps around to last when at start (backward)" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      focusables = [btn1, btn2]

      result = cycler.find_next(btn1, focusables, forward: false)
      result.should eq(btn2)
    end

    it "returns nil for empty focusables list" do
      cycler = CrymbleUI::FocusCycler.new
      focusables = [] of CrymbleUI::Widget

      result = cycler.find_next(nil, focusables, forward: true)
      result.should be_nil
    end

    it "returns first widget when current not in list" do
      cycler = CrymbleUI::FocusCycler.new

      btn1 = FocusableCyclerTestWidget.new("btn1", 0.0, 0.0)
      btn2 = FocusableCyclerTestWidget.new("btn2", 0.0, 50.0)
      other = FocusableCyclerTestWidget.new("other", 0.0, 100.0)
      focusables = [btn1, btn2]

      result = cycler.find_next(other, focusables, forward: true)
      result.should eq(btn1)
    end
  end
end
