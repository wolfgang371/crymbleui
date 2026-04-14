require "../spec_helper"
require "../../src/testing/test_render_backend"

describe CrymbleUI::Widget do
    describe "#initialize" do
        it "creates widget with ID" do
            widget = TestWidget.new(id: "test_widget")
            widget.id.should eq("test_widget")
        end

        it "creates widget without ID" do
            widget = TestWidget.new
            widget.id.should be_nil
        end

        it "starts with empty children" do
            widget = TestWidget.new
            widget.children.should be_empty
        end

        it "starts as needing layout" do
            widget = TestWidget.new
            widget.state.should eq(CrymbleUI::WidgetState::NeedsLayout)
        end
    end

    describe "#path_id" do
        it "returns ID for root widget" do
            widget = TestWidget.new(id: "root")
            widget.path_id.should eq("root")
        end

        it "returns class name if no ID" do
            widget = TestWidget.new
            widget.path_id.should eq("TestWidget")
        end

        it "returns label if no ID but has label" do
            widget = TestWidget.new(label: "MyWidget")
            widget.path_id.should eq("MyWidget")
        end

        it "builds hierarchical path for nested widgets" do
            parent = TestWidget.new(id: "parent")
            child = TestWidget.new(id: "child")
            parent.add_child(child)

            child.path_id.should eq("parent/child")
        end

        it "builds deep hierarchical paths" do
            root = TestWidget.new(id: "root")
            middle = TestWidget.new(id: "middle")
            leaf = TestWidget.new(id: "leaf")

            root.add_child(middle)
            middle.add_child(leaf)

            leaf.path_id.should eq("root/middle/leaf")
        end
    end

    describe "#add_child" do
        it "adds child to children array" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)

            parent.children.should contain(child)
        end

        it "sets child's parent reference" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)

            child.parent.should eq(parent)
        end

        it "marks parent as needing layout" do
            parent = TestWidget.new
            parent.state = CrymbleUI::WidgetState::Clean
            child = TestWidget.new
            parent.add_child(child)

            parent.needs_layout?.should be_true
        end

        it "warns when adding child with duplicate ID (but still adds it)" do
            parent = TestWidget.new(id: "parent")
            child1 = TestWidget.new(id: "duplicate")
            child2 = TestWidget.new(id: "duplicate")

            # First child should add without warning
            parent.add_child(child1)
            parent.children.size.should eq(1)

            # Second child with same ID should warn (to STDERR) but still be added
            # Disable warnings for this test to avoid noise
            CrymbleUI::Widget.enable_warnings = false
            parent.add_child(child2)
            CrymbleUI::Widget.enable_warnings = true

            parent.children.size.should eq(2)
            parent.children.should contain(child1)
            parent.children.should contain(child2)
        end
    end

    describe "#remove_child" do
        it "removes child from children array" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)
            parent.remove_child(child)

            parent.children.should_not contain(child)
        end

        it "clears child's parent reference" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)
            parent.remove_child(child)

            child.parent.should be_nil
        end
    end

    describe "#clear_children" do
        it "removes all children" do
            parent = TestWidget.new
            child1 = TestWidget.new
            child2 = TestWidget.new
            parent.add_child(child1)
            parent.add_child(child2)
            parent.clear_children

            parent.children.should be_empty
        end

        it "clears parent references" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)
            parent.clear_children

            child.parent.should be_nil
        end
    end

    describe "#mark_needs_layout" do
        it "sets state to NeedsLayout" do
            widget = TestWidget.new
            widget.state = CrymbleUI::WidgetState::Clean
            widget.mark_needs_layout

            widget.state.should eq(CrymbleUI::WidgetState::NeedsLayout)
        end

        it "propagates to parent" do
            parent = TestWidget.new
            child = TestWidget.new
            parent.add_child(child)
            parent.state = CrymbleUI::WidgetState::Clean
            child.state = CrymbleUI::WidgetState::Clean

            child.mark_needs_layout

            parent.state.should eq(CrymbleUI::WidgetState::NeedsLayout)
        end
    end

    describe "#find_by_id" do
        it "finds widget by ID" do
            widget = TestWidget.new(id: "target")
            widget.find_by_id("target").should eq(widget)
        end

        it "finds child by ID" do
            parent = TestWidget.new(id: "parent")
            child = TestWidget.new(id: "child")
            parent.add_child(child)

            parent.find_by_id("child").should eq(child)
        end

        it "returns nil if not found" do
            widget = TestWidget.new(id: "widget")
            widget.find_by_id("nonexistent").should be_nil
        end

        it "searches recursively" do
            root = TestWidget.new(id: "root")
            middle = TestWidget.new(id: "middle")
            leaf = TestWidget.new(id: "leaf")
            root.add_child(middle)
            middle.add_child(leaf)

            root.find_by_id("leaf").should eq(leaf)
        end
    end

    describe "#find_by_path" do
        it "finds widget by path" do
            parent = TestWidget.new(id: "parent")
            child = TestWidget.new(id: "child")
            parent.add_child(child)

            parent.find_by_path("parent/child").should eq(child)
        end
    end

    describe "#find_all" do
        it "finds all widgets matching predicate" do
            parent = TestWidget.new(id: "parent")
            child1 = TestWidget.new(id: "child1")
            child2 = TestWidget.new(id: "child2")
            parent.add_child(child1)
            parent.add_child(child2)

            results = parent.find_all { |w| w.id.try(&.starts_with?("child")) || false }
            results.size.should eq(2)
            results.should contain(child1)
            results.should contain(child2)
        end
    end

    describe "#hit_test" do
        it "returns widget if point is inside bounds" do
            widget = TestWidget.new(id: "widget")
            widget.bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)

            point = CrymbleUI::Vec2.new(50.0, 50.0)
            widget.hit_test(point).should eq(widget)
        end

        it "returns nil if point is outside bounds" do
            widget = TestWidget.new(id: "widget")
            widget.bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)

            point = CrymbleUI::Vec2.new(200.0, 200.0)
            widget.hit_test(point).should be_nil
        end

        it "returns child if point hits child" do
            parent = TestWidget.new(id: "parent")
            child = TestWidget.new(id: "child")
            parent.add_child(child)

            parent.bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 200.0)
            child.bounds = CrymbleUI::Rect.new(50.0, 50.0, 100.0, 100.0)

            point = CrymbleUI::Vec2.new(75.0, 75.0)
            parent.hit_test(point).should eq(child)
        end
    end

    describe "#trigger_click" do
        it "calls on_click handler" do
            widget = TestWidget.new(id: "button")
            widget.trigger_click

            widget.click_count.should eq(1)
        end

        it "can be called multiple times" do
            widget = TestWidget.new(id: "button")
            widget.trigger_click
            widget.trigger_click
            widget.trigger_click

            widget.click_count.should eq(3)
        end
    end

    describe "#measure and #layout" do
        it "measures widget size" do
            widget = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 75.0))
            constraints = CrymbleUI::BoxConstraints.new
            size = widget.measure(constraints)

            size.width.should eq(150.0)
            size.height.should eq(75.0)
        end

        it "lays out widget at position" do
            widget = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            widget.layout(constraints, position)

            widget.bounds.x.should eq(10.0)
            widget.bounds.y.should eq(20.0)
            widget.bounds.width.should eq(100.0)
            widget.bounds.height.should eq(50.0)
        end
    end

    describe "#layout skip path" do
        it "invalidates background_backend when position changes" do
            # Sibling B at position (0, 50). After layout skip, moved to (0, 80).
            # Its background_backend must be invalidated (holds content from old position).
            widget = TestWidget.new(id: "sibling_b")
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 50.0))

            # First layout — sets bounds and caches constraints
            widget.layout(constraints, CrymbleUI::Vec2.new(0.0, 50.0))
            widget.bounds.y.should eq(50.0)

            # Simulate a render that sets up background_backend
            fake_backend = CrymbleUI::Testing::TestRenderBackend.new(100, 50)
            widget.background_backend = fake_backend
            widget.state = CrymbleUI::WidgetState::Clean

            # Second layout with same constraints but different position (sibling A grew)
            widget.layout(constraints, CrymbleUI::Vec2.new(0.0, 80.0))

            # Position should be updated
            widget.bounds.y.should eq(80.0)

            # Background must be invalidated (old content was at y=50, now at y=80)
            widget.background_backend.should be_nil
        end

        it "keeps background_backend when position unchanged" do
            widget = TestWidget.new(id: "stable")
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 50.0))

            widget.layout(constraints, CrymbleUI::Vec2.new(0.0, 50.0))

            fake_backend = CrymbleUI::Testing::TestRenderBackend.new(100, 50)
            widget.background_backend = fake_backend
            widget.state = CrymbleUI::WidgetState::Clean

            # Same constraints AND same position — skip path, keep background
            widget.layout(constraints, CrymbleUI::Vec2.new(0.0, 50.0))

            widget.background_backend.should_not be_nil
        end
    end
end
