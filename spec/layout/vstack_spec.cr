require "../spec_helper"
require "../../src/layout/vstack"

describe CrymbleUI::VStack do
    describe "#initialize" do
        it "creates vstack with default spacing" do
            vstack = CrymbleUI::VStack.new
            vstack.spacing.should eq(0.0)
        end

        it "creates vstack with custom spacing" do
            vstack = CrymbleUI::VStack.new(spacing: 10.0)
            vstack.spacing.should eq(10.0)
        end

        it "accepts id parameter" do
            vstack = CrymbleUI::VStack.new(id: "my_stack")
            vstack.id.should eq("my_stack")
        end

        it "starts with no children" do
            vstack = CrymbleUI::VStack.new
            vstack.children.should be_empty
        end
    end

    describe "#measure" do
        it "returns zero size with no children" do
            vstack = CrymbleUI::VStack.new
            constraints = CrymbleUI::BoxConstraints.new
            size = vstack.measure(constraints)

            size.width.should eq(0.0)
            size.height.should eq(0.0)
        end

        it "sums heights of children" do
            vstack = CrymbleUI::VStack.new

            # Add children with known sizes
            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            vstack.add_child(child1)
            vstack.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            size = vstack.measure(constraints)

            # Height should be sum: 50 + 30 = 80
            size.height.should eq(80.0)
        end

        it "uses max width of children" do
            vstack = CrymbleUI::VStack.new

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 30.0))
            vstack.add_child(child1)
            vstack.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            size = vstack.measure(constraints)

            # Width should be max: max(100, 150) = 150
            size.width.should eq(150.0)
        end

        it "adds spacing between children" do
            vstack = CrymbleUI::VStack.new(spacing: 10.0)

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            child3 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 20.0))
            vstack.add_child(child1)
            vstack.add_child(child2)
            vstack.add_child(child3)

            constraints = CrymbleUI::BoxConstraints.new
            size = vstack.measure(constraints)

            # Height: 50 + 10 + 30 + 10 + 20 = 120 (spacing between, not after)
            size.height.should eq(120.0)
        end

        it "respects box constraints" do
            vstack = CrymbleUI::VStack.new

            # Add children that would exceed constraints
            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
            vstack.add_child(child1)
            vstack.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new(
                max_width: 100.0,
                max_height: 150.0
            )
            size = vstack.measure(constraints)

            # Should be constrained
            size.width.should be <= 100.0
            size.height.should be <= 150.0
        end
    end

    describe "#layout" do
        it "positions children vertically" do
            vstack = CrymbleUI::VStack.new

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            vstack.add_child(child1)
            vstack.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            vstack.layout(constraints, position)

            # With parent-relative bounds, children are positioned relative to VStack
            # First child at top of VStack (relative position 0, 0)
            child1.bounds.x.should eq(0.0)
            child1.bounds.y.should eq(0.0)

            # Second child below first (relative to VStack)
            child2.bounds.x.should eq(0.0)
            child2.bounds.y.should eq(50.0)  # child1 height

            # Absolute positions should match old behavior
            child1.absolute_bounds.x.should eq(10.0)  # VStack x + child1 relative x
            child1.absolute_bounds.y.should eq(20.0)  # VStack y + child1 relative y
            child2.absolute_bounds.y.should eq(70.0)  # 20 + 50
        end

        it "applies spacing between children" do
            vstack = CrymbleUI::VStack.new(spacing: 15.0)

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            vstack.add_child(child1)
            vstack.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)

            vstack.layout(constraints, position)

            # First child at 0
            child1.bounds.y.should eq(0.0)

            # Second child: 0 + 50 (child1 height) + 15 (spacing) = 65
            child2.bounds.y.should eq(65.0)
        end

        it "sets vstack bounds" do
            vstack = CrymbleUI::VStack.new

            child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            vstack.add_child(child)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(5.0, 10.0)

            vstack.layout(constraints, position)

            vstack.bounds.x.should eq(5.0)
            vstack.bounds.y.should eq(10.0)
            vstack.bounds.width.should eq(100.0)
            vstack.bounds.height.should eq(50.0)
        end

        it "marks vstack as not dirty after layout" do
            vstack = CrymbleUI::VStack.new
            vstack.state = CrymbleUI::WidgetState::NeedsLayout

            child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            vstack.add_child(child)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)

            vstack.layout(constraints, position)

            vstack.state.should eq(CrymbleUI::WidgetState::Clean)
        end
    end


    describe "integration with widgets" do
        it "can layout Text widgets" do
            vstack = CrymbleUI::VStack.new(spacing: 5.0)

            text1 = CrymbleUI::Text.new("Hello", font_scale: 1)
            text2 = CrymbleUI::Text.new("World", font_scale: 1)
            vstack.add_child(text1)
            vstack.add_child(text2)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)

            vstack.layout(constraints, position)

            # Children should be positioned vertically with spacing
            text1.bounds.y.should eq(0.0)
            text2.bounds.y.should be > text1.bounds.height
        end

        it "supports nested VStacks" do
            outer = CrymbleUI::VStack.new
            inner = CrymbleUI::VStack.new

            text1 = CrymbleUI::Text.new("A")
            text2 = CrymbleUI::Text.new("B")
            inner.add_child(text1)
            inner.add_child(text2)

            outer.add_child(inner)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)

            outer.layout(constraints, position)

            # All widgets should be laid out
            outer.bounds.width.should be > 0
            inner.bounds.width.should be > 0
            text1.bounds.width.should be > 0
        end
    end
end
