require "../spec_helper"
require "../../src/testing/test_renderer"

# Test for buffer recenter bug: garbling when scrolling down then up
# Root cause: When viewport_cache buffer recenters, visible widgets' background_backend
# is NOT invalidated, causing stale backgrounds to be restored at wrong positions.
describe "ScrollView buffer recenter" do
  describe "background invalidation on buffer recenter" do
    it "renders correctly during incremental scroll with buffer recenters" do
      # BUG: During incremental scroll, some widgets STAY visible through buffer recenter.
      # Without fix, STAYING widgets restore stale backgrounds → garbling.
      # With fix, invalidate_visible_widget_backgrounds clears backgrounds on recenter.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Use distinct colors to detect garbling
      red = CrymbleUI::Color.new(255, 0, 0, 255)
      green = CrymbleUI::Color.new(0, 255, 0, 255)
      blue = CrymbleUI::Color.new(0, 0, 255, 255)

      # First 10 RED, next 10 GREEN, rest BLUE
      10.times { |i|
        btn = CrymbleUI::Button.new("R#{i}") { }
        btn.background_color = red
        vstack.add_child(btn)
      }
      10.times { |i|
        btn = CrymbleUI::Button.new("G#{i}") { }
        btn.background_color = green
        vstack.add_child(btn)
      }
      30.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = blue
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)
      sample_x = 12  # button BG left of the centered label — robust to text-ink snapping (re-baselined: headless draw_text now snaps like SFML)
      sample_y = 20

      # Verify initial state: RED
      initial_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      (initial_pixel.try(&.r) == red.r).should be_true

      # Scroll DOWN incrementally (one scroll + render at a time)
      # This creates STAYING widgets through buffer recenters
      # ~20px per scroll, 20 scrolls = ~400px (past RED into GREEN region)
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Should see GREEN now (scrolled past RED buttons)
      after_down_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      (after_down_pixel.try(&.g) == green.g).should be_true

      # Scroll BACK UP incrementally
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Should see RED again (not garbled fragments from scroll-down position)
      # BUG: Without fix, STAYING widgets show GREEN/BLUE fragments (stale backgrounds)
      after_up_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      (after_up_pixel.try(&.r) == red.r).should be_true
    end

    it "renders correctly after scroll down and up (no garbling)" do
      # Visual verification: after scroll round-trip, widgets should render
      # with correct backgrounds, not stale content from old buffer positions.
      # This test mirrors the working test in scroll_view_viewport_cache_spec.cr
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      red = CrymbleUI::Color.new(255, 0, 0, 255)
      green = CrymbleUI::Color.new(0, 255, 0, 255)

      # First 10 buttons are RED
      10.times { |i|
        btn = CrymbleUI::Button.new("R#{i}") { }
        btn.background_color = red
        vstack.add_child(btn)
      }
      # Next 10 buttons are GREEN
      10.times { |i|
        btn = CrymbleUI::Button.new("G#{i}") { }
        btn.background_color = green
        vstack.add_child(btn)
      }
      # Rest are default
      30.times { |i| vstack.add_child(CrymbleUI::Button.new("B#{i}") { }) }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Sample point near top of content area (same as working test)
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)
      sample_y = 20

      # Verify initial state shows RED
      initial_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      initial_is_red = initial_pixel && initial_pixel.r == red.r && initial_pixel.g == red.g && initial_pixel.b == red.b
      initial_is_red.should be_true

      # Scroll down 400px (past RED buttons)
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Verify we see GREEN (scrolled past RED)
      mid_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      mid_is_green = mid_pixel && mid_pixel.r == green.r && mid_pixel.g == green.g && mid_pixel.b == green.b
      mid_is_green.should be_true

      # NOW: Scroll back up to original position (triggers second buffer recenter)
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # After scroll reversal, should see RED again (not garbled)
      # BUG: Without fix, stale backgrounds from GREEN position get restored → garbling
      after_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      after_is_red = after_pixel && after_pixel.r == red.r && after_pixel.g == red.g && after_pixel.b == red.b
      after_is_red.should be_true
    end

    it "no garbling artifacts in spacing between buttons after round-trip" do
      # The garbling bug often appears as artifacts in the spacing BETWEEN buttons
      # This test specifically checks spacing pixels remain clean after scroll round-trip
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 8.0)  # Larger spacing to make gaps obvious

      button_color = CrymbleUI::Color.new(100, 150, 200, 255)
      50.times { |i|
        btn = CrymbleUI::Button.new("Btn#{i}") { }
        btn.background_color = button_color
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Find spacing pixels (not button color) before scroll
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)
      spacing_y_positions = [] of Int32

      (10..280).each do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        next unless pixel
        is_button = pixel.r == button_color.r && pixel.g == button_color.g && pixel.b == button_color.b
        spacing_y_positions << y unless is_button
      end

      # Record colors at spacing positions before scroll
      spacing_colors_before = spacing_y_positions.first(10).map do |y|
        renderer.backend.get_pixel(sample_x, y)
      end

      # Scroll down significantly (trigger buffer recenter)
      30.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Scroll back up (trigger another buffer recenter)
      30.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Check spacing pixels after round-trip - should match original (no artifacts)
      artifacts_found = 0
      spacing_colors_before.each_with_index do |before, i|
        next unless before
        y = spacing_y_positions[i]
        after = renderer.backend.get_pixel(sample_x, y)
        next unless after

        # BUG: Garbling causes spacing to have wrong color (button fragments)
        if before.r != after.r || before.g != after.g || before.b != after.b
          artifacts_found += 1
        end
      end

      artifacts_found.should eq(0)
    end
  end
end
