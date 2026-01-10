require "../spec_helper"
require "../../src/testing/test_renderer"

# Bug: When scrolled to bottom, then enlarging viewport - scroll position not adjusted
# Root cause: clamp_scroll_offset() not called in perform_layout() when viewport_size changes
describe "ScrollView viewport resize" do
  it "clamps scroll offset when viewport grows" do
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

    # Get content and viewport sizes
    content_height = scroll_view.content_size.height
    viewport_height = scroll_view.viewport_size.height
    max_scroll = content_height - viewport_height

    # Scroll to bottom
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, max_scroll))
    scroll_view.scroll_offset.y.should eq max_scroll  # Sanity check

    # Now simulate viewport growing by 100px
    # This means max_scroll should decrease by 100
    new_max_scroll = max_scroll - 100.0

    # Re-layout with larger constraints (simulating window resize)
    larger_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 400.0))  # 100px taller
    scroll_view.mark_needs_layout
    scroll_view.layout(larger_constraints, CrymbleUI::Vec2.new(0.0, 0.0))

    # After resize, scroll offset should be clamped to new max
    # Bug: offset stays at old max_scroll (too high), leaving blank space at bottom
    scroll_view.scroll_offset.y.should be <= new_max_scroll + 1.0  # Allow small FP tolerance
  end

  it "does not affect scroll when viewport shrinks" do
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

    # Scroll to middle position
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 100.0))
    middle_offset = scroll_view.scroll_offset.y

    # Re-layout with smaller constraints (simulating window resize smaller)
    smaller_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 200.0))  # 100px shorter
    scroll_view.mark_needs_layout
    scroll_view.layout(smaller_constraints, CrymbleUI::Vec2.new(0.0, 0.0))

    # Scroll offset should remain the same (still valid within new max)
    scroll_view.scroll_offset.y.should eq middle_offset
  end
end
