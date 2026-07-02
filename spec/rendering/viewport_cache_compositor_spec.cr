require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/core/layer"

# Helper module for viewport_cache compositor tests
module ViewportCacheTestHelper
  def self.create_viewport_cache_layer(width : Int32, height : Int32, scroll_x : Float64 = 0.0, scroll_y : Float64 = 0.0)
    bounds = CrymbleUI::Rect.new(0, 0, width.to_f64, height.to_f64)
    layer = CrymbleUI::Layer.new("viewport_cache_test", bounds)
    layer.viewport_cache = true
    layer.scroll_offset = CrymbleUI::Vec2.new(scroll_x, scroll_y)
    # NEW: buffer_origin must be set so viewport samples from correct buffer position
    # viewport_pos = scroll_offset - buffer_origin, so buffer_origin = 0 means
    # viewport samples from scroll_offset position in buffer
    layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(0.0, 0.0))
    layer
  end
end

describe "Viewport cache compositor blitting" do
  describe "non-wrapped case (scroll offset within bounds)" do
    it "blits normally when scroll_offset is zero" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 0.0, 0.0)

      # Create and assign backend to layer
      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # Draw a colored rectangle in the backend
      10.times do |y|
        10.times do |x|
          backend.set_pixel(x + 10, y + 10, CrymbleUI::Color.new(255, 0, 0, 255))
        end
      end

      # Composite to window
      renderer.composite_layer_to_window(layer)

      # Check that content appears at expected position (layer.bounds = 0,0)
      window_backend = renderer.backend
      # Red pixel should be at (10, 10) in window
      pixel = window_backend.get_pixel(10, 10).not_nil!
      pixel.r.should eq(255)
      pixel.g.should eq(0)
    end

    it "blits normally when scroll_offset doesn't cause wrap" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 10.0, 10.0)  # Small scroll, no wrap

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # Draw at position (20, 20) in texture (content pos 20,20 with scroll 10,10 = visible at 10,10)
      10.times do |y|
        10.times do |x|
          backend.set_pixel(x + 20, y + 20, CrymbleUI::Color.new(0, 255, 0, 255))
        end
      end

      renderer.composite_layer_to_window(layer)

      # With scroll_offset (10,10), content at texture (20,20) should appear at screen (10,10)
      # Because viewport shows content from (10,10) to (110,110), and texture(20,20) = content(20,20)
      window_backend = renderer.backend
      pixel = window_backend.get_pixel(10, 10).not_nil!
      pixel.g.should eq(255)
    end
  end

  describe "vertical scroll (sliding viewport)" do
    it "samples from buffer at scroll_offset position" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      # Viewport is 100x100, buffer is 200x200 (large enough for scroll)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 0.0, 50.0)  # Scrolled 50px down

      # Create large buffer that can hold content beyond viewport
      backend = CrymbleUI::Testing::TestRenderBackend.new(200, 200, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # NEW MODEL: viewport samples from buffer at (scroll_offset - buffer_origin)
      # With buffer_origin=0 and scroll_offset.y=50, viewport samples from buffer y=50

      # Draw marker at buffer y=60 (should appear at screen y=10 after scroll)
      # screen_y = buffer_y - viewport_y = 60 - 50 = 10
      5.times do |y|
        5.times do |x|
          backend.set_pixel(x + 10, 60 + y, CrymbleUI::Color.new(0, 0, 255, 255))
        end
      end

      # Draw marker at buffer y=120 (should appear at screen y=70 after scroll)
      # screen_y = buffer_y - viewport_y = 120 - 50 = 70
      5.times do |y|
        5.times do |x|
          backend.set_pixel(x + 10, 120 + y, CrymbleUI::Color.new(255, 0, 0, 255))
        end
      end

      renderer.composite_layer_to_window(layer)

      window_backend = renderer.backend

      # Blue marker at buffer y=60, scroll=50, should appear at screen y=10
      blue_pixel = window_backend.get_pixel(10, 10).not_nil!
      blue_pixel.b.should eq(255)

      # Red marker at buffer y=120, scroll=50, should appear at screen y=70
      red_pixel = window_backend.get_pixel(10, 70).not_nil!
      red_pixel.r.should eq(255)
    end
  end

  describe "horizontal scroll (sliding viewport)" do
    it "samples from buffer at scroll_offset.x position" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 50.0, 0.0)  # Scrolled 50px right

      # Large buffer for horizontal scrolling
      backend = CrymbleUI::Testing::TestRenderBackend.new(200, 200, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # Draw marker at buffer x=60 (should appear at screen x=10 after scroll)
      # screen_x = buffer_x - viewport_x = 60 - 50 = 10
      5.times do |y|
        5.times do |x|
          backend.set_pixel(60 + x, y + 10, CrymbleUI::Color.new(0, 255, 0, 255))
        end
      end

      # Draw marker at buffer x=120 (should appear at screen x=70 after scroll)
      5.times do |y|
        5.times do |x|
          backend.set_pixel(120 + x, y + 10, CrymbleUI::Color.new(255, 255, 0, 255))
        end
      end

      renderer.composite_layer_to_window(layer)

      window_backend = renderer.backend

      # Green marker at buffer x=60, scroll=50, should appear at screen x=10
      green_pixel = window_backend.get_pixel(10, 10).not_nil!
      green_pixel.g.should eq(255)

      # Yellow marker at buffer x=120, scroll=50, should appear at screen x=70
      yellow_pixel = window_backend.get_pixel(70, 10).not_nil!
      yellow_pixel.r.should eq(255)
      yellow_pixel.g.should eq(255)
    end
  end

  describe "2D scroll (sliding viewport both directions)" do
    it "samples from buffer at (scroll_x, scroll_y) position" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 50.0, 50.0)  # Scrolled 50px in both directions

      # Large buffer for 2D scrolling
      backend = CrymbleUI::Testing::TestRenderBackend.new(200, 200, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # Draw 4 quadrant markers at buffer positions
      # With scroll=(50,50), viewport samples buffer (50-150, 50-150)
      # Q1 (buffer 60,60) → screen (10,10): Blue
      # Q2 (buffer 120,60) → screen (70,10): Green
      # Q3 (buffer 60,120) → screen (10,70): Red
      # Q4 (buffer 120,120) → screen (70,70): Yellow

      backend.set_pixel(60, 60, CrymbleUI::Color.new(0, 0, 255, 255))    # Q1: Blue
      backend.set_pixel(120, 60, CrymbleUI::Color.new(0, 255, 0, 255))   # Q2: Green
      backend.set_pixel(60, 120, CrymbleUI::Color.new(255, 0, 0, 255))   # Q3: Red
      backend.set_pixel(120, 120, CrymbleUI::Color.new(255, 255, 0, 255)) # Q4: Yellow

      renderer.composite_layer_to_window(layer)

      window_backend = renderer.backend

      # Verify all 4 markers at expected screen positions
      window_backend.get_pixel(10, 10).not_nil!.b.should eq(255)  # Blue
      window_backend.get_pixel(70, 10).not_nil!.g.should eq(255)  # Green
      window_backend.get_pixel(10, 70).not_nil!.r.should eq(255)  # Red
      q4 = window_backend.get_pixel(70, 70).not_nil!
      q4.r.should eq(255)  # Yellow
      q4.g.should eq(255)
    end
  end

  describe "blit count for wrapped compositing" do
    it "uses 1 blit when no wrap needed" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 0.0, 0.0)

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      renderer.reset_counters
      renderer.composite_layer_to_window(layer)

      renderer.backend_blit_count.should eq(1)
    end

    # NOTE: With viewport-relative rendering, wrap-around blitting is no longer needed
    # Widgets render at (layout - scroll_offset), so content is always at position 0 in texture
    # Compositor always uses 1 blit regardless of scroll_offset
    it "uses 1 blit with viewport-relative rendering (no wrap needed)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 0.0, 80.0)

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend
      layer.recenter_origin!(backend.width, backend.height) # fitting origin (production recenters at high scroll) — blit count is origin-independent, and this keeps -Dverify_bounds clean

      renderer.reset_counters
      renderer.composite_layer_to_window(layer)

      # Content is rendered at viewport-relative positions, so no wrap needed at compositor
      renderer.backend_blit_count.should eq(1)
    end

    it "uses 1 blit for horizontal scroll (no wrap needed)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 80.0, 0.0)

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend
      layer.recenter_origin!(backend.width, backend.height) # fitting origin (production recenters at high scroll) — blit count is origin-independent, and this keeps -Dverify_bounds clean

      renderer.reset_counters
      renderer.composite_layer_to_window(layer)

      renderer.backend_blit_count.should eq(1)
    end

    it "uses 1 blit for 2D scroll (no wrap needed)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 80.0, 80.0)

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend
      layer.recenter_origin!(backend.width, backend.height) # fitting origin (production recenters at high scroll) — blit count is origin-independent, and this keeps -Dverify_bounds clean

      renderer.reset_counters
      renderer.composite_layer_to_window(layer)

      renderer.backend_blit_count.should eq(1)
    end
  end

  describe "non-viewport_cache layers remain unchanged" do
    it "ignores scroll_offset for non-viewport_cache layers" do
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
      layer = ViewportCacheTestHelper.create_viewport_cache_layer(100, 100, 50.0, 50.0)
      layer.viewport_cache = false  # Disable viewport_cache mode

      backend = CrymbleUI::Testing::TestRenderBackend.new(120, 120, CrymbleUI::Color.new(0, 0, 0, 0))
      layer.backend = backend

      # Draw at texture position (10, 10)
      backend.set_pixel(10, 10, CrymbleUI::Color.new(255, 0, 0, 255))

      renderer.composite_layer_to_window(layer)

      window_backend = renderer.backend
      # For non-viewport_cache, scroll_offset should be ignored
      # Content at texture (10, 10) should appear at screen (10, 10)
      pixel = window_backend.get_pixel(10, 10).not_nil!
      pixel.r.should eq(255)
    end
  end
end
