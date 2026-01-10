require "../spec_helper"
require "../../src/input/focus_navigator"

# Helper to create a focusable test widget with specific bounds
class FocusableTestWidget < CrymbleUI::Widget
  def initialize(id : String, x : Float64, y : Float64, width : Float64 = 100.0, height : Float64 = 30.0)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(x, y, width, height)
  end

  def focusable? : Bool
    true
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

describe CrymbleUI::FocusNavigator do
  describe "#find_neighbor" do
    it "finds widget directly below" do
      navigator = CrymbleUI::FocusNavigator.new

      # Vertical layout: top, middle, bottom
      top = FocusableTestWidget.new("top", 100.0, 50.0)
      middle = FocusableTestWidget.new("middle", 100.0, 100.0)
      bottom = FocusableTestWidget.new("bottom", 100.0, 150.0)
      candidates = [top, middle, bottom]

      result = navigator.find_neighbor(top, candidates, :down)
      result.should eq(middle)
    end

    it "finds widget directly above" do
      navigator = CrymbleUI::FocusNavigator.new

      top = FocusableTestWidget.new("top", 100.0, 50.0)
      middle = FocusableTestWidget.new("middle", 100.0, 100.0)
      bottom = FocusableTestWidget.new("bottom", 100.0, 150.0)
      candidates = [top, middle, bottom]

      result = navigator.find_neighbor(bottom, candidates, :up)
      result.should eq(middle)
    end

    it "finds widget directly to the right" do
      navigator = CrymbleUI::FocusNavigator.new

      # Horizontal layout: left, center, right
      left = FocusableTestWidget.new("left", 50.0, 100.0)
      center = FocusableTestWidget.new("center", 160.0, 100.0)
      right = FocusableTestWidget.new("right", 270.0, 100.0)
      candidates = [left, center, right]

      result = navigator.find_neighbor(left, candidates, :right)
      result.should eq(center)
    end

    it "finds widget directly to the left" do
      navigator = CrymbleUI::FocusNavigator.new

      left = FocusableTestWidget.new("left", 50.0, 100.0)
      center = FocusableTestWidget.new("center", 160.0, 100.0)
      right = FocusableTestWidget.new("right", 270.0, 100.0)
      candidates = [left, center, right]

      result = navigator.find_neighbor(right, candidates, :left)
      result.should eq(center)
    end

    it "prefers aligned widgets over closer unaligned ones" do
      navigator = CrymbleUI::FocusNavigator.new

      # Current widget at center
      current = FocusableTestWidget.new("current", 100.0, 100.0)
      # Aligned below (same X column) but further
      aligned = FocusableTestWidget.new("aligned", 100.0, 200.0)
      # Closer but off to the side
      closer_unaligned = FocusableTestWidget.new("closer", 200.0, 130.0)
      candidates = [current, aligned, closer_unaligned]

      result = navigator.find_neighbor(current, candidates, :down)
      result.should eq(aligned)
    end

    it "returns nil when no widget in direction" do
      navigator = CrymbleUI::FocusNavigator.new

      top = FocusableTestWidget.new("top", 100.0, 50.0)
      candidates = [top]

      result = navigator.find_neighbor(top, candidates, :up)
      result.should be_nil
    end

    it "excludes current widget from candidates" do
      navigator = CrymbleUI::FocusNavigator.new

      only_widget = FocusableTestWidget.new("only", 100.0, 100.0)
      candidates = [only_widget]

      result = navigator.find_neighbor(only_widget, candidates, :down)
      result.should be_nil
    end

    it "handles grid layout navigation (2x2)" do
      navigator = CrymbleUI::FocusNavigator.new

      # 2x2 grid:
      # [top_left]  [top_right]
      # [bot_left]  [bot_right]
      top_left = FocusableTestWidget.new("tl", 50.0, 50.0)
      top_right = FocusableTestWidget.new("tr", 200.0, 50.0)
      bot_left = FocusableTestWidget.new("bl", 50.0, 150.0)
      bot_right = FocusableTestWidget.new("br", 200.0, 150.0)
      candidates = [top_left, top_right, bot_left, bot_right]

      # From top_left, down should go to bot_left (same column)
      navigator.find_neighbor(top_left, candidates, :down).should eq(bot_left)
      # From top_left, right should go to top_right (same row)
      navigator.find_neighbor(top_left, candidates, :right).should eq(top_right)
      # From bot_right, up should go to top_right
      navigator.find_neighbor(bot_right, candidates, :up).should eq(top_right)
      # From bot_right, left should go to bot_left
      navigator.find_neighbor(bot_right, candidates, :left).should eq(bot_left)
    end

    it "handles overlapping widgets on secondary axis" do
      navigator = CrymbleUI::FocusNavigator.new

      # Widget A is wide, widgets B and C overlap with it horizontally
      # A: x=0, width=300 (spans full width)
      # B: x=0, width=100 (left side)
      # C: x=200, width=100 (right side)
      wide = FocusableTestWidget.new("wide", 0.0, 50.0, 300.0, 30.0)
      left = FocusableTestWidget.new("left", 0.0, 100.0, 100.0, 30.0)
      right = FocusableTestWidget.new("right", 200.0, 100.0, 100.0, 30.0)
      candidates = [wide, left, right]

      # From wide, down should prefer left (overlaps and is to the left)
      result = navigator.find_neighbor(wide, candidates, :down)
      # Both overlap with wide, but left has smaller X offset from wide's center
      # Wide center is at x=150, left center is at x=50, right center is at x=250
      # left is closer to wide's center
      result.should eq(left)
    end
  end

  describe "focus_override" do
    it "uses explicit override when specified for direction" do
      navigator = CrymbleUI::FocusNavigator.new

      current = FocusableTestWidget.new("current", 100.0, 100.0)
      spatial_up = FocusableTestWidget.new("spatial_up", 100.0, 50.0)  # Spatially above
      override_target = FocusableTestWidget.new("override_id", 200.0, 200.0)  # Far away

      # Set explicit override for Up direction
      current.focus_override = CrymbleUI::FocusOverride.new(up: "override_id")

      result = navigator.find_neighbor(current, [spatial_up, override_target], :up)

      # Should use override, not spatial navigation
      result.should eq(override_target)
    end

    it "falls back to spatial navigation when override ID not found" do
      navigator = CrymbleUI::FocusNavigator.new

      current = FocusableTestWidget.new("current", 100.0, 100.0)
      spatial_up = FocusableTestWidget.new("spatial_up", 100.0, 50.0)

      # Set override to non-existent ID
      current.focus_override = CrymbleUI::FocusOverride.new(up: "nonexistent")

      result = navigator.find_neighbor(current, [spatial_up], :up)

      # Should fall back to spatial navigation
      result.should eq(spatial_up)
    end

    it "uses spatial navigation when no override for direction" do
      navigator = CrymbleUI::FocusNavigator.new

      current = FocusableTestWidget.new("current", 100.0, 100.0)
      spatial_up = FocusableTestWidget.new("spatial_up", 100.0, 50.0)

      # Set override for different direction
      current.focus_override = CrymbleUI::FocusOverride.new(down: "some_id")

      result = navigator.find_neighbor(current, [spatial_up], :up)

      # Should use spatial navigation
      result.should eq(spatial_up)
    end
  end
end
