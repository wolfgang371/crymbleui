require "../spec_helper"

describe CrymbleUI::WindowPanel do
    describe "#initialize" do
        it "creates panel with basic properties" do
            panel = CrymbleUI::WindowPanel.new("Test Panel", 100.0, 50.0, 200.0, 150.0)
            panel.title.should eq("Test Panel")
            panel.x.should eq(100.0)
            panel.y.should eq(50.0)
            panel.width.should eq(200.0)
            panel.height.should eq(150.0)
        end

        it "defaults to closeable, draggable, resizable" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.closeable.should be_true
            panel.draggable.should be_true
            panel.resizable.should be_true
        end

        it "starts with z_index 0" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.z_index.should eq(0)
        end

        it "starts not closed" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.closed.should be_false
        end
    end

    describe "#close and #open" do
        it "closes panel" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.close
            panel.closed.should be_true
        end

        it "opens panel" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.close
            panel.open
            panel.closed.should be_false
        end

        it "toggles panel state" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 100.0, 100.0)
            panel.toggle
            panel.closed.should be_true
            panel.toggle
            panel.closed.should be_false
        end
    end

    describe "#bring_to_front" do
        it "increases z_index when not highest" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel1 = CrymbleUI::WindowPanel.new("Panel 1", 0.0, 0.0, 100.0, 100.0, z_index: 1)
            panel2 = CrymbleUI::WindowPanel.new("Panel 2", 50.0, 50.0, 100.0, 100.0, z_index: 2)

            window.add_child(panel1)
            window.add_child(panel2)

            panel1.bring_to_front
            panel1.z_index.should be > panel2.z_index
        end

        it "sets z_index to max+10 when already on top" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel1 = CrymbleUI::WindowPanel.new("Panel 1", 0.0, 0.0, 100.0, 100.0, z_index: 5)
            panel2 = CrymbleUI::WindowPanel.new("Panel 2", 50.0, 50.0, 100.0, 100.0, z_index: 2)

            window.add_child(panel1)
            window.add_child(panel2)

            panel1.bring_to_front
            # Panel 1 gets max+10 (5+10=15) to ensure child layers (scrollbar) stay behind
            # This ensures panels with same z_index can be brought to front
            panel1.z_index.should eq(15)
            panel1.z_index.should be > panel2.z_index
        end
    end

    describe "dragging" do
        it "starts dragging on title bar mouse down" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            # Click on title bar
            point = CrymbleUI::Vec2.new(150.0, 115.0)  # Middle of title bar
            panel.on_mouse_down(point)

            # Move mouse
            new_point = CrymbleUI::Vec2.new(200.0, 165.0)
            panel.on_mouse_move(new_point)

            # Panel should have moved
            panel.x.should be_close(150.0, 0.1)
            panel.y.should be_close(150.0, 0.1)

            # Bounds should be updated too
            panel.bounds.x.should be_close(150.0, 0.1)
            panel.bounds.y.should be_close(150.0, 0.1)
        end

        it "updates child positions when panel is dragged" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            button = CrymbleUI::Button.new("Click me") { }

            window.add_child(panel)
            panel.add_child(button)

            # Layout everything
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # With parent-relative bounds, button.bounds is relative to panel
            initial_button_rel_x = button.bounds.x
            initial_button_rel_y = button.bounds.y
            initial_button_abs = button.absolute_bounds

            # Drag panel
            point = CrymbleUI::Vec2.new(150.0, 115.0)
            panel.on_mouse_down(point)
            new_point = CrymbleUI::Vec2.new(200.0, 165.0)
            panel.on_mouse_move(new_point)
            panel.on_mouse_up(new_point)

            # Panel moved by ~50, ~50
            panel.x.should be_close(150.0, 0.1)
            panel.y.should be_close(150.0, 0.1)

            # Button's relative position unchanged (parent-relative bounds)
            button.bounds.x.should be_close(initial_button_rel_x, 0.1)
            button.bounds.y.should be_close(initial_button_rel_y, 0.1)

            # But absolute position moved with panel
            delta_x = panel.x - 100.0
            delta_y = panel.y - 100.0
            new_abs = button.absolute_bounds
            new_abs.x.should be_close(initial_button_abs.x + delta_x, 0.1)
            new_abs.y.should be_close(initial_button_abs.y + delta_y, 0.1)
        end

        it "does not drag when not draggable" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0, draggable: false)

            point = CrymbleUI::Vec2.new(150.0, 115.0)
            panel.on_mouse_down(point)

            new_point = CrymbleUI::Vec2.new(200.0, 165.0)
            panel.on_mouse_move(new_point)

            # Panel should not have moved
            panel.x.should eq(100.0)
            panel.y.should eq(100.0)
        end

        it "stops dragging on mouse up" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            point = CrymbleUI::Vec2.new(150.0, 115.0)
            panel.on_mouse_down(point)

            panel.on_mouse_up(point)

            # Further moves should not affect position
            panel.on_mouse_move(CrymbleUI::Vec2.new(300.0, 300.0))
            panel.x.should eq(100.0)
            panel.y.should eq(100.0)
        end
    end

    describe "resizing" do
        it "resizes from right edge" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            # Click on right edge
            point = CrymbleUI::Vec2.new(299.0, 150.0)  # Near right edge
            panel.on_mouse_down(point)

            # Drag to right
            new_point = CrymbleUI::Vec2.new(349.0, 150.0)
            panel.on_mouse_move(new_point)

            # Width should have increased
            panel.width.should be_close(250.0, 1.0)
            panel.x.should eq(100.0)  # Position unchanged
        end

        it "resizes from bottom-right corner" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            # Click on bottom-right corner
            point = CrymbleUI::Vec2.new(299.0, 249.0)
            panel.on_mouse_down(point)

            # Drag down and right
            new_point = CrymbleUI::Vec2.new(349.0, 299.0)
            panel.on_mouse_move(new_point)

            # Both dimensions should increase
            panel.width.should be_close(250.0, 1.0)
            panel.height.should be_close(200.0, 1.0)
        end

        it "enforces minimum size during resize" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            # Try to resize to very small
            point = CrymbleUI::Vec2.new(299.0, 150.0)
            panel.on_mouse_down(point)

            # Drag far left (try to make width negative)
            new_point = CrymbleUI::Vec2.new(50.0, 150.0)
            panel.on_mouse_move(new_point)

            # Width should be clamped to minimum (100.0)
            panel.width.should eq(100.0)
        end

        it "does not resize when not resizable" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0, resizable: false)

            point = CrymbleUI::Vec2.new(299.0, 150.0)
            panel.on_mouse_down(point)

            new_point = CrymbleUI::Vec2.new(349.0, 150.0)
            panel.on_mouse_move(new_point)

            # Size should not change
            panel.width.should eq(200.0)
        end
    end

    describe "rendering" do
        it "does not render when closed" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            panel.close

            # Just verify closed state prevents render logic
            panel.closed.should be_true
        end
    end

    describe "hit testing" do
        it "returns nil when closed" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            panel.close

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
            panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

            point = CrymbleUI::Vec2.new(150.0, 150.0)
            panel.hit_test(point).should be_nil
        end

        it "detects clicks on panel when open" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
            panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

            point = CrymbleUI::Vec2.new(150.0, 150.0)
            hit = panel.hit_test(point)
            # With Chrome/Content architecture, clicking content area returns Content widget (not panel)
            hit.should_not be_nil
            hit.should be_a(CrymbleUI::WindowPanel::Content)
        end
    end

    describe "integration: z-ordering" do
        it "brings panel to front when clicking panel directly" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel1 = CrymbleUI::WindowPanel.new("Panel 1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
            panel2 = CrymbleUI::WindowPanel.new("Panel 2", 150.0, 150.0, 200.0, 150.0, z_index: 2)

            window.add_child(panel1)
            window.add_child(panel2)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # Panel2 starts with higher z_index
            panel1.z_index.should eq(1)
            panel2.z_index.should eq(2)

            # Click on panel1 (in an area that's not overlapping panel2)
            click_point = CrymbleUI::Vec2.new(120.0, 120.0)
            hit = window.hit_test(click_point)
            hit.should eq(panel1)

            # Simulate mouse down on panel1
            panel1.on_mouse_down(click_point)

            # Panel1 should now have higher z_index than panel2
            panel1.z_index.should be > panel2.z_index
        end

        it "brings panel to front when clicking button inside panel" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            # Panels don't overlap, so hit testing is unambiguous
            panel1 = CrymbleUI::WindowPanel.new("Panel 1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
            panel2 = CrymbleUI::WindowPanel.new("Panel 2", 400.0, 100.0, 200.0, 150.0, z_index: 2)

            button1 = CrymbleUI::Button.new("Button in Panel 1") { }
            panel1.add_child(button1)

            window.add_child(panel1)
            window.add_child(panel2)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # Panel2 starts with higher z_index
            panel1.z_index.should eq(1)
            panel2.z_index.should eq(2)

            # Click on button inside panel1 (use absolute bounds for hit testing)
            abs_bounds = button1.absolute_bounds
            button_center = CrymbleUI::Vec2.new(
                abs_bounds.x + abs_bounds.width / 2,
                abs_bounds.y + abs_bounds.height / 2
            )

            hit = window.hit_test(button_center)
            hit.should eq(button1)

            # Simulate mouse down on button (should bring panel1 to front)
            button1.on_mouse_down(button_center)

            # Panel1 should now have higher z_index than panel2
            panel1.z_index.should be > panel2.z_index
        end

        it "increments z_index even if already highest" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel1 = CrymbleUI::WindowPanel.new("Panel 1", 100.0, 100.0, 200.0, 150.0, z_index: 5)
            panel2 = CrymbleUI::WindowPanel.new("Panel 2", 150.0, 150.0, 200.0, 150.0, z_index: 2)

            window.add_child(panel1)
            window.add_child(panel2)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            initial_z = panel1.z_index

            # Click panel1 (already highest)
            click_point = CrymbleUI::Vec2.new(120.0, 120.0)
            panel1.on_mouse_down(click_point)

            # Gets max+10 even though already highest (handles same z_index case)
            # +10 ensures child layers (scrollbar z+2) stay behind next panel's base z
            panel1.z_index.should eq(initial_z + 10)
        end
    end

    describe "integration: child interaction" do
        it "button inside panel responds to first click" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

            click_count = 0
            button = CrymbleUI::Button.new("Test Button") { click_count += 1 }

            window.add_child(panel)
            panel.add_child(button)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # Get button position (use absolute bounds for hit testing)
            abs_bounds = button.absolute_bounds
            button_center = CrymbleUI::Vec2.new(
                abs_bounds.x + abs_bounds.width / 2,
                abs_bounds.y + abs_bounds.height / 2
            )

            # Simulate click: mouse down on button
            hit_widget = window.hit_test(button_center)
            hit_widget.should_not be_nil
            hit_widget.not_nil!.should eq(button)  # Sanity check

            # Call mouse handlers as renderer would
            hit = hit_widget.not_nil!
            hit.on_mouse_down(button_center)
            hit.on_mouse_up(button_center)

            # Check if still same widget (no rebuild)
            hit_widget_up = window.hit_test(button_center)
            hit_widget_up.should eq(hit)  # Widget didn't change

            # Trigger click
            hit.trigger_click

            # Button should have been clicked ONCE
            click_count.should eq(1)
        end

        it "panel comes to front when clicking child button" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0, z_index: 1)

            button = CrymbleUI::Button.new("Test Button") { }

            window.add_child(panel)
            panel.add_child(button)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            initial_z = panel.z_index

            # Click button (use absolute bounds for hit testing)
            abs_bounds = button.absolute_bounds
            button_center = CrymbleUI::Vec2.new(
                abs_bounds.x + abs_bounds.width / 2,
                abs_bounds.y + abs_bounds.height / 2
            )

            hit_widget = window.hit_test(button_center)
            hit_widget.should_not be_nil
            hit = hit_widget.not_nil!
            hit.on_mouse_down(button_center)
            hit.on_mouse_up(button_center)
            hit.trigger_click

            # Panel z_index SHOULD have increased (bring_containing_panel_to_front called)
            panel.z_index.should be > initial_z
        end
    end

    describe "#to_primitives" do
        # WindowPanel is now a pure container - Chrome widget handles rendering
        # Primitive generation tests removed (obsolete architecture)

        it "returns empty array when closed" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 200.0, 150.0)
            panel.close
            bounds = CrymbleUI::Rect.new(0, 0, 200, 150)

            primitives = panel.to_primitives(bounds)

            primitives.should be_empty
        end

    end

    describe "primitive caching" do
        it "uses Dynamic cache policy (default)" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 200.0, 150.0)

            panel.cache_policy.should eq(CrymbleUI::CachePolicy::Dynamic)
        end

        it "caches primitives when state is clean" do
            panel = CrymbleUI::WindowPanel.new("Test", 0.0, 0.0, 200.0, 150.0)
            panel.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)
            bounds = CrymbleUI::Rect.new(0, 0, 200, 150)

            # First call generates
            primitives1 = panel.get_primitives(bounds)
            panel.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = panel.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        # Obsolete: "regenerates when background color changes" - background now managed by layer.background_color
    end

    describe "#constrain_to_window_bounds" do
        it "keeps panel within window bounds" do
            panel = CrymbleUI::WindowPanel.new("Test", 500.0, 500.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Panel at 500, 500 is within bounds - should not change
            panel.constrain_to_window_bounds(window_bounds)
            panel.x.should eq(500.0)
            panel.y.should eq(500.0)
        end

        it "constrains panel dragged too far right" do
            panel = CrymbleUI::WindowPanel.new("Test", 1000.0, 100.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Panel would be mostly off-screen to the right
            panel.constrain_to_window_bounds(window_bounds)

            # Should be constrained to keep MIN_VISIBLE_MARGIN visible
            expected_max_x = 800.0 - CrymbleUI::WindowPanel::MIN_VISIBLE_MARGIN
            panel.x.should eq(expected_max_x)
        end

        it "constrains panel dragged too far left" do
            panel = CrymbleUI::WindowPanel.new("Test", -300.0, 100.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Panel would be mostly off-screen to the left
            panel.constrain_to_window_bounds(window_bounds)

            # Should be constrained to keep MIN_VISIBLE_MARGIN visible
            expected_min_x = 0.0 - 200.0 + CrymbleUI::WindowPanel::MIN_VISIBLE_MARGIN
            panel.x.should eq(expected_min_x)
        end

        it "constrains panel dragged above window" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, -50.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Panel would be above window
            panel.constrain_to_window_bounds(window_bounds)

            # Should be constrained to window top
            panel.y.should eq(0.0)
        end

        it "constrains panel dragged below window" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 700.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Panel would be mostly off-screen below window
            panel.constrain_to_window_bounds(window_bounds)

            # Should be constrained to keep title bar visible
            expected_max_y = 600.0 - panel.title_bar_height
            panel.y.should eq(expected_max_y)
        end

        it "updates bounds when position changes" do
            panel = CrymbleUI::WindowPanel.new("Test", 1000.0, 100.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            panel.constrain_to_window_bounds(window_bounds)

            # Bounds should be updated to match new position
            panel.bounds.x.should eq(panel.x)
            panel.bounds.y.should eq(panel.y)
        end
    end

    describe "path_id uniqueness" do
        it "label returns the panel title for unique path_id" do
            panel = CrymbleUI::WindowPanel.new("My Custom Panel", 0.0, 0.0, 100.0, 100.0)
            panel.label.should eq("My Custom Panel")
        end

        it "multiple panels have unique path_ids based on title" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel1 = CrymbleUI::WindowPanel.new("Panel A", 0.0, 0.0, 100.0, 100.0)
            panel2 = CrymbleUI::WindowPanel.new("Panel B", 100.0, 0.0, 100.0, 100.0)

            window.add_child(panel1)
            window.add_child(panel2)

            # Each panel should have a unique path_id based on its title
            panel1.path_id.should_not eq(panel2.path_id)
            panel1.path_id.should contain("Panel A")
            panel2.path_id.should contain("Panel B")
        end
    end
end
