require "../../src/crymble-ui"

# Simplified SFML visual test for buffer recenter garbling bug
# Uses LARGE COLORED BOXES and pixel sampling to detect visual corruption
#
# Test uses pure colored rectangles (no text) for reliable pixel sampling
#
# Usage:
#   shards build buffer_recenter_autotest
#   DISPLAY=:0 timeout 15 ./bin/buffer_recenter_autotest
#   cat /tmp/buffer_recenter_results.log

module ScreenCapture
  @@renderer : CrymbleUI::SFMLRenderer? = nil

  def self.renderer=(r : CrymbleUI::SFMLRenderer)
    @@renderer = r
  end

  def self.renderer : CrymbleUI::SFMLRenderer?
    @@renderer
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

  def self.pixel_to_string(pixel : SF::Color) : String
    "RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a})"
  end
end

def run_with_screen_capture(app : CrymbleUI::App)
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
end

# Status indicator circle (same as showcase_demo)
class StatusIndicator < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  property active : Bool
  property size : Float64

  def initialize(@active = false, @size = 12.0)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@size, @size)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    color = @active ? CrymbleUI::Color.new(100, 255, 100, 255) : CrymbleUI::Color.new(255, 100, 100, 255)
    primitives do
      draw_circle(CrymbleUI::Vec2.new(bounds.width / 2, bounds.height / 2), @size / 2, color, fill: true)
    end
  end
end

