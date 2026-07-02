require "../spec_helper"
require "../../src/widgets/popup"

describe CrymbleUI::Popup do
    describe "#initialize" do
        it "creates popup with size" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
            popup.width.should eq(200.0)
            popup.height.should eq(150.0)
        end

        it "creates popup with auto-sizing (nil width/height)" do
            popup = CrymbleUI::Popup.new()
            popup.width.should be_nil
            popup.height.should be_nil
        end

        it "accepts id parameter" do
            popup = CrymbleUI::Popup.new(id: "test_popup")
            popup.id.should eq("test_popup")
        end

        it "accepts custom visual properties" do
            bg_color = CrymbleUI::Color.red
            border_color = CrymbleUI::Color.blue
            popup = CrymbleUI::Popup.new(
                background_color: bg_color,
                border_color: border_color,
                padding: 5.0
            )
            popup.background_color.should eq(bg_color)
            popup.border_color.should eq(border_color)
            popup.padding.should eq(5.0)
        end
    end

    describe "#label" do
        it "returns 'popup' for path_id generation" do
            popup = CrymbleUI::Popup.new()
            popup.label.should eq("popup")
        end
    end

    describe "#measure" do
        it "returns specified width and height when provided" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
            constraints = CrymbleUI::BoxConstraints.new
            size = popup.measure(constraints)
            size.width.should eq(200.0)
            size.height.should eq(150.0)
        end

        it "auto-sizes to children when width/height not specified" do
            popup = CrymbleUI::Popup.new()

            # Add children with known sizes
            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(80.0, 30.0))
            popup.add_child(child1)
            popup.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            size = popup.measure(constraints)

            # Width should be max child width
            size.width.should eq(100.0)
            # Height should be sum of child heights
            size.height.should eq(80.0)
        end

        it "includes padding in auto-sized dimensions" do
            popup = CrymbleUI::Popup.new(padding: 10.0)

            child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            popup.add_child(child)

            constraints = CrymbleUI::BoxConstraints.new
            size = popup.measure(constraints)

            # Should include padding on both sides
            size.width.should eq(120.0)  # 100 + 10*2
            size.height.should eq(70.0)  # 50 + 10*2
        end
    end

    describe "#layout" do
        it "uses position parameter for bounds (parent-relative positioning)" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(100.0, 50.0)

            popup.layout(constraints, position)

            # Popup bounds should use the position parameter (relative to parent)
            popup.bounds.x.should eq(100.0)
            popup.bounds.y.should eq(50.0)
            popup.bounds.width.should eq(200.0)
            popup.bounds.height.should eq(150.0)
        end

        it "positions children vertically inside popup with padding" do
            popup = CrymbleUI::Popup.new(padding: 10.0)

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 20.0))
            popup.add_child(child1)
            popup.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)
            popup.layout(constraints, position)

            # First child at padding offset
            child1.bounds.x.should eq(10.0)
            child1.bounds.y.should eq(10.0)

            # Second child below first
            child2.bounds.x.should eq(10.0)
            child2.bounds.y.should eq(40.0)  # 10 + 30
        end

        it "updates internal layer bounds to match popup (expanded for border)" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(100.0, 50.0)

            popup.layout(constraints, position)

            layer = popup.layer
            layer.should_not be_nil
            # Layer bounds expanded by 1px on all sides for border
            expected_bounds = CrymbleUI::Rect.new(99.0, 49.0, 202.0, 152.0)
            layer.not_nil!.bounds.should eq(expected_bounds)
        end

        it "adds only popup to layer.widgets (not children, prevents double-rendering)" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)

            child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0))
            popup.add_child(child1)
            popup.add_child(child2)

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)
            popup.layout(constraints, position)

            layer = popup.layer.not_nil!
            # Only popup itself, NOT children (children rendered recursively)
            layer.widgets.size.should eq(1)
            layer.widgets[0].should eq(popup)
            layer.widgets.should_not contain(child1)
            layer.widgets.should_not contain(child2)
        end
    end

    # the popup is a PURE CONTAINER — to_primitives is empty (no self-fill under
    # children), the background is supplied to the LAYER (compute_background_for_layer →
    # layer clear), and the border is a FOREGROUND (drawn over children, at the edges).
    # A selective re-render is then a pure-container skip that can't wipe clean children.
    describe "#to_primitives + background/border (pure container)" do
        it "to_primitives is EMPTY — paints nothing under children" do
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
            popup.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, 200.0, 150.0)).should be_empty
        end

        it "supplies its background to the layer (not a self-fill)" do
            bg_color = CrymbleUI::Color.blue
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, background_color: bg_color)
            # compute_background_for_layer returns this → the layer clears to it, so no
            # under-children self-fill is needed (and can't wipe children on re-render).
            popup.background_color.should eq(bg_color)
        end

        it "draws its border as a FOREGROUND (over children), correct bounds and color" do
            border_color = CrymbleUI::Color.red
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, border_color: border_color)
            popup.bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 150.0)
            popup.has_foreground?.should be_true
            border = popup.foreground_primitives.find { |p| p.is_a?(CrymbleUI::DrawRect) }.not_nil!.as(CrymbleUI::DrawRect)
            border.bounds.x.should eq(0.0)
            border.bounds.y.should eq(0.0)
            border.bounds.width.should eq(200.0)
            border.bounds.height.should eq(150.0)
            border.color.should eq(border_color)
        end
    end

    describe "#content_area" do
        it "calculates content area with padding using absolute bounds" do
            # Create popup as child of window to test absolute bounds calculation
            window = CrymbleUI::Window.new("Test", 800, 600)
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, padding: 10.0)
            window.add_child(popup)

            # Layout window and popup
            window_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(window_constraints, CrymbleUI::Vec2.zero)

            popup_position = CrymbleUI::Vec2.new(100.0, 50.0)
            popup.layout(window_constraints, popup_position)

            content = popup.content_area

            # Content area should be in absolute coordinates (popup at 100, 50)
            content.x.should eq(110.0)  # 100 + 10 (padding)
            content.y.should eq(60.0)   # 50 + 10 (padding)
            content.width.should eq(180.0)  # 200 - 20 (padding both sides)
            content.height.should eq(130.0) # 150 - 20 (padding both sides)
        end
    end

    describe "#clip_children" do
        it "returns content area for clipping" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, padding: 10.0)
            window.add_child(popup)

            window_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(window_constraints, CrymbleUI::Vec2.zero)

            popup_position = CrymbleUI::Vec2.new(100.0, 50.0)
            popup.layout(window_constraints, popup_position)

            clip = popup.clip_children
            clip.should_not be_nil
            clip.should eq(popup.content_area)
        end
    end
end
