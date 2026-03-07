require "../../src/crymble-ui"

# Minimal visible cell for autotest pixel scanning (emits fill_rect).
class AutotestCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(text : String = "", id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    size = measure(constraints)
    @bounds = CrymbleUI::Rect.new(position, size)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), CrymbleUI::Color.new(45, 50, 55, 255))
    end
  end
end

# Bug 2 autotest: Buffer origin drift during hscroll
#
# Tests whether viewport_cache buffer_origin drifts after scroll round-trip.
# Captures software-composited window output (what user sees) and counts
# black pixels (window bg showing where cells should be).
#
# Test progression: 3 hops → 2 hops → 1 hop to find minimum reproduction.
# No rebuilds during scroll steps (matches real SFML demo behavior).
#
# Usage:
#   shards build sticky_scroll_autotest
#   DISPLAY=:0 timeout 60 ./bin/sticky_scroll_autotest
#   cat /tmp/sticky_scroll_results.log

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

  # Capture software-composited window output (what the user sees).
  # Overlays layers bottom-to-top: content → sticky_col → sticky_row → sticky_corner
  def self.capture_window_composite(
    content_layer : CrymbleUI::Layer?,
    sticky_col_layer : CrymbleUI::Layer?,
    sticky_row_layer : CrymbleUI::Layer?,
    sticky_corner_layer : CrymbleUI::Layer?,
    window_width : Int32, window_height : Int32,
    bg_rgba : UInt32, step : Int32 = 2
  ) : Array(Tuple(Int32, Int32, UInt32))
    # Start with window background for all sampled positions
    pixels = Hash(Tuple(Int32, Int32), UInt32).new

    # Initialize with background color at sampled positions
    y = 0
    while y < window_height
      x = 0
      while x < window_width
        pixels[{x, y}] = bg_rgba
        x += step
      end
      y += step
    end

    # Overlay layers bottom-to-top
    [content_layer, sticky_col_layer, sticky_row_layer, sticky_corner_layer].each do |layer|
      next unless layer
      visible = capture_layer_visible_region(layer, step)
      layer_x = layer.bounds.x.to_i
      layer_y = layer.bounds.y.to_i

      # For viewport_cache layers, buffer coords must be converted to viewport-relative
      # before mapping to screen. The SFML compositor does this via texture_rect offset;
      # we do it explicitly here.
      vp_offset_x = 0
      vp_offset_y = 0
      if layer.viewport_cache
        vp_offset_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
        vp_offset_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
      end

      visible.each do |lx, ly, rgba|
        # Convert buffer coords to screen coordinates
        # For viewport_cache: subtract viewport offset to get layer-relative, then add layer position
        sx = (lx - vp_offset_x) + layer_x
        sy = (ly - vp_offset_y) + layer_y
        # Snap to step grid for consistent lookup
        sx = (sx // step) * step
        sy = (sy // step) * step
        next if sx < 0 || sy < 0 || sx >= window_width || sy >= window_height
        # Skip transparent pixels (don't overwrite lower layers)
        a = rgba & 0xFF
        pixels[{sx, sy}] = rgba if a > 128
      end
    end

    pixels.map { |(pos, rgba)| {pos[0], pos[1], rgba} }
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

  # Black pixel = window background showing where cells should be
  # Window bg: ~(40,40,40), Cell bg: ~(45,50,55)
  def self.is_black_pixel?(rgba : UInt32) : Bool
    r = ((rgba >> 24) & 0xFF).to_i
    g = ((rgba >> 16) & 0xFF).to_i
    b = ((rgba >> 8) & 0xFF).to_i
    a = (rgba & 0xFF).to_i
    avg = (r + g + b) / 3
    a > 200 && avg < 43
  end

  def self.count_black_pixels(pixels : Array(Tuple(Int32, Int32, UInt32))) : Int32
    pixels.count { |_, _, rgba| is_black_pixel?(rgba) }
  end
end

# Task board adapter (same as virtual_matrix_demo.cr)
class AutotestTaskBoardAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @data : Array(Array(String))
  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))

  def initialize
    @data = [
      ["",         "1-Ready", "1-Ready",   "1-Ready",  "1-Ready", "2-InWork", "2-InWork",  "2-InWork",  "2-InWork",      "3-Done", "3-Done", "3-Done", "3-Done"],
      ["1-High",   "0",       "Carol",     "Audi",     "Design",  "1",        "Alice",     "BMW",       "Code",          "",       "",       "",       ""],
      ["1-High",   "",        "",          "",         "",        "2",        "Carol",     "Audi",      "Architecture",  "",       "",       "",       ""],
    ]

    define_merge({0, 1}, {0, 4})
    define_merge({0, 5}, {0, 8})
    define_merge({0, 9}, {0, 12})
    define_merge({1, 0}, {2, 0})
    define_merge({2, 1}, {2, 4})
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    AutotestCell.new(@data[row]?.try(&.[col]?) || "")
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {[1, 2, 0], [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end

  private def define_merge(top_left : Tuple(Int32, Int32), bottom_right : Tuple(Int32, Int32))
    @merges << {top_left, bottom_right}
  end
end

class StickyScrollAutoTest < CrymbleUI::App
  WINDOW_W = 700
  WINDOW_H = 150
  # Window background packed as RGBA UInt32: rgb(80,80,80) with alpha=255
  # (SFML default bg is darker, but the actual bg color is set in the renderer)
  WINDOW_BG_RGBA = (80_u32 << 24) | (80_u32 << 16) | (80_u32 << 8) | 255_u32

  @adapter = AutotestTaskBoardAdapter.new
  @scheduled_first = false

  # Test state machine
  enum Phase
    Settle       # Phase 0: Initial settle
    Baseline     # Phase 1: Capture baseline at scroll=0
    Test3Hops    # Phase 2: 3 hops right → back → compare
    Reset3       # Phase 3: Reset before 2-hop test
    Test2Hops    # Phase 4: 2 hops right → back → compare
    Reset2       # Phase 5: Reset before 1-hop test
    Test1Hop     # Phase 6: 1 hop right → back → compare
    Ctrl0Fix     # Phase 7: Ctrl+0 fix verification
    Results      # Phase 8: Output results
    Done         # Phase 9: Quit
  end

  @phase = Phase::Settle
  @sub_step = 0  # Sub-step within each phase (scroll steps, settle cycles)
  @scrolling_right = true

  # Captured data
  @baseline_black = 0
  @baseline_buf_origin = CrymbleUI::Vec2.zero

  # Results per hop count: {hops => {black_pixels, buf_origin, delta}}
  @results = Hash(Int32, NamedTuple(black: Int32, buf_origin: CrymbleUI::Vec2, delta: Int32)).new
  @ctrl0_black = 0
  @ctrl0_buf_origin = CrymbleUI::Vec2.zero

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule(30) { run_phase }
    end

    matrix = CrymbleUI::VirtualMatrix.new(adapter: @adapter, id: "task_board")
    matrix.col_width(0, 4.0)
    matrix.row_height(0, 1.5)

    window("Sticky Scroll Autotest", WINDOW_W, WINDOW_H) do
      widget(matrix)
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

  # --- Layer access helpers ---

  private def get_scroll_view : CrymbleUI::ScrollView?
    find("task_board").as?(CrymbleUI::VirtualMatrix).try(&.@content_scroll_view)
  end

  private def get_content_layer : CrymbleUI::Layer?
    find("task_board").as?(CrymbleUI::VirtualMatrix).try(&.content_layer)
  end

  private def get_buf_origin : CrymbleUI::Vec2
    get_content_layer.try(&.buffer_origin) || CrymbleUI::Vec2.zero
  end

  private def get_scroll_offset : CrymbleUI::Vec2
    find("task_board").as?(CrymbleUI::VirtualMatrix).try(&.scroll_offset) || CrymbleUI::Vec2.zero
  end

  # --- Capture helpers ---

  private def capture_composite : Array(Tuple(Int32, Int32, UInt32))
    sv = get_scroll_view
    LayerCapture.capture_window_composite(
      get_content_layer,
      sv.try(&.sticky_col_layer),
      sv.try(&.sticky_row_layer),
      sv.try(&.sticky_corner_layer),
      WINDOW_W, WINDOW_H, WINDOW_BG_RGBA, step: 2
    )
  end

  private def save_layer_images(label : String)
    sv = get_scroll_view
    if sv
      LayerCapture.save_layer_image(sv.sticky_col_layer, "/tmp/sticky_col_#{label}.png")
      LayerCapture.save_layer_image(sv.sticky_row_layer, "/tmp/sticky_row_#{label}.png")
      LayerCapture.save_layer_image(sv.sticky_corner_layer, "/tmp/sticky_corner_#{label}.png")
    end
    LayerCapture.save_layer_image(get_content_layer, "/tmp/content_layer_#{label}.png")
  end

  private def log_state(label : String)
    scroll = get_scroll_offset
    bo = get_buf_origin
    vp_x = (scroll.x - bo.x).round(1)
    vp_y = (scroll.y - bo.y).round(1)
    log("  #{label}: scroll=(#{scroll.x.round(1)},#{scroll.y.round(1)}) buf_origin=(#{bo.x.round(1)},#{bo.y.round(1)}) viewport_in_buf=(#{vp_x},#{vp_y})")
  end

  # --- Scroll helpers ---

  private def scroll_right_one_hop
    handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -10.0), CrymbleUI::Vec2.new(350.0, 75.0), shift: true)
    # Process layout if needed (cell creation triggers NeedsLayout)
    rebuild if root.try(&.needs_layout?)
  end

  private def scroll_left_one_hop
    handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 10.0), CrymbleUI::Vec2.new(350.0, 75.0), shift: true)
    rebuild if root.try(&.needs_layout?)
  end

  # --- Reset (Ctrl+0 simulation) ---

  private def start_reset(next_phase : Phase)
    log("  Resetting (Ctrl+0)...")
    # Mark root AND content_layer for full re-render
    # root.mark_needs_layout triggers rebuild; content_layer.mark_needs_layout
    # ensures viewport_cache buffer_origin is recalculated on next render
    root.try(&.mark_needs_layout)
    find("task_board").as?(CrymbleUI::VirtualMatrix).try(&.content_layer).try(&.mark_needs_layout)
    rebuild if root.try(&.needs_layout?)
    @sub_step = 0
    # Settle over several render cycles
    schedule(50) { settle_reset(next_phase) }
  end

  private def settle_reset(next_phase : Phase)
    @sub_step += 1
    rebuild if root.try(&.needs_layout?)
    if @sub_step < 3
      schedule(50) { settle_reset(next_phase) }
    else
      @phase = next_phase
      @sub_step = 0
      @scrolling_right = true
      schedule(10) { run_phase }
    end
  end

  # --- Main phase dispatcher ---

  private def run_phase
    case @phase
    when Phase::Settle
      log("=== PHASE: SETTLE ===")
      root.try(&.mark_needs_layout)
      rebuild if root.try(&.needs_layout?)
      @phase = Phase::Baseline
      schedule(30) { run_phase }

    when Phase::Baseline
      log("\n=== PHASE: BASELINE (scroll=0) ===")
      log_state("baseline")
      save_layer_images("baseline")
      pixels = capture_composite
      @baseline_black = LayerCapture.count_black_pixels(pixels)
      @baseline_buf_origin = get_buf_origin
      log("  black pixels: #{@baseline_black}")
      @phase = Phase::Test3Hops
      @sub_step = 0
      @scrolling_right = true
      schedule(5) { run_hop_test(3) }

    when Phase::Test3Hops
      run_hop_test(3)
    when Phase::Reset3
      start_reset(Phase::Test2Hops)
    when Phase::Test2Hops
      run_hop_test(2)
    when Phase::Reset2
      start_reset(Phase::Test1Hop)
    when Phase::Test1Hop
      run_hop_test(1)

    when Phase::Ctrl0Fix
      log("\n=== PHASE: CTRL+0 FIX VERIFICATION ===")
      root.try(&.mark_needs_layout)
      find("task_board").as?(CrymbleUI::VirtualMatrix).try(&.content_layer).try(&.mark_needs_layout)
      rebuild if root.try(&.needs_layout?)
      @sub_step = 0
      schedule(50) { settle_ctrl0 }

    when Phase::Results
      output_results
      @phase = Phase::Done
      schedule(10) { run_phase }

    when Phase::Done
      quit
    end
  end

  # --- Hop test: scroll N hops right, then back to 0, capture, compare ---

  private def run_hop_test(n_hops : Int32)
    if @scrolling_right
      if @sub_step < n_hops
        scroll_right_one_hop
        @sub_step += 1
        scroll = get_scroll_offset
        log("  scroll RIGHT hop #{@sub_step}/#{n_hops}: scroll_x=#{scroll.x.round(1)}")
        log_state("  after hop")
        schedule(5) { run_hop_test(n_hops) }
      else
        # Switch to scrolling left
        @scrolling_right = false
        @sub_step = 0
        schedule(5) { run_hop_test(n_hops) }
      end
    else
      # Scroll left: n_hops + extra to ensure we reach 0
      max_left = n_hops + 3
      scroll = get_scroll_offset
      if @sub_step < max_left && scroll.x > 0.01
        scroll_left_one_hop
        @sub_step += 1
        scroll = get_scroll_offset
        log("  scroll LEFT  hop #{@sub_step}/#{max_left}: scroll_x=#{scroll.x.round(1)}")
        log_state("  after hop")
        schedule(5) { run_hop_test(n_hops) }
      else
        # Done scrolling — wait one frame for render to complete, then capture
        schedule(20) { finish_hop_test(n_hops) }
      end
    end
  end

  private def finish_hop_test(n_hops : Int32)
    log("\n=== RESULT: #{n_hops} HOPS RIGHT→BACK ===")
    log_state("after round-trip")
    save_layer_images("#{n_hops}hops")

    pixels = capture_composite
    black = LayerCapture.count_black_pixels(pixels)
    bo = get_buf_origin
    delta = black - @baseline_black

    log("  black pixels: #{black} (baseline=#{@baseline_black}, delta=#{delta >= 0 ? "+" : ""}#{delta})")
    log("  buf_origin drift: #{bo == @baseline_buf_origin ? "NONE" : "(#{bo.x.round(1)},#{bo.y.round(1)}) vs baseline (#{@baseline_buf_origin.x.round(1)},#{@baseline_buf_origin.y.round(1)})"}")

    if delta > 0
      log("  *** BUG DETECTED: +#{delta} black pixels ***")
    else
      log("  OK (no black pixel increase)")
    end

    @results[n_hops] = {black: black, buf_origin: bo, delta: delta}

    # Advance to next phase
    case n_hops
    when 3
      @phase = Phase::Reset3
      @sub_step = 0
      @scrolling_right = true
      schedule(5) { run_phase }
    when 2
      @phase = Phase::Reset2
      @sub_step = 0
      @scrolling_right = true
      schedule(5) { run_phase }
    when 1
      @phase = Phase::Ctrl0Fix
      schedule(5) { run_phase }
    end
  end

  # --- Ctrl+0 settle + capture ---

  private def settle_ctrl0
    @sub_step += 1
    rebuild if root.try(&.needs_layout?)
    if @sub_step < 5
      schedule(50) { settle_ctrl0 }
    else
      log_state("after Ctrl+0")
      save_layer_images("ctrl0")
      pixels = capture_composite
      @ctrl0_black = LayerCapture.count_black_pixels(pixels)
      @ctrl0_buf_origin = get_buf_origin
      log("  black pixels: #{@ctrl0_black} (baseline=#{@baseline_black})")
      if @ctrl0_black <= @baseline_black + 10
        log("  Ctrl+0 restored to baseline")
      else
        log("  *** Ctrl+0 did NOT fully fix: #{@ctrl0_black} vs baseline #{@baseline_black} ***")
      end
      @phase = Phase::Results
      schedule(5) { run_phase }
    end
  end

  # --- Output ---

  private def output_results
    # Find minimum reproduction
    min_repro = nil
    [3, 2, 1].each do |n|
      if r = @results[n]?
        min_repro = n if r[:delta] > 0
      end
    end

    File.open("/tmp/sticky_scroll_results.log", "w") do |f|
      f.puts "=== Bug 2 Autotest: Buffer Origin Drift ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""
      f.puts "BASELINE (scroll=0):"
      f.puts "  buf_origin=(#{@baseline_buf_origin.x.round(1)},#{@baseline_buf_origin.y.round(1)})"
      f.puts "  black pixels: #{@baseline_black}"
      f.puts ""

      [3, 2, 1].each do |n|
        if r = @results[n]?
          bo = r[:buf_origin]
          drifted = bo != @baseline_buf_origin
          f.puts "#{n} HOPS RIGHT->BACK:"
          f.puts "  buf_origin=(#{bo.x.round(1)},#{bo.y.round(1)})#{drifted ? " <- DRIFT!" : ""}"
          f.puts "  black pixels: #{r[:black]} (#{r[:delta] >= 0 ? "+" : ""}#{r[:delta]})"
          f.puts "  #{r[:delta] > 0 ? "*** BUG DETECTED ***" : "OK"}"
          f.puts ""
        end
      end

      f.puts "CTRL+0 FIX:"
      f.puts "  buf_origin=(#{@ctrl0_buf_origin.x.round(1)},#{@ctrl0_buf_origin.y.round(1)})"
      f.puts "  black pixels: #{@ctrl0_black}"
      f.puts "  #{@ctrl0_black <= @baseline_black + 10 ? "OK (restored)" : "STILL BROKEN"}"
      f.puts ""

      if min_repro
        f.puts "*** Minimum reproduction: #{min_repro} hop(s) ***"
      else
        f.puts "*** BUG NOT DETECTED at any hop count ***"
      end
      f.puts ""
      f.puts "See /tmp/sticky_scroll_state.log for detailed trace"
      f.puts "Debug PNGs: /tmp/content_layer_{baseline,Nhops,ctrl0}.png etc."
    end

    # Console summary
    puts "\n=== Bug 2 Autotest: Buffer Origin Drift ==="
    puts "Baseline: #{@baseline_black} black pixels, buf_origin=(#{@baseline_buf_origin.x.round(1)},#{@baseline_buf_origin.y.round(1)})"
    [3, 2, 1].each do |n|
      if r = @results[n]?
        status = r[:delta] > 0 ? "BUG +#{r[:delta]}" : "OK"
        puts "#{n} hops: #{r[:black]} black pixels, buf_origin=(#{r[:buf_origin].x.round(1)},#{r[:buf_origin].y.round(1)}) #{status}"
      end
    end
    puts "Ctrl+0:  #{@ctrl0_black} black pixels, buf_origin=(#{@ctrl0_buf_origin.x.round(1)},#{@ctrl0_buf_origin.y.round(1)})"
    if min_repro
      puts "\n*** Minimum reproduction: #{min_repro} hop(s) ***"
    else
      puts "\n*** Bug not detected ***"
    end
  end

  private def log(msg : String)
    File.open("/tmp/sticky_scroll_state.log", "a") { |f| f.puts msg }
    puts msg
  end
end

File.write("/tmp/sticky_scroll_state.log", "")
File.write("/tmp/sticky_scroll_results.log", "")

app = StickyScrollAutoTest.new
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
