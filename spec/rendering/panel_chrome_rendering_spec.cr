require "../spec_helper"
require "../../src/testing/test_renderer"

# Test that WindowPanel chrome (title bar, borders) renders correctly
# User report: "when I run stress_panel_demo, I don't see the chrome"
#
# Tests use TWO approaches:
# 1. PRIMITIVE COUNTING - for performance testing
# 2. PIXEL CHECKING - for visual correctness
describe "WindowPanel Chrome Rendering" do
  # === VISUAL CORRECTNESS TESTS (pixel-based) ===

  describe "visual correctness (pixel-based)" do
    it "title bar is visible (non-white pixels)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("My Panel", 50.0, 50.0, 200.0, 150.0)

      window.add_child(panel)
      app.root_widget = window
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      renderer.render_frame(app)

      backend = renderer.backend

      # Sample multiple pixels in title bar area
      # Title bar is at (50, 50) with height ~30px
      title_samples = [
        {x: 150, y: 65},  # Center
        {x: 100, y: 65},  # Left side
        {x: 200, y: 65},  # Right side
      ]

      visible_pixels = 0
      title_samples.each do |sample|
        pixel = backend.get_pixel(sample[:x], sample[:y])
        next unless pixel

        # Check pixel is not white (255,255,255) and not transparent
        is_white = (pixel.r == 255 && pixel.g == 255 && pixel.b == 255)
        is_transparent = (pixel.a == 0)

        unless is_white || is_transparent
          visible_pixels += 1
        end
      end

      # At least 2 of 3 samples should show visible title bar
      visible_pixels.should be >= 2
    end

    it "panel background is visible" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)

      window.add_child(panel)
      app.root_widget = window
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      renderer.render_frame(app)

      backend = renderer.backend

      # Sample pixel in panel body (below title bar)
      body_x = 150  # Center
      body_y = 125  # Middle of body (50 + 30 title + 45)

      pixel = backend.get_pixel(body_x, body_y)
      pixel.should_not be_nil

      if pix = pixel
        is_white = (pix.r == 255 && pix.g == 255 && pix.b == 255)
        is_transparent = (pix.a == 0)

        # Panel body should have background color (not white/transparent)
        (is_white || is_transparent).should be_false

      end
    end

    it "panel border is visible" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)

      window.add_child(panel)
      app.root_widget = window
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      renderer.render_frame(app)

      backend = renderer.backend

      # Sample pixels on border edges
      border_samples = [
        {x: 50, y: 50},    # Top-left corner
        {x: 249, y: 50},   # Top-right corner
        {x: 50, y: 199},   # Bottom-left corner
        {x: 249, y: 199},  # Bottom-right corner
      ]

      visible_borders = 0
      border_samples.each do |sample|
        pixel = backend.get_pixel(sample[:x], sample[:y])
        next unless pixel

        # Border should be visible (non-white, non-transparent)
        is_white = (pixel.r == 255 && pixel.g == 255 && pixel.b == 255)
        is_transparent = (pixel.a == 0)

        unless is_white || is_transparent
          visible_borders += 1
        end
      end

      # At least 3 of 4 corners should show border
      visible_borders.should be >= 3
    end

    it "button inside panel is visible" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)
      app.root_widget = window

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      renderer.render_frame(app)

      backend = renderer.backend

      # The button's default fill (#0078D7) must be painted somewhere inside its bounds. Scan the
      # interior rather than probing one point: a non-fill body takes its INTRINSIC width inside the
      # panel (it needn't span the whole content area), so the centered white label sits near the
      # left edge — a single upper-left probe would land on the glyph, not the fill.
      abs_bounds = button.absolute_bounds
      found_fill = false
      x0 = abs_bounds.x.to_i
      y0 = abs_bounds.y.to_i
      (2...(abs_bounds.width.to_i - 2)).step(2) do |dx|
        (2...(abs_bounds.height.to_i - 2)).step(2) do |dy|
          if px = backend.get_pixel(x0 + dx, y0 + dy)
            found_fill = true if px.r == 0 && px.g == 120 && px.b == 215
          end
        end
      end
      found_fill.should be_true
    end
  end

  # === PERFORMANCE TESTS (primitive counting) ===

  describe "performance (primitive counting)" do
    it "panel chrome uses reasonable number of primitives" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("My Panel", 50.0, 50.0, 200.0, 150.0)

      window.add_child(panel)
      app.root_widget = window
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

      renderer.reset_counters
      renderer.render_frame(app)

      # Panel chrome primitives:
      # - Background fill rect (body)
      # - Border rect
      # - Title bar fill rect
      # - Title bar border line
      # - Title text
      # Expected: 5-10 primitives

      count = renderer.primitive_count
      count.should be >= 5
      count.should be <= 15  # Not too many (over-rendering)

    end

    it "panel with button uses reasonable primitives" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)
      app.root_widget = window

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

      renderer.reset_counters
      renderer.render_frame(app)

      # Panel chrome: ~5 + Button: ~3 = ~8-15 primitives
      count = renderer.primitive_count
      count.should be >= 5
      count.should be <= 20

    end

    it "stress test: 3 panels with buttons (performance check)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)

      3.times do |i|
        panel = CrymbleUI::WindowPanel.new("Panel #{i}", 50.0 + i * 220.0, 50.0, 200.0, 150.0)

        2.times do |j|
          button = CrymbleUI::Button.new("Btn #{j}") { }
          panel.add_child(button)
        end

        window.add_child(panel)
      app.root_widget = window
      end

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

      renderer.reset_counters
      renderer.render_frame(app)

      # 3 panels * (5 chrome + 2*3 button) = ~45 primitives
      count = renderer.primitive_count
      count.should be >= 30
      count.should be <= 80  # Not over-rendering

    end
  end
end
