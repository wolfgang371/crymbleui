require "../spec_helper"
require "../../src/widgets/text"

describe CrymbleUI::Text do
    describe "#initialize" do
        it "creates text widget with content" do
            text = CrymbleUI::Text.new("Hello")
            text.text.should eq("Hello")
        end

        it "uses default font scale (0 = 14pt)" do
            text = CrymbleUI::Text.new("Hello")
            text.font_scale.should eq(0)
            text.font_size.should eq(14.0)
        end

        it "uses default black color" do
            text = CrymbleUI::Text.new("Hello")
            text.color.r.should eq(0)
            text.color.g.should eq(0)
            text.color.b.should eq(0)
            text.color.a.should eq(255)
        end

        it "accepts custom font scale" do
            text = CrymbleUI::Text.new("Hello", font_scale: 4)
            text.font_scale.should eq(4)
            text.font_size.should be_close(20.49, 0.1)  # 14 * 1.1^4
        end

        it "accepts custom color" do
            color = CrymbleUI::Color.new(255, 0, 0, 255)
            text = CrymbleUI::Text.new("Hello", color: color)
            text.color.should eq(color)
        end

        it "accepts id parameter" do
            text = CrymbleUI::Text.new("Hello", id: "my_text")
            text.id.should eq("my_text")
        end
    end

    describe "#label" do
        it "returns text content as label" do
            text = CrymbleUI::Text.new("Hello World")
            text.label.should eq("Hello World")
        end
    end

    describe "#measure" do
        it "calculates size based on text length" do
            text = CrymbleUI::Text.new("Hello")
            constraints = CrymbleUI::BoxConstraints.new
            size = text.measure(constraints)

            # With actual font metrics (not approximation)
            size.width.should be > 0
            size.height.should be > 0
            # Width should be reasonable for 5 chars at font_size 16
            size.width.should be >= 40.0
            size.width.should be <= 60.0
        end

        it "scales with font scale" do
            text = CrymbleUI::Text.new("Test", font_scale: 6)  # ~24.77pt
            constraints = CrymbleUI::BoxConstraints.new
            size = text.measure(constraints)

            # Larger font should produce larger measurements
            size.width.should be > 50.0
            size.height.should be > 20.0
        end

        it "respects box constraints" do
            text = CrymbleUI::Text.new("Very long text that should be constrained")
            constraints = CrymbleUI::BoxConstraints.new(
                max_width: 100.0,
                max_height: 50.0
            )
            size = text.measure(constraints)

            size.width.should be <= 100.0
            size.height.should be <= 50.0
        end
    end

    describe "#layout" do
        it "sets bounds based on position and measured size" do
            text = CrymbleUI::Text.new("Hello")
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            text.layout(constraints, position)

            text.bounds.x.should eq(10.0)
            text.bounds.y.should eq(20.0)
            text.bounds.width.should be > 0
            text.bounds.height.should be > 0
        end

        it "marks widget as needing render after layout" do
            text = CrymbleUI::Text.new("Hello")
            text.state = CrymbleUI::WidgetState::NeedsLayout

            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(0.0, 0.0)
            text.layout(constraints, position)

            # After layout, widget needs to be rendered
            text.state.should eq(CrymbleUI::WidgetState::NeedsRender)
        end
    end


    describe "integration" do
        it "can be added as child to widget tree" do
            parent = TestWidget.new(id: "parent")
            text = CrymbleUI::Text.new("Child text", id: "text1")

            parent.add_child(text)

            parent.children.should contain(text)
            text.parent.should eq(parent)
        end

        it "generates correct path_id" do
            parent = TestWidget.new(id: "window")
            text = CrymbleUI::Text.new("Save", id: "save_btn")
            parent.add_child(text)

            text.path_id.should eq("window/save_btn")
        end

        it "uses text as path segment when no id" do
            parent = TestWidget.new(id: "panel")
            text = CrymbleUI::Text.new("Status: OK")
            parent.add_child(text)

            text.path_id.should eq("panel/Status: OK")
        end
    end

    describe "#to_primitives" do
        it "generates single DrawText primitive" do
            text = CrymbleUI::Text.new("Hello", font_scale: 3)  # ~18.63pt
            bounds = CrymbleUI::Rect.new(10.0, 10.0, 100.0, 30.0)

            primitives = text.to_primitives(bounds)

            primitives.size.should eq(1)
            primitives[0].should be_a(CrymbleUI::DrawText)
        end

        it "primitive has correct text content" do
            text = CrymbleUI::Text.new("Test Message")
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            primitives = text.to_primitives(bounds)
            primitive = primitives[0].as(CrymbleUI::DrawText)

            primitive.text.should eq("Test Message")
        end

        it "primitive has correct position from bounds" do
            text = CrymbleUI::Text.new("Hello")
            bounds = CrymbleUI::Rect.new(25.0, 50.0, 100.0, 30.0)

            primitives = text.to_primitives(bounds)
            primitive = primitives[0].as(CrymbleUI::DrawText)

            # Text is left-aligned at x=padding (0 by default), vertically centered
            font_size = text.font_size
            expected_x = 0.0  # padding=0 default
            expected_y = (30.0 - font_size) / 2.0
            # draw_text compensates for SFML local_bounds offsets
            if font = CrymbleUI::Widget.font
                left_offset, top_offset = font.get_text_offsets("Hello", font_size)
                expected_x -= left_offset
                expected_y -= top_offset
            end
            primitive.position.x.should be_close(expected_x, 1.0)
            primitive.position.y.should be_close(expected_y, 1.0)
        end

        it "primitive has correct color" do
            color = CrymbleUI::Color.new(255, 128, 0, 255)
            text = CrymbleUI::Text.new("Colored", color: color)
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            primitives = text.to_primitives(bounds)
            primitive = primitives[0].as(CrymbleUI::DrawText)

            primitive.color.should eq(color)
        end

        it "primitive has correct font size" do
            text = CrymbleUI::Text.new("Sized", font_scale: 6)  # ~24.77pt
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 40.0)

            primitives = text.to_primitives(bounds)
            primitive = primitives[0].as(CrymbleUI::DrawText)

            primitive.size.should be_close(24.77, 0.1)
        end

    end

    describe "vertical centering in constrained bounds" do
        it "text is vertically centered when bounds are taller than natural" do
            text = CrymbleUI::Text.new("Hello")
            tall_bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 60.0)

            # Layout with tight constraints (like VirtualMatrix cell)
            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 60.0)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(tall_bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            # draw_text compensates for font offsets (SFML top_offset), so compute expected
            # the same way: center with font_size, then subtract top_offset
            font_size = text.font_size
            expected_y = (60.0 - font_size) / 2.0
            if font = CrymbleUI::Widget.font
                _, top_offset = font.get_text_offsets("Hello", font_size)
                expected_y -= top_offset
            end
            dt.position.y.should be_close(expected_y, 1.0)
        end

        it "text is vertically centered with background fill" do
            text = CrymbleUI::Text.new("World", background_color: CrymbleUI::Color.new(255, 255, 255, 255))
            tall_bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 40.0)

            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 40.0)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(tall_bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            font_size = text.font_size
            expected_y = (40.0 - font_size) / 2.0
            if font = CrymbleUI::Widget.font
                _, top_offset = font.get_text_offsets("World", font_size)
                expected_y -= top_offset
            end
            dt.position.y.should be_close(expected_y, 1.0)
        end

        it "text stays at y=0 when bounds match natural height" do
            text = CrymbleUI::Text.new("Hi")
            natural_h = text.font_size
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, natural_h)

            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, natural_h)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            # At natural height, centering is no-op: (font_size - font_size) / 2 = 0
            # draw_text subtracts top_offset, so expected = 0 - top_offset
            expected_y = 0.0
            if font = CrymbleUI::Widget.font
                _, top_offset = font.get_text_offsets("Hi", text.font_size)
                expected_y -= top_offset
            end
            dt.position.y.should be_close(expected_y, 1.0)
        end
    end

    describe "padding" do
        it "text is left-aligned with padding offset in wide bounds" do
            text = CrymbleUI::Text.new("Hello", padding: 4.0)
            wide_bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)

            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 30.0)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(wide_bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            expected_x = 4.0
            if font = CrymbleUI::Widget.font
                left_offset, _ = font.get_text_offsets("Hello", text.font_size)
                expected_x -= left_offset
            end
            dt.position.x.should be_close(expected_x, 1.0)
        end

        it "padding=0 gives x=0 (default, backward compatible)" do
            text = CrymbleUI::Text.new("Hi")
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 30.0)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            expected_x = 0.0
            if font = CrymbleUI::Widget.font
                left_offset, _ = font.get_text_offsets("Hi", text.font_size)
                expected_x -= left_offset
            end
            dt.position.x.should be_close(expected_x, 1.0)
        end

        it "padding included in measure" do
            text_no_pad = CrymbleUI::Text.new("X")
            text_with_pad = CrymbleUI::Text.new("X", padding: 4.0)
            constraints = CrymbleUI::BoxConstraints.new

            size_no_pad = text_no_pad.measure(constraints)
            size_with_pad = text_with_pad.measure(constraints)

            size_with_pad.width.should be_close(size_no_pad.width + 8.0, 0.1)
            size_with_pad.height.should be_close(size_no_pad.height + 8.0, 0.1)
        end

        it "vertical centering accounts for padding" do
            text = CrymbleUI::Text.new("Hi", padding: 4.0)
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 40.0)

            text.perform_layout(
                CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 40.0)),
                CrymbleUI::Vec2.zero
            )
            prims = text.to_primitives(bounds)
            dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            font_size = text.font_size
            # Vertical: padding + centered within content area
            content_h = 40.0 - 4.0 * 2
            expected_y = 4.0 + (content_h - font_size) / 2.0
            if font = CrymbleUI::Widget.font
                _, top_offset = font.get_text_offsets("Hi", font_size)
                expected_y -= top_offset
            end
            dt.position.y.should be_close(expected_y, 1.0)
        end
    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            text = CrymbleUI::Text.new("Cached")
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            # First call generates
            primitives1 = text.get_primitives(bounds)
            text.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = text.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates primitives when marked dirty" do
            text = CrymbleUI::Text.new("Dynamic")
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            primitives1 = text.get_primitives(bounds)
            text.mark_needs_render  # Invalidate cache
            primitives2 = text.get_primitives(bounds)

            primitives1.should_not be(primitives2)  # Different objects
        end

        it "regenerates primitives when text changes" do
            text = CrymbleUI::Text.new("Original")
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)

            primitives1 = text.get_primitives(bounds)
            primitive1 = primitives1[0].as(CrymbleUI::DrawText)

            # Change text and mark dirty
            text.text = "Modified"
            text.mark_needs_render

            primitives2 = text.get_primitives(bounds)
            primitive2 = primitives2[0].as(CrymbleUI::DrawText)

            primitive1.text.should eq("Original")
            primitive2.text.should eq("Modified")
        end
    end
end
