require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"

# SFML autotest for blit-shift content-reset bug
#
# After scrolling down ~4-5 rows in VirtualMatrix, data cells snap to showing
# (0,*) content instead of the expected (~4,*) range. This is an SFML-specific
# bug where blit_region Y-flip compensation puts overlap content at wrong
# dest coordinates. TestRenderBackend lacks this flip, so headless tests pass.
#
# Strategy: Capture content_layer pixels before and after vertical scroll.
# After scrolling 120px down (past cache_extent=100), the visible region of
# the content layer should show DIFFERENT content than pre-scroll. If the
# same pixel pattern appears → blit-shift put row 0 at wrong position → BUG.
#
# Usage:
#   shards build blit_shift_vthumb_autotest
#   DISPLAY=:0 timeout 20 ./bin/blit_shift_vthumb_autotest
#   cat /tmp/blit_shift_vthumb_results.log
#   cat /tmp/blit_shift_trace.log

# Pixel capture from layer backends (CrSFMLBackend → RenderTexture → Image)
module LayerCapture
  # Capture a region of pixels from a layer's backend as {x, y, RGBA} tuples
  def self.capture_layer_region(layer : CrymbleUI::Layer?, x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32, step : Int32 = 2) : Array(Tuple(Int32, Int32, UInt32))
    result = [] of Tuple(Int32, Int32, UInt32)
    return result unless layer
    backend = layer.backend
    return result unless backend.is_a?(CrymbleUI::CrSFMLBackend)
    image = backend.texture.copy_to_image
    y = y1
    while y <= y2
      x = x1
      while x <= x2
        if x >= 0 && y >= 0 && x < image.size.x.to_i && y < image.size.y.to_i
          px = image.get_pixel(x, y)
          rgba = (px.r.to_u32 << 24) | (px.g.to_u32 << 16) | (px.b.to_u32 << 8) | px.a.to_u32
          result << {x, y, rgba}
        end
        x += step
      end
      y += step
    end
    result
  end

  # Capture the VISIBLE region of a layer (accounts for viewport_cache offset)
  def self.capture_layer_visible_region(layer : CrymbleUI::Layer, step : Int32 = 2) : Array(Tuple(Int32, Int32, UInt32))
    if layer.viewport_cache
      buf_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
      buf_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
      vp_w = layer.bounds.width.to_i
      vp_h = layer.bounds.height.to_i
      capture_layer_region(layer, buf_x, buf_y, buf_x + vp_w, buf_y + vp_h, step)
    else
      b = layer.bounds
      capture_layer_region(layer, 0, 0, b.width.to_i, b.height.to_i, step)
    end
  end

  # Save a layer's backend to a PNG file
  def self.save_layer_image(layer : CrymbleUI::Layer?, path : String)
    return unless layer
    backend = layer.backend
    return unless backend.is_a?(CrymbleUI::CrSFMLBackend)
    image = backend.texture.copy_to_image
    image.save_to_file(path)
  end

  def self.rgba_string(rgba : UInt32) : String
    r = (rgba >> 24) & 0xFF
    g = (rgba >> 16) & 0xFF
    b = (rgba >> 8) & 0xFF
    a = rgba & 0xFF
    "RGBA(#{r},#{g},#{b},#{a})"
  end
end

