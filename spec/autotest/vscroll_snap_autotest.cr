require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"

# SFML autotest: Vertical scroll snap bug reproduction
#
# Reproduces the VirtualMatrix bug with compound cells + sticky headers
# during vertical scrolling:
#   (a) After scrolling down ~4 rows, cells (4,*) display correctly at row 7
#   (b) Scrolling a bit further causes cells (0,*) to snap in at row 7 — wrong data
#   (c) Scrolling all the way back up produces blank rows (3-6 empty) + misaligned data
#
# The immediate-mode cache validator detects pixel mismatches between the
# cached pipeline and a fresh to_primitives() re-render.
#
# Usage:
#   shards build vscroll_snap_autotest -Dcache_validation
#   DISPLAY=:0 timeout 120 ./bin/vscroll_snap_autotest
#   cat /tmp/vscroll_snap_results.log

{% unless flag?(:cache_validation) %}
  {{ raise "vscroll_snap_autotest requires -Dcache_validation flag" }}
{% end %}

module LayerCapture
  def self.save_layer_image(layer : CrymbleUI::Layer?, path : String)
    return unless layer
    backend = layer.backend
    return unless backend.is_a?(CrymbleUI::CrSFMLBackend)
    image = backend.texture.copy_to_image
    image.save_to_file(path)
  end
end


class VScrollSnapAutoTest < CrymbleUI::App
  WINDOW_W = 1400
  WINDOW_H =  900

  SCROLL_STEPS = 10  # steps each direction (enough for 2+ recenters)
  DELAY_MS     = 100  # ms between steps

  @adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
  @scheduled_first = false

  enum Phase
    Settle
    ScrollDown   # vertical scroll down
    ScrollBack   # vertical scroll back up
    Results
    Done
  end

  @phase = Phase::Settle
  @step = 0
  @total_failures = 0

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!
      schedule(800) { run_phase }
    end

    window("VScroll Snap Autotest", WINDOW_W, WINDOW_H) do
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

  private def run_phase
    case @phase
    when Phase::Settle
      log("=== SETTLE ===")
      root.try(&.mark_needs_layout)
      rebuild if root.try(&.needs_layout?)
      LayerCapture.save_layer_image(get_content_layer, "/tmp/vscroll_content_initial.png")
      @phase = Phase::ScrollDown
      @step = 0
      schedule(500) { run_phase }

    when Phase::ScrollDown
      if @step < SCROLL_STEPS
        do_scroll_step(:down)
        @step += 1
        # Save mid-scroll PNG at step 5 (pre-snap point)
        if @step == 5
          LayerCapture.save_layer_image(get_content_layer, "/tmp/vscroll_content_mid_down.png")
          log("  -- saved mid-scroll PNG at step 5 --")
        end
        schedule(DELAY_MS) { run_phase }
      else
        log("=== ScrollDown done (#{SCROLL_STEPS} steps) ===")
        LayerCapture.save_layer_image(get_content_layer, "/tmp/vscroll_content_scrolled_down.png")
        @phase = Phase::ScrollBack
        @step = 0
        schedule(300) { run_phase }
      end

    when Phase::ScrollBack
      if @step < SCROLL_STEPS
        do_scroll_step(:up)
        @step += 1
        schedule(DELAY_MS) { run_phase }
      else
        log("=== ScrollBack done (#{SCROLL_STEPS} steps) ===")
        LayerCapture.save_layer_image(get_content_layer, "/tmp/vscroll_content_scrolled_back.png")
        @phase = Phase::Results
        schedule(300) { run_phase }
      end

    when Phase::Results
      output_results
      @phase = Phase::Done
      schedule(500) { run_phase }

    when Phase::Done
      quit
    end
  end

  private def do_scroll_step(direction : Symbol)
    matrix = get_matrix
    return unless matrix

    abs = matrix.absolute_bounds
    center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)

    # Vertical-only scroll: down = -1, up = +1
    v_dir = direction == :down ? -1.0 : 1.0

    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, v_dir), center)
    rebuild if root.try(&.needs_layout?)

    # Check for new failures after this step
    failures = CrymbleUI::CacheValidation.failures
    new_count = failures.size - @total_failures
    if new_count > 0
      log("  Step #{@step} #{direction}: #{new_count} NEW failure(s) — frame #{CrymbleUI::CacheValidation.frame_counter}")
      @total_failures = failures.size
    end
  end

  private def output_results
    failures = CrymbleUI::CacheValidation.failures

    File.open("/tmp/vscroll_snap_results.log", "w") do |f|
      f.puts "=== VScroll Snap Bug Autotest ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts "Scroll: #{SCROLL_STEPS} vertical steps down + #{SCROLL_STEPS} back up"
      f.puts ""

      if failures.empty?
        f.puts "*** NO MISMATCHES — TEST PASSED ***"
      else
        f.puts "*** #{failures.size} MISMATCH(ES) DETECTED — TEST FAILED ***"
        f.puts ""
        failures.each_with_index do |fail, i|
          f.puts "  [#{i + 1}] #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame}"
          f.puts "       mismatches=#{fail.mismatch_count}/#{fail.total_pixels}"
          x, y, cached, uncached = fail.first_mismatch
          f.puts "       first_at=(#{x},#{y}) cached=0x#{cached.to_s(16)} uncached=0x#{uncached.to_s(16)}"
          f.puts "       diff: /tmp/cv_diff_#{fail.layer_id}_f#{fail.frame}.ppm"
        end
      end

      f.puts ""
      f.puts "Layer PNGs:"
      f.puts "  /tmp/vscroll_content_initial.png"
      f.puts "  /tmp/vscroll_content_mid_down.png"
      f.puts "  /tmp/vscroll_content_scrolled_down.png"
      f.puts "  /tmp/vscroll_content_scrolled_back.png"
    end

    puts "\n=== VScroll Snap Bug Autotest ==="
    if failures.empty?
      puts "*** NO MISMATCHES — TEST PASSED ***"
    else
      puts "*** #{failures.size} MISMATCH(ES) DETECTED — TEST FAILED ***"
      failures.first(5).each_with_index do |fail, i|
        puts "  [#{i + 1}] #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame} mismatches=#{fail.mismatch_count}/#{fail.total_pixels}"
      end
      puts "  ... see /tmp/vscroll_snap_results.log for full list"
      puts "  ... diff PPMs at /tmp/cv_diff_*.ppm"
    end
  end

  private def log(msg : String)
    File.open("/tmp/vscroll_snap_trace.log", "a") { |f| f.puts msg }
    puts msg
  end
end

# Clear logs
File.write("/tmp/vscroll_snap_trace.log", "")
File.write("/tmp/vscroll_snap_results.log", "")

app = VScrollSnapAutoTest.new
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
