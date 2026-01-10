require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"

# DSL-style app that creates NEW widget instances on each build() call
# This mimics how real SFML apps using DSL work, unlike TestApp which
# returns the same instance. Critical for testing reconciliation bugs.
class DSLStyleScrollApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    # Create NEW instances every time (like DSL does)
    window = CrymbleUI::Window.new("Test", 400, 300)
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_scroll")
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)
    window.add_child(scroll_view)
    window
  end
end

describe "ScrollView Scrollbar Interaction" do
  it "preserves scroll position after rebuild (wheel jerk-to-top bug)" do
    # Bug: copy_state_from didn't copy @content_size/@viewport_size.
    # After DSL rebuild, new widget had zero sizes. When the next wheel event
    # calls clamp_scroll_offset with zero sizes, max=0 and scroll resets to 0.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = DSLStyleScrollApp.new
    app.build_tree  # Initialize root widget (like SFML renderer does)

    renderer.render_frame(app)

    # Find the ScrollView in the tree
    scroll_view = app.root.not_nil!.find_by_id("test_scroll").not_nil!.as(CrymbleUI::ScrollView)
    scroll_view.scroll_offset.y.should eq 0.0

    # First wheel scroll
    point = CrymbleUI::Vec2.new(200.0, 150.0)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), point)  # Scroll down

    scroll_after_first_wheel = scroll_view.scroll_offset.y
    scroll_after_first_wheel.should be > 50.0  # Should have scrolled significantly

    # SFML calls rebuild() when needs_layout? is true - creates NEW widget instances
    app.rebuild

    # Get the NEW ScrollView (state was copied but sizes might be zero)
    new_scroll_view = app.root.not_nil!.find_by_id("test_scroll").not_nil!.as(CrymbleUI::ScrollView)

    # BUG: New widget has scroll_offset copied but content_size/viewport_size are ZERO
    # A second wheel event will call clamp_scroll_offset with zero sizes → reset to 0
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point)  # Another small scroll

    # Without fix: new_scroll_view.scroll_offset.y would be 0.0 (clamped to max=0)
    # With fix: should be scroll_after_first_wheel + 20 (second scroll delta)
    new_scroll_view.scroll_offset.y.should be > scroll_after_first_wheel
  end

  it "hit tests correctly when ScrollView has parent offset (absolute vs relative coords bug)" do
    # Bug: on_mouse_down used @bounds.x (relative to parent) instead of
    # absolute_bounds.x when converting absolute click coords to local.
    # This caused hit testing to be shifted by the parent's offset.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # Use VStack with padding to create a parent offset
    # This ensures ScrollView's @bounds.x != absolute_bounds.x
    outer_vstack = CrymbleUI::VStack.new(padding: 20.0)  # Creates 20px offset
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_scroll")
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)
    outer_vstack.add_child(scroll_view)

    window.add_child(outer_vstack)
    app.root_widget = window
    renderer.render_frame(app)

    # Verify we have the expected parent offset
    abs_bounds = scroll_view.absolute_bounds
    rel_bounds = scroll_view.bounds
    parent_offset_x = abs_bounds.x - rel_bounds.x
    parent_offset_x.should be > 0  # Must have non-zero parent offset

    # Calculate where the scrollbar should be in ABSOLUTE coordinates
    scrollbar_local_x = rel_bounds.width - 16.0  # 16 = SCROLLBAR_WIDTH
    scrollbar_abs_x = abs_bounds.x + scrollbar_local_x

    # Click in the middle of the scrollbar using ABSOLUTE coordinates
    click_x = scrollbar_abs_x + 8.0  # Middle of 16px scrollbar
    click_y = abs_bounds.y + 100.0   # Somewhere in the track (below thumb)
    click_point = CrymbleUI::Vec2.new(click_x, click_y)

    # The click should trigger page scroll (clicking in track, not thumb)
    initial_offset = scroll_view.scroll_offset.y
    app.handle_mouse_down(click_point)
    app.handle_mouse_up(click_point)

    # Should have scrolled - if hit test was using wrong coords, this would fail
    scroll_view.scroll_offset.y.should be > initial_offset
  end

  it "scrolls proportionally during continuous drag with render frames (REPRODUCER)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # Setup: Very tall content (100 buttons = ~2000px) in small viewport (300px)
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_scroll")
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    100.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Verify we have very tall content
    content_height = scroll_view.content_size.height
    viewport_height = scroll_view.viewport_size.height
    max_scroll = content_height - viewport_height

    content_height.should be > 1500.0  # Should be ~2000px

    # Find thumb center (should be near top since content is very tall)
    # Thumb now starts at ARROW_SIZE (16) to avoid overlapping up arrow
    scrollbar_x = scroll_view.bounds.x + scroll_view.bounds.width - 16.0  # SCROLLBAR_WIDTH in ABSOLUTE coords
    arrow_size = 16.0
    thumb_center = CrymbleUI::Vec2.new(scrollbar_x + 8.0, scroll_view.bounds.y + arrow_size + 15.0)  # y=31 is in thumb

    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 0.0

    # Start drag
    app.handle_mouse_down(thumb_center)

    # Simulate continuous drag with render frames (like real SFML app)
    # Drag 100px down in 10 steps
    10.times do |i|
      drag_point = CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + (i + 1) * 10.0)
      app.handle_mouse_move(drag_point)
      renderer.render_frame(app)  # ← KEY: render between moves like real app
    end

    app.handle_mouse_up(CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + 100.0))

    # Expect: Proportional scroll (NOT jump to max)
    # With 100px drag on ~300px track, thumb is ~30px, available_track ~270px
    # max_scroll ~3600px, so 100px drag should scroll ~1330px
    final_offset = scroll_view.scroll_offset.y

    final_offset.should be > 100.0  # Should have scrolled significantly
    final_offset.should be < max_scroll * 0.8  # Should NOT be near max (definitely not jumped to max)
  end

  it "scrolls when dragging vertical scrollbar thumb" do
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

    # Calculate thumb position (should be at top initially, below up arrow)
    scrollbar_x = scroll_view.bounds.width - 16.0  # SCROLLBAR_WIDTH
    arrow_size = 16.0  # ARROW_SIZE
    thumb_y = arrow_size  # Thumb starts below up arrow
    thumb_center = CrymbleUI::Vec2.new(scrollbar_x + 8.0, thumb_y + 15.0)

    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 0.0

    # Simulate drag: mouse down, move, mouse up
    app.handle_mouse_down(thumb_center)

    # Drag down 50 pixels
    drag_target = CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + 50.0)
    app.handle_mouse_move(drag_target)

    # Scroll offset should have increased proportionally
    scroll_view.scroll_offset.y.should be > initial_offset
    mid_offset = scroll_view.scroll_offset.y

    app.handle_mouse_up(drag_target)

    # Offset should remain after mouse up (not reset)
    scroll_view.scroll_offset.y.should eq mid_offset
  end

  it "scrolls down when clicking below thumb in vertical scrollbar track" do
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

    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 0.0

    # Click in track below thumb (middle of scrollbar, should be below thumb)
    scrollbar_x = scroll_view.bounds.width - 16.0
    track_click = CrymbleUI::Vec2.new(scrollbar_x + 8.0, 150.0)  # Middle of 300px height

    app.handle_mouse_down(track_click)
    app.handle_mouse_up(track_click)

    # Should have scrolled down by ~page amount
    scroll_view.scroll_offset.y.should be > initial_offset
    scroll_view.scroll_offset.y.should be > 50.0  # Significant scroll
  end

  it "scrolls up when clicking above thumb in vertical scrollbar track" do
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

    # First scroll to middle
    max_scroll = scroll_view.content_size.height - scroll_view.viewport_size.height
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, max_scroll / 2.0))
    renderer.render_frame(app)

    mid_offset = scroll_view.scroll_offset.y
    mid_offset.should be > 0.0

    # Click in track above thumb (near top, should be above thumb)
    scrollbar_x = scroll_view.bounds.width - 16.0
    track_click = CrymbleUI::Vec2.new(scrollbar_x + 8.0, 30.0)  # Near top

    app.handle_mouse_down(track_click)
    app.handle_mouse_up(track_click)

    # Should have scrolled up (offset decreased)
    scroll_view.scroll_offset.y.should be < mid_offset
  end

  it "scrolls down when clicking down arrow on vertical scrollbar" do
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

    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 0.0

    # Click down arrow (bottom of scrollbar)
    # Arrow is at bottom of scrollbar, ARROW_SIZE = 16.0
    scrollbar_x = scroll_view.bounds.width - 16.0
    down_arrow_y = scroll_view.bounds.height - 8.0  # Center of arrow
    arrow_click = CrymbleUI::Vec2.new(scrollbar_x + 8.0, down_arrow_y)

    app.handle_mouse_down(arrow_click)
    app.handle_mouse_up(arrow_click)

    # Should have scrolled down by line amount (~20 pixels)
    scroll_view.scroll_offset.y.should be > initial_offset
    scroll_view.scroll_offset.y.should be <= 30.0  # Small scroll
  end

  it "scrolls up when clicking up arrow on vertical scrollbar" do
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

    # First scroll down a bit
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 50.0))
    renderer.render_frame(app)

    initial_offset = scroll_view.scroll_offset.y
    initial_offset.should eq 50.0

    # Click up arrow (top of scrollbar)
    scrollbar_x = scroll_view.bounds.width - 16.0
    up_arrow_y = 8.0  # Center of top arrow
    arrow_click = CrymbleUI::Vec2.new(scrollbar_x + 8.0, up_arrow_y)

    app.handle_mouse_down(arrow_click)
    app.handle_mouse_up(arrow_click)

    # Should have scrolled up by line amount (~20 pixels)
    scroll_view.scroll_offset.y.should be < initial_offset
    scroll_view.scroll_offset.y.should be >= 20.0  # Decreased by ~20
  end

  it "handles horizontal scrollbar thumb dragging" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
    # Create wide content
    hstack = CrymbleUI::HStack.new(spacing: 5.0)
    20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
    scroll_view.set_content(hstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Calculate thumb position (should be at left initially, past left arrow)
    scrollbar_y = scroll_view.bounds.height - 16.0  # SCROLLBAR_WIDTH
    arrow_size = 16.0  # ARROW_SIZE
    thumb_x = arrow_size  # Thumb starts after left arrow
    thumb_center = CrymbleUI::Vec2.new(thumb_x + 15.0, scrollbar_y + 8.0)

    initial_offset = scroll_view.scroll_offset.x
    initial_offset.should eq 0.0

    # Simulate drag: mouse down, move right, mouse up
    app.handle_mouse_down(thumb_center)

    # Drag right 50 pixels
    drag_target = CrymbleUI::Vec2.new(thumb_center.x + 50.0, thumb_center.y)
    app.handle_mouse_move(drag_target)

    # Scroll offset should have increased
    scroll_view.scroll_offset.x.should be > initial_offset

    app.handle_mouse_up(drag_target)
  end

  it "stops dragging when mouse is released" do
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

    scrollbar_x = scroll_view.bounds.width - 16.0
    arrow_size = 16.0  # ARROW_SIZE
    thumb_center = CrymbleUI::Vec2.new(scrollbar_x + 8.0, arrow_size + 15.0)  # Thumb starts below arrow

    # Start drag
    app.handle_mouse_down(thumb_center)
    app.handle_mouse_move(CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + 50.0))

    offset_during_drag = scroll_view.scroll_offset.y
    offset_during_drag.should be > 0.0

    # Release mouse
    app.handle_mouse_up(CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + 50.0))

    # Move mouse further (should not affect scroll anymore)
    app.handle_mouse_move(CrymbleUI::Vec2.new(thumb_center.x, thumb_center.y + 100.0))

    # Offset should not have changed after mouse up
    scroll_view.scroll_offset.y.should eq offset_during_drag
  end

  it "clamps scroll when dragging beyond bounds" do
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

    # Calculate max_scroll using effective viewport (after render when sizes are known)
    effective_viewport = scroll_view.viewport_size.height
    max_scroll = scroll_view.content_size.height - effective_viewport

    scrollbar_x = scroll_view.bounds.width - 16.0
    arrow_size = 16.0  # ARROW_SIZE
    thumb_center = CrymbleUI::Vec2.new(scrollbar_x + 8.0, arrow_size + 15.0)  # Thumb starts below arrow

    # Start drag and move way past bottom
    app.handle_mouse_down(thumb_center)
    app.handle_mouse_move(CrymbleUI::Vec2.new(thumb_center.x, 10000.0))

    # Should be clamped to max_scroll, not beyond
    scroll_view.scroll_offset.y.should eq max_scroll

    app.handle_mouse_up(CrymbleUI::Vec2.new(thumb_center.x, 10000.0))
  end

  it "scrollbar track click scrolls in Both direction mode" do
    # Bug: In "Both" direction, clicking scrollbar track doesn't scroll.
    # The hit_test may return content behind the scrollbar, or ScrollView doesn't
    # properly handle the click.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # ScrollView with Both direction - will have both scrollbars
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

    # Grid of buttons that extends beyond viewport
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    10.times do
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      10.times { hstack.add_child(CrymbleUI::Button.new("B") { }) }
      vstack.add_child(hstack)
    end
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Initial scroll should be 0
    scroll_view.scroll_offset.y.should eq 0.0

    # Click below thumb on vertical scrollbar track (page down)
    # The scrollbar is on the right edge
    abs = scroll_view.absolute_bounds
    scrollbar_x = abs.x + scroll_view.bounds.width - 8.0  # Middle of 16px scrollbar

    # Click at bottom of track (below the thumb)
    # With this content/viewport ratio, thumb is ~74% of track height (~209px)
    # So click at y=250 (local) which is definitely below thumb
    track_click_y = abs.y + 250.0

    app.handle_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, track_click_y))
    app.handle_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, track_click_y))

    # Should have scrolled down (page scroll)
    scroll_view.scroll_offset.y.should be > 0.0
  end

  it "scrollbar thumb at max position when scroll at true max (Both mode)" do
    # Bug: Scrollbar thumb calculations use @viewport_size directly, but should use
    # effective viewport (minus scrollbar width). Result: thumb shows "at max" visually
    # but there's still more content to scroll to.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # ScrollView with Both direction - will have both scrollbars
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

    # Grid of buttons (32x32 like demo)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    32.times do
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      32.times { hstack.add_child(CrymbleUI::Button.new("B") { }) }
      vstack.add_child(hstack)
    end
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    scrollbar_width = 16.0

    # Scroll to huge value to hit max
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(10000.0, 10000.0))
    renderer.render_frame(app)

    # Calculate true max scroll AFTER render (viewport_size may change between renders)
    effective_height = scroll_view.viewport_size.height - scrollbar_width
    true_max_y = scroll_view.content_size.height - effective_height

    # Scroll should be clamped to true max
    scroll_view.scroll_offset.y.should eq true_max_y

    # Get scrollbar primitives to check thumb position
    prims = scroll_view.to_primitives(scroll_view.bounds)
    fill_rects = prims.select { |p| p.is_a?(CrymbleUI::FillRect) }.map(&.as(CrymbleUI::FillRect))

    # Find vertical scrollbar rects (on right edge)
    vertical_rects = fill_rects.select { |r| r.bounds.x >= scroll_view.bounds.width - scrollbar_width - 1 }
    vertical_rects.size.should be >= 2  # Track + thumb at minimum

    # Find thumb (smaller height than track)
    track_height = scroll_view.viewport_size.height - scrollbar_width
    thumb = vertical_rects.find { |r| r.bounds.height < track_height - 10 }
    thumb.should_not be_nil

    # At max scroll, thumb bottom should be at (or near) bottom of available track
    # Available track excludes both arrows, so track_bottom = track_height - ARROW_SIZE
    arrow_size = 16.0
    track_height = scroll_view.viewport_size.height - scrollbar_width
    track_bottom = track_height - arrow_size  # Bottom of usable track (above down arrow)
    thumb_bottom = thumb.not_nil!.bounds.y + thumb.not_nil!.bounds.height

    # Thumb should be at bottom of available track (within a few pixels)
    (track_bottom - thumb_bottom).abs.should be <= 5.0
  end

  it "dragging thumb to track bottom scrolls to true max content" do
    # Bug: Drag-to-scroll conversion uses wrong max_scroll, so dragging thumb
    # to bottom of track doesn't actually scroll to true max.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

    # Grid of buttons
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    32.times do
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      32.times { hstack.add_child(CrymbleUI::Button.new("B") { }) }
      vstack.add_child(hstack)
    end
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    scrollbar_width = 16.0
    arrow_size = 16.0

    # Find thumb starting position (at top, below up arrow)
    scrollbar_x = scroll_view.bounds.width - scrollbar_width / 2.0
    thumb_start_y = scroll_view.bounds.y + arrow_size + 15.0  # Near top of thumb, below arrow

    # Start drag on thumb
    app.handle_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, thumb_start_y))

    # Drag to bottom of available track (above down arrow and horizontal scrollbar)
    track_height = scroll_view.viewport_size.height - scrollbar_width
    track_bottom_y = scroll_view.bounds.y + track_height - arrow_size - 5.0
    app.handle_mouse_move(CrymbleUI::Vec2.new(scrollbar_x, track_bottom_y))
    renderer.render_frame(app)

    app.handle_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, track_bottom_y))

    # Calculate true max scroll AFTER render (viewport_size may change)
    effective_height = scroll_view.viewport_size.height - scrollbar_width
    true_max_y = scroll_view.content_size.height - effective_height

    # Should be at true max scroll (not the wrong max from buggy calculation)
    # Allow tolerance for rounding and thumb size calculation differences
    (scroll_view.scroll_offset.y - true_max_y).abs.should be <= 50.0
  end

  it "allows scrolling to see full content when both scrollbars visible" do
    # Bug: clamp_scroll_offset uses @viewport_size but doesn't account for
    # scrollbars reducing the visible content area. Result: can't scroll far
    # enough to see bottom-right content.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    # ScrollView with Both direction - will have both scrollbars
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

    # Content larger than viewport in both dimensions
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    10.times do
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      10.times { hstack.add_child(CrymbleUI::Button.new("Btn") { }) }
      vstack.add_child(hstack)
    end
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Verify both scrollbars are needed
    scroll_view.content_size.width.should be > scroll_view.viewport_size.width
    scroll_view.content_size.height.should be > scroll_view.viewport_size.height

    scrollbar_width = 16.0  # CrymbleUI::ScrollView::SCROLLBAR_WIDTH

    # Try to scroll far beyond any reasonable max
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(10000.0, 10000.0))
    renderer.render_frame(app)  # Trigger layout which calls clamp_scroll_offset

    # After render, get the actual viewport and content sizes (may change during layout)
    effective_width = scroll_view.viewport_size.width - scrollbar_width
    effective_height = scroll_view.viewport_size.height - scrollbar_width
    expected_max_x = scroll_view.content_size.width - effective_width
    expected_max_y = scroll_view.content_size.height - effective_height

    # Should be clamped to expected max (not less)
    # Bug: clamp uses viewport_size instead of effective viewport, so max is too small
    scroll_view.scroll_offset.x.should eq expected_max_x
    scroll_view.scroll_offset.y.should eq expected_max_y
  end

  it "thumb does not overlap up arrow at min scroll" do
    # Bug: Thumb at scroll_offset=0 starts at y=0, overlapping the up arrow.
    # Expected: Thumb starts at y=ARROW_SIZE (16) to be below the arrow.
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

    # At scroll_offset=0, thumb should be at top of track but below arrow
    scroll_view.scroll_offset.y.should eq 0.0

    # Get scrollbar primitives
    prims = scroll_view.to_primitives(scroll_view.bounds)
    fill_rects = prims.select { |p| p.is_a?(CrymbleUI::FillRect) }.map(&.as(CrymbleUI::FillRect))

    # Find vertical thumb (smaller rect on right side)
    scrollbar_width = 16.0
    arrow_size = 16.0
    scrollbar_x = scroll_view.bounds.width - scrollbar_width
    vertical_rects = fill_rects.select { |r| r.bounds.x >= scrollbar_x - 1 }
    thumb = vertical_rects.find { |r| r.bounds.height < scroll_view.bounds.height - 10 }
    thumb.should_not be_nil

    # Thumb top should be at or below arrow bottom
    thumb.not_nil!.bounds.y.should be >= arrow_size
  end

  it "thumb does not overlap down arrow at max scroll" do
    # Bug: Thumb at max scroll extends to bottom, overlapping down arrow.
    # Expected: Thumb ends at track_height - ARROW_SIZE.
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

    # Scroll to max
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 10000.0))
    renderer.render_frame(app)

    # Get scrollbar primitives
    prims = scroll_view.to_primitives(scroll_view.bounds)
    fill_rects = prims.select { |p| p.is_a?(CrymbleUI::FillRect) }.map(&.as(CrymbleUI::FillRect))

    # Find vertical thumb
    scrollbar_width = 16.0
    arrow_size = 16.0
    scrollbar_x = scroll_view.bounds.width - scrollbar_width
    vertical_rects = fill_rects.select { |r| r.bounds.x >= scrollbar_x - 1 }
    thumb = vertical_rects.find { |r| r.bounds.height < scroll_view.bounds.height - 10 }
    thumb.should_not be_nil

    # Thumb bottom should be at or above down arrow top
    track_height = scroll_view.bounds.height
    thumb_bottom = thumb.not_nil!.bounds.y + thumb.not_nil!.bounds.height
    thumb_bottom.should be <= track_height - arrow_size
  end
end