class BufferRecenterAutoTest < CrymbleUI::App
  @test_phase = 0
  @test_results = [] of String
  @scheduled_first = false

  # Store initial screen capture to compare with final
  @initial_pixels : Array(Tuple(Int32, Int32, SF::Color))? = nil
  @sample_positions : Array(Tuple(Int32, Int32)) = [] of Tuple(Int32, Int32)

  def build : CrymbleUI::Widget
    if @test_phase == 0 && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule_next_phase(500)
    end

    # EXACTLY match showcase_demo structure: WindowPanel → ScrollView → StatusIndicator + Text
    window("Buffer Recenter Test", 400, 400) do
      window_panel(title: "Preview (ScrollView)", x: 10.0, y: 10.0, width: 380.0, height: 380.0,
                   resizable: true, id: "test_panel") do
        vstack(spacing: 10.0, padding: 10.0) do
          text("Scroll test items:", font_scale: -1)
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_sv") do
              vstack(spacing: 5.0) do
                # 30 items - same as showcase with "Add 5" clicked multiple times
                30.times do |i|
                  hstack(spacing: 8.0) do
                    widget StatusIndicator.new(active: i.even?, size: 10.0)
                    text("Item #{i + 1}", font_scale: -1)
                  end
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
    sv = find("test_sv").as?(CrymbleUI::ScrollView)

    case @test_phase
    when 0
      log_separator("PHASE 0: CAPTURE INITIAL STATE")
      if s = sv
        abs = s.absolute_bounds
        log_info("ScrollView absolute_bounds: #{abs}")
        log_info("scroll_offset: #{s.scroll_offset}")

        # Sample multiple positions in scroll view content area
        @sample_positions.clear
        @initial_pixels = [] of Tuple(Int32, Int32, SF::Color)

        # Sample DENSELY in the content area where text items appear
        # Focus on the left portion where StatusIndicator + text render
        x_start = (abs.x + 10).to_i
        x_end = (abs.x + 150).to_i  # Text is on the left
        y_start = (abs.y + 10).to_i
        y_end = (abs.y + abs.height - 30).to_i  # Leave room for scrollbar

        # Sample every 5 pixels for dense coverage
        y = y_start
        while y <= y_end
          x = x_start
          while x <= x_end
            @sample_positions << {x, y}
            if pixel = ScreenCapture.sample_pixel(x, y)
              @initial_pixels.not_nil! << {x, y, pixel}
            end
            x += 5
          end
          y += 5
        end

        log_info("Captured #{@initial_pixels.try(&.size) || 0} pixels")

        @test_results << "CAPTURED: #{@initial_pixels.try(&.size) || 0} initial pixels"
      end
      @test_phase = 1
      schedule_next_phase(200)

    when 1
      log_separator("PHASE 1: SCROLL DOWN")
      if s = sv
        # Scroll down SMALL amount - enough to make Item 1 exit viewport but NOT trigger recenter
        # This tests Bug 2: non-recenter garbling (widget exits/re-enters without buffer clear)
        # 5 wheel events ≈ 75 pixels (each wheel ≈ 15 pixels)
        5.times { s.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0)) }
        log_info("After scroll down: scroll_offset=#{s.scroll_offset}")
      end
      @test_phase = 2
      schedule_next_phase(300)

    when 2
      log_separator("PHASE 2: SCROLL BACK UP")
      if s = sv
        # Scroll back to original position
        5.times { s.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0)) }
        log_info("After scroll up: scroll_offset=#{s.scroll_offset}")
      end
      @test_phase = 3
      schedule_next_phase(300)

    when 3
      log_separator("PHASE 3: COMPARE WITH INITIAL STATE")
      if s = sv
        log_info("scroll_offset: #{s.scroll_offset}")

        mismatches = 0
        total = 0

        if initial = @initial_pixels
          initial.each do |(x, y, initial_pixel)|
            total += 1
            if final_pixel = ScreenCapture.sample_pixel(x, y)
              # Compare pixels - allow small tolerance for rendering differences
              if pixels_different?(initial_pixel, final_pixel)
                mismatches += 1
                log_info("MISMATCH at (#{x},#{y}): #{ScreenCapture.pixel_to_string(initial_pixel)} -> #{ScreenCapture.pixel_to_string(final_pixel)}")
              end
            end
          end
        end

        if mismatches > 0
          @test_results << "GARBLING_DETECTED: #{mismatches}/#{total} pixels changed after scroll round-trip"
        else
          @test_results << "NO_GARBLING: All #{total} pixels match after scroll round-trip"
        end
      end
      @test_phase = 4
      schedule_next_phase(200)

    when 4
      output_results
      @test_phase = 5
      schedule_next_phase(500)

    when 5
      quit
    end
  end

  private def pixels_different?(a : SF::Color, b : SF::Color) : Bool
    # Allow small tolerance for rendering differences (e.g., anti-aliasing)
    tolerance = 5
    (a.r.to_i - b.r.to_i).abs > tolerance ||
    (a.g.to_i - b.g.to_i).abs > tolerance ||
    (a.b.to_i - b.b.to_i).abs > tolerance
  end

  private def log_separator(title : String)
    File.open("/tmp/buffer_recenter_state.log", "a") { |f| f.puts "\n=== #{title} ===" }
  end

  private def log_info(msg : String)
    File.open("/tmp/buffer_recenter_state.log", "a") { |f| f.puts "  #{msg}" }
  end

  private def log_pixel(label : String, x : Int32, y : Int32, pixel : SF::Color)
    File.open("/tmp/buffer_recenter_state.log", "a") do |f|
      f.puts "  #{label} at (#{x},#{y}): #{ScreenCapture.pixel_to_string(pixel)}"
    end
  end

  private def output_results
    has_garbling = @test_results.any? { |r| r.includes?("GARBLING_DETECTED") }

    File.open("/tmp/buffer_recenter_results.log", "w") do |f|
      f.puts "=== Buffer Recenter Visual Test ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      if has_garbling
        f.puts "*** GARBLING DETECTED - TEST FAILED ***"
      else
        f.puts "*** NO GARBLING - TEST PASSED ***"
      end
      f.puts ""
      f.puts "See /tmp/buffer_recenter_state.log for details"
    end

    puts "\n=== Buffer Recenter Visual Test ==="
    @test_results.each { |r| puts r }

    if has_garbling
      puts "\n*** GARBLING DETECTED - TEST FAILED ***"
    else
      puts "\n*** NO GARBLING - TEST PASSED ***"
    end
  end
end

File.write("/tmp/buffer_recenter_state.log", "")
File.write("/tmp/buffer_recenter_results.log", "")

app = BufferRecenterAutoTest.new
run_with_screen_capture(app)
