require "../spec_helper"
require "../../src/widgets/button"
require "../../src/widgets/checkbox"

describe "Focusable Widgets" do
  describe CrymbleUI::Button do
    describe "#focusable?" do
      it "is focusable" do
        button = CrymbleUI::Button.new("Click") { }
        button.focusable?.should be_true
      end
    end

    describe "focus_highlighted?" do
      it "defaults to false" do
        button = CrymbleUI::Button.new("Click") { }
        button.focus_highlighted?.should be_false
      end

      it "can be set to true" do
        button = CrymbleUI::Button.new("Click") { }
        button.focus_highlighted = true
        button.focus_highlighted?.should be_true
      end

      it "marks needs render when changed" do
        button = CrymbleUI::Button.new("Click") { }
        # Layout first to set state to Clean
        constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 100.0))
        button.layout(constraints, CrymbleUI::Vec2.zero)
        button.clear_state_for_test

        button.focus_highlighted = true

        button.needs_render?.should be_true
      end
    end

    describe "visual appearance when focused" do
      it "uses brightened colors when focus_highlighted" do
        button = CrymbleUI::Button.new("Click") { }
        constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 100.0))
        button.layout(constraints, CrymbleUI::Vec2.zero)

        # Get primitives without focus highlight
        button.focus_highlighted = false
        normal_prims = button.to_primitives(button.bounds)

        # Get primitives with focus highlight
        button.focus_highlighted = true
        focused_prims = button.to_primitives(button.bounds)

        # Background FillRect should be brighter when focus_highlighted
        normal_fill = normal_prims.find { |p| p.is_a?(CrymbleUI::FillRect) }.as(CrymbleUI::FillRect)
        focused_fill = focused_prims.find { |p| p.is_a?(CrymbleUI::FillRect) }.as(CrymbleUI::FillRect)

        # Focused should be brighter (higher RGB values)
        focused_fill.color.r.should be >= normal_fill.color.r
        focused_fill.color.g.should be > normal_fill.color.g
        focused_fill.color.b.should be > normal_fill.color.b
      end
    end

    describe "keyboard activation" do
      it "has trigger_click method for Enter/Space activation" do
        clicked = false
        button = CrymbleUI::Button.new("Click") { clicked = true }

        button.trigger_click

        clicked.should be_true
      end
    end
  end

  describe CrymbleUI::Checkbox do
    describe "#focusable?" do
      it "is focusable" do
        checkbox = CrymbleUI::Checkbox.new("Check me", checked: false) { }
        checkbox.focusable?.should be_true
      end
    end

    describe "focus_highlighted?" do
      it "defaults to false" do
        checkbox = CrymbleUI::Checkbox.new("Check me", checked: false) { }
        checkbox.focus_highlighted?.should be_false
      end

      it "can be set to true" do
        checkbox = CrymbleUI::Checkbox.new("Check me", checked: false) { }
        checkbox.focus_highlighted = true
        checkbox.focus_highlighted?.should be_true
      end
    end

    describe "keyboard activation" do
      it "has trigger_click method for Space/Enter activation" do
        clicked = false
        checkbox = CrymbleUI::Checkbox.new("Check me", checked: false) { clicked = true }

        checkbox.trigger_click

        clicked.should be_true
      end
    end
  end
end
