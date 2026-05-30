require "../spec_helper"
require "../../src/widgets/separator"

describe CrymbleUI::Separator do
    describe "#initialize" do
        it "creates separator with default color" do
            separator = CrymbleUI::Separator.new
            separator.color.r.should eq(200)
            separator.color.g.should eq(200)
            separator.color.b.should eq(200)
        end

        it "creates separator with custom color" do
            color = CrymbleUI::Color.new(100, 100, 100, 255)
            separator = CrymbleUI::Separator.new(color: color)
            separator.color.should eq(color)
        end

        it "accepts id parameter" do
            separator = CrymbleUI::Separator.new(id: "sep1")
            separator.id.should eq("sep1")
        end
    end

    describe "#label" do
        it "returns 'separator' for path_id generation" do
            separator = CrymbleUI::Separator.new
            separator.label.should eq("separator")
        end
    end

    describe "#measure" do
        it "returns minimal natural width (0) regardless of constraint" do
            # A separator should NOT dominate a column's natural width — its
            # job is to fill space at layout time, not claim it at measure
            # time. Returning constraint.max_width here was a real bug: the
            # natural width grew between popup measure passes (INFINITY → 150,
            # loose(N) → N), forcing RecursiveGrid#scale_to_fill to shrink
            # other columns and clipping their content (e.g. "Ctrl+U" in the
            # cell context menu).
            separator = CrymbleUI::Separator.new

            size = separator.measure(CrymbleUI::BoxConstraints.new(max_width: 200.0, max_height: 300.0))
            size.width.should eq(0.0)
            size.height.should eq(CrymbleUI::Separator::SEPARATOR_HEIGHT)

            size = separator.measure(CrymbleUI::BoxConstraints.new)  # infinite
            size.width.should eq(0.0)
            size.height.should eq(CrymbleUI::Separator::SEPARATOR_HEIGHT)
        end
    end

    describe "#layout" do
        it "sets bounds at given position" do
            separator = CrymbleUI::Separator.new
            constraints = CrymbleUI::BoxConstraints.new(max_width: 100.0, max_height: 50.0)
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            separator.layout(constraints, position)

            separator.bounds.x.should eq(10.0)
            separator.bounds.y.should eq(20.0)
            separator.bounds.width.should eq(100.0)
            separator.bounds.height.should eq(CrymbleUI::Separator::SEPARATOR_HEIGHT)
        end
    end

    describe "#to_primitives" do
        it "generates single FillRect primitive" do
            separator = CrymbleUI::Separator.new
            bounds = CrymbleUI::Rect.new(0, 0, 100, 5)

            primitives = separator.to_primitives(bounds)

            primitives.size.should eq(1)
            primitives[0].should be_a(CrymbleUI::FillRect)
        end

        it "primitive has correct bounds (with margins)" do
            separator = CrymbleUI::Separator.new
            bounds = CrymbleUI::Rect.new(10, 20, 100, 5)

            primitives = separator.to_primitives(bounds)
            line = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Line should have 4px left margin, 8px less width (4px each side)
            line.bounds.x.should eq(4.0)  # 0 + 4 (widget-local)
            line.bounds.width.should eq(92.0)  # 100 - 8
            line.bounds.height.should eq(1.0)  # Line thickness
        end

        it "primitive has correct color" do
            color = CrymbleUI::Color.new(50, 50, 50, 255)
            separator = CrymbleUI::Separator.new(color: color)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 5)

            primitives = separator.to_primitives(bounds)
            line = primitives[0].as(CrymbleUI::FillRect)

            line.color.should eq(color)
        end

        it "line is centered vertically in bounds" do
            separator = CrymbleUI::Separator.new
            bounds = CrymbleUI::Rect.new(0, 10, 100, 5)

            primitives = separator.to_primitives(bounds)
            line = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Line should be at 0 + SEPARATOR_HEIGHT / 2.0
            expected_y = 0.0 + (CrymbleUI::Separator::SEPARATOR_HEIGHT / 2.0)
            line.bounds.y.should eq(expected_y)
        end

    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            separator = CrymbleUI::Separator.new
            bounds = CrymbleUI::Rect.new(0, 0, 100, 5)

            # First call generates
            primitives1 = separator.get_primitives(bounds)
            separator.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = separator.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates primitives when color changes" do
            separator = CrymbleUI::Separator.new
            bounds = CrymbleUI::Rect.new(0, 0, 100, 5)

            primitives1 = separator.get_primitives(bounds)
            line1 = primitives1[0].as(CrymbleUI::FillRect)

            # color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            separator.color = new_color

            primitives2 = separator.get_primitives(bounds)
            line2 = primitives2[0].as(CrymbleUI::FillRect)

            line1.color.should_not eq(new_color)
            line2.color.should eq(new_color)
        end
    end
end
