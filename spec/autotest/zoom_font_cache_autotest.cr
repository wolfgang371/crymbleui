require "../../src/crymble-ui"

# SFML visual test for zoom font cache corruption bug
#
# Root cause: @@font_cache in SFMLRenderer cached SF::Font objects by zoom level.
# On second zoom cycle, the cached font was reused with a stale/corrupted SFML
# glyph atlas, causing garbled rendering.
#
# Test design: Render text labels at 100% zoom, capture baseline pixels from the
# root layer backend. Then perform two zoom-in/zoom-out cycles back to 100%.
# After cycle 2, compare pixels with baseline. With the bug: cached font → atlas
# corruption → mismatch. Without the bug: fresh font each time → pixels match.
#
# Usage:
#   crystal build spec/autotest/zoom_font_cache_autotest.cr -o bin/zoom_font_cache_autotest
#   DISPLAY=:0 timeout 20 ./bin/zoom_font_cache_autotest
#   cat /tmp/zoom_font_cache_results.log

module LayerCapture
  # Capture a grid of pixels from the first (root) layer's backend
  def self.capture_root_layer(root : CrymbleUI::Widget, step : Int32 = 5) : Array(Tuple(Int32, Int32, UInt32))
    result = [] of Tuple(Int32, Int32, UInt32)
    layers = CrymbleUI::Layer.active_layers(root)
    return result if layers.empty?

    # Use the first layer (root layer where text labels render)
    layer = layers.first
    backend = layer.backend
    return result unless backend.is_a?(CrymbleUI::CrSFMLBackend)

    image = backend.texture.copy_to_image

    # Sample a dense grid across the text rendering area
    x_start = 20
    x_end = [layer.bounds.width.to_i - 10, 380].min
    y_start = 20
    y_end = [layer.bounds.height.to_i - 10, 260].min

    y = y_start
    while y <= y_end
      x = x_start
      while x <= x_end
        if x >= 0 && y >= 0 && x < image.size.x.to_i && y < image.size.y.to_i
          pixel = image.get_pixel(x, y)
          rgba = (pixel.r.to_u32 << 24) | (pixel.g.to_u32 << 16) | (pixel.b.to_u32 << 8) | pixel.a.to_u32
          result << {x, y, rgba}
        end
        x += step
      end
      y += step
    end
    result
  end

  def self.rgba_to_string(rgba : UInt32) : String
    r = (rgba >> 24) & 0xFF
    g = (rgba >> 16) & 0xFF
    b = (rgba >> 8) & 0xFF
    a = rgba & 0xFF
    "RGBA(#{r},#{g},#{b},#{a})"
  end

  def self.pixels_different?(a : UInt32, b : UInt32, tolerance : Int32 = 5) : Bool
    ar = ((a >> 24) & 0xFF).to_i
    ag = ((a >> 16) & 0xFF).to_i
    ab = ((a >> 8) & 0xFF).to_i
    br = ((b >> 24) & 0xFF).to_i
    bg = ((b >> 16) & 0xFF).to_i
    bb = ((b >> 8) & 0xFF).to_i
    (ar - br).abs > tolerance || (ag - bg).abs > tolerance || (ab - bb).abs > tolerance
  end
end

