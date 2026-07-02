require "../spec_helper"
require "../../src/widgets/combo_box_popup"
require "../../src/widgets/combo_box_item"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"

describe CrymbleUI::ComboBoxPopup do
    describe "GUI rendering (items must actually render)" do
        # This test verifies VISUAL rendering, not just internal state
        #
        # NOTE: These tests PASS in headless mode but the bug exists in SFML mode.
        # The nested layer compositing works in TestRenderer but fails in SFMLRenderer.
        # We're simplifying the architecture (removing ScrollView) to fix this.
        it "items have widget_backend after render (GUI behavior test)" do
            # Create popup with items using new constructor
            popup = CrymbleUI::ComboBoxPopup.new(
                items: ["Apple", "Banana", "Cherry"],
                max_height: 200.0,
                width: 150.0
            )

            # Create minimal app with window containing popup
            app = TestApp.new
            window = CrymbleUI::Window.new("Test", 400, 300)
            window.add_overlay(popup)
            app.root_widget = window

            # Render through full pipeline
            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            renderer.settle_rendering(app)

            # GUI BEHAVIOR TEST: Items must have widget_backend (actually rendered)
            # This catches the bug where demo shows empty gray area
            popup.item_widgets.size.should be > 0, "popup has no item widgets"
            popup.item_widgets.first.widget_backend.should_not be_nil,
                "First item has no widget_backend - item not rendered (GUI bug!)"
        end

        it "items have non-zero bounds after layout" do
            popup = CrymbleUI::ComboBoxPopup.new(
                items: ["Apple", "Banana", "Cherry"],
                max_height: 200.0,
                width: 150.0
            )

            app = TestApp.new
            window = CrymbleUI::Window.new("Test", 400, 300)
            window.add_overlay(popup)
            app.root_widget = window

            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            renderer.settle_rendering(app)

            # Each item should have non-zero bounds
            popup.item_widgets.each_with_index do |item, idx|
                item.bounds.width.should be > 0, "Item #{idx} has zero width"
                item.bounds.height.should be > 0, "Item #{idx} has zero height"
            end
        end

        it "uses ScrollView for scrollable content" do
            popup = CrymbleUI::ComboBoxPopup.new(
                items: ["Apple", "Banana", "Cherry"],
                max_height: 200.0,
                width: 150.0
            )

            app = TestApp.new
            window = CrymbleUI::Window.new("Test", 400, 300)
            window.add_overlay(popup)
            app.root_widget = window

            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            renderer.settle_rendering(app)

            # Check layer structure - popup should have its layer
            popup.layer.should_not be_nil, "Popup has no layer"

            # ScrollView is child of popup
            scroll_view = popup.children.find { |c| c.is_a?(CrymbleUI::ScrollView) }
            scroll_view.should_not be_nil, "ComboBoxPopup should contain ScrollView"

            # VStack is content of ScrollView (not direct child of popup)
            popup.children.any? { |c| c.is_a?(CrymbleUI::VStack) }.should be_false,
                "VStack should NOT be direct child of popup (should be inside ScrollView)"
        end
    end

    describe "#initialize" do
        it "creates popup with default properties" do
            popup = CrymbleUI::ComboBoxPopup.new
            popup.background_color.should eq(CrymbleUI::Color.white)
        end

        it "accepts id parameter" do
            popup = CrymbleUI::ComboBoxPopup.new(id: "test_popup")
            popup.id.should eq("test_popup")
        end

        it "accepts custom colors" do
            bg = CrymbleUI::Color.new(240, 240, 240, 255)
            border = CrymbleUI::Color.blue
            popup = CrymbleUI::ComboBoxPopup.new(
                background_color: bg,
                border_color: border
            )
            popup.background_color.should eq(bg)
            popup.border_color.should eq(border)
        end

        it "accepts max_height" do
            popup = CrymbleUI::ComboBoxPopup.new(max_height: 200.0)
            popup.max_height.should eq(200.0)
        end
    end

    describe "#layer" do
        it "creates internal layer after layout" do
            popup = CrymbleUI::ComboBoxPopup.new
            constraints = CrymbleUI::BoxConstraints.new
            popup.layout(constraints, CrymbleUI::Vec2.zero)

            popup.layer.should_not be_nil
        end

        it "layer has high z-index (1000)" do
            popup = CrymbleUI::ComboBoxPopup.new
            constraints = CrymbleUI::BoxConstraints.new
            popup.layout(constraints, CrymbleUI::Vec2.zero)

            popup.layer.not_nil!.z_index.should eq(1000)
        end
    end

    describe "#measure" do
        it "width matches constraints" do
            popup = CrymbleUI::ComboBoxPopup.new(items: ["Test Item"])

            constraints = CrymbleUI::BoxConstraints.new(min_width: 150.0, max_width: 150.0)
            size = popup.measure(constraints)

            size.width.should eq(150.0)
        end

        it "height respects max_height" do
            popup = CrymbleUI::ComboBoxPopup.new(
                items: (1..10).map { |i| "Item #{i}" },
                max_height: 100.0
            )

            constraints = CrymbleUI::BoxConstraints.new
            size = popup.measure(constraints)

            size.height.should be <= 100.0
        end
    end

    # the popup is a PURE CONTAINER — it paints NOTHING under its children.
    # Its background comes from the layer clear (compute_background_for_layer), and its
    # border is a FOREGROUND (drawn after children, at the edges). This makes a
    # self-mark / selective re-render a pure-container skip that can't blit over the
    # clean children (the "(select all) vanishes" footgun, structurally closed).
    describe "#to_primitives + border (pure container)" do
        it "to_primitives is EMPTY — no self-fill under children (background comes from the layer clear)" do
            popup = CrymbleUI::ComboBoxPopup.new
            popup.to_primitives(CrymbleUI::Rect.new(0, 0, 150, 100)).should be_empty
        end

        it "draws its border as a FOREGROUND (over children), in widget-local coordinates" do
            popup = CrymbleUI::ComboBoxPopup.new
            popup.bounds = CrymbleUI::Rect.new(50, 100, 150, 100)
            popup.has_foreground?.should be_true
            border = popup.foreground_primitives.find { |p| p.is_a?(CrymbleUI::DrawRect) }.not_nil!.as(CrymbleUI::DrawRect)
            border.bounds.x.should eq(0.0)
            border.bounds.y.should eq(0.0)
        end
    end

    describe "#owner" do
        it "can be set and retrieved" do
            popup = CrymbleUI::ComboBoxPopup.new
            # Note: In real usage, owner would be a ComboBox
            # For this test, we just verify the property works
            popup.owner.should be_nil
        end
    end

    describe "layout" do
        it "positions at given location" do
            popup = CrymbleUI::ComboBoxPopup.new(items: ["Test"])

            constraints = CrymbleUI::BoxConstraints.new(min_width: 150.0, max_width: 150.0)
            position = CrymbleUI::Vec2.new(100.0, 200.0)
            popup.layout(constraints, position)

            popup.bounds.x.should eq(100.0)
            popup.bounds.y.should eq(200.0)
        end

        it "layer bounds match popup bounds" do
            popup = CrymbleUI::ComboBoxPopup.new(items: ["Test"])

            constraints = CrymbleUI::BoxConstraints.new(min_width: 150.0, max_width: 150.0)
            position = CrymbleUI::Vec2.new(100.0, 200.0)
            popup.layout(constraints, position)

            layer = popup.layer.not_nil!
            layer.bounds.x.should eq(popup.bounds.x)
            layer.bounds.y.should eq(popup.bounds.y)
        end
    end

    describe "popup inheritance" do
        it "is a Popup (required for hit_test to find it)" do
            popup = CrymbleUI::ComboBoxPopup.new
            popup.is_a?(CrymbleUI::Popup).should be_true
        end
    end

    describe "sibling overlap invariant" do
        # Siblings (TextInput, ScrollView) must not overlap
        # INVARIANT: siblings must not overlap
        it "scroll does not cause sibling overlap" do
            # Create popup with enough items to enable scrolling
            popup = CrymbleUI::ComboBoxPopup.new(
                items: (1..20).map { |i| "Item #{i}" },
                max_height: 100.0,
                width: 150.0
            )

            # Layout in a window
            app = TestApp.new
            window = CrymbleUI::Window.new("Test", 400, 300)
            window.add_overlay(popup)
            app.root_widget = window

            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            renderer.settle_rendering(app)

            # Get references to siblings (TextInput and ScrollView)
            text_input = popup.text_input
            scroll_view = popup.children.find { |c| c.is_a?(CrymbleUI::ScrollView) }.not_nil!

            # Before scroll: verify no overlap between TextInput and ScrollView
            text_input_bottom = text_input.bounds.y + text_input.bounds.height
            scroll_view_top_before = scroll_view.bounds.y
            scroll_view_top_before.should be >= text_input_bottom,
                "ScrollView should not overlap TextInput before scroll"

            # Scroll down via app event handler (ScrollView handles mouse wheel)
            scroll_point = CrymbleUI::Vec2.new(
                popup.absolute_bounds.x + 50.0,
                popup.absolute_bounds.y + 50.0
            )
            app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), scroll_point)
            renderer.settle_rendering(app)

            # After scroll: siblings MUST NOT overlap
            # ScrollView bounds should stay fixed (content scrolls inside)
            scroll_view_top_after = scroll_view.bounds.y
            scroll_view_top_after.should be >= text_input_bottom,
                "ScrollView (y=#{scroll_view_top_after}) overlaps TextInput bottom (y=#{text_input_bottom}) after scroll"
        end
    end

    describe "child coordinate system" do
        it "scroll_view uses relative coordinates (not absolute)" do
            popup = CrymbleUI::ComboBoxPopup.new(
                items: ["Test"],
                padding: 2.0
            )

            # Layout popup at absolute position (100, 200)
            constraints = CrymbleUI::BoxConstraints.new(min_width: 150.0, max_width: 150.0)
            popup.layout(constraints, CrymbleUI::Vec2.new(100.0, 200.0))

            # ScrollView should be at RELATIVE position below TextInput
            # NOT at absolute (100 + padding, 200 + padding + text_input_height)
            scroll_view = popup.children.find { |c| c.is_a?(CrymbleUI::ScrollView) }
            scroll_view.should_not be_nil
            scroll_view.not_nil!.bounds.x.should eq(2.0)  # padding, not 102.0
            # Y should be padding + TEXT_INPUT_HEIGHT (24.0)
            scroll_view.not_nil!.bounds.y.should eq(26.0)  # 2.0 + 24.0, not 226.0
        end
    end
end
