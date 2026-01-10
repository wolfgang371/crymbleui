require "../spec_helper"
require "../../src/widgets/window"

describe CrymbleUI::Window do
    describe "#initialize" do
        it "creates window with title, width, and height" do
            window = CrymbleUI::Window.new("Test App", 800, 600)
            window.title.should eq("Test App")
            window.width.should eq(800)
            window.height.should eq(600)
        end

        it "accepts id parameter" do
            window = CrymbleUI::Window.new("Test App", 800, 600, id: "main_window")
            window.id.should eq("main_window")
        end
    end

    describe "#measure" do
        it "returns specified width and height" do
            window = CrymbleUI::Window.new("Test App", 800, 600)
            constraints = CrymbleUI::BoxConstraints.new

            size = window.measure(constraints)

            size.width.should eq(800.0)
            size.height.should eq(600.0)
        end
    end

    describe "#to_primitives" do
        it "returns empty array (Window is just a container)" do
            window = CrymbleUI::Window.new("Test App", 800, 600)
            bounds = CrymbleUI::Rect.new(0, 0, 800, 600)

            primitives = window.to_primitives(bounds)

            primitives.should be_empty
        end

        it "returns empty array even with children" do
            window = CrymbleUI::Window.new("Test App", 800, 600)
            text = CrymbleUI::Text.new("Hello")
            window.add_child(text)
            bounds = CrymbleUI::Rect.new(0, 0, 800, 600)

            primitives = window.to_primitives(bounds)

            # Window doesn't render children's primitives
            # Children render themselves during traversal
            primitives.should be_empty
        end
    end

    describe "primitive caching" do
        it "uses Dynamic cache policy (default)" do
            window = CrymbleUI::Window.new("Test App", 800, 600)

            window.cache_policy.should eq(CrymbleUI::CachePolicy::Dynamic)
        end

        it "always returns empty primitives (nothing to cache)" do
            window = CrymbleUI::Window.new("Test App", 800, 600)
            bounds = CrymbleUI::Rect.new(0, 0, 800, 600)

            # First call
            primitives1 = window.get_primitives(bounds)
            window.clear_render_state_recursive  # Mark clean

            # Second call
            primitives2 = window.get_primitives(bounds)

            primitives1.should be_empty
            primitives2.should be_empty
        end
    end

    describe "overlay layout (TEST MODE)" do
        # Overlays (popups, tooltips) must be laid out by Window.perform_layout
        # Previously ComboBox worked around this by calling popup.layout() directly

        it "layouts overlays during perform_layout" do
            window = CrymbleUI::Window.new("Test App", 800, 600)

            # Create a popup overlay with explicit size
            popup = CrymbleUI::Popup.new(z_index: 1000, width: 150.0, height: 100.0)
            window.add_overlay(popup)

            # Before layout, bounds should be zero (not laid out yet)
            popup.bounds.should eq(CrymbleUI::Rect.zero)

            # Layout the window
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Overlay should have been laid out (bounds should match explicit size)
            popup.bounds.width.should eq(150.0)
            popup.bounds.height.should eq(100.0)
        end

        it "lays out multiple overlays" do
            window = CrymbleUI::Window.new("Test App", 800, 600)

            popup1 = CrymbleUI::Popup.new(z_index: 1000, width: 100.0, height: 50.0)
            popup2 = CrymbleUI::Popup.new(z_index: 1001, width: 120.0, height: 60.0)

            window.add_overlay(popup1)
            window.add_overlay(popup2)

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            popup1.bounds.width.should eq(100.0)
            popup2.bounds.width.should eq(120.0)
        end
    end

    describe "click-outside-to-close (TEST MODE)" do
        # When clicking outside a popup, on_click_outside should be called
        # This allows popups to close themselves

        it "calls on_click_outside when clicking outside popup bounds" do
            window = CrymbleUI::Window.new("Test App", 800, 600)

            popup = CrymbleUI::Popup.new(z_index: 1000, width: 100.0, height: 50.0)
            window.add_overlay(popup)

            # Layout to set bounds
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Popup is at (0, 0) with size 100x50
            # Track if on_click_outside was called
            click_outside_called = false
            popup.on_click_outside_callback = -> { click_outside_called = true; nil }

            # Click outside popup (at 200, 200)
            window.notify_overlays_of_click(CrymbleUI::Vec2.new(200.0, 200.0))

            click_outside_called.should be_true
        end

        it "does not call on_click_outside when clicking inside popup bounds" do
            window = CrymbleUI::Window.new("Test App", 800, 600)

            popup = CrymbleUI::Popup.new(z_index: 1000, width: 100.0, height: 50.0)
            window.add_overlay(popup)

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            click_outside_called = false
            popup.on_click_outside_callback = -> { click_outside_called = true; nil }

            # Click inside popup (at 50, 25)
            window.notify_overlays_of_click(CrymbleUI::Vec2.new(50.0, 25.0))

            click_outside_called.should be_false
        end
    end
end
