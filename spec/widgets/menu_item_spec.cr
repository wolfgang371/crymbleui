require "../spec_helper"
require "../../src/widgets/menu_item"

describe CrymbleUI::MenuItem do
    describe "#initialize" do
        it "creates menu item with label" do
            item = CrymbleUI::MenuItem.new("Copy") { }
            item.label_text.should eq("Copy")
            item.shortcut.should be_nil
            item.checked.should be_false
        end

        it "creates menu item with shortcut" do
            item = CrymbleUI::MenuItem.new("Save", "Ctrl+S") { }
            item.label_text.should eq("Save")
            item.shortcut.should eq("Ctrl+S")
        end

        it "creates checkable menu item when checked is provided" do
            item = CrymbleUI::MenuItem.new("Dark Mode", checked: false) { }
            item.checkable.should be_true
            item.checked.should be_false
        end

        it "creates checked menu item" do
            item = CrymbleUI::MenuItem.new("Show Toolbar", checked: true) { }
            item.checkable.should be_true
            item.checked.should be_true
        end

        it "accepts id parameter" do
            item = CrymbleUI::MenuItem.new("Test", id: "test_item") { }
            item.id.should eq("test_item")
        end
    end

    describe "#label" do
        it "returns 'menuitem' for path_id generation" do
            item = CrymbleUI::MenuItem.new("Test") { }
            item.label.should eq("menuitem")
        end
    end

    describe "#measure" do
        it "returns dynamic height based on font" do
            item = CrymbleUI::MenuItem.new("Test") { }
            constraints = CrymbleUI::BoxConstraints.new
            size = item.measure(constraints)

            size.height.should eq(item.item_height)
        end

        it "width includes space for checkmark, label, and padding" do
            item = CrymbleUI::MenuItem.new("Copy") { }
            constraints = CrymbleUI::BoxConstraints.new
            size = item.measure(constraints)

            # Should include: check width (16) + label + padding*2
            size.width.should be > 16.0
        end

        it "width includes shortcut when present" do
            item1 = CrymbleUI::MenuItem.new("Copy") { }
            item2 = CrymbleUI::MenuItem.new("Copy", "Ctrl+C") { }
            constraints = CrymbleUI::BoxConstraints.new

            size1 = item1.measure(constraints)
            size2 = item2.measure(constraints)

            # Item with shortcut should be wider
            size2.width.should be > size1.width
        end
    end

    describe "#on_mouse_enter and #on_mouse_exit" do
        it "sets hovered state and marks for render" do
            item = CrymbleUI::MenuItem.new("Test") { }
            item.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            item.on_mouse_enter
            item.needs_render?.should be_true
        end

        it "clears hovered state on exit" do
            item = CrymbleUI::MenuItem.new("Test") { }
            item.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            item.on_mouse_enter
            item.get_primitives(item.bounds) # real render: captures `hovered` (reactive, no manual mark)

            item.on_mouse_exit
            item.needs_render?.should be_true
        end
    end

    describe "#to_primitives" do
        it "generates label text primitive (minimum)" do
            item = CrymbleUI::MenuItem.new("Copy") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives = item.to_primitives(bounds)

            # Minimum: just label text
            primitives.size.should be >= 1
            primitives.any? { |p| p.is_a?(CrymbleUI::DrawText) }.should be_true
        end

        it "includes hover background when hovered" do
            item = CrymbleUI::MenuItem.new("Copy") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            # Not hovered
            primitives1 = item.to_primitives(bounds)
            fill_rects1 = primitives1.select { |p| p.is_a?(CrymbleUI::FillRect) }

            # Hovered
            item.on_mouse_enter
            primitives2 = item.to_primitives(bounds)
            fill_rects2 = primitives2.select { |p| p.is_a?(CrymbleUI::FillRect) }

            # Hovered should have more FillRect (hover background)
            fill_rects2.size.should be > fill_rects1.size
        end

        it "hover background has correct bounds and color" do
            hover_color = CrymbleUI::Color.new(0, 120, 215, 255)
            item = CrymbleUI::MenuItem.new("Copy", hover_color: hover_color) { }
            bounds = CrymbleUI::Rect.new(10, 20, 150, 24)

            item.on_mouse_enter
            primitives = item.to_primitives(bounds)
            bg = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }.as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            bg.bounds.should eq(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height))
            bg.color.should eq(hover_color)
        end

        it "includes checkmark when checked" do
            item = CrymbleUI::MenuItem.new("Dark Mode", checked: true) { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives = item.to_primitives(bounds)
            lines = primitives.select { |p| p.is_a?(CrymbleUI::DrawLine) }

            # Should have checkmark (two line segments)
            lines.size.should eq(2)
        end

        it "no checkmark when unchecked" do
            item = CrymbleUI::MenuItem.new("Dark Mode", checked: false) { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives = item.to_primitives(bounds)
            texts = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }.map(&.as(CrymbleUI::DrawText))

            # Should NOT have checkmark text
            texts.any? { |t| t.text == "✓" }.should be_false
        end

        it "label text has correct content" do
            item = CrymbleUI::MenuItem.new("Copy to Clipboard") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives = item.to_primitives(bounds)
            label = primitives.find { |p| p.is_a?(CrymbleUI::DrawText) && p.as(CrymbleUI::DrawText).text == "Copy to Clipboard" }

            label.should_not be_nil
        end

        it "includes shortcut text when present" do
            item = CrymbleUI::MenuItem.new("Save", "Ctrl+S") { }
            bounds = CrymbleUI::Rect.new(0, 0, 200, 24)

            primitives = item.to_primitives(bounds)
            texts = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }.map(&.as(CrymbleUI::DrawText))

            # Should have shortcut text
            texts.any? { |t| t.text == "Ctrl+S" }.should be_true
        end

        it "no shortcut text when not present" do
            item = CrymbleUI::MenuItem.new("Copy") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives = item.to_primitives(bounds)
            texts = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }.map(&.as(CrymbleUI::DrawText))

            # Should only have label text
            texts.size.should eq(1)
            texts[0].text.should eq("Copy")
        end

        it "text color changes when hovered" do
            text_color = CrymbleUI::Color.new(0, 0, 0, 255)
            item = CrymbleUI::MenuItem.new("Copy", text_color: text_color) { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            # Not hovered - should use text_color
            primitives1 = item.to_primitives(bounds)
            label1 = primitives1.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            # Hovered - should use white
            item.on_mouse_enter
            primitives2 = item.to_primitives(bounds)
            label2 = primitives2.find { |p| p.is_a?(CrymbleUI::DrawText) && p.as(CrymbleUI::DrawText).text == "Copy" }.as(CrymbleUI::DrawText)

            label1.color.should eq(text_color)
            label2.color.should eq(CrymbleUI::Color.white)
        end

    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            item = CrymbleUI::MenuItem.new("Cached") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            # First call generates
            primitives1 = item.get_primitives(bounds)
            item.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = item.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates when hover state changes" do
            item = CrymbleUI::MenuItem.new("Hover") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives1 = item.get_primitives(bounds)

            # on_mouse_enter calls mark_needs_render
            item.on_mouse_enter

            primitives2 = item.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates when checked state changes" do
            item = CrymbleUI::MenuItem.new("Toggle", checked: false) { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives1 = item.get_primitives(bounds)

            # checked= calls mark_needs_render
            item.checked = true

            primitives2 = item.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates when label changes" do
            item = CrymbleUI::MenuItem.new("Original") { }
            bounds = CrymbleUI::Rect.new(0, 0, 150, 24)

            primitives1 = item.get_primitives(bounds)

            # label_text= calls mark_needs_render
            item.label_text = "Modified"

            primitives2 = item.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end
    end
end
