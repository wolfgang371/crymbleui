require "../spec_helper"
require "../../src/testing/test_renderer"

# Test widget that simulates CPUMonitor behavior:
# - Fixed widget size (doesn't change when content changes)
# - Transparent background
# - Content width can change (like text getting shorter)
# - Uses mark_needs_render only (not mark_needs_layout)
class FixedSizeContentWidget < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  property content_width : Float64
  property widget_width : Float64
  property widget_height : Float64

  def initialize(@widget_width : Float64, @widget_height : Float64, @content_width : Float64, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    # Always return FIXED size, regardless of content_width
    # This simulates CPUMonitor which has fixed padding around text
    CrymbleUI::Size.new(@widget_width, @widget_height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    size = measure(constraints)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, size.width, size.height)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      # Transparent background (like CPUMonitor default)
      # This cannot clear old pixels!
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, @widget_width, @widget_height),
                CrymbleUI::Color.new(255, 255, 255, 0))  # Transparent

      # Render content with current width (like text that can shrink)
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, @content_width, @widget_height),
                CrymbleUI::Color.red)
    end
  end

  def label : String?
    "fixed_size_content"
  end
end

# Tests for widget content shrink without size change (simulates CPUMonitor bug)
#
# BUG: When widget content shrinks (e.g., red bar 100px → 80px) but widget SIZE
# stays the same, old pixels remain visible because:
# 1. mark_needs_render doesn't trigger layout (widget size unchanged)
# 2. Transparent background can't clear old pixels
# 3. Selective rendering only updates new content area
#
# This is different from widget_shrink_cache_spec.cr where widget SIZE actually changes.
describe "Widget Content Shrink Without Size Change" do
  it "clears old pixels when content shrinks but widget size stays same" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create widget with:
    # - Fixed widget size: 120px x 50px (stays constant)
    # - Initial content width: 100px (red bar)
    widget = FixedSizeContentWidget.new(
      widget_width: 120.0,
      widget_height: 50.0,
      content_width: 100.0
    )
    window.add_child(widget)
    app.root_widget = window

    # Frame 1: Render widget with 100px wide red bar (widget is 120px wide)
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    # Get the window backend to check pixels
    window_backend = renderer.backend
    widget_x = 8  # CONTENT_PADDING

    # Verify initial state: red pixels from x=8 to x=108
    pixel_99 = window_backend.get_pixel(widget_x + 99, widget_x + 10)
    pixel_99.should eq(CrymbleUI::Color.red)

    # Frame 2: Shrink CONTENT to 80px (widget size stays 120px)
    widget.content_width = 80.0

    # CRITICAL: Call mark_needs_render ONLY (not mark_needs_layout)
    # This simulates CPUMonitor behavior - content changes but no layout
    widget.mark_needs_render

    renderer.render_frame(app)

    # Check pixels after content shrink:
    # - Pixels [8...88] should be red (new content)
    # - Pixels [88...108] should be white background (cleared!)
    #   BUG: These pixels are still red from old content

    # Check pixel inside new content area - should still be red
    pixel_79 = window_backend.get_pixel(widget_x + 79, widget_x + 10)
    pixel_79.should eq(CrymbleUI::Color.red)

    # Check pixel outside new content (was inside old content)
    # Should be white background, NOT red
    # This is where the bug manifests - old red pixels remain
    pixel_89 = window_backend.get_pixel(widget_x + 89, widget_x + 10)
    window_background = CrymbleUI::Color.new(255, 255, 255, 255)
    pixel_89.should eq(window_background)
  end
end
