require "../spec_helper"
require "../../src/testing/test_renderer"

describe "ScrollView viewport_cache integration" do
  describe "viewport_cache layer creation" do
    it "creates a viewport_cache content layer" do
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

      # ScrollView should have created a viewport_cache content layer
      content_layer = scroll_view.content_layer
      content_layer.should_not be_nil
      content_layer.not_nil!.viewport_cache.should be_true
    end

    it "has separate scrollbar layer (non-viewport_cache)" do
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

      # Scrollbar should be on a separate non-viewport_cache layer
      scrollbar_layer = scroll_view.scrollbar_layer
      scrollbar_layer.should_not be_nil
      scrollbar_layer.not_nil!.viewport_cache.should be_false
    end
  end

  describe "scroll without layout" do
    it "does not call mark_needs_layout on wheel scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll down
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app)

      # Layout should NOT have been called (scroll is O(1))
      renderer.layout_count.should eq(0)
    end

    it "updates layer scroll_offset on scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Get initial scroll offset
      initial_offset = scroll_view.scroll_offset.y

      # Scroll down
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))

      # Scroll offset should have changed
      scroll_view.scroll_offset.y.should be > initial_offset

      # Content layer scroll_offset should match
      content_layer = scroll_view.content_layer.not_nil!
      content_layer.scroll_offset.y.should eq(scroll_view.scroll_offset.y)
    end
  end

  describe "visibility tracking" do
    it "only renders widgets that are in viewport" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render - only visible buttons should render
      renderer.settle_rendering(app)

      # Get visible widget count from layer
      content_layer = scroll_view.content_layer.not_nil!
      visible_count = scroll_view.visible_widget_count

      # With 100 buttons, not all should be visible in 300px height viewport
      visible_count.should be < 100
      visible_count.should be > 0
    end

    it "renders newly visible widgets on scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      100.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll down significantly
      10.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Should have rendered only the newly visible widgets (not all 100)
      # Primitive count should be low (only new widgets + scrollbar)
      renderer.primitive_count.should be < 50  # Much less than full re-render
    end

    it "wipes textures for widgets that scroll out of viewport" do
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

      # Get first button
      first_button = vstack.children.first

      # First button should have widget_backend initially (it's visible)
      first_button.widget_backend.should_not be_nil

      # Scroll down a lot (first button should scroll out)
      50.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # First button should have widget_backend wiped (it's out of viewport)
      first_button.widget_backend.should be_nil
    end

    # REMOVED: Superficial test "re-renders widgets that scroll back INTO viewport"
    # Only checked widget_backend != nil, not visual correctness
    # Replaced with pixel-based tests below
  end

  describe "scrollbar rendering" do
    it "scrollbar updates position on scroll without full re-render" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll down
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app)

      # Only scrollbar should have re-rendered (thumb position changed)
      # Content widgets should not have re-rendered
      renderer.layout_count.should eq(0)
    end

    # REMOVED: Superficial test "scrollbar layer is included in collected layers"
    # Only checked layer collection, not visual rendering
    # Replaced with pixel-based tests below
  end

  # REMOVED: Superficial test section "hit testing with scroll offset"
  # Only checked hit_test return value, not visual correctness
  # Hit testing accuracy does not prove rendering is correct

  describe "performance comparison" do
    it "scroll performance is O(1) not O(n widgets)" do
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
      layout_50 = renderer.layout_count

      # Test with 200 buttons (4x more)
      app_200 = TestApp.new
      window_200 = CrymbleUI::Window.new("Test", 400, 300)
      scroll_view_200 = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack_200 = CrymbleUI::VStack.new(spacing: 5.0)
      200.times { vstack_200.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view_200.set_content(vstack_200)
      window_200.add_child(scroll_view_200)
      app_200.root_widget = window_200

      renderer.settle_rendering(app_200)
      renderer.reset_counters
      scroll_view_200.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_200)
      prims_200 = renderer.primitive_count
      layout_200 = renderer.layout_count

      # O(1) performance: primitive count should be similar (not 4x)
      # Allow 50% variance, but definitely not 4x
      prims_200.should be <= prims_50 * 2

      # Layout should be 0 for both
      layout_50.should eq(0)
      layout_200.should eq(0)
    end
  end

  # === PROPER VISUAL CORRECTNESS TESTS ===
  # These tests verify actual rendered pixels, not just internal state

  describe "visual correctness - scrolled content" do
    it "after scroll, viewport shows NEWLY visible content, not old wrapped pixels" do
      # BUG: Viewport cache rendering shows wrapped garbage instead of newly rendered content.
      # Widgets are rendered to their layout position (y=0,100,200...) but viewport_cache needs
      # them to appear at WRAPPED texture positions (y % texture_height).
      #
      # This test uses DIFFERENT COLORED buttons so we can distinguish which button's
      # content is displayed after scrolling:
      # - First 10 buttons: RED (255, 0, 0)
      # - Buttons 10-19: GREEN (0, 255, 0)
      # After scrolling 300px, we should see GREEN buttons, not RED!
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
      # Rest are blue (default)
      30.times { |i| vstack.add_child(CrymbleUI::Button.new("B#{i}") { }) }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Sample point near top of content area
      # Note: Button starts at x=8 (CONTENT_PADDING) and is ~40px wide
      sample_x = 12  # button BG left of the centered label — robust to text-ink snapping (re-baselined: headless draw_text now snaps like SFML)
      sample_y = 20  # Within first button (starts at y=8)

      # Verify initial render shows RED (first buttons are red)
      initial_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      initial_is_red = initial_pixel && initial_pixel.r == red.r &&
                       initial_pixel.g == red.g && initial_pixel.b == red.b
      initial_is_red.should be_true

      # Scroll down 400px (20 scrolls * 20px) - past all red buttons (which end at y=389)
      # Button 10 (first green, at y=390) should now be at the top of the viewport
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # After scrolling, we should see GREEN buttons at the top, NOT RED!
      # If viewport_cache is broken, we'd still see RED (wrapped old pixels)
      after_pixel = renderer.backend.get_pixel(sample_x, sample_y)
      after_is_green = after_pixel && after_pixel.r == green.r &&
                       after_pixel.g == green.g && after_pixel.b == green.b

      # This assertion will FAIL if viewport_cache rendering is broken:
      # - Broken: still shows RED (old wrapped pixels from texture y=0)
      # - Working: shows GREEN (newly visible button 12)
      after_is_green.should be_true
    end

    it "newly entering widgets are rendered to correct screen position" do
      # Verify that when a widget scrolls INTO the viewport, it appears at
      # a reasonable SCREEN position (within expected range).
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Create buttons with alternating colors so we can identify them
      50.times { |i|
        btn = CrymbleUI::Button.new("Btn#{i}") { }
        # Every 5th button is MAGENTA, others are default blue
        if i % 5 == 0
          btn.background_color = CrymbleUI::Color.new(255, 0, 255, 255)  # Magenta
        end
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      magenta = CrymbleUI::Color.new(255, 0, 255, 255)
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)

      # Initially, button 10 (first off-screen magenta) is not visible
      # Scroll down to bring button 10 into view
      20.times do  # 20 * 20px = 400px scroll
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Button 10 (magenta, y=390) should now be visible near the top
      # With scroll 400, button 10 should be at viewport y = 390 - 400 = -10 (partially visible)
      # Button 15 (magenta, y=585) should be at viewport y = 585 - 400 = 185

      # Search for magenta in the visible area - it should exist somewhere
      magenta_found = false
      magenta_y = -1
      (8...290).each do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        if pixel && pixel.r == magenta.r && pixel.g == magenta.g && pixel.b == magenta.b
          magenta_found = true
          magenta_y = y
          break
        end
      end

      # Magenta should be found somewhere in the visible area
      magenta_found.should be_true
    end
  end

  describe "visual correctness - scrollbar thumb position" do
    it "scrollbar is rendered to window buffer" do
      # BUG: ScrollView creates scrollbar_layer but never adds itself to
      # scrollbar_layer.widgets, so no primitives are rendered to that layer.
      # This test verifies the scrollbar is actually visible in rendered output.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # ScrollView starts at x=8 (CONTENT_PADDING), width=384
      # Scrollbar is at x = 8 + 384 - 16 = 376 to 392
      # Track color is (220, 220, 220) light gray, thumb is (150, 150, 150) darker gray
      scrollbar_center_x = 385  # Center of scrollbar track (8 + 384 - 8)
      thumb_color = CrymbleUI::Color.new(150, 150, 150, 255)
      track_color = CrymbleUI::Color.new(220, 220, 220, 255)

      # Verify scrollbar is rendered by checking for either track OR thumb color
      # (thumb overlaps track, so we might see either)
      scrollbar_found = (0...renderer.backend.height).any? do |y|
        pixel = renderer.backend.get_pixel(scrollbar_center_x, y)
        next false unless pixel
        is_track = pixel.r == track_color.r && pixel.g == track_color.g && pixel.b == track_color.b
        is_thumb = pixel.r == thumb_color.r && pixel.g == thumb_color.g && pixel.b == thumb_color.b
        is_track || is_thumb
      end
      scrollbar_found.should be_true
    end

    it "scrollbar thumb moves after scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # ScrollView at x=8, width=384, so scrollbar center at x = 8 + 384 - 8 = 384
      scrollbar_x = 385  # Center of scrollbar track
      thumb_color = CrymbleUI::Color.new(150, 150, 150, 255)

      # Find initial thumb position by scanning for thumb color
      initial_thumb_top = find_thumb_top(renderer.backend, scrollbar_x, thumb_color)
      initial_thumb_top.should_not be_nil

      # Scroll down significantly
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Find new thumb position
      after_scroll_thumb_top = find_thumb_top(renderer.backend, scrollbar_x, thumb_color)
      after_scroll_thumb_top.should_not be_nil

      # Thumb should have moved DOWN (larger y value)
      after_scroll_thumb_top.not_nil!.should be > initial_thumb_top.not_nil!
    end
  end

  describe "visual correctness - horizontal wheel scroll" do
    it "horizontal wheel delta only changes scroll_offset.x on horizontal scrollview" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create HORIZONTAL scroll view
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      50.times { hstack.add_child(CrymbleUI::Button.new("Btn") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x
      initial_y = scroll_view.scroll_offset.y

      # Send HORIZONTAL wheel delta (like touchpad horizontal swipe)
      # delta.x = -1.0 means scroll right (content moves left)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), CrymbleUI::Vec2.new(200.0, 150.0))

      # X offset should have changed (scrolled right)
      scroll_view.scroll_offset.x.should be > initial_x

      # Y offset should NOT have changed
      scroll_view.scroll_offset.y.should eq(initial_y)
    end

    it "vertical wheel delta does NOT scroll horizontal-only scrollview (strict axis matching)" do
      # Strict behavior: each axis only responds to matching wheel delta
      # Use shift+vertical or horizontal wheel to scroll horizontal scrollviews
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create HORIZONTAL scroll view
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      50.times { hstack.add_child(CrymbleUI::Button.new("Btn") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x
      initial_y = scroll_view.scroll_offset.y

      # Send VERTICAL wheel delta to a HORIZONTAL scrollview
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))

      # X offset should NOT change - strict axis matching
      scroll_view.scroll_offset.x.should eq(initial_x)

      # Y offset should NOT change
      scroll_view.scroll_offset.y.should eq(initial_y)
    end

    it "horizontal wheel delta only changes x on Both direction scrollview" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create BOTH direction scroll view
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
      # Create a large grid that can scroll both ways
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        20.times { hstack.add_child(CrymbleUI::Button.new("Btn") { }) }
        vstack.add_child(hstack)
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x
      initial_y = scroll_view.scroll_offset.y

      # Send HORIZONTAL wheel delta only (like touchpad horizontal swipe)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), CrymbleUI::Vec2.new(200.0, 150.0))

      # X offset should have changed (scrolled right)
      scroll_view.scroll_offset.x.should be > initial_x

      # Y offset should NOT have changed - horizontal wheel should only scroll horizontally
      scroll_view.scroll_offset.y.should eq(initial_y)
    end
  end

  # === CRITICAL VISUAL CORRECTNESS TESTS ===
  # These tests catch bugs that superficial tests miss:
  # - Bug (d): Wrong render order - button 31 appearing between 15 and 17
  # - Bug (a): Garbling - old pixels mixed with new, overlapping content
  # - Bug (e): Spacing loss - buttons touching with no gap after scroll

  describe "visual correctness - sequential order (bug d)" do
    it "buttons appear in sequential order after scroll - no skipped indices" do
      # BUG (d): Screenshot shows V-Button 31 appearing between buttons 15 and 17
      # This happens when viewport_cache wrapping incorrectly maps widget positions
      #
      # Test: Create 50 buttons with UNIQUE colors (index-based RGB)
      # After scroll, sample multiple Y positions and verify colors appear
      # in SEQUENTIAL order (no out-of-bounds content, no skips)
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Create 50 buttons with UNIQUE colors based on index
      # Use R channel as index identifier (0-49)
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        # Unique color: R=50+i*4, G=100, B=100 (distinct, non-overlapping)
        btn.background_color = CrymbleUI::Color.new((50 + i * 4).to_u8, 100_u8, 100_u8, 255_u8)
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Scroll down to show buttons around index 15-25
      # Each button is ~25px tall (20px + 5px spacing)
      # Scroll 375px = 15 buttons worth
      19.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Now verify buttons appear in SEQUENTIAL ORDER
      # Sample X position (within button content area)
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)

      # Collect button indices visible at different Y positions
      # by reading pixel colors and extracting index from R channel
      visible_indices = [] of Int32
      current_y = 10  # Start below title bar

      while current_y < 290  # Stay within viewport
        pixel = renderer.backend.get_pixel(sample_x, current_y)
        if pixel && pixel.g == 100_u8 && pixel.b == 100_u8
          # This is one of our index-coded buttons
          index = (pixel.r.to_i - 50) // 4
          if index >= 0 && index < 50
            # Only record if different from last (we're scanning through button height)
            if visible_indices.empty? || visible_indices.last != index
              visible_indices << index
            end
          end
        end
        current_y += 5  # Sample every 5 pixels
      end

      # Verify sequential order - each index should be exactly 1 more than previous
      # BUG: If we see [15, 31, 17, 18] this test fails (31 is out of order)
      visible_indices.size.should be >= 2  # Should see at least 2 buttons

      (1...visible_indices.size).each do |i|
        diff = visible_indices[i] - visible_indices[i - 1]
        # Sequential buttons should have diff of exactly 1
        # Allow diff of 0 (same button) but NOT large jumps (bug d)
        diff.should be <= 1
        diff.should be >= 0
      end
    end

    it "no content from beyond scroll range appears in viewport" do
      # BUG (d): Button 31 should NOT appear when viewport shows buttons 15-25
      # This test specifically checks that out-of-range content doesn't bleed through
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Create buttons where certain indices have VERY DISTINCT colors
      # Buttons 30-39 are CYAN (easily detectable)
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        if i >= 30 && i < 40
          btn.background_color = CrymbleUI::Color.new(0_u8, 255_u8, 255_u8, 255_u8)  # CYAN
        else
          btn.background_color = CrymbleUI::Color.new(100_u8, 100_u8, 100_u8, 255_u8)  # Gray
        end
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Scroll to show buttons 15-25 approximately
      # 375px scroll = ~15 buttons
      19.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Verify NO CYAN pixels in viewport (buttons 30-39 should not be visible)
      # Scan entire content area for cyan
      cyan = CrymbleUI::Color.new(0_u8, 255_u8, 255_u8, 255_u8)
      cyan_found = false

      (10..50).each do |x|  # Button content area
        (10..290).each do |y|  # Viewport area
          pixel = renderer.backend.get_pixel(x, y)
          if pixel && pixel.r == cyan.r && pixel.g == cyan.g && pixel.b == cyan.b
            cyan_found = true
            break
          end
        end
        break if cyan_found
      end

      # SHOULD NOT find cyan - buttons 30-39 are not in scroll range 15-25
      cyan_found.should be_false
    end
  end

  describe "visual correctness - no garbling (bug a)" do
    it "each pixel row shows content from exactly ONE button" do
      # BUG (a): Screenshot shows garbled pixels - multiple buttons' content
      # overlapping/mixing on the same row
      #
      # Test: Create alternating RED/BLUE buttons
      # Sample a horizontal line - should see ONLY one color (+ spacing/background)
      # NOT a mix of both button colors on the same row
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      red = CrymbleUI::Color.new(255_u8, 0_u8, 0_u8, 255_u8)
      blue = CrymbleUI::Color.new(0_u8, 0_u8, 255_u8, 255_u8)

      # Alternating RED/BLUE buttons
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = (i % 2 == 0) ? red : blue
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Scroll down
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Sample multiple rows in the content area
      # Each row should have ONLY red OR ONLY blue (never both)
      garbling_detected = false

      (20..280).step(10) do |y|
        has_red = false
        has_blue = false

        (15..60).each do |x|  # Horizontal scan across button width
          pixel = renderer.backend.get_pixel(x, y)
          next unless pixel

          # Check if this pixel is red (button color)
          if pixel.r > 200 && pixel.g < 50 && pixel.b < 50
            has_red = true
          end
          # Check if this pixel is blue (button color)
          if pixel.b > 200 && pixel.r < 50 && pixel.g < 50
            has_blue = true
          end
        end

        # GARBLING: same row has BOTH red AND blue pixels
        # This means two buttons' content is overlapping
        if has_red && has_blue
          garbling_detected = true
          break
        end
      end

      garbling_detected.should be_false
    end

    it "after full wrap-around scroll, old content is completely replaced" do
      # BUG (a): Old pixels remain visible after scroll
      # When content wraps around in viewport_cache buffer, old content should be
      # overwritten, not mixed with new content
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      yellow = CrymbleUI::Color.new(255_u8, 255_u8, 0_u8, 255_u8)
      purple = CrymbleUI::Color.new(128_u8, 0_u8, 128_u8, 255_u8)

      # First 10 buttons YELLOW, rest PURPLE
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = (i < 10) ? yellow : purple
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Verify yellow is visible initially
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)
      initial_has_yellow = (10..280).any? do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        pixel && pixel.r > 200 && pixel.g > 200 && pixel.b < 50
      end
      initial_has_yellow.should be_true

      # Scroll far enough that yellow buttons are completely out of view
      # and content has wrapped around in the viewport_cache buffer
      30.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # After scrolling 600px, yellow buttons (0-9) should be completely gone
      # Check that NO yellow pixels remain (old content replaced)
      yellow_found = (10..280).any? do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        pixel && pixel.r > 200 && pixel.g > 200 && pixel.b < 50
      end

      # SHOULD NOT find yellow - it should be completely scrolled out and replaced
      yellow_found.should be_false
    end
  end

  describe "visual correctness - spacing preserved (bug e)" do
    it "maintains VStack spacing between buttons after scroll" do
      # BUG (e): Screenshot shows buttons touching with no gap
      # VStack has spacing: 5.0, but after scroll the gap disappears
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)  # 5px spacing!

      # All buttons same color so we can detect spacing (background color)
      button_color = CrymbleUI::Color.new(100_u8, 150_u8, 200_u8, 255_u8)
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = button_color
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Scroll down
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Scan vertically to find button-to-gap-to-button transitions
      sample_x = 12  # button BG, off the label ink (see first re-baseline note)
      gap_found = false
      in_button = false
      gap_size = 0

      (10..280).each do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        next unless pixel

        is_button = (pixel.r == button_color.r && pixel.g == button_color.g && pixel.b == button_color.b)

        if in_button && !is_button
          # Transitioned from button to gap
          gap_size = 1
        elsif !in_button && is_button && gap_size > 0
          # Found gap between buttons
          gap_found = true
          # Gap should be approximately 5px (VStack spacing)
          gap_size.should be >= 3  # Allow some tolerance
          gap_size.should be <= 7  # But not too big
          break
        elsif !in_button && !is_button && gap_size > 0
          # Still in gap, counting size
          gap_size += 1
        end

        in_button = is_button
      end

      # MUST find at least one gap (spacing preserved)
      gap_found.should be_true
    end

    it "horizontal scroll preserves HStack spacing" do
      # Bug (e) variant for horizontal scrolling
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)  # 5px spacing!

      button_color = CrymbleUI::Color.new(200_u8, 100_u8, 150_u8, 255_u8)
      50.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = button_color
        hstack.add_child(btn)
      }

      scroll_view.set_content(hstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Scroll right
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), CrymbleUI::Vec2.new(200.0, 150.0))
      end
      renderer.render_frame(app)

      # Scan horizontally to find button-to-gap-to-button transitions
      # For HStack, buttons are at the TOP of the content area, not middle
      sample_y = 25  # Near top of content area (after window chrome + padding)
      gap_found = false
      in_button = false
      gap_size = 0

      (10..380).each do |x|
        pixel = renderer.backend.get_pixel(x, sample_y)
        next unless pixel

        is_button = (pixel.r == button_color.r && pixel.g == button_color.g && pixel.b == button_color.b)

        if in_button && !is_button
          gap_size = 1
        elsif !in_button && is_button && gap_size > 0
          gap_found = true
          gap_size.should be >= 3
          gap_size.should be <= 7
          break
        elsif !in_button && !is_button && gap_size > 0
          gap_size += 1
        end

        in_button = is_button
      end

      gap_found.should be_true
    end
  end

  describe "scroll round-trip visual correctness" do
    it "spacing between buttons is clean after scroll down and back up" do
      # BUG: After scrolling down and back up, artifacts appear in the spacing
      # between buttons (diagonal lines/hatching pattern).
      # Uses 32x32 grid like the "both" panel in scroll_view_demo.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 400)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)  # 5px spacing like demo

      # Create 32x32 grid = 1024 buttons (same as "both" panel)
      32.times do |row|
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        32.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}") { }
          hstack.add_child(btn)
        end
        vstack.add_child(hstack)
      end

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Collect spacing pixels at multiple locations
      # Sample points in the spacing BETWEEN rows (in the 5px gaps)
      spacing_points = [
        {x: 50, y: 40},   # Between row 0 and 1
        {x: 100, y: 80},  # Between row 1 and 2
        {x: 150, y: 120}, # Between row 2 and 3
        {x: 200, y: 160}, # Between row 3 and 4
      ]

      # Record initial colors at spacing points
      initial_colors = spacing_points.map do |pt|
        renderer.backend.get_pixel(pt[:x], pt[:y])
      end

      # Scroll down significantly (like user scrolling through content)
      50.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 200.0))
      end
      renderer.render_frame(app)

      # Scroll back up to original position
      50.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 200.0))
      end
      renderer.render_frame(app)

      # After round-trip, check all spacing points
      all_clean = true
      spacing_points.each_with_index do |pt, i|
        after_pixel = renderer.backend.get_pixel(pt[:x], pt[:y])
        initial = initial_colors[i]

        next unless initial && after_pixel

        # Colors should match (no artifacts)
        unless after_pixel.r == initial.r &&
               after_pixel.g == initial.g &&
               after_pixel.b == initial.b
          all_clean = false
          # Debug output for failure
        end
      end

      all_clean.should be_true
    end
  end

  describe "pure container cache bug" do
    it "pure containers (VStack/HStack) do not have widget_backend" do
      # Pure containers with no visual primitives should never create widget_backend.
      # Creating and blitting uninitialized textures would cause artifacts.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      # Create grid: VStack contains HStacks which contain Buttons
      # VStack and HStacks are pure containers (no primitives)
      8.times do |row|
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        8.times do |col|
          hstack.add_child(CrymbleUI::Button.new("#{row},#{col}") { })
        end
        vstack.add_child(hstack)
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.settle_rendering(app)

      # Scroll down and back up (triggers cache path for returning widgets)
      10.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end
      10.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 3.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # KEY ASSERTION: Pure containers should NOT have widget_backend
      # If they do, we're wasting memory and risking artifact bugs
      vstack.widget_backend.should be_nil

      # Check HStacks too
      hstacks_with_backend = vstack.children.count { |c| c.widget_backend != nil }
      hstacks_with_backend.should eq(0)
    end
  end

  describe "visual correctness - no missing rows" do
    it "all rows in viewport range are visible (no gaps)", tags: "slow" do
      # BUG: Screenshot shows rows 14-15 missing between rows 4-13 and 16-17
      # This test creates unique-colored rows and verifies NO gaps exist
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 400)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Create 32 rows with unique colors (row index encoded in R channel)
      32.times do |row|
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        8.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}") { }
          # Encode row index in R channel: R = 50 + row*6 (50-242 range)
          btn.background_color = CrymbleUI::Color.new((50 + row * 6).to_u8, 100_u8, 150_u8, 255_u8)
          hstack.add_child(btn)
        end
        vstack.add_child(hstack)
      end

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)

      # Simulate slow scrollbar drag using on_mouse_move while dragging vertical scrollbar thumb
      # The bug appeared during scrollbar drag - let's replicate that interaction
      scrollbar_x = 385.0  # X position of vertical scrollbar track
      thumb_start_y = 50.0  # Approximate thumb starting position

      # Start drag on scrollbar thumb
      scroll_view.on_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, thumb_start_y))
      renderer.render_frame(app)

      # Drag thumb down slowly (1px at a time) - this triggers incremental scroll
      # Each mouse move updates scroll_offset based on thumb position
      all_visible_during_scroll = [] of Array(Int32)

      (1..100).each do |i|
        scroll_view.on_mouse_move(CrymbleUI::Vec2.new(scrollbar_x, thumb_start_y + i.to_f64))
        renderer.render_frame(app)

        # Sample visible rows at each step to catch transient gaps
        step_visible = Set(Int32).new
        (10..380).step(5) do |y|
          pixel = renderer.backend.get_pixel(50, y)
          next unless pixel
          if pixel.g == 100_u8 && pixel.b == 150_u8
            row_index = (pixel.r.to_i - 50) // 6
            step_visible << row_index if row_index >= 0 && row_index < 32
          end
        end
        all_visible_during_scroll << step_visible.to_a.sort
      end

      # End drag
      scroll_view.on_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, thumb_start_y + 100.0))
      renderer.render_frame(app)

      # Scan vertically and extract visible row indices from pixel colors
      sample_x = 50  # Within button content area
      visible_rows = Set(Int32).new

      (10..380).step(5) do |y|
        pixel = renderer.backend.get_pixel(sample_x, y)
        next unless pixel
        # Check if this is a button pixel (G=100, B=150)
        if pixel.g == 100_u8 && pixel.b == 150_u8
          row_index = (pixel.r.to_i - 50) // 6
          visible_rows << row_index if row_index >= 0 && row_index < 32
        end
      end

      # KEY ASSERTION: Visible rows must be CONTIGUOUS (no gaps) at EVERY step during scroll
      # Check each step captured during scrollbar drag for gaps
      gaps_found = [] of String
      all_visible_during_scroll.each_with_index do |sorted_rows, step|
        next if sorted_rows.size < 2  # Need at least 2 rows to check gaps

        (1...sorted_rows.size).each do |i|
          gap = sorted_rows[i] - sorted_rows[i - 1]
          if gap > 1
            gaps_found << "Step #{step}: Gap between row #{sorted_rows[i - 1]} and #{sorted_rows[i]} (#{gap - 1} rows missing), visible=#{sorted_rows.inspect}"
          end
        end
      end

      # Also check final state
      sorted_rows = visible_rows.to_a.sort

      # Report ALL gaps found during scroll
      if gaps_found.size > 0
        gaps_found.first(10).each { |msg| puts "  #{msg}" }
        fail "MISSING ROWS: #{gaps_found.size} gap(s) detected during scroll. First: #{gaps_found.first}"
      end

      sorted_rows.size.should be >= 5  # At least 5 rows visible at end
    end

    it "renders widgets at buffer positions beyond viewport size" do
      # BUG: layer_clip_rect was set to viewport size, but viewport_cache buffers
      # are larger than viewport. Widgets at buf_y > viewport_height were clipped.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 368)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 368)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      # Create rows with unique colors (R channel encodes row index)
      20.times do |row|
        btn = CrymbleUI::Button.new("Row #{row}") { }
        btn.background_color = CrymbleUI::Color.new((100 + row * 7).to_u8, 50_u8, 50_u8, 255_u8)
        vstack.add_child(btn)
      end

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Get the content layer's backend
      content_layer = scroll_view.content_layer.not_nil!
      backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

      # Verify buffer is larger than viewport (viewport_cache characteristic)
      backend.height.should be > 368

      # Scroll until we have widgets at buffer positions > viewport height
      # Each wheel scroll moves ~30-40px, need to scroll enough that row ~10-12
      # wraps to the bottom of the buffer (buf_y > 368)
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 200.0))
        renderer.render_frame(app)
      end

      # Sample the buffer at positions beyond viewport height
      # If the bug exists, these will be zeros (transparent/unwritten)
      found_content_beyond_viewport = false
      (370..backend.height - 10).each do |y|
        # Sample at x=100 (well inside button area)
        pixel = backend.get_pixel(100, y)
        if pixel && pixel.a > 0 && (pixel.r > 100 || pixel.g > 50 || pixel.b > 50)
          found_content_beyond_viewport = true
          break
        end
      end

      found_content_beyond_viewport.should be_true
    end
  end
end

# Helper function to find the topmost pixel of the scrollbar thumb
private def find_thumb_top(backend : CrymbleUI::Testing::TestRenderBackend, x : Int32, thumb_color : CrymbleUI::Color) : Int32?
  (0...backend.height).each do |y|
    pixel = backend.get_pixel(x, y)
    if pixel && pixel.r == thumb_color.r && pixel.g == thumb_color.g && pixel.b == thumb_color.b
      return y
    end
  end
  nil
end
