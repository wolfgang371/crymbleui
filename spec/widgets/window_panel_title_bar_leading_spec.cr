require "../spec_helper"
require "../../src/widgets/window_panel"

# Minimal widget for testing — fixed-size, no rendering. We just need a
# Widget instance with hit_test/absolute_bounds working.
class LeadingTestWidget < CrymbleUI::Widget
    def initialize(id : String? = nil)
        super(id: id)
    end

    def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
        CrymbleUI::Size.new(constraints.max_width, constraints.max_height)
    end

    def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
        @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
        [] of CrymbleUI::DrawPrimitive
    end
end

# A draggable child in the title bar (e.g., a "link grip") needs to capture
# mouse-down BEFORE the panel-drag handler claims it, so the user can drag
# the icon without moving the whole panel. This spec verifies the slot
# mechanics: layout positions the widget at the title bar's leading edge,
# hit_test routes to the widget within its bounds, and empty title-bar
# area still falls through to the panel (panel-drag preserved).

describe "WindowPanel#title_bar_leading" do
    it "lays out the leading widget at the title bar's leading edge" do
        wp = CrymbleUI::WindowPanel.new(title: "S", x: 50.0, y: 60.0,
                                         width: 300.0, height: 200.0)
        leading = LeadingTestWidget.new(id: "L")
        wp.title_bar_leading = leading
        wp.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0)),
                  CrymbleUI::Vec2.new(50.0, 60.0))

        lb = leading.absolute_bounds
        # Vertically inside the title bar.
        lb.y.should be >= 60.0
        (lb.y + lb.height).should be <= (60.0 + wp.title_bar_height)
        # Near the panel's left edge (within a tight padding).
        (lb.x - 50.0).should be < 20.0
        # Non-zero size — otherwise nothing to hit / drag.
        lb.width.should be > 0.0
        lb.height.should be > 0.0
    end

    it "routes hit_test on the leading widget's bounds to the widget (panel-drag yields)" do
        wp = CrymbleUI::WindowPanel.new(title: "S", x: 50.0, y: 60.0,
                                         width: 300.0, height: 200.0)
        leading = LeadingTestWidget.new(id: "L")
        wp.title_bar_leading = leading
        wp.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0)),
                  CrymbleUI::Vec2.new(50.0, 60.0))

        lb = leading.absolute_bounds
        center = CrymbleUI::Vec2.new(lb.x + lb.width / 2.0, lb.y + lb.height / 2.0)
        wp.hit_test(center).should eq(leading)
    end

    it "hit_test on empty title-bar area still returns the panel (drag preserved)" do
        wp = CrymbleUI::WindowPanel.new(title: "S", x: 50.0, y: 60.0,
                                         width: 300.0, height: 200.0)
        leading = LeadingTestWidget.new(id: "L")
        wp.title_bar_leading = leading
        wp.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0)),
                  CrymbleUI::Vec2.new(50.0, 60.0))

        lb = leading.absolute_bounds
        # Past the leading widget, well clear of max/close buttons on the right.
        empty = CrymbleUI::Vec2.new(lb.x + lb.width + 50.0, lb.y + lb.height / 2.0)
        wp.hit_test(empty).should eq(wp)
    end
end