class ZoomFontCacheAutoTest < CrymbleUI::App
  enum Phase
    Settle
    CaptureBaseline
    ZoomIn1
    ZoomOut1
    ZoomIn2
    ZoomOut2
    CompareResults
    Done
  end

  @phase = Phase::Settle
  @scheduled_first = false

  # Pixel data: array of (x, y, rgba_packed) tuples
  @baseline_pixels : Array(Tuple(Int32, Int32, UInt32)) = [] of Tuple(Int32, Int32, UInt32)
  @test_results = [] of String

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule(500) { run_phase }
    end

    # Simple window with large text labels — font rendering is what we're testing
    window("Zoom Font Cache Test", 400, 300) do
      vstack(spacing: 12.0, padding: 20.0) do
        text("ABCDEFGHIJ", font_scale: 2)
        text("klmnopqrst", font_scale: 2)
        text("0123456789", font_scale: 2)
        text("ZOOM TEST!", font_scale: 3)
        text("The quick brown fox", font_scale: 1)
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

  private def schedule(delay_ms : Int32, &block)
    CrymbleUI::Widget.scheduler.schedule(
      Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000),
      &block
    )
  end

  private def run_phase
    case @phase
    when .settle?
      log("=== PHASE: Settle (wait for stable rendering) ===")
      @phase = Phase::CaptureBaseline
      schedule(300) { run_phase }

    when .capture_baseline?
      log("=== PHASE: Capture baseline at 100% zoom ===")
      if r = root
        @baseline_pixels = LayerCapture.capture_root_layer(r)
      end
      log("  Captured #{@baseline_pixels.size} baseline pixels")
      @test_results << "BASELINE: #{@baseline_pixels.size} pixels captured"
      @phase = Phase::ZoomIn1
      schedule(200) { run_phase }

    when .zoom_in1?
      log("=== PHASE: Zoom In (cycle 1) ===")
      do_zoom_in
      @phase = Phase::ZoomOut1
      schedule(400) { run_phase }

    when .zoom_out1?
      log("=== PHASE: Zoom Out back to 100% (cycle 1) ===")
      do_zoom_out
      log("  Zoom factor after cycle 1: #{CrymbleUI::FontSizing.zoom_percentage}")
      @phase = Phase::ZoomIn2
      schedule(400) { run_phase }

    when .zoom_in2?
      log("=== PHASE: Zoom In (cycle 2) ===")
      do_zoom_in
      @phase = Phase::ZoomOut2
      schedule(400) { run_phase }

    when .zoom_out2?
      log("=== PHASE: Zoom Out back to 100% (cycle 2) ===")
      do_zoom_out
      log("  Zoom factor after cycle 2: #{CrymbleUI::FontSizing.zoom_percentage}")
      @phase = Phase::CompareResults
      schedule(400) { run_phase }

    when .compare_results?
      log("=== PHASE: Compare pixels after 2 zoom cycles ===")
      compare_with_baseline
      output_results
      @phase = Phase::Done
      schedule(500) { run_phase }

    when .done?
      quit
    end
  end

  # Zoom in one step via FontSizing (triggers on_zoom_change callback in renderer)
  private def do_zoom_in
    CrymbleUI::FontSizing.zoom_in
    root.try &.mark_needs_layout
    log("  Zoomed in to #{CrymbleUI::FontSizing.zoom_percentage}")
  end

  # Zoom out one step
  private def do_zoom_out
    CrymbleUI::FontSizing.zoom_out
    root.try &.mark_needs_layout
    log("  Zoomed out to #{CrymbleUI::FontSizing.zoom_percentage}")
  end

  # Compare current layer pixels with baseline
  private def compare_with_baseline
    r = root
    unless r
      @test_results << "ERROR: No root widget"
      return
    end

    current_pixels = LayerCapture.capture_root_layer(r)
    if current_pixels.empty?
      @test_results << "ERROR: Could not capture layer pixels for comparison"
      return
    end

    # Build lookup for current pixels
    current_map = {} of Tuple(Int32, Int32) => UInt32
    current_pixels.each { |(x, y, rgba)| current_map[{x, y}] = rgba }

    total = 0
    mismatches = 0
    mismatch_examples = [] of String

    @baseline_pixels.each do |(x, y, baseline_rgba)|
      if current_rgba = current_map[{x, y}]?
        total += 1
        if LayerCapture.pixels_different?(baseline_rgba, current_rgba)
          mismatches += 1
          if mismatch_examples.size < 10
            mismatch_examples << "  (#{x},#{y}): #{LayerCapture.rgba_to_string(baseline_rgba)} -> #{LayerCapture.rgba_to_string(current_rgba)}"
          end
        end
      end
    end

    pct = total > 0 ? (mismatches.to_f / total * 100).round(1) : 0.0
    log("  Compared #{total} pixels: #{mismatches} mismatches (#{pct}%)")
    mismatch_examples.each { |ex| log(ex) }

    if pct > 5.0
      @test_results << "CORRUPTION_DETECTED: #{mismatches}/#{total} pixels differ (#{pct}%) after 2 zoom cycles"
    else
      @test_results << "CLEAN: #{mismatches}/#{total} pixels differ (#{pct}%) — within tolerance"
    end
  end

  private def log(msg : String)
    File.open("/tmp/zoom_font_cache_state.log", "a") { |f| f.puts msg }
    puts msg
  end

  private def output_results
    has_corruption = @test_results.any? { |r| r.includes?("CORRUPTION_DETECTED") }

    File.open("/tmp/zoom_font_cache_results.log", "w") do |f|
      f.puts "=== Zoom Font Cache Visual Test ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      if has_corruption
        f.puts "*** CORRUPTION DETECTED - TEST FAILED ***"
        f.puts "Font cache reuse caused glyph atlas corruption after 2 zoom cycles."
      else
        f.puts "*** NO CORRUPTION - TEST PASSED ***"
        f.puts "Fresh font creation on each zoom change prevents atlas corruption."
      end
      f.puts ""
      f.puts "See /tmp/zoom_font_cache_state.log for details"
    end

    puts ""
    puts "=== Zoom Font Cache Visual Test ==="
    @test_results.each { |r| puts r }

    if has_corruption
      puts "\n*** CORRUPTION DETECTED - TEST FAILED ***"
    else
      puts "\n*** NO CORRUPTION - TEST PASSED ***"
    end
  end
end

# Clear logs
File.write("/tmp/zoom_font_cache_state.log", "")
File.write("/tmp/zoom_font_cache_results.log", "")

# Bootstrap and run
app = ZoomFontCacheAutoTest.new
app.build_tree
root = app.root
raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)
window_widget = root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(
  width: window_widget.width,
  height: window_widget.height,
  title: window_widget.title
)
renderer.run(app)
