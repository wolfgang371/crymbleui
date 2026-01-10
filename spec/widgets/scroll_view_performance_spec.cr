require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

describe "ScrollView performance" do
  describe "idle frame rendering" do
    it "renders 0 widgets after settle (diagnostic)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Simple ScrollView with content
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Settle initial rendering
      renderer.settle_rendering(app)

      # Reset all counters
      CrymbleUI::LayerRenderer.reset_frame_counters
      renderer.reset_counters

      # Render one more frame with NO interaction
      renderer.render_frame(app)

      # Diagnostic: show which widgets were rendered
      widget_count = CrymbleUI::LayerRenderer.frame_widget_count
      if widget_count > 0
        widget_list = CrymbleUI::LayerRenderer.rendered_widgets.join("\n  ")
        fail "Expected 0 widgets on idle frame, got #{widget_count}:\n  #{widget_list}"
      end
    end
  end

  describe "O(1) scroll performance" do
    it "layout_count is 0 during mouse wheel scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Settle initial rendering
      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll 10 times
      10.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # NO layout calls during scroll - this is the key O(1) metric
      renderer.layout_count.should eq(0)
    end

    it "scroll renders only newly-visible widgets, not all visible" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Settle initial rendering - all visible widgets render once
      renderer.settle_rendering(app)
      CrymbleUI::LayerRenderer.reset_frame_counters
      renderer.reset_counters

      # Small scroll - only 1-2 new widgets should enter viewport
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app)

      widget_count = CrymbleUI::LayerRenderer.frame_widget_count

      # KEY ASSERTION: Only newly-appearing widgets should render
      # A small scroll should reveal at most 1-2 new widgets
      # Already-visible widgets just moved - their content is unchanged, shouldn't re-render
      # Allow scrollbar (1 widget) + newly visible buttons (1-2) = max 4
      widget_count.should be <= 4
    end

    it "continuous scroll renders O(1) widgets per frame" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.settle_rendering(app)

      # Scroll 10 frames continuously
      total_widgets = 0
      10.times do
        CrymbleUI::LayerRenderer.reset_frame_counters
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
        total_widgets += CrymbleUI::LayerRenderer.frame_widget_count
      end

      # 10 scroll frames should render ~10-30 widgets total (1-3 new per frame)
      # NOT 10 frames × 10 visible widgets = 100 widgets
      total_widgets.should be <= 40
    end

    it "primitive count scales with viewport, not content" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Test with 50 buttons
      app_50 = TestApp.new
      window_50 = CrymbleUI::Window.new("Test", 400, 300)
      scroll_view_50 = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack_50 = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack_50.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view_50.set_content(vstack_50)
      window_50.add_child(scroll_view_50)
      app_50.root_widget = window_50

      renderer.settle_rendering(app_50)
      renderer.reset_counters
      scroll_view_50.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_50)
      prims_50 = renderer.primitive_count

      # Test with 500 buttons (10x more)
      app_500 = TestApp.new
      window_500 = CrymbleUI::Window.new("Test", 400, 300)
      scroll_view_500 = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack_500 = CrymbleUI::VStack.new(spacing: 5.0)
      500.times { vstack_500.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view_500.set_content(vstack_500)
      window_500.add_child(scroll_view_500)
      app_500.root_widget = window_500

      renderer.settle_rendering(app_500)
      renderer.reset_counters
      scroll_view_500.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_500)
      prims_500 = renderer.primitive_count

      # O(1) performance: primitive count should be similar (not 10x)
      # Allow 3x variance for edge effects, but definitely not 10x
      prims_500.should be <= prims_50 * 3
    end

    it "layout_count is 0 during scrollbar thumb drag" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.settle_rendering(app)
      renderer.reset_counters

      # Calculate scrollbar thumb position
      scrollbar_x = 400.0 - 8.0  # Center of scrollbar
      thumb_y = 20.0             # Approximately where thumb starts

      # Simulate thumb drag
      abs = scroll_view.absolute_bounds
      local_point = CrymbleUI::Vec2.new(scrollbar_x - abs.x, thumb_y)
      abs_point = CrymbleUI::Vec2.new(scrollbar_x, thumb_y)

      # Mouse down on thumb
      scroll_view.on_mouse_down(abs_point)
      renderer.render_frame(app)

      renderer.reset_counters

      # Drag down
      5.times do |i|
        move_point = CrymbleUI::Vec2.new(scrollbar_x, thumb_y + (i + 1) * 10.0)
        scroll_view.on_mouse_move(move_point)
        renderer.render_frame(app)
      end

      # NO layout calls during drag
      renderer.layout_count.should eq(0)

      scroll_view.on_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + 50.0))
    end

    it "layout_count is 0 during arrow click scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.settle_rendering(app)
      renderer.reset_counters

      # Click down arrow multiple times
      arrow_x = 400.0 - 8.0
      # Down arrow is at bottom of track (track_height - arrow_size/2)
      track_height = 300.0 - 16.0  # viewport - scrollbar_width for horizontal
      down_arrow_y = track_height - 8.0  # Center of down arrow

      5.times do
        scroll_view.on_mouse_down(CrymbleUI::Vec2.new(arrow_x, down_arrow_y))
        scroll_view.on_mouse_up(CrymbleUI::Vec2.new(arrow_x, down_arrow_y))
        renderer.render_frame(app)
      end

      # NO layout calls during arrow clicks
      renderer.layout_count.should eq(0)
    end

    it "layout_count is 0 during track click scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.settle_rendering(app)
      renderer.reset_counters

      # Click in track below thumb (page down)
      track_click_x = 400.0 - 8.0
      track_click_y = 150.0  # Somewhere in the middle of the track

      3.times do
        scroll_view.on_mouse_down(CrymbleUI::Vec2.new(track_click_x, track_click_y))
        scroll_view.on_mouse_up(CrymbleUI::Vec2.new(track_click_x, track_click_y))
        renderer.render_frame(app)
      end

      # NO layout calls during track clicks
      renderer.layout_count.should eq(0)
    end
  end

  describe "O(visible) widget iteration" do
    it "iterates only visible widgets during scroll, not all content widgets" do
      # Create a large grid like the "both" panel: 32x32 = 1024 buttons
      # This tests that we iterate O(visible) not O(total) widgets
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      # Create 32x32 grid = 1024 buttons total
      32.times do |row|
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        32.times do |col|
          hstack.add_child(CrymbleUI::Button.new("#{row},#{col}") { })
        end
        vstack.add_child(hstack)
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Settle initial rendering
      renderer.settle_rendering(app)

      # Reset counters and scroll
      CrymbleUI::LayerRenderer.reset_frame_counters
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app)

      widgets_iterated = CrymbleUI::LayerRenderer.frame_widgets_iterated

      # KEY ASSERTION: Should iterate only visible widgets (~50-100), not all 1024
      # A 400x300 viewport can show maybe 5x5 to 8x8 buttons = 25-64 visible
      # Plus container widgets (VStack, HStacks) = maybe 50-150 widgets max
      # If we iterate all 1024 buttons, this test FAILS
      widgets_iterated.should be <= 200
    end
  end

  describe "memory efficiency" do
    it "widgets outside viewport have nil widget_backend" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # First button should have widget_backend (it's visible)
      first_button = vstack.children.first
      first_button.widget_backend.should_not be_nil

      # Scroll down a lot (first button should scroll out)
      50.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # First button should have widget_backend wiped (it's out of viewport)
      first_button.widget_backend.should be_nil
    end
  end

  describe "O(visible) iteration scaling" do
    it "scroll iterations scale with visible widgets, not total widgets" do
      # This test verifies O(visible) not O(total) widget iteration during scroll
      # Without viewport_cache optimization: 500-button list would iterate ~10x more than 50-button
      # With viewport_cache: both iterate only visible widgets (ratio ~1.0)
      create_scroll_app = ->(n : Int32) {
        app = TestApp.new
        window = CrymbleUI::Window.new("Test", 400, 300)
        scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
        vstack = CrymbleUI::VStack.new(spacing: 5.0)
        n.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
        scroll_view.set_content(vstack)
        window.add_child(scroll_view)
        app.root_widget = window
        {app, scroll_view}
      }

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Test with 50 buttons
      app_50, scroll_view_50 = create_scroll_app.call(50)
      renderer.settle_rendering(app_50)
      CrymbleUI::LayerRenderer.reset_frame_counters
      scroll_view_50.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_50)
      iter_50 = CrymbleUI::LayerRenderer.frame_widgets_iterated

      # Test with 500 buttons (10x more)
      app_500, scroll_view_500 = create_scroll_app.call(500)
      renderer.settle_rendering(app_500)
      CrymbleUI::LayerRenderer.reset_frame_counters
      scroll_view_500.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_500)
      iter_500 = CrymbleUI::LayerRenderer.frame_widgets_iterated

      # O(visible) PERFORMANCE REQUIREMENT:
      # Both apps show ~same number of visible widgets in 400x300 viewport
      # With viewport_cache: iterations should NOT scale with total widget count
      # Without viewport_cache: iter_500 would be ~10x iter_50 (O(total))
      # Allow 3x overhead for visibility margin/cache_extent, but NOT 10x
      iter_500.should be <= iter_50 * 3
    end
  end
end
