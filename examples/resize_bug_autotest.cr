require "../src/crymble"

# Automated test to reproduce ScrollView-in-Panel resize bug
# The bug shows content floating outside panel during resize
#
# This test:
# 1. Creates a panel with ScrollView content
# 2. Captures initial pixel sample
# 3. Simulates resize drag
# 4. Captures pixel sample after resize
# 5. Compares to verify content is within panel
#
# Usage:
#   shards build resize_bug_autotest
#   DISPLAY=:0 timeout 15 ./bin/resize_bug_autotest

module ScreenCapture
  @@renderer : CrymbleUI::SFMLRenderer? = nil

  def self.renderer=(r : CrymbleUI::SFMLRenderer)
    @@renderer = r
  end

  def self.capture_window : SF::Image?
    return nil unless renderer = @@renderer
    return nil unless window = renderer.window
    texture = SF::Texture.new(window.size.x, window.size.y)
    texture.update(window)
    texture.copy_to_image
  end

  def self.sample_pixel(x : Int32, y : Int32) : SF::Color?
    return nil unless image = capture_window
    return nil if x < 0 || y < 0 || x >= image.size.x.to_i || y >= image.size.y.to_i
    image.get_pixel(x, y)
  end
end

class ResizeBugAutotest < CrymbleUI::App
  @test_phase = 0
  @scheduled = false

  PANEL_X = 100.0
  PANEL_Y = 100.0
  PANEL_WIDTH = 300.0
  PANEL_HEIGHT = 250.0
  TITLE_BAR_HEIGHT = 28.0

  def build : CrymbleUI::Widget
    if @test_phase == 0 && !@scheduled && scheduler_ready?
      @scheduled = true
      schedule_next_phase(500)
    end

    window("Resize Bug Test", 800, 600) do
      window_panel(title: "Preview (ScrollView)", x: PANEL_X, y: PANEL_Y,
                   width: PANEL_WIDTH, height: PANEL_HEIGHT,
                   resizable: true, id: "panel") do
        vstack(spacing: 5.0, padding: 10.0) do
          text("Items:")
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll") do
              vstack(spacing: 5.0) do
                10.times do |i|
                  text("Item #{i + 1}")
                end
              end
            end
          end
        end
      end
    end
  end

  private def scheduler_ready? : Bool
    begin
      CrymbleUI::Widget.scheduler
      true
    rescue
      false
    end
  end

  private def schedule_next_phase(delay_ms : Int32)
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms * 1_000_000)) do
      run_test_phase
    end
  end

  private def run_test_phase
    panel = find("panel").as?(CrymbleUI::WindowPanel)
    scroll = find("scroll").as?(CrymbleUI::ScrollView)

    case @test_phase
    when 0
      log("=== INITIAL STATE ===")
      if p = panel
        log("Panel: pos=(#{p.x},#{p.y}) size=(#{p.width},#{p.height})")
      end
      if s = scroll
        log("ScrollView: absolute_bounds=#{s.absolute_bounds}")
        if cl = s.content_layer
          log("ScrollView content_layer bounds=#{cl.bounds}")
        end
      end

      # Sample pixel inside panel content area
      sample_x = (PANEL_X + 50).to_i
      sample_y = (PANEL_Y + TITLE_BAR_HEIGHT + 50).to_i
      if pixel = ScreenCapture.sample_pixel(sample_x, sample_y)
        log("Initial pixel at (#{sample_x},#{sample_y}): RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a})")
      end

      @test_phase = 1
      schedule_next_phase(200)

    when 1
      log("=== START RESIZE ===")
      if p = panel
        resize_x = p.x + p.width - 5.0
        resize_y = p.y + p.height - 5.0
        handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
        log("Mouse down at (#{resize_x},#{resize_y})")
      end
      @test_phase = 2
      schedule_next_phase(100)

    when 2
      log("=== EXPAND RESIZE ===")
      if p = panel
        new_x = p.x + p.width - 5.0 + 100.0  # Expand 100px
        new_y = p.y + p.height - 5.0 + 100.0
        handle_mouse_move(CrymbleUI::Vec2.new(new_x, new_y))
        log("Mouse move to (#{new_x},#{new_y})")
      end
      @test_phase = 3
      schedule_next_phase(300)  # Wait for render

    when 3
      log("=== AFTER RESIZE (DURING DRAG) ===")
      # Re-find after potential rebuild
      panel = find("panel").as?(CrymbleUI::WindowPanel)
      scroll = find("scroll").as?(CrymbleUI::ScrollView)

      if p = panel
        log("Panel: pos=(#{p.x},#{p.y}) size=(#{p.width},#{p.height})")
        log("Panel resizing?: #{p.resizing?}")
        log("Panel @resize_start_bounds: #{p.resize_start_bounds}")
        log("Panel @resize_edge: #{p.resize_edge}")
        log("Panel @resize_start_pos: #{p.resize_start_pos}")
      end
      if s = scroll
        log("ScrollView: absolute_bounds=#{s.absolute_bounds}")
        if cl = s.content_layer
          log("ScrollView content_layer bounds=#{cl.bounds}")
        end
      end

      # KEY TEST: Sample pixels to verify content is INSIDE panel
      # If bug exists, content pixels will be at wrong offset

      # Panel content area (after resize)
      if p = panel
        panel_right = (p.x + p.width).to_i
        panel_bottom = (p.y + p.height).to_i

        # Sample inside panel content area
        inside_x = (p.x + 100).to_i
        inside_y = (p.y + TITLE_BAR_HEIGHT + 100).to_i
        if pixel = ScreenCapture.sample_pixel(inside_x, inside_y)
          is_content = pixel.r < 200 && pixel.g < 200 && pixel.b < 200 && pixel.a > 0
          log("Inside panel (#{inside_x},#{inside_y}): RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a}) content?=#{is_content}")
        end

        # Sample OUTSIDE panel (where content should NOT be)
        # If bug exists, content might be here
        outside_x = panel_right + 50
        outside_y = panel_bottom + 50
        if pixel = ScreenCapture.sample_pixel(outside_x, outside_y)
          is_content = pixel.r < 200 && pixel.g < 200 && pixel.b < 200 && pixel.a > 0
          log("Outside panel (#{outside_x},#{outside_y}): RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a}) content?=#{is_content}")
          if is_content
            log("BUG DETECTED: Content found outside panel!")
          end
        end
      end

      @test_phase = 4
      schedule_next_phase(100)

    when 4
      log("=== END RESIZE ===")
      if p = panel
        handle_mouse_up(CrymbleUI::Vec2.new(p.x + p.width, p.y + p.height))
      end
      @test_phase = 5
      schedule_next_phase(500)

    when 5
      log("=== DONE ===")
      quit
    end
  end

  private def log(msg : String)
    puts msg
    File.open("/tmp/resize_bug_test.log", "a") do |f|
      f.puts msg
    end
  end
end

# Run
app = ResizeBugAutotest.new
app.build_tree
root = app.root
raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)

window_widget = root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(
  width: window_widget.width,
  height: window_widget.height,
  title: window_widget.title
)
ScreenCapture.renderer = renderer
renderer.run(app)
