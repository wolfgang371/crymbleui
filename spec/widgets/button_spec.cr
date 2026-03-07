require "../spec_helper"
require "../../src/widgets/button"

# Test app for Button integration tests
class ButtonTestApp < CrymbleUI::App
    property clicked : Bool = false

    def build : CrymbleUI::Widget
        vstack = CrymbleUI::VStack.new(id: "root")
        button = CrymbleUI::Button.new("Click", id: "btn") { @clicked = true }
        vstack.add_child(button)
        vstack
    end
end

describe CrymbleUI::Button do
    describe "#initialize with callback" do
        it "creates button with text and callback" do
            clicked = false
            button = CrymbleUI::Button.new("Click Me") { clicked = true }

            button.text.should eq("Click Me")
            button.on_click_callback.should_not be_nil
        end

        it "uses default colors" do
            button = CrymbleUI::Button.new("Test") { }

            # Blue background
            button.background_color.r.should eq(0)
            button.background_color.g.should eq(120)
            button.background_color.b.should eq(215)

            # White text
            button.text_color.r.should eq(255)
            button.text_color.g.should eq(255)
            button.text_color.b.should eq(255)
        end

        it "uses default padding and font scale" do
            button = CrymbleUI::Button.new("Test") { }

            button.padding.should eq(10.0)
            button.font_scale.should eq(0)
            button.font_size.should eq(14.0)  # scale 0 = 14pt base
        end

        it "accepts id parameter" do
            button = CrymbleUI::Button.new("Test", id: "my_button") { }
            button.id.should eq("my_button")
        end

        it "accepts custom colors" do
            bg = CrymbleUI::Color.new(255, 0, 0, 255)
            fg = CrymbleUI::Color.new(0, 0, 0, 255)

            button = CrymbleUI::Button.new(
                "Test",
                background_color: bg,
                text_color: fg
            ) { }

            button.background_color.should eq(bg)
            button.text_color.should eq(fg)
        end
    end

    describe "#initialize without callback" do
        it "creates button without callback" do
            button = CrymbleUI::Button.new("Click Me")

            button.text.should eq("Click Me")
            button.on_click_callback.should be_nil
        end

        it "accepts all styling parameters" do
            button = CrymbleUI::Button.new(
                "Test",
                id: "btn",
                font_scale: 3,
                padding: 15.0
            )

            button.text.should eq("Test")
            button.id.should eq("btn")
            button.font_scale.should eq(3)
            button.padding.should eq(15.0)
        end
    end

    describe "#label" do
        it "returns button text as label" do
            button = CrymbleUI::Button.new("Save")
            button.label.should eq("Save")
        end
    end

    describe "#measure" do
        it "calculates size based on text and padding" do
            button = CrymbleUI::Button.new("Test", padding: 10.0, font_scale: 1)
            constraints = CrymbleUI::BoxConstraints.new

            size = button.measure(constraints)

            # With actual font metrics, size should be reasonable
            size.width.should be > 30.0  # At least text width
            size.height.should be > 20.0  # At least padding
        end

        it "scales with font scale" do
            small_button = CrymbleUI::Button.new("Hi", padding: 0.0, font_scale: 1)
            large_button = CrymbleUI::Button.new("Hi", padding: 0.0, font_scale: 7)
            constraints = CrymbleUI::BoxConstraints.new

            small_size = small_button.measure(constraints)
            large_size = large_button.measure(constraints)

            # Larger font should produce larger measurements
            large_size.width.should be > small_size.width
            large_size.height.should be > small_size.height
        end

        it "includes padding in size" do
            no_padding = CrymbleUI::Button.new("X", padding: 0.0, font_scale: -3)
            with_padding = CrymbleUI::Button.new("X", padding: 20.0, font_scale: -3)
            constraints = CrymbleUI::BoxConstraints.new

            size_no_pad = no_padding.measure(constraints)
            size_with_pad = with_padding.measure(constraints)

            # Padding should add exactly 40 (20*2) to width and height
            size_with_pad.width.should be_close(size_no_pad.width + 40.0, 0.1)
            size_with_pad.height.should be_close(size_no_pad.height + 40.0, 0.1)
        end

        it "respects box constraints" do
            button = CrymbleUI::Button.new("Very long button text here")
            constraints = CrymbleUI::BoxConstraints.new(
                max_width: 100.0,
                max_height: 50.0
            )

            size = button.measure(constraints)

            size.width.should be <= 100.0
            size.height.should be <= 50.0
        end
    end

    describe "#layout" do
        it "sets bounds at given position" do
            button = CrymbleUI::Button.new("Click")
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            button.layout(constraints, position)

            button.bounds.x.should eq(10.0)
            button.bounds.y.should eq(20.0)
            button.bounds.width.should be > 0
            button.bounds.height.should be > 0
        end

        it "marks button as needing render after layout" do
            button = CrymbleUI::Button.new("Test")
            button.state = CrymbleUI::WidgetState::NeedsLayout

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)
            button.layout(constraints, position)

            # After layout, widget needs to be rendered
            button.state.should eq(CrymbleUI::WidgetState::NeedsRender)
        end
    end


    describe "#on_click" do
        it "calls the callback when clicked" do
            clicked = false
            button = CrymbleUI::Button.new("Click") { clicked = true }

            button.on_click

            clicked.should be_true
        end

        it "can be called multiple times" do
            count = 0
            button = CrymbleUI::Button.new("Click") { count += 1 }

            button.on_click
            button.on_click
            button.on_click

            count.should eq(3)
        end

        it "does nothing when no callback is set" do
            button = CrymbleUI::Button.new("Click")

            # Should not raise
            button.on_click
        end
    end

    describe "#trigger_click" do
        it "triggers the callback via trigger_click" do
            clicked = false
            button = CrymbleUI::Button.new("Test") { clicked = true }

            button.trigger_click

            clicked.should be_true
        end
    end

    describe "integration" do
        it "works in widget tree" do
            parent = CrymbleUI::VStack.new(id: "container")
            button = CrymbleUI::Button.new("Save", id: "save_btn") { }

            parent.add_child(button)

            parent.children.should contain(button)
            button.parent.should eq(parent)
            button.path_id.should eq("container/save_btn")
        end

        it "generates path_id from text when no id" do
            parent = CrymbleUI::VStack.new(id: "toolbar")
            button = CrymbleUI::Button.new("Submit") { }

            parent.add_child(button)

            button.path_id.should eq("toolbar/Submit")
        end

        it "can be found with WidgetTester" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = ButtonTestApp.new

            tester.pump(app)

            # Find button
            button = tester.find("btn")
            button.should_not be_nil
            button.not_nil!.is_a?(CrymbleUI::Button).should be_true

            # Trigger click
            tester.tap("btn")

            # Check callback was called
            app.clicked.should be_true
        end
    end

    describe "#to_primitives" do
        it "generates three primitives (background, border, text)" do
            button = CrymbleUI::Button.new("Click")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = button.to_primitives(bounds)

            primitives.size.should eq(3)
            primitives[0].should be_a(CrymbleUI::FillRect)
            primitives[1].should be_a(CrymbleUI::DrawRect)
            primitives[2].should be_a(CrymbleUI::DrawText)
        end

        it "background primitive has correct bounds and color" do
            bg = CrymbleUI::Color.new(255, 0, 0, 255)
            button = CrymbleUI::Button.new("Test", background_color: bg)
            bounds = CrymbleUI::Rect.new(10, 20, 100, 40)

            primitives = button.to_primitives(bounds)
            background = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: starts at (0,0)
            background.bounds.should eq(CrymbleUI::Rect.new(0, 0, 100, 40))
            background.color.should eq(bg)
        end

        it "border primitive has correct bounds and color" do
            border = CrymbleUI::Color.new(0, 255, 0, 255)
            button = CrymbleUI::Button.new("Test", border_color: border)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = button.to_primitives(bounds)
            border_prim = primitives[1].as(CrymbleUI::DrawRect)

            border_prim.bounds.should eq(bounds)
            border_prim.color.should eq(border)
        end

        it "text primitive has correct content and position (aligned)" do
            button = CrymbleUI::Button.new("Save", padding: 10.0, font_scale: 1)
            bounds = CrymbleUI::Rect.new(5, 15, 100, 40)
            font_size = button.font_size  # ~15.4pt

            primitives = button.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.text.should eq("Save")

            # Text should be centered both horizontally and vertically
            # draw_text compensates for SFML's left/top offsets
            # Widget-local coordinates: origin is (0,0)
            text_size = CrymbleUI::Widget.measure_text("Save", font_size)
            # Horizontal: centered minus left offset (widget-local origin)
            expected_x_center = 0.0 + (bounds.width - text_size.width) / 2.0
            # Vertical: centered minus top offset (widget-local origin)
            expected_y_center = 0.0 + (bounds.height - font_size) / 2.0
            if font = CrymbleUI::Widget.font
                left_offset, top_offset = font.get_text_offsets("Save", font_size)
                expected_x = expected_x_center - left_offset
                expected_y = expected_y_center - top_offset
            else
                expected_x = expected_x_center
                expected_y = expected_y_center
            end

            text.position.x.should eq(expected_x)
            text.position.y.should eq(expected_y)
        end

        it "text primitive has correct color and size" do
            color = CrymbleUI::Color.new(0, 0, 255, 255)
            button = CrymbleUI::Button.new("Test", text_color: color, font_scale: 4)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = button.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.color.should eq(color)
            text.size.should be_close(20.49, 0.1)  # scale 4 = 14 * 1.1^4
        end

    end

    describe "hover state primitives" do
        it "generates brighter colors when hovered" do
            bg = CrymbleUI::Color.new(100, 100, 100, 255)
            border = CrymbleUI::Color.new(50, 50, 50, 255)
            button = CrymbleUI::Button.new("Hover", background_color: bg, border_color: border)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            # Normal state
            normal_prims = button.to_primitives(bounds)
            normal_bg = normal_prims[0].as(CrymbleUI::FillRect)
            normal_border = normal_prims[1].as(CrymbleUI::DrawRect)

            # Enter hover state
            button.on_mouse_enter

            # Hovered state
            hover_prims = button.to_primitives(bounds)
            hover_bg = hover_prims[0].as(CrymbleUI::FillRect)
            hover_border = hover_prims[1].as(CrymbleUI::DrawRect)

            # Colors should be brighter (multiplied by HOVER_BRIGHTNESS = 1.15)
            hover_bg.color.r.should be > normal_bg.color.r
            hover_bg.color.g.should be > normal_bg.color.g
            hover_bg.color.b.should be > normal_bg.color.b

            hover_border.color.r.should be > normal_border.color.r
            hover_border.color.g.should be > normal_border.color.g
            hover_border.color.b.should be > normal_border.color.b
        end

        it "reverts to normal colors when hover ends" do
            bg = CrymbleUI::Color.new(100, 100, 100, 255)
            button = CrymbleUI::Button.new("Test", background_color: bg)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            # Enter and exit hover
            button.on_mouse_enter
            button.on_mouse_exit

            # Should be back to normal
            primitives = button.to_primitives(bounds)
            background = primitives[0].as(CrymbleUI::FillRect)

            background.color.should eq(bg)
        end
    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            button = CrymbleUI::Button.new("Cached")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            # First call generates
            primitives1 = button.get_primitives(bounds)
            button.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = button.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates primitives when hover state changes" do
            button = CrymbleUI::Button.new("Hover")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives1 = button.get_primitives(bounds)

            # on_mouse_enter calls mark_needs_render
            button.on_mouse_enter

            primitives2 = button.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)

            # And colors should be different
            bg1 = primitives1[0].as(CrymbleUI::FillRect)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)
            bg1.color.should_not eq(bg2.color)
        end

        it "regenerates primitives when text changes" do
            button = CrymbleUI::Button.new("Original")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives1 = button.get_primitives(bounds)
            text1 = primitives1[2].as(CrymbleUI::DrawText)

            # text= calls mark_needs_render
            button.text = "Modified"

            primitives2 = button.get_primitives(bounds)
            text2 = primitives2[2].as(CrymbleUI::DrawText)

            text1.text.should eq("Original")
            text2.text.should eq("Modified")
        end

        it "regenerates primitives when colors change" do
            button = CrymbleUI::Button.new("Test")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives1 = button.get_primitives(bounds)
            bg1 = primitives1[0].as(CrymbleUI::FillRect)

            # background_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            button.background_color = new_color

            primitives2 = button.get_primitives(bounds)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)

            bg1.color.should_not eq(new_color)
            bg2.color.should eq(new_color)
        end
    end
end
