require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"

# SFML autotest: Immediate-mode cache validation for VirtualMatrix
#
# Scrolls the demo-configured VirtualMatrix diagonally (alternating H/V),
# then back. After each scroll step, captures the cached layer pixels and
# a fresh immediate-mode re-render, compares pixel-by-pixel, and saves
# side-by-side diff PNGs on any mismatch.
#
# This catches real SFML rendering bugs (Y-flip, compound cell width,
# buffer origin drift) that headless TestRenderBackend cannot reproduce.
#
# Usage:
#   shards build immediate_mode_autotest -Dcache_validation
#   DISPLAY=:0 timeout 120 ./bin/immediate_mode_autotest
#   cat /tmp/imm_autotest_results.log
#   # Check /tmp/imm_diff_*.png for visual diffs

{% unless flag?(:cache_validation) %}
  {{ raise "immediate_mode_autotest requires -Dcache_validation flag" }}
{% end %}

# Reuse LayerCapture for PNG saving
module LayerCapture
  def self.save_layer_image(layer : CrymbleUI::Layer?, path : String)
    return unless layer
    backend = layer.backend
    return unless backend.is_a?(CrymbleUI::CrSFMLBackend)
    image = backend.texture.copy_to_image
    image.save_to_file(path)
  end
end

class ImmediateModeAutoTest < CrymbleUI::App
  WINDOW_W = 1400
  WINDOW_H =  900

  SCROLL_STEPS = 20 # steps each direction
  DELAY_MS     = 100 # ms between steps

  @adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
  @scheduled_first = false

  enum Phase
    Settle
    ScrollOut     # scroll right + down
    ScrollBack    # scroll left + up
    Results
    Done
  end

  @phase = Phase::Settle
  @step = 0
  @total_failures = 0

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      # Enable immediate mode validation
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!
      schedule(800) { run_phase }
    end

    window("ImmediateMode Autotest", WINDOW_W, WINDOW_H) do
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
      # Save initial state
      LayerCapture.save_layer_image(get_content_layer, "/tmp/imm_content_initial.png")
      @phase = Phase::ScrollOut
      @step = 0
      schedule(500) { run_phase }

    when Phase::ScrollOut
      if @step < SCROLL_STEPS
        do_scroll_step(:out)
        @step += 1
        schedule(DELAY_MS) { run_phase }
      else
        log("=== ScrollOut done (#{SCROLL_STEPS} steps) ===")
        LayerCapture.save_layer_image(get_content_layer, "/tmp/imm_content_scrolled_out.png")
        @phase = Phase::ScrollBack
        @step = 0
        schedule(300) { run_phase }
      end

    when Phase::ScrollBack
      if @step < SCROLL_STEPS
        do_scroll_step(:back)
        @step += 1
        schedule(DELAY_MS) { run_phase }
      else
        log("=== ScrollBack done (#{SCROLL_STEPS} steps) ===")
        LayerCapture.save_layer_image(get_content_layer, "/tmp/imm_content_scrolled_back.png")
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

    # Alternate: horizontal then vertical each step
    h_dir = direction == :out ? -1.0 : 1.0
    v_dir = direction == :out ? -1.0 : 1.0

    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(h_dir, 0.0), center)
    rebuild if root.try(&.needs_layout?)

    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, v_dir), center)
    rebuild if root.try(&.needs_layout?)

    # Check for new failures after this step
    failures = CrymbleUI::CacheValidation.failures
    new_count = failures.size - @total_failures
    if new_count > 0
      log("  Step #{@step} #{direction}: #{new_count} NEW failure(s) — frame #{CrymbleUI::CacheValidation.frame_counter}")
      # Diff PPMs are saved automatically by validate_immediate_mode
      @total_failures = failures.size
    end
  end

  private def output_results
    failures = CrymbleUI::CacheValidation.failures

    File.open("/tmp/imm_autotest_results.log", "w") do |f|
      f.puts "=== Immediate-Mode Cache Validation Autotest ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts "Scroll: #{SCROLL_STEPS} diagonal steps out + #{SCROLL_STEPS} back"
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
      f.puts "  /tmp/imm_content_initial.png"
      f.puts "  /tmp/imm_content_scrolled_out.png"
      f.puts "  /tmp/imm_content_scrolled_back.png"
    end

    puts "\n=== Immediate-Mode Cache Validation Autotest ==="
    if failures.empty?
      puts "*** NO MISMATCHES — TEST PASSED ***"
    else
      puts "*** #{failures.size} MISMATCH(ES) DETECTED — TEST FAILED ***"
      failures.first(5).each_with_index do |fail, i|
        puts "  [#{i + 1}] #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame} mismatches=#{fail.mismatch_count}/#{fail.total_pixels}"
      end
      puts "  ... see /tmp/imm_autotest_results.log for full list"
      puts "  ... diff PPMs at /tmp/cv_diff_*.ppm"
    end
  end

  private def log(msg : String)
    File.open("/tmp/imm_autotest_trace.log", "a") { |f| f.puts msg }
    puts msg
  end
end

# Clear logs
File.write("/tmp/imm_autotest_trace.log", "")
File.write("/tmp/imm_autotest_results.log", "")

app = ImmediateModeAutoTest.new
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
