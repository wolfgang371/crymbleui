require "../spec_helper"

describe "WindowPanel performance optimizations" do
    describe "programmatic panel movement" do
        it "can move panel programmatically" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            panel.move_to(200.0, 200.0)

            panel.x.should eq(200.0)
            panel.y.should eq(200.0)
            panel.bounds.x.should eq(200.0)
            panel.bounds.y.should eq(200.0)
        end

        it "can move panel by relative offset" do
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)

            panel.move_by(50.0, 50.0)

            panel.x.should eq(150.0)
            panel.y.should eq(150.0)
        end

        it "updates child positions when moved programmatically" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            button = CrymbleUI::Button.new("Click", id: "btn") { }

            window.add_child(panel)
            panel.add_child(button)

            # Layout everything
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # With parent-relative bounds, button.bounds is relative to panel
            # and doesn't change when panel moves
            initial_btn_rel_x = button.bounds.x
            initial_btn_rel_y = button.bounds.y

            # But absolute position should reflect initial window position
            initial_btn_abs = button.absolute_bounds

            # Move panel programmatically
            panel.move_by(50.0, 50.0)

            # Button's relative position unchanged
            button.bounds.x.should be_close(initial_btn_rel_x, 0.1)
            button.bounds.y.should be_close(initial_btn_rel_y, 0.1)

            # Button's absolute position should have moved with panel
            new_abs = button.absolute_bounds
            new_abs.x.should be_close(initial_btn_abs.x + 50.0, 0.1)
            new_abs.y.should be_close(initial_btn_abs.y + 50.0, 0.1)
        end
    end

    # Future optimization: Per-panel texture caching
    # TODO: Implement per-panel texture cache that doesn't invalidate on position changes
    # Goals:
    #   - Panel moves (move_to/move_by) should not trigger cache re-render
    #   - Only content changes should trigger re-render
    #   - Expected: cache_render_count == 0 after position changes

    describe "render count optimization" do
        it "re-renders cache when panel content actually changes" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            button = CrymbleUI::Button.new("Click") { }

            window.add_child(panel)
            panel.add_child(button)

            # Layout everything
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            CrymbleUI::Widget.reset_render_counts

            # Changing button appearance should trigger cache re-render
            button.mark_needs_render

            # Verify flag is set and propagated (actual cache re-render would happen during render pass)
            button.needs_render?.should be_true

            # With new architecture, propagation goes to layer (not parent widget)
            # Panel layer should need render since child changed
            panel_layer = panel.layer.not_nil!
            panel_layer.needs_render?.should be_true
        end
    end

    describe "mouse-driven drag optimization" do
        it "defers layout during drag (tested via mouse events)" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
            button = CrymbleUI::Button.new("Click", id: "btn") { }

            window.add_child(panel)
            panel.add_child(button)

            # Layout everything
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # With parent-relative bounds, button.bounds is relative to panel
            initial_btn_rel_x = button.bounds.x
            initial_btn_abs_x = button.absolute_bounds.x

            # Simulate drag: mouse down on title bar
            point = CrymbleUI::Vec2.new(150.0, 115.0)  # Title bar
            panel.on_mouse_down(point)

            # Drag 10 times (simulating mouse move events)
            10.times do
                point = CrymbleUI::Vec2.new(point.x + 10.0, point.y)
                panel.on_mouse_move(point)
            end

            # During drag, panel position changes but children NOT re-laid out
            panel.x.should be_close(200.0, 1.0)  # Moved by ~100px

            # With parent-relative bounds, button.bounds (relative) stays the same
            # Only absolute_bounds changes with panel movement
            button.bounds.x.should be_close(initial_btn_rel_x, 1.0)

            # Absolute position follows panel
            delta_x = panel.x - 100.0
            button.absolute_bounds.x.should be_close(initial_btn_abs_x + delta_x, 1.0)

            # Mouse up - no layout needed with parent-relative bounds
            panel.on_mouse_up(point)
        end
    end
end
