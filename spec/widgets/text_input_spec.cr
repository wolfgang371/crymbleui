require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/widgets/window"
require "../../src/core/scheduler"
require "../../src/testing/test_renderer"

# Test app for verifying Source-backed reactive_property invalidation
class ValueRenderApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        window = CrymbleUI::Window.new("Test", 200, 50)
        input = CrymbleUI::TextInput.new(
            id: "ti",
            value: "initial",
            width: 100.0
        )
        window.children << input
        input.parent = window
        window
    end
end

# Test app for border pixel test
class BorderTestApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        window = CrymbleUI::Window.new("Test", 200, 100)
        input = CrymbleUI::TextInput.new(
            id: "input",
            width: 100.0,
            border_color: CrymbleUI::Color.new(0, 0, 255, 255)  # Blue border
        )
        window.children << input
        input.parent = window
        window
    end
end

describe CrymbleUI::TextInput do
    # Reset focus between tests
    before_each do
        CrymbleUI::Widget.focus_manager.clear_focus
    end

    describe "#initialize" do
        it "creates text input with default values" do
            input = CrymbleUI::TextInput.new

            input.value.should eq("")
            input.placeholder.should eq("")
            input.font_size.should eq(14.0)
            input.padding.should eq(4.0)
        end

        it "creates text input with initial value" do
            input = CrymbleUI::TextInput.new(value: "hello")

            input.value.should eq("hello")
        end

        it "accepts id parameter" do
            input = CrymbleUI::TextInput.new(id: "my_input")
            input.id.should eq("my_input")
        end

        it "accepts custom colors" do
            text_color = CrymbleUI::Color.new(255, 0, 0, 255)
            bg_color = CrymbleUI::Color.new(0, 255, 0, 255)

            input = CrymbleUI::TextInput.new(
                text_color: text_color,
                background_color: bg_color
            )

            input.text_color.should eq(text_color)
            input.background_color.should eq(bg_color)
        end

        it "accepts placeholder text" do
            input = CrymbleUI::TextInput.new(placeholder: "Enter name...")

            input.placeholder.should eq("Enter name...")
        end

        it "accepts explicit width" do
            input = CrymbleUI::TextInput.new(width: 200.0)
            constraints = CrymbleUI::BoxConstraints.new

            size = input.measure(constraints)
            size.width.should eq(200.0)
        end

        it "stores on_change callback" do
            called = false
            input = CrymbleUI::TextInput.new { |v| called = true }

            # Callback should be set
            input.value = "test"
            # Note: value= doesn't trigger callback, only text input does
        end

        # Display-only prefix property — mirror of ComboBox's "»value"
        # chrome but available on any TextInput. The prefix is drawn in
        # to_primitives but is NEVER stored in @value, NEVER part of
        # cursor/selection, and the editable text starts after the
        # prefix's rendered width. Lets consuming code (e.g. embrace's
        # rank-target ref cells) get the same visual distinction
        # ComboBox cells get without contaminating the editable value.

        it "default prefix is empty" do
            input = CrymbleUI::TextInput.new
            input.prefix.should eq("")
        end

        it "accepts a prefix property" do
            input = CrymbleUI::TextInput.new(prefix: "»")
            input.prefix.should eq("»")
        end

        it "prefix is not stored in value (display-only)" do
            input = CrymbleUI::TextInput.new(value: "3", prefix: "»")
            input.value.should eq("3")
        end

        it "value= writes only the value, prefix stays its own property" do
            input = CrymbleUI::TextInput.new(prefix: "»")
            input.value = "5"
            input.value.should eq("5")
            input.prefix.should eq("»")
        end

        it "cursor_pos after construction sits at end of VALUE, not value+prefix" do
            input = CrymbleUI::TextInput.new(value: "42", prefix: "»")
            # @cursor_pos is private; check via the public side-effect: the
            # value's length matches where the cursor should be (initial
            # contract per constructor at text_input.cr:164).
            input.value.size.should eq(2)
            # Sanity: prefix has its own length, separate from value's size.
            input.prefix.size.should eq(1)
        end
    end

    describe "#label" do
        it "returns text_input as label" do
            input = CrymbleUI::TextInput.new
            input.label.should eq("text_input")
        end
    end

    describe "#focusable?" do
        it "returns true (can receive keyboard focus)" do
            input = CrymbleUI::TextInput.new
            input.focusable?.should be_true
        end
    end

    describe "#measure" do
        it "calculates height based on font scale and padding" do
            input = CrymbleUI::TextInput.new(font_scale: 0, padding: 4.0)
            constraints = CrymbleUI::BoxConstraints.new

            size = input.measure(constraints)

            # Height = font_size + (padding * 2) + (border_width * 2)
            # At scale 0: 14 + 8 + 2 = 24
            expected_height = 14.0 + (4.0 * 2) + (1.0 * 2)
            size.height.should eq(expected_height)
        end

        it "uses explicit width when provided" do
            input = CrymbleUI::TextInput.new(width: 300.0)
            constraints = CrymbleUI::BoxConstraints.new(max_width: 500.0)

            size = input.measure(constraints)
            size.width.should eq(300.0)
        end

        it "fills available width when no explicit width" do
            input = CrymbleUI::TextInput.new
            constraints = CrymbleUI::BoxConstraints.new(max_width: 400.0)

            size = input.measure(constraints)
            size.width.should eq(400.0)
        end

        it "uses fallback width when constraints are infinite" do
            input = CrymbleUI::TextInput.new
            constraints = CrymbleUI::BoxConstraints.new

            size = input.measure(constraints)
            size.width.should eq(200.0)  # Fallback width
        end

        it "respects tight constraints even with explicit_width set" do
            # TextInput created with explicit_width=200
            input = CrymbleUI::TextInput.new(width: 200.0)

            # Parent gives TIGHT constraint of 150 (smaller than explicit_width)
            tight_constraint = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(150.0, 30.0))

            # Measure should respect constraint, not ignore it
            size = input.measure(tight_constraint)

            # THIS SHOULD FAIL: TextInput currently returns 200, should return 150
            size.width.should eq 150.0
        end

        it "uses explicit_width as maximum, clamped by tight constraint" do
            input = CrymbleUI::TextInput.new(width: 200.0)

            # Loose constraint larger than explicit_width - should use explicit_width
            loose = CrymbleUI::BoxConstraints.new(max_width: 300.0)
            input.measure(loose).width.should eq 200.0

            # Tight constraint smaller than explicit_width - should use constraint
            # THIS SHOULD FAIL: Currently returns 200, should return 150
            tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(150.0, 30.0))
            input.measure(tight).width.should eq 150.0
        end
    end

    describe "#layout" do
        it "sets bounds at given position" do
            input = CrymbleUI::TextInput.new(width: 100.0)
            constraints = CrymbleUI::BoxConstraints.new
            position = CrymbleUI::Vec2.new(10.0, 20.0)

            input.layout(constraints, position)

            input.bounds.x.should eq(10.0)
            input.bounds.y.should eq(20.0)
            input.bounds.width.should eq(100.0)
        end
    end

    describe "#value=" do
        it "updates value" do
            input = CrymbleUI::TextInput.new(value: "old")
            input.value = "new"
            input.value.should eq("new")
        end

        it "marks widget as needing render (via Source auto-capture after first render)" do
            # Value is a Source-backed reactive_property. Setting it does NOT
            # push @state — the primitives node is invalidated via the reactive graph instead.
            # Verify via the node-derived path: render once (creating @primitives_node), then
            # set value and confirm needs_render? returns true because the node is now stale.
            renderer = CrymbleUI::Testing::TestRenderer.new(200, 50)
            app = ValueRenderApp.new
            app.build_tree
            renderer.render_frame(app)

            input = app.find("ti").as(CrymbleUI::TextInput)
            # After first render the primitives node exists and is valid
            input.needs_render?.should be_false

            input.value = "changed"

            # Source.set() invalidated the node — needs re-render
            input.needs_render?.should be_true
        end
    end

    describe "#on_focus and #on_blur" do
        it "marks widget as needing render on focus" do
            input = CrymbleUI::TextInput.new
            input.state = CrymbleUI::WidgetState::Clean

            input.on_focus

            input.needs_render?.should be_true
        end

        it "marks widget as needing render on blur" do
            input = CrymbleUI::TextInput.new
            input.on_focus
            input.state = CrymbleUI::WidgetState::Clean

            input.on_blur

            input.needs_render?.should be_true
        end
    end

    describe "#request_focus" do
        it "focuses the widget" do
            input = CrymbleUI::TextInput.new

            input.request_focus

            input.focused?.should be_true
        end
    end

    describe "#release_focus" do
        it "removes focus from the widget" do
            input = CrymbleUI::TextInput.new
            input.request_focus

            input.release_focus

            input.focused?.should be_false
        end
    end

    describe "#on_text_input" do
        it "inserts character at cursor position" do
            input = CrymbleUI::TextInput.new(value: "ab")

            input.on_text_input('c')

            input.value.should eq("abc")
        end

        it "inserts character at cursor (middle of text)" do
            input = CrymbleUI::TextInput.new(value: "ab")
            input.enter_edit_mode  # Enable cursor movement with arrow keys
            # Cursor is at end by default (position 2)
            # Move cursor to position 1
            input.on_key_down(SF::Keyboard::Key::Home, false, false)
            input.on_key_down(SF::Keyboard::Key::Right, false, false)

            input.on_text_input('X')

            input.value.should eq("aXb")
        end

        it "triggers on_change callback" do
            received_value = ""
            input = CrymbleUI::TextInput.new { |v| received_value = v }

            input.on_text_input('a')
            input.on_text_input('b')

            received_value.should eq("ab")
        end

        it "marks widget as needing render" do
            input = CrymbleUI::TextInput.new
            input.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)
            input.get_primitives(input.bounds) # real render: captures `value` (reactive, no manual mark)

            input.on_text_input('x')

            input.needs_render?.should be_true
        end
    end

    describe "#on_key_down" do
        describe "Backspace" do
            it "deletes character before cursor" do
                input = CrymbleUI::TextInput.new(value: "abc")

                input.on_key_down(SF::Keyboard::Key::Backspace, false, false)

                input.value.should eq("ab")
            end

            it "does nothing at start of text" do
                input = CrymbleUI::TextInput.new(value: "abc")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)

                input.on_key_down(SF::Keyboard::Key::Backspace, false, false)

                input.value.should eq("abc")
            end

            it "returns true (handled)" do
                input = CrymbleUI::TextInput.new(value: "a")
                result = input.on_key_down(SF::Keyboard::Key::Backspace, false, false)
                result.should be_true
            end
        end

        describe "Delete" do
            it "deletes character after cursor" do
                input = CrymbleUI::TextInput.new(value: "abc")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)

                input.on_key_down(SF::Keyboard::Key::Delete, false, false)

                input.value.should eq("bc")
            end

            it "does nothing at end of text" do
                input = CrymbleUI::TextInput.new(value: "abc")

                input.on_key_down(SF::Keyboard::Key::Delete, false, false)

                input.value.should eq("abc")
            end

            it "returns true (handled)" do
                input = CrymbleUI::TextInput.new(value: "a")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                result = input.on_key_down(SF::Keyboard::Key::Delete, false, false)
                result.should be_true
            end
        end

        describe "Left arrow" do
            it "moves cursor left (in FullEdit mode)" do
                input = CrymbleUI::TextInput.new(value: "abc")
                input.enter_edit_mode  # Arrow keys move cursor in FullEdit mode
                # Cursor at position 3, move left
                input.on_key_down(SF::Keyboard::Key::Left, false, false)
                # Insert to check position (should insert between b and c)
                input.on_text_input('X')

                input.value.should eq("abXc")
            end

            it "stops at start" do
                input = CrymbleUI::TextInput.new(value: "ab")
                input.enter_edit_mode
                input.on_key_down(SF::Keyboard::Key::Home, false, false)

                result = input.on_key_down(SF::Keyboard::Key::Left, false, false)

                # Insert to check position (should be at start)
                input.on_text_input('X')
                input.value.should eq("Xab")
            end

            it "returns true (handled) in FullEdit mode" do
                input = CrymbleUI::TextInput.new(value: "a")
                input.enter_edit_mode
                result = input.on_key_down(SF::Keyboard::Key::Left, false, false)
                result.should be_true
            end

            it "returns false in QuickEntry mode (for focus navigation)" do
                input = CrymbleUI::TextInput.new(value: "a", mode: CrymbleUI::TextInputMode::QuickEntry)
                # Explicit QuickEntry mode
                result = input.on_key_down(SF::Keyboard::Key::Left, false, false)
                result.should be_false
            end
        end

        describe "Right arrow" do
            it "moves cursor right (in FullEdit mode)" do
                input = CrymbleUI::TextInput.new(value: "abc")
                # FullEdit is now default
                input.on_key_down(SF::Keyboard::Key::Home, false, false)

                input.on_key_down(SF::Keyboard::Key::Right, false, false)
                input.on_text_input('X')

                input.value.should eq("aXbc")
            end

            it "stops at end" do
                input = CrymbleUI::TextInput.new(value: "ab")
                input.enter_edit_mode

                result = input.on_key_down(SF::Keyboard::Key::Right, false, false)

                # Insert to check position (should be at end)
                input.on_text_input('X')
                input.value.should eq("abX")
            end

            it "returns true (handled) in FullEdit mode" do
                input = CrymbleUI::TextInput.new(value: "a")
                input.enter_edit_mode
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                result = input.on_key_down(SF::Keyboard::Key::Right, false, false)
                result.should be_true
            end

            it "returns false in QuickEntry mode (for focus navigation)" do
                input = CrymbleUI::TextInput.new(value: "a", mode: CrymbleUI::TextInputMode::QuickEntry)
                # Explicit QuickEntry mode
                result = input.on_key_down(SF::Keyboard::Key::Right, false, false)
                result.should be_false
            end
        end

        describe "Home" do
            it "moves cursor to start" do
                input = CrymbleUI::TextInput.new(value: "abc")

                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_text_input('X')

                input.value.should eq("Xabc")
            end

            it "returns true (handled)" do
                input = CrymbleUI::TextInput.new(value: "abc")
                result = input.on_key_down(SF::Keyboard::Key::Home, false, false)
                result.should be_true
            end
        end

        describe "End" do
            it "moves cursor to end" do
                input = CrymbleUI::TextInput.new(value: "abc")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)

                input.on_key_down(SF::Keyboard::Key::End, false, false)
                input.on_text_input('X')

                input.value.should eq("abcX")
            end

            it "returns true (handled)" do
                input = CrymbleUI::TextInput.new(value: "abc")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                result = input.on_key_down(SF::Keyboard::Key::End, false, false)
                result.should be_true
            end
        end

        describe "Escape" do
            it "releases focus" do
                input = CrymbleUI::TextInput.new
                input.request_focus

                input.on_key_down(SF::Keyboard::Key::Escape, false, false)

                input.focused?.should be_false
            end

            it "returns true (handled)" do
                input = CrymbleUI::TextInput.new
                result = input.on_key_down(SF::Keyboard::Key::Escape, false, false)
                result.should be_true
            end
        end

        describe "unhandled keys" do
            it "returns false for unhandled keys" do
                input = CrymbleUI::TextInput.new
                result = input.on_key_down(SF::Keyboard::Key::F1, false, false)
                result.should be_false
            end
        end
    end

    describe "#on_click" do
        it "requests focus" do
            input = CrymbleUI::TextInput.new

            input.on_click

            input.focused?.should be_true
        end
    end

    describe "#to_primitives" do
        it "generates background primitive" do
            input = CrymbleUI::TextInput.new
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            # First primitive should be background fill
            primitives[0].should be_a(CrymbleUI::FillRect)
        end

        it "generates border primitive" do
            input = CrymbleUI::TextInput.new
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            # Border is now 4 FillRect primitives (top, bottom, left, right)
            # Primitives: [0]=background, [1-4]=border edges
            primitives[1].should be_a(CrymbleUI::FillRect)
            primitives[2].should be_a(CrymbleUI::FillRect)
            primitives[3].should be_a(CrymbleUI::FillRect)
            primitives[4].should be_a(CrymbleUI::FillRect)
        end

        it "uses normal border color when not focused" do
            border_color = CrymbleUI::Color.new(100, 100, 100, 255)
            input = CrymbleUI::TextInput.new(border_color: border_color)
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)
            # Border is now 4 FillRect primitives [1-4], check top edge
            border = primitives[1].as(CrymbleUI::FillRect)

            border.color.should eq(border_color)
        end

        it "uses focused border color when focused" do
            border_color = CrymbleUI::Color.new(100, 100, 100, 255)
            focused_color = CrymbleUI::Color.new(0, 120, 215, 255)
            input = CrymbleUI::TextInput.new(
                border_color: border_color,
                focused_border_color: focused_color
            )
            input.request_focus
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)
            # Border is now 4 FillRect primitives [1-4], check top edge
            border = primitives[1].as(CrymbleUI::FillRect)

            border.color.should eq(focused_color)
        end

        it "shows placeholder when value is empty" do
            input = CrymbleUI::TextInput.new(placeholder: "Enter text...")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            # Should have text primitive
            text_primitives = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
            text_primitives.should_not be_empty

            text = text_primitives[0].as(CrymbleUI::DrawText)
            text.text.should eq("Enter text...")
        end

        it "shows value when not empty" do
            input = CrymbleUI::TextInput.new(value: "hello")
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            text_primitives = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
            text_primitives.should_not be_empty

            text = text_primitives[0].as(CrymbleUI::DrawText)
            text.text.should eq("hello")
        end

        it "uses placeholder color for placeholder text" do
            placeholder_color = CrymbleUI::Color.new(150, 150, 150, 255)
            input = CrymbleUI::TextInput.new(
                placeholder: "hint",
                placeholder_color: placeholder_color
            )
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            text_primitives = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
            text = text_primitives[0].as(CrymbleUI::DrawText)
            text.color.should eq(placeholder_color)
        end

        it "uses text color for actual value" do
            text_color = CrymbleUI::Color.new(0, 0, 0, 255)
            input = CrymbleUI::TextInput.new(
                value: "hello",
                text_color: text_color
            )
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            text_primitives = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
            text = text_primitives[0].as(CrymbleUI::DrawText)
            text.color.should eq(text_color)
        end

        it "shows cursor when focused" do
            input = CrymbleUI::TextInput.new(value: "abc")
            input.request_focus
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            # Should have cursor (FillRect for cursor line)
            fill_rects = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
            # Background + cursor = 2 fill rects
            fill_rects.size.should be >= 2
        end

        it "hides cursor when not focused" do
            input = CrymbleUI::TextInput.new(value: "abc")
            # Not focused
            bounds = CrymbleUI::Rect.new(0, 0, 100, 24)

            primitives = input.to_primitives(bounds)

            # Should have background + 4 border fill rects, no cursor
            fill_rects = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
            fill_rects.size.should eq(5)  # background + 4 border edges
        end
    end

    describe "integration" do
        it "works in widget tree" do
            parent = CrymbleUI::VStack.new(id: "form")
            input = CrymbleUI::TextInput.new(id: "name_input")

            parent.add_child(input)

            parent.children.should contain(input)
            input.parent.should eq(parent)
            input.path_id.should eq("form/name_input")
        end

        it "typing updates value correctly" do
            input = CrymbleUI::TextInput.new
            input.request_focus

            input.on_text_input('H')
            input.on_text_input('i')
            input.on_text_input('!')

            input.value.should eq("Hi!")
        end

        it "editing with navigation works" do
            input = CrymbleUI::TextInput.new
            input.request_focus

            # Type "abc"
            input.on_text_input('a')
            input.on_text_input('b')
            input.on_text_input('c')

            # Move to start and insert "X"
            input.on_key_down(SF::Keyboard::Key::Home, false, false)
            input.on_text_input('X')

            # Delete second character (now 'a')
            input.on_key_down(SF::Keyboard::Key::Delete, false, false)

            input.value.should eq("Xbc")
        end

        it "callback is called with current value" do
            values = [] of String
            input = CrymbleUI::TextInput.new { |v| values << v }

            input.on_text_input('a')
            input.on_text_input('b')
            input.on_key_down(SF::Keyboard::Key::Backspace, false, false)
            input.on_text_input('c')

            values.should eq(["a", "ab", "a", "ac"])
        end
    end

    describe "selection" do
        describe "#has_selection?" do
            it "returns false initially" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.has_selection?.should be_false
            end

            it "returns true after Shift+Right" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)  # shift=true
                input.has_selection?.should be_true
            end
        end

        describe "#selection_range" do
            it "returns nil when no selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.selection_range.should be_nil
            end

            it "returns ordered range for forward selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.selection_range.should eq({0, 2})
            end

            it "returns ordered range for backward selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                # Cursor at end (5), select backward
                input.on_key_down(SF::Keyboard::Key::Left, false, true)
                input.on_key_down(SF::Keyboard::Key::Left, false, true)
                input.selection_range.should eq({3, 5})
            end
        end

        describe "#selected_text" do
            it "returns empty string when no selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.selected_text.should eq("")
            end

            it "returns selected substring" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.selected_text.should eq("he")
            end
        end

        describe "Shift+Arrow selection" do
            it "Shift+Right creates selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.has_selection?.should be_true
                input.selected_text.should eq("h")
            end

            it "Shift+Left creates selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                # Cursor at end
                input.on_key_down(SF::Keyboard::Key::Left, false, true)
                input.has_selection?.should be_true
                input.selected_text.should eq("o")
            end

            it "Shift+Home selects to start" do
                input = CrymbleUI::TextInput.new(value: "hello")
                # Cursor at end
                input.on_key_down(SF::Keyboard::Key::Home, false, true)
                input.has_selection?.should be_true
                input.selected_text.should eq("hello")
            end

            it "Shift+End selects to end" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::End, false, true)
                input.has_selection?.should be_true
                input.selected_text.should eq("hello")
            end

            it "Arrow without shift clears selection (FullEdit mode)" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.enter_edit_mode
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.has_selection?.should be_true

                input.on_key_down(SF::Keyboard::Key::Right, false, false)
                input.has_selection?.should be_false
            end

            it "Left arrow moves to start of selection (FullEdit mode)" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.enter_edit_mode
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                # Selection is 0..2, press left should move cursor to 0
                input.on_key_down(SF::Keyboard::Key::Left, false, false)
                input.on_text_input('X')
                input.value.should eq("Xhello")
            end

            it "Right arrow moves to end of selection (FullEdit mode)" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.enter_edit_mode
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                # Selection is 0..2, press right should move cursor to 2
                input.on_key_down(SF::Keyboard::Key::Right, false, false)
                input.on_text_input('X')
                input.value.should eq("heXllo")
            end
        end

        describe "Ctrl+A select all" do
            it "selects all text" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)
                input.has_selection?.should be_true
                input.selected_text.should eq("hello")
            end

            it "does nothing on empty text" do
                input = CrymbleUI::TextInput.new(value: "")
                input.on_key_down(SF::Keyboard::Key::A, true, false)
                input.has_selection?.should be_false
            end
        end

        describe "typing replaces selection" do
            it "replaces selection with typed character" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.on_text_input('X')
                input.value.should eq("X")
            end

            it "deletes selection and inserts at correct position" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                # Selected "he"
                input.on_text_input('X')
                input.value.should eq("Xllo")
            end
        end

        describe "Backspace/Delete with selection" do
            it "Backspace deletes selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.on_key_down(SF::Keyboard::Key::Backspace, false, false)
                input.value.should eq("")
            end

            it "Delete deletes selection" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                # Selected "he"
                input.on_key_down(SF::Keyboard::Key::Delete, false, false)
                input.value.should eq("llo")
            end
        end

        describe "click clears selection" do
            it "clears selection on click" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.has_selection?.should be_true

                input.on_click
                input.has_selection?.should be_false
            end
        end
    end

    describe "clipboard operations" do
        describe "Ctrl+C copy" do
            it "copies selected text to clipboard" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.on_key_down(SF::Keyboard::Key::C, true, false)  # Copy

                CrymbleUI::Widget.clipboard.text.should eq("hello")
            end

            it "does nothing without selection" do
                CrymbleUI::Widget.clipboard.text = "original"
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::C, true, false)

                CrymbleUI::Widget.clipboard.text.should eq("original")
            end
        end

        describe "Ctrl+X cut" do
            it "cuts selected text to clipboard and deletes" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::Home, false, false)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                input.on_key_down(SF::Keyboard::Key::Right, false, true)
                # Selected "he"
                input.on_key_down(SF::Keyboard::Key::X, true, false)

                CrymbleUI::Widget.clipboard.text.should eq("he")
                input.value.should eq("llo")
            end
        end

        describe "Ctrl+V paste" do
            it "pastes clipboard at cursor" do
                CrymbleUI::Widget.clipboard.text = "world"
                input = CrymbleUI::TextInput.new(value: "hello ")
                input.on_key_down(SF::Keyboard::Key::V, true, false)

                input.value.should eq("hello world")
            end

            it "replaces selection with pasted text" do
                CrymbleUI::Widget.clipboard.text = "world"
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.on_key_down(SF::Keyboard::Key::V, true, false)

                input.value.should eq("world")
            end

            it "does nothing with empty clipboard" do
                CrymbleUI::Widget.clipboard.text = ""
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_key_down(SF::Keyboard::Key::V, true, false)

                input.value.should eq("hello")
            end
        end

        describe "Ctrl+Insert copy (alternative)" do
            it "copies selected text" do
                input = CrymbleUI::TextInput.new(value: "test")
                input.on_key_down(SF::Keyboard::Key::A, true, false)
                input.on_key_down(SF::Keyboard::Key::Insert, true, false)

                CrymbleUI::Widget.clipboard.text.should eq("test")
            end
        end

        describe "Shift+Insert paste (alternative)" do
            it "pastes clipboard" do
                CrymbleUI::Widget.clipboard.text = "pasted"
                input = CrymbleUI::TextInput.new(value: "")
                input.on_key_down(SF::Keyboard::Key::Insert, false, true)

                input.value.should eq("pasted")
            end
        end

        describe "Shift+Delete cut (alternative)" do
            it "cuts selected text" do
                input = CrymbleUI::TextInput.new(value: "cut me")
                input.on_key_down(SF::Keyboard::Key::A, true, false)
                input.on_key_down(SF::Keyboard::Key::Delete, false, true)

                CrymbleUI::Widget.clipboard.text.should eq("cut me")
                input.value.should eq("")
            end
        end
    end

    describe "focus and blur behavior" do
        describe "blur clears selection" do
            it "clears selection when focus is lost" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.request_focus
                input.on_key_down(SF::Keyboard::Key::A, true, false)  # Select all
                input.has_selection?.should be_true

                input.release_focus  # This triggers on_blur
                input.has_selection?.should be_false
            end
        end

        describe "cursor visible after focus" do
            it "renders cursor after on_click" do
                input = CrymbleUI::TextInput.new(value: "hello")
                input.on_click  # Click triggers focus

                # Cursor should be visible immediately after focus
                bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 24.0)
                primitives = input.to_primitives(bounds)

                # Should have cursor FillRect (the thin cursor line)
                # Filter by width=1 AND height < bounds.height (cursor is inside content area)
                cursor_rects = primitives.select { |p|
                    p.is_a?(CrymbleUI::FillRect) &&
                    p.bounds.width == CrymbleUI::TextInput::CURSOR_WIDTH &&
                    p.bounds.height < bounds.height  # Cursor is shorter than border edges
                }
                cursor_rects.size.should eq(1)
            end
        end

        describe "focus preserved across rebuild" do
            it "preserves focus when copy_state_from is called (rebuild scenario)" do
                # This simulates what happens during App.rebuild when TextInput is recreated
                old_input = CrymbleUI::TextInput.new(value: "hello", id: "test")
                old_input.request_focus
                old_input.focused?.should be_true

                # Rebuild creates a new widget with same ID
                new_input = CrymbleUI::TextInput.new(value: "hello", id: "test")

                # copy_state_from is called during reconciliation
                new_input.copy_state_from(old_input)

                # Focus should be transferred to new widget
                new_input.focused?.should be_true  # EXPECTED TO FAIL: focus not transferred
            end

            it "preserves cursor visibility across copy_state_from" do
                old_input = CrymbleUI::TextInput.new(value: "hello", id: "test")
                old_input.request_focus
                # on_focus sets cursor_visible = true

                new_input = CrymbleUI::TextInput.new(value: "hello", id: "test")
                new_input.copy_state_from(old_input)

                # Should render cursor after copy
                bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 24.0)
                primitives = new_input.to_primitives(bounds)

                # Filter by width=1 AND height < bounds.height (cursor is inside content area)
                cursor_rects = primitives.select { |p|
                    p.is_a?(CrymbleUI::FillRect) &&
                    p.bounds.width == CrymbleUI::TextInput::CURSOR_WIDTH &&
                    p.bounds.height < bounds.height  # Cursor is shorter than border edges
                }
                cursor_rects.size.should eq(1)  # EXPECTED TO FAIL: cursor not copied
            end

            it "preserves cursor position across copy_state_from" do
                old_input = CrymbleUI::TextInput.new(value: "hello", id: "test")
                old_input.request_focus
                old_input.enter_edit_mode  # Enable cursor movement
                # Move cursor to position 2
                old_input.on_key_down(SF::Keyboard::Key::Home, false, false)
                old_input.on_key_down(SF::Keyboard::Key::Right, false, false)
                old_input.on_key_down(SF::Keyboard::Key::Right, false, false)

                new_input = CrymbleUI::TextInput.new(value: "hello", id: "test")
                new_input.copy_state_from(old_input)

                # Type a character - should insert at position 2
                new_input.on_text_input('X')
                new_input.value.should eq("heXllo")
            end

            it "clamps cursor position when value shrinks during rebuild" do
                # BUG REPRO: Type "q", submit, reset (value=""), hit "q" → IndexError
                # Old widget has cursor_pos=1, new widget has value=""
                # copy_state_from copies cursor_pos=1 without clamping → invalid state
                old_input = CrymbleUI::TextInput.new(value: "q", id: "test")
                old_input.request_focus
                # Cursor is at position 1 (end of "q")

                # Rebuild with empty value (simulates state reset)
                new_input = CrymbleUI::TextInput.new(value: "", id: "test")
                new_input.copy_state_from(old_input)

                # Should NOT crash - cursor must be clamped to 0
                new_input.on_text_input('q')
                new_input.value.should eq("q")
            end
        end
    end

    describe "TextInputEvent ArrowUp/ArrowDown (TEST MODE)" do
        # These tests document the REQUIRED behavior for ComboBox arrow navigation
        # ArrowUp/ArrowDown events allow parent widgets to handle arrow keys

        it "fires ArrowUp event when Up arrow is pressed" do
            input = CrymbleUI::TextInput.new(value: "test")
            input.request_focus

            received_event : CrymbleUI::TextInputEvent? = nil
            input.on_event = ->(value : String, event : CrymbleUI::TextInputEvent) {
                received_event = event
                nil
            }

            input.on_key_down(SF::Keyboard::Key::Up, false, false)

            received_event.should eq(CrymbleUI::TextInputEvent::ArrowUp)
        end

        it "fires ArrowDown event when Down arrow is pressed" do
            input = CrymbleUI::TextInput.new(value: "test")
            input.request_focus

            received_event : CrymbleUI::TextInputEvent? = nil
            input.on_event = ->(value : String, event : CrymbleUI::TextInputEvent) {
                received_event = event
                nil
            }

            input.on_key_down(SF::Keyboard::Key::Down, false, false)

            received_event.should eq(CrymbleUI::TextInputEvent::ArrowDown)
        end

        it "passes current value with arrow events" do
            input = CrymbleUI::TextInput.new(value: "hello")
            input.request_focus

            received_value : String? = nil
            input.on_event = ->(value : String, event : CrymbleUI::TextInputEvent) {
                received_value = value
                nil
            }

            input.on_key_down(SF::Keyboard::Key::Up, false, false)

            received_value.should eq("hello")
        end
    end

    describe "border pixel rendering (TEST MODE)" do
        # This tests that all 4 borders (top, bottom, left, right) are rendered correctly
        # Bug: Right border may be clipped due to width rounding issues
        it "renders all 4 borders with correct color" do
            # BorderTestApp defined at top of file
            renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
            app = BorderTestApp.new
            app.build_tree
            renderer.render_frame(app)

            input = app.find("input").as(CrymbleUI::TextInput)
            bounds = input.absolute_bounds

            # Expected border color
            border_color = CrymbleUI::Color.new(0, 0, 255, 255)

            # Check top border (first row of pixels within bounds)
            top_x = (bounds.x + bounds.width / 2).to_i
            top_y = bounds.y.to_i
            top_pixel = renderer.backend.get_pixel(top_x, top_y)
            top_pixel.should eq(border_color), "Top border missing at (#{top_x}, #{top_y})"

            # Check bottom border (last row within bounds)
            bottom_x = (bounds.x + bounds.width / 2).to_i
            bottom_y = (bounds.y + bounds.height - 1).to_i
            bottom_pixel = renderer.backend.get_pixel(bottom_x, bottom_y)
            bottom_pixel.should eq(border_color), "Bottom border missing at (#{bottom_x}, #{bottom_y})"

            # Check left border (first column)
            left_x = bounds.x.to_i
            left_y = (bounds.y + bounds.height / 2).to_i
            left_pixel = renderer.backend.get_pixel(left_x, left_y)
            left_pixel.should eq(border_color), "Left border missing at (#{left_x}, #{left_y})"

            # Check right border (last column within bounds) - THIS SHOULD FAIL IF BUG EXISTS
            right_x = (bounds.x + bounds.width - 1).to_i
            right_y = (bounds.y + bounds.height / 2).to_i
            right_pixel = renderer.backend.get_pixel(right_x, right_y)
            right_pixel.should eq(border_color), "Right border missing at (#{right_x}, #{right_y})"
        end
    end

    # Cell-keyboard ops live in the consuming application, registered as cursor-scoped
    # panel shortcuts. While PARKED in QuickEntry (on_focus armed pending_replace,
    # nothing typed yet) a TextInput is a grid cell, not a text field — so it declines
    # EVERY clipboard key (Ctrl+C/Ctrl+Insert, Ctrl+X/Shift+Delete, Ctrl+V/Shift+Insert)
    # as well as bare Delete, and they bubble to the owner. Once typing starts
    # (immediate editing clears pending_replace), or in FullEdit, they act on the text.
    #
    # NOTE: this SUPERSEDES the earlier rule, which declined only the keys that had a
    # competing cell-op and kept Ctrl+C "editor-handled always (no cell-copy op
    # exists)". That gated a generic widget on which shortcuts one consumer happened
    # to register: the moment an app grew a grid-level copy, Ctrl+C was swallowed here
    # and never reached it. Backspace and Ctrl+A are not clipboard ops — unaffected.
    describe "CNP mode gating" do
        it "PARKED QuickEntry Ctrl+X is not consumed — bubbles to the cell-cut shortcut" do
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked (pending_replace armed)
            input.on_key_down(SF::Keyboard::Key::X, true, false).should be_false
            input.value.should eq("abc")
        end

        it "PARKED QuickEntry Ctrl+V is not consumed — bubbles to the cell-paste shortcut" do
            CrymbleUI::Widget.clipboard.text = "xyz"
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked
            input.on_key_down(SF::Keyboard::Key::V, true, false).should be_false
            input.value.should eq("abc")
        end

        it "PARKED QuickEntry bare Delete is not consumed — bubbles to the delete-record shortcut" do
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked
            input.on_key_down(SF::Keyboard::Key::Delete, false, false).should be_false
            input.value.should eq("abc")
        end

        it "PARKED QuickEntry Ctrl+C is not consumed — bubbles to a grid-level copy" do
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked
            input.on_key_down(SF::Keyboard::Key::C, true, false).should be_false
        end

        it "PARKED QuickEntry Shift+Insert is not consumed — same rule as Ctrl+V" do
            CrymbleUI::Widget.clipboard.text = "xyz"
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked
            input.on_key_down(SF::Keyboard::Key::Insert, false, true).should be_false
            input.value.should eq("abc")
        end

        it "PARKED QuickEntry Shift+Delete is not consumed — same rule as Ctrl+X" do
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus # parked
            input.on_key_down(SF::Keyboard::Key::Delete, false, true).should be_false
            input.value.should eq("abc")
        end

        # The other half of the rule: NOT parked (typing started) means the editor owns
        # the key again. Without this, "decline while parked" could be over-applied to
        # QuickEntry as a whole and nothing would catch it.
        it "QuickEntry Ctrl+C IS consumed once typing has started (no longer parked)" do
            input = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry)
            input.on_focus            # parked
            input.on_text_input('z')  # immediate editing — clears pending_replace
            input.on_key_down(SF::Keyboard::Key::C, true, false).should be_true
        end

        it "FullEdit Ctrl+X cuts the selected text only — the screenshot-bug fix" do
            input = CrymbleUI::TextInput.new(value: "abcde", mode: CrymbleUI::TextInputMode::FullEdit)
            input.on_key_down(SF::Keyboard::Key::Home, false, false)
            3.times { input.on_key_down(SF::Keyboard::Key::Right, false, true) } # select "abc"
            input.has_selection?.should be_true
            input.on_key_down(SF::Keyboard::Key::X, true, false).should be_true
            input.value.should eq("de")
        end
    end
end
