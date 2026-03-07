require "../../src/crymble-ui"

# SFML visual test for VirtualMatrix zoom corruption after two zoom cycles.
#
# Root cause: After DSL rebuild, @content_layer (which is @[Reconcile]) retains
# its old owner_widget pointing to the orphaned VirtualMatrix instance. When
# invalidate_all_layer_backends walks Layer.active_layers(root), in_tree? fails
# for this layer → backend NOT invalidated → stale pixels → corruption.
#
# Also, @last_zoom_factor defaults to 1.0 on the new instance, so perform_layout
# sees 1.0==1.0 and skips zoom-change handling (cache clear, cell rebuild, etc).
#
# Test design: DSL-style app with VirtualMatrix. Settle → capture baseline pixels
# from content_layer → two zoom-in/zoom-out cycles → compare. With the bug:
# stale content layer → pixel corruption. Without: clean rendering.
#
# Usage:
#   crystal build spec/autotest/zoom_virtual_matrix_autotest.cr -o bin/zoom_virtual_matrix_autotest
#   DISPLAY=:0 timeout 30 ./bin/zoom_virtual_matrix_autotest
#   cat /tmp/zoom_vm_results.log

module VMLayerCapture
  # Capture pixels directly from VirtualMatrix's content_layer backend
  def self.capture_content_layer(app : CrymbleUI::App, step : Int32 = 4) : Array(Tuple(Int32, Int32, UInt32))
    result = [] of Tuple(Int32, Int32, UInt32)

    # Find the VirtualMatrix by ID via App
    vm = app.find("zoom_vm_test")
    return result unless vm
    vm_widget = vm.as?(CrymbleUI::VirtualMatrix)
    return result unless vm_widget

    layer = vm_widget.layer
    return result unless layer

    backend = layer.backend
    return result unless backend.is_a?(CrymbleUI::CrSFMLBackend)

    image = backend.texture.copy_to_image

    # Sample a grid across the content layer
    x_end = [layer.bounds.width.to_i - 5, image.size.x.to_i - 1].min
    y_end = [layer.bounds.height.to_i - 5, image.size.y.to_i - 1].min

    y = 5
    while y <= y_end
      x = 5
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

class ZoomVirtualMatrixAutoTest < CrymbleUI::App
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

  @baseline_pixels : Array(Tuple(Int32, Int32, UInt32)) = [] of Tuple(Int32, Int32, UInt32)
  @test_results = [] of String

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule(800) { run_phase }
    end

    # DSL-style app: creates NEW VirtualMatrix on each build() → triggers reconciliation
    window("VM Zoom Test", 600, 400) do
      expanded do
        widget(CrymbleUI::VirtualMatrix.new(10, 8, id: "zoom_vm_test"))
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
      schedule(500) { run_phase }

    when .capture_baseline?
      log("=== PHASE: Capture baseline at 100% zoom ===")
      @baseline_pixels = VMLayerCapture.capture_content_layer(self)
      log("  Captured #{@baseline_pixels.size} baseline pixels")
      @test_results << "BASELINE: #{@baseline_pixels.size} pixels captured"
      @phase = Phase::ZoomIn1
      schedule(300) { run_phase }

    when .zoom_in1?
      log("=== PHASE: Zoom In (cycle 1) ===")
      do_zoom_in
      @phase = Phase::ZoomOut1
      schedule(500) { run_phase }

    when .zoom_out1?
      log("=== PHASE: Zoom Out back to 100% (cycle 1) ===")
      do_zoom_out
      log("  Zoom factor after cycle 1: #{CrymbleUI::FontSizing.zoom_percentage}")
      @phase = Phase::ZoomIn2
      schedule(500) { run_phase }

    when .zoom_in2?
      log("=== PHASE: Zoom In (cycle 2) ===")
      do_zoom_in
      @phase = Phase::ZoomOut2
      schedule(500) { run_phase }

    when .zoom_out2?
      log("=== PHASE: Zoom Out back to 100% (cycle 2) ===")
      do_zoom_out
      log("  Zoom factor after cycle 2: #{CrymbleUI::FontSizing.zoom_percentage}")
      @phase = Phase::CompareResults
      schedule(500) { run_phase }

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

  private def do_zoom_in
    CrymbleUI::FontSizing.zoom_in
    root.try &.mark_needs_layout
    log("  Zoomed in to #{CrymbleUI::FontSizing.zoom_percentage}")
  end

  private def do_zoom_out
    CrymbleUI::FontSizing.zoom_out
    root.try &.mark_needs_layout
    log("  Zoomed out to #{CrymbleUI::FontSizing.zoom_percentage}")
  end

  private def compare_with_baseline
    current_pixels = VMLayerCapture.capture_content_layer(self)
    if current_pixels.empty?
      @test_results << "ERROR: Could not capture content layer pixels for comparison"
      return
    end

    current_map = {} of Tuple(Int32, Int32) => UInt32
    current_pixels.each { |(x, y, rgba)| current_map[{x, y}] = rgba }

    total = 0
    mismatches = 0
    mismatch_examples = [] of String

    @baseline_pixels.each do |(x, y, baseline_rgba)|
      if current_rgba = current_map[{x, y}]?
        total += 1
        if VMLayerCapture.pixels_different?(baseline_rgba, current_rgba)
          mismatches += 1
          if mismatch_examples.size < 10
            mismatch_examples << "  (#{x},#{y}): #{VMLayerCapture.rgba_to_string(baseline_rgba)} -> #{VMLayerCapture.rgba_to_string(current_rgba)}"
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
    File.open("/tmp/zoom_vm_state.log", "a") { |f| f.puts msg }
    puts msg
  end

  private def output_results
    has_corruption = @test_results.any? { |r| r.includes?("CORRUPTION_DETECTED") }

    File.open("/tmp/zoom_vm_results.log", "w") do |f|
      f.puts "=== VirtualMatrix Zoom Visual Test ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      if has_corruption
        f.puts "*** CORRUPTION DETECTED - TEST FAILED ***"
        f.puts "Stale content_layer owner_widget caused zoom corruption after 2 cycles."
      else
        f.puts "*** NO CORRUPTION - TEST PASSED ***"
        f.puts "Content layer owner_widget correctly updated on reconciliation."
      end
      f.puts ""
      f.puts "See /tmp/zoom_vm_state.log for details"
    end

    puts ""
    puts "=== VirtualMatrix Zoom Visual Test ==="
    @test_results.each { |r| puts r }

    if has_corruption
      puts "\n*** CORRUPTION DETECTED - TEST FAILED ***"
    else
      puts "\n*** NO CORRUPTION - TEST PASSED ***"
    end
  end
end

# Clear logs
File.write("/tmp/zoom_vm_state.log", "")
File.write("/tmp/zoom_vm_results.log", "")

# Bootstrap and run
app = ZoomVirtualMatrixAutoTest.new
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
