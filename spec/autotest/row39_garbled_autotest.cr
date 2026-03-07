require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"

# SFML autotest: Row 39 garbled rendering reproduction
#
# Reproduces the VirtualMatrix bug where ruler row 39 (grid row 38, data row 36)
# shows garbled/overlapping text after scrolling down ~10 wheel events.
# Demo config: nrhl=2, nchl=2, rhs=3, chs=3, lrs=10, lcs=10, 1400x900.
#
# The garbled row spans ALL columns (sticky headers + content), suggesting
# a cell positioning or layer rendering issue.
#
# Three run modes:
#   1. Normal (cached): shards build row39_garbled_autotest && DISPLAY=:0 timeout 60 ./bin/row39_garbled_autotest
#   2. Immediate-only:  shards build row39_garbled_autotest -Dimmediate_mode_only && DISPLAY=:0 timeout 60 ./bin/row39_garbled_autotest
#   3. Cache validation: shards build row39_garbled_autotest -Dcache_validation && DISPLAY=:0 timeout 60 ./bin/row39_garbled_autotest
#
# Output:
#   /tmp/row39_results.log           — pass/fail summary
#   /tmp/row39_trace.log             — step-by-step trace
#   /tmp/row39_content_*.png         — content layer snapshots
#   /tmp/row39_sticky_col_*.png      — sticky col layer snapshots
#   /tmp/row39_sticky_row_*.png      — sticky row layer snapshots
#   /tmp/row39_cell_positions.log      — cell bounds near row 38

module LayerCapture
  def self.save_layer_image(layer : CrymbleUI::Layer?, path : String)
    return unless layer
    backend = layer.backend
    return unless backend.is_a?(CrymbleUI::CrSFMLBackend)
    image = backend.texture.copy_to_image
    image.save_to_file(path)
  end
end