class BlitShiftVthumbAutoTest < CrymbleUI::App
  WINDOW_W = 1400
  WINDOW_H = 900

  @adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
  @scheduled_first = false

  enum Phase
    Settle          # Phase 0: Initial settle
    CaptureBaseline # Phase 1: Capture pre-scroll visible region pixels
    ScrollDown      # Phase 2: Scroll down 4 wheel events (120px, past cache_extent=100)
    CaptureAfter    # Phase 3: Capture post-scroll visible region and compare
    Results         # Phase 4: Output results
    Done            # Phase 5: Quit
  end

  @phase = Phase::Settle
  @sub_step = 0

  # Pixel snapshots from content_layer visible region: {buf_x, buf_y, RGBA}
  @baseline_pixels = [] of Tuple(Int32, Int32, UInt32)
  @after_pixels = [] of Tuple(Int32, Int32, UInt32)

  # Saved viewport offsets (buffer coords where viewport sits)
  @baseline_vp_offset = {0, 0}

  @test_results = [] of String

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule(500) { run_phase }
    end

    window("Blit-Shift VThumb Autotest", WINDOW_W, WINDOW_H) do
      expanded do
        widget(CrymbleUI::VirtualMatrix.new(
          adapter: @adapter,
          id: "test_matrix",
          cursor_highlight_delta: -30,
          content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
        ))
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
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000), &block)
  end

  private def get_matrix : CrymbleUI::VirtualMatrix?
    find("test_matrix").as?(CrymbleUI::VirtualMatrix)
  end

  private def get_content_layer : CrymbleUI::Layer?
    get_matrix.try(&.content_layer)
  end

  private def get_scroll_view : CrymbleUI::ScrollView?
    get_matrix.try(&.@content_scroll_view)
  end

  private def get_scroll_offset : CrymbleUI::Vec2
    get_matrix.try(&.@scroll_offset) || CrymbleUI::Vec2.zero
  end

  private def get_buf_origin : CrymbleUI::Vec2
    get_content_layer.try(&.buffer_origin) || CrymbleUI::Vec2.zero
  end

  private def run_phase
    case @phase
    when Phase::Settle
      log("=== PHASE 0: SETTLE ===")
      # Let the matrix fully render
      root.try(&.mark_needs_layout)
      rebuild if root.try(&.needs_layout?)
      @phase = Phase::CaptureBaseline
      schedule(500) { run_phase }

    when Phase::CaptureBaseline
      log("=== PHASE 1: CAPTURE BASELINE ===")
      log_state("baseline")

      if layer = get_content_layer
        # Save viewport offset at baseline time
        if layer.viewport_cache
          @baseline_vp_offset = {(layer.scroll_offset.x - layer.buffer_origin.x).to_i,
                                  (layer.scroll_offset.y - layer.buffer_origin.y).to_i}
        end
        log("  baseline viewport offset in buffer: (#{@baseline_vp_offset[0]}, #{@baseline_vp_offset[1]})")

        @baseline_pixels = LayerCapture.capture_layer_visible_region(layer, step: 3)
        log("  Captured #{@baseline_pixels.size} baseline pixels from content_layer visible region")

        # Log a few sample pixels
        @baseline_pixels.first(5).each do |x, y, rgba|
          log("    sample (#{x},#{y}): #{LayerCapture.rgba_string(rgba)}")
        end
      end

      # Save baseline layer image
      LayerCapture.save_layer_image(get_content_layer, "/tmp/blit_shift_content_baseline.png")

      @phase = Phase::ScrollDown
      @sub_step = 0
      schedule(300) { run_phase }

    when Phase::ScrollDown
      log("=== PHASE 2: SCROLL DOWN ===")
      if matrix = get_matrix
        # 4 wheel events × 30px/event = 120px scroll (past cache_extent=100)
        abs = matrix.absolute_bounds
        center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)

        4.times do |i|
          matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
          log("  Wheel event #{i + 1}: scroll_offset=#{get_scroll_offset}")
        end

        # Let render process
        rebuild if root.try(&.needs_layout?)
        log_state("after scroll")
      end

      @phase = Phase::CaptureAfter
      schedule(200) { run_phase }

    when Phase::CaptureAfter
      log("=== PHASE 3: CAPTURE AFTER SCROLL ===")
      log_state("capture")

      if layer = get_content_layer
        @after_pixels = LayerCapture.capture_layer_visible_region(layer, step: 3)
        log("  Captured #{@after_pixels.size} after-scroll pixels from content_layer visible region")

        # Log a few sample pixels
        @after_pixels.first(5).each do |x, y, rgba|
          log("    sample (#{x},#{y}): #{LayerCapture.rgba_string(rgba)}")
        end
      end

      # Save post-scroll layer images
      LayerCapture.save_layer_image(get_content_layer, "/tmp/blit_shift_content_after_scroll.png")

      # Compare: after scrolling 120px down, the visible region should show
      # DIFFERENT pixel content than baseline. We compare by looking at what
      # fraction of the viewport pixels (at the SAME viewport-relative position)
      # are identical before vs after scroll.
      #
      # Approach: The visible region pixels are in buffer coordinates. At baseline,
      # the viewport is at buffer position (vp_x0, vp_y0). After scroll, it's at
      # (vp_x1, vp_y1). If content shifted correctly, the pixel at a given
      # viewport-relative position (e.g. 20px from top) should show different content.
      #
      # Simplest: just compare pixel counts. Baseline and after should have very
      # different pixel distributions if content actually changed.

      # Build a viewport-relative pixel map for comparison
      baseline_viewport = to_viewport_relative(@baseline_pixels, @baseline_vp_offset)
      after_viewport = to_viewport_relative(@after_pixels, get_after_viewport_offset)

      matching = 0
      different = 0
      total = 0

      # Compare at same viewport-relative positions
      after_map = Hash(Tuple(Int32, Int32), UInt32).new
      after_viewport.each { |x, y, rgba| after_map[{x, y}] = rgba }

      baseline_viewport.each do |bx, by, b_rgba|
        if a_rgba = after_map[{bx, by}]?
          total += 1
          if pixels_similar?(b_rgba, a_rgba)
            matching += 1
          else
            different += 1
          end
        end
      end

      match_pct = total > 0 ? (matching * 100.0 / total).round(1) : 0.0

      log("  Viewport-relative comparison: #{matching} matching, #{different} different out of #{total}")
      log("  Match percentage: #{match_pct}%")

      # If >70% of pixels match after scrolling 120px, the content didn't actually
      # change — the blit-shift put row 0 content where row ~4 should be.
      if match_pct > 70.0
        @test_results << "CONTENT_RESET_DETECTED: #{match_pct}% pixel match after 120px scroll"
        @test_results << "  Expected different content (row ~4+), got same as baseline (row 0)"
        log("  *** BUG DETECTED: Content reset to row 0! ***")
      else
        @test_results << "CONTENT_CHANGED: #{match_pct}% match — content shifted correctly"
        log("  OK: Content shifted as expected after scroll")
      end

      # Also check scroll_offset is correct
      scroll = get_scroll_offset
      if scroll.y < 100.0
        @test_results << "SCROLL_OFFSET_LOW: y=#{scroll.y.round(1)} (expected ~120)"
        log("  WARNING: scroll_offset.y only #{scroll.y.round(1)} — expected ~120")
      else
        @test_results << "SCROLL_OFFSET_OK: y=#{scroll.y.round(1)}"
      end

      # Log buffer origin state
      bo = get_buf_origin
      @test_results << "BUFFER_ORIGIN: (#{bo.x.round(1)}, #{bo.y.round(1)})"

      @phase = Phase::Results
      schedule(200) { run_phase }

    when Phase::Results
      output_results
      @phase = Phase::Done
      schedule(500) { run_phase }

    when Phase::Done
      quit
    end
  end

  private def get_after_viewport_offset : Tuple(Int32, Int32)
    if layer = get_content_layer
      if layer.viewport_cache
        buf_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
        buf_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
        return {buf_x, buf_y}
      end
    end
    {0, 0}
  end

  # Convert buffer-coordinate pixels to viewport-relative coordinates
  private def to_viewport_relative(pixels : Array(Tuple(Int32, Int32, UInt32)), vp_offset : Tuple(Int32, Int32)) : Array(Tuple(Int32, Int32, UInt32))
    pixels.map { |x, y, rgba| {x - vp_offset[0], y - vp_offset[1], rgba} }
  end

  private def pixels_similar?(a : UInt32, b : UInt32) : Bool
    tolerance = 8
    ar = ((a >> 24) & 0xFF).to_i
    ag = ((a >> 16) & 0xFF).to_i
    ab = ((a >> 8) & 0xFF).to_i
    br = ((b >> 24) & 0xFF).to_i
    bg = ((b >> 16) & 0xFF).to_i
    bb = ((b >> 8) & 0xFF).to_i
    (ar - br).abs <= tolerance &&
    (ag - bg).abs <= tolerance &&
    (ab - bb).abs <= tolerance
  end

  private def log_state(label : String)
    scroll = get_scroll_offset
    bo = get_buf_origin
    vp_x = (scroll.x - bo.x).round(1)
    vp_y = (scroll.y - bo.y).round(1)
    log("  #{label}: scroll=(#{scroll.x.round(1)},#{scroll.y.round(1)}) buf_origin=(#{bo.x.round(1)},#{bo.y.round(1)}) viewport_in_buf=(#{vp_x},#{vp_y})")
  end

  private def output_results
    has_bug = @test_results.any? { |r| r.includes?("CONTENT_RESET_DETECTED") }

    File.open("/tmp/blit_shift_vthumb_results.log", "w") do |f|
      f.puts "=== Blit-Shift Content-Reset Autotest ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      if has_bug
        f.puts "*** CONTENT RESET BUG DETECTED — TEST FAILED ***"
        f.puts ""
        f.puts "After scrolling down 120px (4 wheel events x 30px):"
        f.puts "  Data cells show row 0 content instead of expected row ~4"
        f.puts "  This is the blit-shift Y-flip bug in CrSFMLBackend.blit_region"
      else
        f.puts "*** NO BUG DETECTED — TEST PASSED ***"
      end
      f.puts ""
      f.puts "Debug artifacts:"
      f.puts "  /tmp/blit_shift_content_baseline.png"
      f.puts "  /tmp/blit_shift_content_after_scroll.png"
      f.puts "  /tmp/blit_shift_trace.log (instrumentation)"
      f.puts "  /tmp/blit_shift_state.log (detailed trace)"
    end

    puts "\n=== Blit-Shift Content-Reset Autotest ==="
    @test_results.each { |r| puts r }

    if has_bug
      puts "\n*** CONTENT RESET BUG DETECTED — TEST FAILED ***"
    else
      puts "\n*** NO BUG DETECTED — TEST PASSED ***"
    end
  end

  private def log(msg : String)
    File.open("/tmp/blit_shift_state.log", "a") { |f| f.puts msg }
    puts msg
  end
end

# Clear log files
File.write("/tmp/blit_shift_state.log", "")
File.write("/tmp/blit_shift_vthumb_results.log", "")
File.write("/tmp/blit_shift_trace.log", "")

app = BlitShiftVthumbAutoTest.new
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
