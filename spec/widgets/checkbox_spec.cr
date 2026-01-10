require "../spec_helper"

# Test app for checkbox testing
class CheckboxTestApp < CrymbleUI::App
    @accepted : Bool = false
    @select_all : CrymbleUI::CheckState = CrymbleUI::CheckState::Unchecked

    def accepted : Bool
        @accepted
    end

    def select_all : CrymbleUI::CheckState
        @select_all
    end

    def accepted=(value : Bool)
        @accepted = value
        if root = @root
            root.mark_needs_layout
        else
            rebuild
        end
    end

    def select_all=(value : CrymbleUI::CheckState)
        @select_all = value
        if root = @root
            root.mark_needs_layout
        else
            rebuild
        end
    end

    def build : CrymbleUI::Widget
        window("Test", 400, 300) do
            vstack do
                # Bool checkbox with block
                checkbox("Accept", checked: self.accepted, id: "accept_cb") do
                    self.accepted = !self.accepted
                end

                # Tristate checkbox with block
                checkbox("Select all", state: self.select_all, id: "select_all_cb") do
                    current = self.select_all
                    self.select_all = case current
                    when CrymbleUI::CheckState::Unchecked then CrymbleUI::CheckState::Checked
                    when CrymbleUI::CheckState::Checked then CrymbleUI::CheckState::Indeterminate
                    when CrymbleUI::CheckState::Indeterminate then CrymbleUI::CheckState::Unchecked
                    else CrymbleUI::CheckState::Unchecked
                    end
                end
            end
        end
    end
end