class Row39GarbledAutoTest < CrymbleUI::App
  WINDOW_W = 1400
  WINDOW_H =  900

  SCROLL_STEPS = 10  # 10 wheel events to reproduce the garbled row
  DELAY_MS     = 150  # ms between steps (allow SFML to render each frame)

  @adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
  @scheduled_first = false

  enum Phase
    Settle
    ScrollDown    # 10 vertical scroll steps
    Capture       # capture all layers + window screenshot
    Results
    Done
  end

  @phase = Phase::Settle
  @step = 0
  @cv_failures_before_scroll = 0

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      {% if flag?(:cache_validation) %}
        CrymbleUI::CacheValidation.enable(:immediate_mode)
        CrymbleUI::CacheValidation.clear_failures!
      {% end %}
      schedule(800) { run_phase }
    end

    # Match the demo layout: VStack with labels above/below the matrix
    window("Row39 Garbled Autotest", WINDOW_W, WINDOW_H) do
      vstack(padding: 10.0, spacing: 5.0) do
        text("VirtualMatrix Demo", color: CrymbleUI::Color.new(0, 0, 0, 255), font_scale: 2)
        hstack(spacing: 10.0) do
          text("col_hdr_levels: 2")
          text("row_hdr_levels: 2")
          text("row_hdr_span: 3")
        end
        hstack(spacing: 10.0) do
          text("col_hdr_span: 3")
          text("leaf_row_span: 10")
          text("leaf_col_span: 10")
        end
        text("Size: 92x92")
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(
            adapter: @adapter,
            id: "test_matrix",
            cursor_highlight_delta: -30,
            content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
          ))
        end
        hstack(spacing: 20.0) do
          text("Arrow keys: Navigate")
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

  private def schedule(delay_ms : Int32, &block)
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000), &block)
  end

  private def get_matrix : CrymbleUI::VirtualMatrix?
    find("test_matrix").as?(CrymbleUI::VirtualMatrix)
  end

  private def run_phase
    case @phase
    when Phase::Settle
      log("=== SETTLE ===")
      root.try(&.mark_needs_layout)
      rebuild if root.try(&.needs_layout?)

      # Save initial layer images
      if matrix = get_matrix
        sv = matrix.content_scroll_view
        if sv
          LayerCapture.save_layer_image(sv.content_layer, "/tmp/row39_content_initial.png")
          LayerCapture.save_layer_image(sv.sticky_col_layer, "/tmp/row39_sticky_col_initial.png")
          LayerCapture.save_layer_image(sv.sticky_row_layer, "/tmp/row39_sticky_row_initial.png")
        end
        log("  scroll_offset: #{matrix.scroll_offset}")
        log("  active_cells: #{matrix.active_cells.size}")
      end

      {% if flag?(:cache_validation) %}
        @cv_failures_before_scroll = CrymbleUI::CacheValidation.failures.size
      {% end %}

      @phase = Phase::ScrollDown
      @step = 0
      schedule(500) { run_phase }

    when Phase::ScrollDown
      if @step < SCROLL_STEPS
        do_scroll_step
        @step += 1
        schedule(DELAY_MS) { run_phase }
      else
        log("=== ScrollDown done (#{SCROLL_STEPS} steps) ===")
        @phase = Phase::Capture
        schedule(300) { run_phase }
      end

    when Phase::Capture
      log("=== CAPTURE ===")
      capture_all_layers
      dump_cell_positions
      @phase = Phase::Results
      schedule(300) { run_phase }

    when Phase::Results
      output_results
      @phase = Phase::Done
      schedule(500) { run_phase }

    when Phase::Done
      quit
    end
  end

  private def do_scroll_step
    matrix = get_matrix
    return unless matrix

    abs = matrix.absolute_bounds
    center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)

    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
    rebuild if root.try(&.needs_layout?)

    log("  Step #{@step}: scroll_offset=#{matrix.scroll_offset}")

    {% if flag?(:cache_validation) %}
      failures = CrymbleUI::CacheValidation.failures
      new_count = failures.size - @cv_failures_before_scroll
      if new_count > 0
        new_failures = failures[@cv_failures_before_scroll..]
        new_failures.each do |fail|
          log("    CV MISMATCH: #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame} mismatches=#{fail.mismatch_count}/#{fail.total_pixels}")
        end
        @cv_failures_before_scroll = failures.size
      end
    {% end %}
  end

  private def capture_all_layers
    matrix = get_matrix
    return unless matrix

    sv = matrix.content_scroll_view
    if sv
      LayerCapture.save_layer_image(sv.content_layer, "/tmp/row39_content_after_scroll.png")
      LayerCapture.save_layer_image(sv.sticky_col_layer, "/tmp/row39_sticky_col_after_scroll.png")
      LayerCapture.save_layer_image(sv.sticky_row_layer, "/tmp/row39_sticky_row_after_scroll.png")
      LayerCapture.save_layer_image(sv.sticky_corner_layer, "/tmp/row39_sticky_corner_after_scroll.png")
      log("  Saved layer PNGs to /tmp/row39_*_after_scroll.png")
    end

    log("  (Window screenshot not available — inspect layer PNGs)")
  end

  private def dump_cell_positions
    matrix = get_matrix
    return unless matrix

    File.open("/tmp/row39_cell_positions.log", "w") do |f|
      f.puts "=== Cell Positions After 10 Vertical Scrolls ==="
      f.puts "scroll_offset: #{matrix.scroll_offset}"
      f.puts "active_cells count: #{matrix.active_cells.size}"
      f.puts ""

      # Focus on rows 35-42 (grid rows near the garbled area)
      f.puts "--- Cells near grid row 38 (data row 36 / ruler row 39) ---"
      (35..42).each do |r|
        f.puts "  Grid row #{r} (ruler #{r + 1}):"
        [0, 1, 2, 3].each do |c|
          cell = matrix.active_cells[{r, c}]?
          if cell
            bb = matrix.get_bounding_box({r, c})
            is_compound = bb[0] != bb[1]
            f.puts "    col #{c}: bounds=#{cell.bounds} class=#{cell.class.name.split("::").last} compound=#{is_compound} bb=#{bb}"
          else
            f.puts "    col #{c}: NOT IN active_cells"
          end
        end
      end

      # Check for overlapping cells in col 2 (first data column)
      f.puts ""
      f.puts "--- Y-overlap check (col 2) ---"
      col2_cells = matrix.active_cells.select { |k, _| k[1] == 2 && k[0] >= 2 }.to_a.sort_by { |_, w| w.bounds.y }
      col2_cells.each_cons(2) do |pair|
        key_a, w_a = pair[0]
        key_b, w_b = pair[1]
        bottom_a = w_a.bounds.y + w_a.bounds.height
        gap = w_b.bounds.y - bottom_a
        if gap < -0.5
          f.puts "  OVERLAP: #{key_a} (y=#{w_a.bounds.y.round(1)} h=#{w_a.bounds.height.round(1)}) → #{key_b} (y=#{w_b.bounds.y.round(1)}): overlap=#{(-gap).round(1)}px"
        end
      end

      # Check sticky col 0 cells
      f.puts ""
      f.puts "--- Sticky col 0 cells (sorted by Y) ---"
      col0_cells = matrix.active_cells.select { |k, _| k[1] == 0 }.to_a.sort_by { |_, w| w.bounds.y }
      col0_cells.each do |key, w|
        bb = matrix.get_bounding_box(key)
        f.puts "  #{key}: y=#{w.bounds.y.round(1)} h=#{w.bounds.height.round(1)} w=#{w.bounds.width.round(1)} bb=#{bb}"
      end
    end

    log("  Saved cell positions to /tmp/row39_cell_positions.log")
  end

  private def output_results
    File.open("/tmp/row39_results.log", "w") do |f|
      f.puts "=== Row 39 Garbled Rendering Autotest ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts "Mode: #{mode_string}"
      f.puts "Scroll: #{SCROLL_STEPS} vertical steps down"
      f.puts ""

      {% if flag?(:cache_validation) %}
        failures = CrymbleUI::CacheValidation.failures
        if failures.empty?
          f.puts "Cache Validation: *** NO MISMATCHES ***"
        else
          f.puts "Cache Validation: *** #{failures.size} MISMATCH(ES) ***"
          failures.each_with_index do |fail, i|
            f.puts "  [#{i + 1}] #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame}"
            f.puts "       mismatches=#{fail.mismatch_count}/#{fail.total_pixels}"
            x, y, cached, uncached = fail.first_mismatch
            f.puts "       first_at=(#{x},#{y}) cached=0x#{cached.to_s(16)} uncached=0x#{uncached.to_s(16)}"
          end
        end
      {% else %}
        f.puts "Cache Validation: disabled (build with -Dcache_validation to enable)"
      {% end %}

      f.puts ""
      f.puts "Layer PNGs saved to /tmp/row39_*.png"
      f.puts "Cell positions saved to /tmp/row39_cell_positions.log"
      f.puts ""
      f.puts "Inspect /tmp/row39_content_after_scroll.png for visual garbling near row 39."
      f.puts "Compare with immediate_mode_only build for ground truth."
    end

    puts "\n=== Row 39 Garbled Rendering Autotest ==="
    puts "Mode: #{mode_string}"

    {% if flag?(:cache_validation) %}
      failures = CrymbleUI::CacheValidation.failures
      if failures.empty?
        puts "Cache Validation: NO MISMATCHES"
      else
        puts "Cache Validation: #{failures.size} MISMATCH(ES)"
        failures.first(3).each_with_index do |fail, i|
          puts "  [#{i + 1}] #{fail.cache_level} layer=#{fail.layer_id} frame=#{fail.frame} mismatches=#{fail.mismatch_count}"
        end
      end
    {% end %}

    puts "Results: /tmp/row39_results.log"
    puts "Cell positions: /tmp/row39_cell_positions.log"
    puts "Layer PNGs: /tmp/row39_*_after_scroll.png"
  end

  private def mode_string : String
    {% if flag?(:immediate_mode_only) %}
      "immediate_mode_only"
    {% elsif flag?(:cache_validation) %}
      "cache_validation"
    {% else %}
      "normal (cached)"
    {% end %}
  end

  private def log(msg : String)
    File.open("/tmp/row39_trace.log", "a") { |f| f.puts msg }
    puts msg
  end
end

# Clear logs
File.write("/tmp/row39_trace.log", "")
File.write("/tmp/row39_results.log", "")

app = Row39GarbledAutoTest.new
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
