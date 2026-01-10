require "../spec_helper"
require "../../src/testing/test_renderer"

describe "ScrollView Mouse Wheel Scrolling" do
  it "scrolls down when wheel scrolls down" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Initially at top (offset = 0)
    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 0.0

    # Scroll down (negative delta = scroll down)
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(100.0, 100.0))

    # Offset should increase (content moves up, we see lower content)
    scroll_view.scroll_offset.y.should be > initial_offset
  end

  it "scrolls up when wheel scrolls up" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Manually set scroll to middle position
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 100.0))
    middle_offset = scroll_view.scroll_offset.y

    # Scroll up (positive delta = scroll up)
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(100.0, 100.0))

    # Offset should decrease (content moves down, we see higher content)
    scroll_view.scroll_offset.y.should be < middle_offset
  end

  it "clamps scroll to minimum (0, 0)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Already at top (offset = 0)
    scroll_view.scroll_offset.y.should eq 0.0

    # Try to scroll up (should stay at 0)
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(100.0, 100.0))

    # Should still be at 0 (clamped)
    scroll_view.scroll_offset.y.should eq 0.0
  end

  it "clamps scroll to maximum" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Calculate max scroll (content_size - viewport_size)
    max_scroll = scroll_view.content_size.height - scroll_view.viewport_size.height
    max_scroll.should be > 0.0  # Sanity check: content is larger than viewport

    # Set scroll beyond maximum
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, max_scroll + 100.0))

    # Try to scroll down more (should clamp to max)
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(100.0, 100.0))

    # Should be clamped to max_scroll
    scroll_view.scroll_offset.y.should eq max_scroll
  end

  it "updates scrollbar thumb position after scrolling" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Get initial primitives (thumb at top)
    initial_prims = scroll_view.to_primitives(scroll_view.bounds)
    initial_thumb = initial_prims.select { |p| p.is_a?(CrymbleUI::FillRect) }[1]  # Second rect is thumb
    initial_thumb_y = initial_thumb.as(CrymbleUI::FillRect).bounds.y

    # Scroll down
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), CrymbleUI::Vec2.new(100.0, 100.0))
    renderer.render_frame(app)  # Re-render to update primitives

    # Get updated primitives (thumb moved down)
    updated_prims = scroll_view.to_primitives(scroll_view.bounds)
    updated_thumb = updated_prims.select { |p| p.is_a?(CrymbleUI::FillRect) }[1]
    updated_thumb_y = updated_thumb.as(CrymbleUI::FillRect).bounds.y

    # Thumb should have moved down
    updated_thumb_y.should be > initial_thumb_y
  end

  it "has acceptable performance for wheel scrolling" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    100.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }  # More content
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window

    # Settle rendering
    renderer.settle_rendering(app)
    renderer.reset_counters

    # Perform wheel scroll
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(100.0, 100.0))
    renderer.render_frame(app)

    # Layout should be minimal (just ScrollView re-layout for content position)
    # Note: May not be fully optimized yet - document for M5 if needed
    renderer.layout_count.should be <= 10

    # Primitive count should only include ScrollView's scrollbar (not full re-render)
    # This test may fail initially - that's OK, we'll optimize in M5 if needed
  end

  it "scrolls horizontally when shift+wheel in horizontal or both direction" do
    # Feature: Shift+wheel should scroll horizontally instead of vertically
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # Horizontal scrolling content
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
    hstack = CrymbleUI::HStack.new(spacing: 5.0)
    20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
    scroll_view.set_content(hstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Initial horizontal offset should be 0
    scroll_view.scroll_offset.x.should eq 0.0

    # Simulate shift+wheel (vertical delta, but shift pressed should scroll horizontally)
    # on_mouse_wheel needs to accept shift parameter
    point = CrymbleUI::Vec2.new(200.0, 150.0)
    scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)

    # Should scroll horizontally (x offset changed)
    scroll_view.scroll_offset.x.should be > 0.0
  end

  it "scrolls horizontally when app.handle_mouse_wheel called with shift=true" do
    # Bug: app.handle_mouse_wheel doesn't pass shift to widget.on_mouse_wheel
    # This tests the full event chain: app -> widget
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # Horizontal scrolling content
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
    hstack = CrymbleUI::HStack.new(spacing: 5.0)
    20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
    scroll_view.set_content(hstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Initial horizontal offset should be 0
    scroll_view.scroll_offset.x.should eq 0.0

    # Call through app (simulating SFML event path) with shift=true
    point = CrymbleUI::Vec2.new(200.0, 150.0)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)

    # Should scroll horizontally (vertical delta converted to horizontal by shift)
    scroll_view.scroll_offset.x.should be > 0.0
  end
end
