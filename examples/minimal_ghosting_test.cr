require "../src/crymble"

# Minimal test to check if ghosting is VirtualMatrix-specific or general rendering issue
#
# This test creates simple Text widgets WITHOUT VirtualMatrix to isolate the issue.
# If ghosting appears here, the issue is in the general rendering pipeline.
# If ghosting does NOT appear, the issue is VirtualMatrix-specific.
#
# Run: shards build minimal_ghosting_test && DISPLAY=:0 ./bin/minimal_ghosting_test

module MinimalScreenCapture
  @@renderer : CrymbleUI::SFMLRenderer? = nil

  def self.renderer=(r : CrymbleUI::SFMLRenderer)
    @@renderer = r
  end

  def self.capture_window : SF::Image?
    return nil unless renderer = @@renderer
    return nil unless window = renderer.window
    window.display
    sleep(0.05)
    texture = SF::Texture.new(window.size.x, window.size.y)
    texture.update(window)
    texture.copy_to_image
  end

  def self.sample_region(x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32, step : Int32 = 10) : Array(Tuple(Int32, Int32, SF::Color))
    samples = [] of Tuple(Int32, Int32, SF::Color)
    return samples unless image = capture_window

    (y1...y2).step(step) do |y|
      (x1...x2).step(step) do |x|
        next if x < 0 || y < 0 || x >= image.size.x.to_i || y >= image.size.y.to_i
        pixel = image.get_pixel(x, y)
        samples << {x, y, pixel}
      end
    end
    samples
  end
end

class MinimalGhostingTest < CrymbleUI::App
  VIEWPORT_WIDTH  = 1400
  VIEWPORT_HEIGHT = 800

  @test_phase = 0
  @scheduled = false
  @status : String = "Initializing..."
  @left_ratio : Float64 = 0.0
  @right_ratio : Float64 = 0.0

  # Test mode: how many text widgets to create
  @text_count : Int32

  def initialize(@text_count : Int32 = 100)
    super()
  end

  def build : CrymbleUI::Widget
    if @test_phase == 0 && !@scheduled && scheduler_ready?
      @scheduled = true
      schedule_next_phase(1000)
    end

    window("Minimal Ghosting Test", VIEWPORT_WIDTH, VIEWPORT_HEIGHT) do
      vstack(padding: 10.0, spacing: 10.0) do
        text("Minimal Ghosting Test - NO VirtualMatrix", font_scale: 2)
        text("Testing #{@text_count} text widgets per panel")

        expanded do
          hstack(spacing: 15.0) do
            # Left panel: simple vstack of text widgets
            expanded do
              vstack(spacing: 5.0) do
                text("Left Panel (scrollable)", font_scale: 1)
                expanded do
                  scroll_view(direction: CrymbleUI::ScrollDirection::Both, id: "left_scroll") do
                    vstack(spacing: 2.0, padding: 5.0) do
                      @text_count.times do |i|
                        text("Left Text #{i}: Alpha Beta Gamma")
                      end
                    end
                  end
                end
              end
            end

            # Right panel: identical
            expanded do
              vstack(spacing: 5.0) do
                text("Right Panel (scrollable)", font_scale: 1)
                expanded do
                  scroll_view(direction: CrymbleUI::ScrollDirection::Both, id: "right_scroll") do
                    vstack(spacing: 2.0, padding: 5.0) do
                      @text_count.times do |i|
                        text("Right Text #{i}: Alpha Beta Gamma")
                      end
                    end
                  end
                end
              end
            end
          end
        end

        vstack(spacing: 5.0) do
          text(@status)
          text("Left ratio: #{@left_ratio.round(2)} | Right ratio: #{@right_ratio.round(2)}")
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
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000_i64)) do
      run_test_phase
    end
  end

  private def run_test_phase
    case @test_phase
    when 0
      @status = "Waiting for render..."
      @test_phase = 1
      rebuild
      schedule_next_phase(1500)
    when 1
      @status = "Sampling panels..."
      rebuild

      # Sample left panel (x: 20-650)
      left_samples = MinimalScreenCapture.sample_region(20, 130, 650, 750, step: 15)
      @left_ratio = analyze_samples(left_samples)

      # Sample right panel (x: 720-1370)
      right_samples = MinimalScreenCapture.sample_region(720, 130, 1370, 750, step: 15)
      @right_ratio = analyze_samples(right_samples)

      @test_phase = 2
      schedule_next_phase(100)
    when 2
      # Report results
      left_status = @left_ratio < 0.8 ? "PASS" : "FAIL"
      right_status = @right_ratio < 0.8 ? "PASS" : "FAIL"

      @status = "Left: #{left_status} (#{@left_ratio.round(2)}) | Right: #{right_status} (#{@right_ratio.round(2)})"

      puts "=" * 60
      puts "MINIMAL GHOSTING TEST RESULTS (#{@text_count} text widgets)"
      puts "=" * 60
      puts "Left panel:  ratio=#{@left_ratio.round(2)} #{left_status}"
      puts "Right panel: ratio=#{@right_ratio.round(2)} #{right_status}"
      puts ""
      if @left_ratio < 0.8 && @right_ratio < 0.8
        puts ">>> NO GHOSTING - Issue is VirtualMatrix-specific <<<"
      elsif @left_ratio < 0.8 && @right_ratio >= 0.8
        puts ">>> RIGHT PANEL GHOSTING - Same pattern as VirtualMatrix! <<<"
        puts "Issue is NOT VirtualMatrix-specific - it's in the rendering pipeline"
      else
        puts ">>> BOTH PANELS HAVE ISSUES - General rendering problem <<<"
      end
      puts "=" * 60

      rebuild
      @test_phase = 3
      schedule_next_phase(5000)  # Keep window open for inspection
    when 3
      quit
    end
  end

  private def analyze_samples(samples : Array(Tuple(Int32, Int32, SF::Color))) : Float64
    bright_count = 0
    faded_count = 0

    samples.each do |_, _, pixel|
      brightness = (pixel.r.to_i + pixel.g.to_i + pixel.b.to_i) / 3

      if pixel.a == 255
        if brightness > 200  # Bright text
          bright_count += 1
        elsif brightness > 100 && brightness < 200  # Faded text
          faded_count += 1
        end
      end
    end

    bright_count > 0 ? faded_count.to_f / bright_count : Float64::INFINITY
  end
end

# Parse command line for text count
text_count = 100
if ARGV.size > 0
  text_count = ARGV[0].to_i
end

app = MinimalGhostingTest.new(text_count: text_count)
app.build_tree
root = app.root
raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)

window_widget = root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(
  width: window_widget.width,
  height: window_widget.height,
  title: window_widget.title
)
MinimalScreenCapture.renderer = renderer
renderer.run(app)