describe CrymbleUI::Checkbox do
    describe ".new" do
        it "creates a checkbox with default values" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            checkbox.text.should eq("Test")
            checkbox.checked.should be_false
            checkbox.check_state.should eq(CrymbleUI::CheckState::Unchecked)
        end

        it "creates a checkbox with checked state" do
            checkbox = CrymbleUI::Checkbox.new("Test", checked: true)
            checkbox.checked.should be_true
        end

        it "creates a checkbox with tristate" do
            checkbox = CrymbleUI::Checkbox.new("Test", check_state: CrymbleUI::CheckState::Indeterminate)
            checkbox.check_state.should eq(CrymbleUI::CheckState::Indeterminate)
        end

        it "creates a checkbox with custom colors" do
            checkbox = CrymbleUI::Checkbox.new(
                "Test",
                text_color: CrymbleUI::Color.red,
                box_color: CrymbleUI::Color.blue,
                check_color: CrymbleUI::Color.green
            )
            checkbox.text_color.should eq(CrymbleUI::Color.red)
            checkbox.box_color.should eq(CrymbleUI::Color.blue)
            checkbox.check_color.should eq(CrymbleUI::Color.green)
        end

        it "creates a checkbox with custom scales" do
            checkbox = CrymbleUI::Checkbox.new(
                "Test",
                box_scale: 1,
                spacing: 10.0,
                font_scale: 1
            )
            checkbox.box_scale.should eq(1)
            checkbox.spacing.should eq(10.0)
            checkbox.font_scale.should eq(1)
        end
    end

    describe "#checked=" do
        it "updates the checked state and marks for render" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            checkbox.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            checkbox.checked = true
            checkbox.checked.should be_true
            checkbox.needs_render?.should be_true
        end
    end

    describe "#check_state=" do
        it "updates the check state and marks for render" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            checkbox.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            checkbox.check_state = CrymbleUI::CheckState::Checked
            checkbox.check_state.should eq(CrymbleUI::CheckState::Checked)
            checkbox.needs_render?.should be_true
        end
    end

    describe "#measure" do
        it "returns appropriate size based on label and box" do
            checkbox = CrymbleUI::Checkbox.new("Test", box_scale: 0, font_scale: 0)
            constraints = CrymbleUI::BoxConstraints.new(max_width: 800.0, max_height: 600.0)
            size = checkbox.measure(constraints)

            # Width should be box + spacing + approximate text width
            size.width.should be > checkbox.effective_box_size
            # Height should be at least box size or font size
            size.height.should be >= checkbox.effective_box_size
        end
    end

    describe "#layout" do
        it "positions checkbox at given position" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 400.0))
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            checkbox.layout(constraints, position)

            checkbox.bounds.x.should eq(10.0)
            checkbox.bounds.y.should eq(20.0)
        end
    end

    describe "#trigger_click" do
        it "calls the click callback when provided" do
            clicked = false
            checkbox = CrymbleUI::Checkbox.new("Test") do
                clicked = true
            end

            checkbox.trigger_click
            clicked.should be_true
        end

        it "does nothing when no callback provided" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            # Should not raise
            checkbox.trigger_click
        end
    end

    describe "#label" do
        it "returns 'checkbox' for path_id generation" do
            checkbox = CrymbleUI::Checkbox.new("Test Label")
            checkbox.label.should eq("checkbox")
        end
    end

    describe "property setters" do
        it "marks needs_render when visual properties change" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            checkbox.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            checkbox.font_scale = 1
            checkbox.needs_render?.should be_true
            checkbox.state = CrymbleUI::WidgetState::Clean

            checkbox.text_color = CrymbleUI::Color.red
            checkbox.needs_render?.should be_true
            checkbox.state = CrymbleUI::WidgetState::Clean

            checkbox.box_color = CrymbleUI::Color.blue
            checkbox.needs_render?.should be_true
            checkbox.state = CrymbleUI::WidgetState::Clean

            checkbox.check_color = CrymbleUI::Color.green
            checkbox.needs_render?.should be_true
        end

        it "marks needs_layout when structural properties change" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            checkbox.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            checkbox.box_scale = 1
            checkbox.needs_layout?.should be_true
            checkbox.state = CrymbleUI::WidgetState::Clean

            checkbox.spacing = 10.0
            checkbox.needs_layout?.should be_true
        end
    end

    describe "integration with app" do
        it "toggles bool checkbox when clicked" do
            app = CheckboxTestApp.new
            app.build_tree

            # Layout the tree
            root = app.root.not_nil!
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
            root.layout(constraints, CrymbleUI::Vec2.zero)

            # Find checkbox
            cb = root.find_by_id("accept_cb").not_nil!.as(CrymbleUI::Checkbox)

            # Initial state should be unchecked
            app.accepted.should be_false

            # Trigger click directly
            cb.trigger_click

            # State should now be true
            app.accepted.should be_true

            # Rebuild and layout the tree
            app.rebuild
            app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)

            # Find checkbox in new tree
            new_cb = app.root.not_nil!.find_by_id("accept_cb").not_nil!.as(CrymbleUI::Checkbox)

            # Checkbox should show as checked
            new_cb.checked.should be_true
        end

        it "cycles through tristate checkbox states when clicked" do
            app = CheckboxTestApp.new
            app.build_tree

            # Layout the tree
            root = app.root.not_nil!
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
            root.layout(constraints, CrymbleUI::Vec2.zero)

            # Find checkbox
            cb = root.find_by_id("select_all_cb").not_nil!.as(CrymbleUI::Checkbox)

            # Initial state should be unchecked
            app.select_all.should eq(CrymbleUI::CheckState::Unchecked)

            # Click 1: Unchecked -> Checked
            cb.trigger_click
            app.select_all.should eq(CrymbleUI::CheckState::Checked)

            # Rebuild and layout
            app.rebuild
            app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)
            cb = app.root.not_nil!.find_by_id("select_all_cb").not_nil!.as(CrymbleUI::Checkbox)

            # Click 2: Checked -> Indeterminate
            cb.trigger_click
            app.select_all.should eq(CrymbleUI::CheckState::Indeterminate)

            # Rebuild and layout
            app.rebuild
            app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)
            cb = app.root.not_nil!.find_by_id("select_all_cb").not_nil!.as(CrymbleUI::Checkbox)

            # Click 3: Indeterminate -> Unchecked
            cb.trigger_click
            app.select_all.should eq(CrymbleUI::CheckState::Unchecked)
        end
    end

    describe "#to_primitives" do
        it "generates primitives for unchecked state" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = checkbox.to_primitives(bounds)

            # Unchecked: 4 border rects (top/bottom/left/right) + text (5 primitives)
            primitives.size.should eq(5)
            primitives[0].should be_a(CrymbleUI::FillRect)  # Top edge
            primitives[1].should be_a(CrymbleUI::FillRect)  # Bottom edge
            primitives[2].should be_a(CrymbleUI::FillRect)  # Left edge
            primitives[3].should be_a(CrymbleUI::FillRect)  # Right edge
            primitives[4].should be_a(CrymbleUI::DrawText)  # Label text
        end

        it "generates primitives for checked state" do
            checkbox = CrymbleUI::Checkbox.new("Test", checked: true)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = checkbox.to_primitives(bounds)

            # Checked: 4 border rects + 2 checkmark lines + junction circle + text (8 primitives)
            primitives.size.should eq(8)
            primitives[0].should be_a(CrymbleUI::FillRect)   # Top edge
            primitives[1].should be_a(CrymbleUI::FillRect)   # Bottom edge
            primitives[2].should be_a(CrymbleUI::FillRect)   # Left edge
            primitives[3].should be_a(CrymbleUI::FillRect)   # Right edge
            primitives[4].should be_a(CrymbleUI::DrawLine)   # Check mark line 1
            primitives[5].should be_a(CrymbleUI::DrawLine)   # Check mark line 2
            primitives[6].should be_a(CrymbleUI::DrawCircle) # Junction circle
            primitives[7].should be_a(CrymbleUI::DrawText)   # Label text
        end

        it "generates primitives for indeterminate state" do
            checkbox = CrymbleUI::Checkbox.new("Test", check_state: CrymbleUI::CheckState::Indeterminate)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = checkbox.to_primitives(bounds)

            # Indeterminate: 4 border rects + horizontal line + text (6 primitives)
            primitives.size.should eq(6)
            primitives[0].should be_a(CrymbleUI::FillRect)  # Top edge
            primitives[1].should be_a(CrymbleUI::FillRect)  # Bottom edge
            primitives[2].should be_a(CrymbleUI::FillRect)  # Left edge
            primitives[3].should be_a(CrymbleUI::FillRect)  # Right edge
            primitives[4].should be_a(CrymbleUI::DrawLine)  # Horizontal line
            primitives[5].should be_a(CrymbleUI::DrawText)  # Label text
        end

        it "box primitive has correct bounds and color" do
            box_color = CrymbleUI::Color.new(50, 50, 50, 255)
            checkbox = CrymbleUI::Checkbox.new("Test", box_color: box_color, box_scale: 1)
            bounds = CrymbleUI::Rect.new(10, 10, 100, 40)

            primitives = checkbox.to_primitives(bounds)
            top_edge = primitives[0].as(CrymbleUI::FillRect)
            left_edge = primitives[2].as(CrymbleUI::FillRect)

            # Box border should have correct dimensions based on effective_box_size
            expected_size = checkbox.effective_box_size
            top_edge.bounds.width.should be_close(expected_size, 0.1)
            top_edge.bounds.height.should eq(1.0)
            top_edge.color.should eq(box_color)
            # Left edge should span full box height
            left_edge.bounds.width.should eq(1.0)
            left_edge.bounds.height.should be_close(expected_size, 0.1)
            left_edge.color.should eq(box_color)
        end

        it "check mark primitive has correct color" do
            check_color = CrymbleUI::Color.green
            checkbox = CrymbleUI::Checkbox.new("Test", checked: true, check_color: check_color, box_scale: 0)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = checkbox.to_primitives(bounds)
            check_line1 = primitives[4].as(CrymbleUI::DrawLine)
            check_line2 = primitives[5].as(CrymbleUI::DrawLine)

            # Both checkmark lines should have the check color
            check_line1.color.should eq(check_color)
            check_line2.color.should eq(check_color)
        end

        it "text primitive has correct content and color" do
            text_color = CrymbleUI::Color.new(255, 0, 0, 255)
            checkbox = CrymbleUI::Checkbox.new("Accept Terms", text_color: text_color)
            bounds = CrymbleUI::Rect.new(0, 0, 150, 30)

            primitives = checkbox.to_primitives(bounds)
            text = primitives.last.as(CrymbleUI::DrawText)

            text.text.should eq("Accept Terms")
            text.color.should eq(text_color)
        end

        it "text primitive is positioned after box and spacing" do
            checkbox = CrymbleUI::Checkbox.new("Test", box_scale: 0, spacing: 10.0)
            bounds = CrymbleUI::Rect.new(5, 10, 100, 30)

            primitives = checkbox.to_primitives(bounds)
            text = primitives.last.as(CrymbleUI::DrawText)

            # Text at widget-local: box_x (0) + effective_box_size + spacing
            expected_x = checkbox.effective_box_size + 10.0
            text.position.x.should be_close(expected_x, 2.0)
        end

    end

    describe "focus highlighting" do
        it "renders box with brighter color when focus_highlighted is true" do
            box_color = CrymbleUI::Color.new(100, 100, 100, 255)
            checkbox = CrymbleUI::Checkbox.new("Test", box_color: box_color)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            # Get primitives without focus highlight
            checkbox.focus_highlighted = false
            primitives_normal = checkbox.to_primitives(bounds)
            top_edge_normal = primitives_normal[0].as(CrymbleUI::FillRect)

            # Get primitives with focus highlight
            checkbox.focus_highlighted = true
            checkbox.mark_needs_render  # Ensure regeneration
            primitives_highlighted = checkbox.to_primitives(bounds)
            top_edge_highlighted = primitives_highlighted[0].as(CrymbleUI::FillRect)

            # Box border should be brighter when focus_highlighted (like button does)
            # Uses additive HSV brightness (0.35 in V space for checkbox)
            expected_bright = box_color.add_brightness(0.35)
            top_edge_normal.color.should eq(box_color)
            top_edge_highlighted.color.should eq(expected_bright)
        end

        it "all four border edges use highlighted color" do
            box_color = CrymbleUI::Color.new(100, 100, 100, 255)
            checkbox = CrymbleUI::Checkbox.new("Test", box_color: box_color)
            checkbox.focus_highlighted = true
            bounds = CrymbleUI::Rect.new(0, 0, 100, 40)

            primitives = checkbox.to_primitives(bounds)

            # All 4 border edges should have the brightened color
            expected_bright = box_color.add_brightness(0.35)
            primitives[0].as(CrymbleUI::FillRect).color.should eq(expected_bright)  # Top
            primitives[1].as(CrymbleUI::FillRect).color.should eq(expected_bright)  # Bottom
            primitives[2].as(CrymbleUI::FillRect).color.should eq(expected_bright)  # Left
            primitives[3].as(CrymbleUI::FillRect).color.should eq(expected_bright)  # Right
        end
    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            checkbox = CrymbleUI::Checkbox.new("Cached")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 30)

            # First call generates
            primitives1 = checkbox.get_primitives(bounds)
            checkbox.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = checkbox.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates primitives when checked state changes" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 30)

            # Get unchecked primitives
            primitives1 = checkbox.get_primitives(bounds)
            primitives1.size.should eq(5)  # Unchecked: 4 border rects + text

            # Change to checked (calls mark_needs_render)
            checkbox.checked = true

            # Get checked primitives
            primitives2 = checkbox.get_primitives(bounds)
            primitives2.size.should eq(8)  # Checked: 4 border rects + 2 checkmark lines + junction circle + text

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates primitives when check_state changes" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 30)

            primitives1 = checkbox.get_primitives(bounds)

            # check_state= calls mark_needs_render
            checkbox.check_state = CrymbleUI::CheckState::Indeterminate

            primitives2 = checkbox.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates primitives when text changes" do
            checkbox = CrymbleUI::Checkbox.new("Original")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 30)

            primitives1 = checkbox.get_primitives(bounds)
            text1 = primitives1.last.as(CrymbleUI::DrawText)

            # text= calls mark_needs_render
            checkbox.text = "Modified"

            primitives2 = checkbox.get_primitives(bounds)
            text2 = primitives2.last.as(CrymbleUI::DrawText)

            text1.text.should eq("Original")
            text2.text.should eq("Modified")
        end

        it "regenerates primitives when colors change" do
            checkbox = CrymbleUI::Checkbox.new("Test")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 30)

            primitives1 = checkbox.get_primitives(bounds)
            top_edge1 = primitives1[0].as(CrymbleUI::FillRect)

            # box_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            checkbox.box_color = new_color

            primitives2 = checkbox.get_primitives(bounds)
            top_edge2 = primitives2[0].as(CrymbleUI::FillRect)

            top_edge1.color.should_not eq(new_color)
            top_edge2.color.should eq(new_color)
        end
    end
end
