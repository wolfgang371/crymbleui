require "../spec_helper"
require "../../src/testing/test_renderer"

# Test for ScrollView clipping bug: content renders above ScrollView bounds
# Bug: Items render INTO sibling widget area (buttons) above ScrollView
#
# NOTE: This test passes in TestRenderer. The bug is SFML-specific.
# Run showcase_demo to reproduce the bug visually.
describe "ScrollView clipping" do
  describe "content clipping at top boundary" do
    it "clips content to ScrollView bounds (no overflow above)" do
      # Setup: VStack with header button, then ScrollView below
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      container = CrymbleUI::VStack.new(spacing: 0.0)

      # Header with BLUE background
      header = CrymbleUI::Button.new("Header") { }
      header.background_color = CrymbleUI::Color.new(0, 0, 255, 255)
      container.add_child(header)

      # ScrollView with RED content
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      content_vstack = CrymbleUI::VStack.new(spacing: 2.0)
      20.times do |i|
        btn = CrymbleUI::Button.new("Item #{i}") { }
        btn.background_color = CrymbleUI::Color.new(255, 0, 0, 255)
        content_vstack.add_child(btn)
      end
      scroll_view.set_content(content_vstack)
      container.add_child(scroll_view)
      window.add_child(container)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Scroll down then back up (bug appears after scrolling)
      scroll_view.scroll_offset = CrymbleUI::Vec2.new(0.0, 50.0)
      renderer.render_frame(app)
      scroll_view.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
      renderer.render_frame(app)

      # Check: no RED pixels above ScrollView layer
      scroll_view_top_y = scroll_view.layer.not_nil!.bounds.y.to_i

      (0...scroll_view_top_y).step(5).each do |sample_y|
        [10, 100, 200].each do |sample_x|
          pixel = renderer.backend.get_pixel(sample_x, sample_y)
          if pixel && pixel.r > 200 && pixel.g < 50 && pixel.b < 50
            fail "RED pixel at (#{sample_x}, #{sample_y}) - scroll content leaked!"
          end
        end
      end

      # Verify ScrollView content IS visible in its area
      scroll_y = (scroll_view.absolute_bounds.y + 20).to_i
      pixel = renderer.backend.get_pixel(50, scroll_y)
      pixel.should_not be_nil
      pixel.not_nil!.r.should be > 100, "ScrollView content should be red"
    end
  end
end
