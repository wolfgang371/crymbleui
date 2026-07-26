require "../../src/crymble-ui"
require "../../src/testing/configurable_matrix_adapter"
require "../../src/testing/layer_capture"

# SFML PARITY SWEEP — the ONE durable cross-backend instrument that replaces the retired one-off
# autotest fleet. It drives REAL SFML rendering (Y-flip FBOs, real GPU sampling, real font/GC cost —
# the things headless TestRenderBackend is unfaithful to) through the three structural configurations
# and the scroll magnitudes that historically produced SFML-only bugs, and asserts on:
#   (1) cv  — the -Dcache_validation immediate-mode validator runs on every viewport_cache content
#             layer (cached buffer vs a fresh to_primitives() re-render): the stale-cache / blit-shift
#             corruption class (row39, vthumb).
#   (2) GAP — black-pixel counting via LayerCapture on the sticky-inclusive WINDOW COMPOSITE (the only
#             sticky-inclusive "what the user sees" view any instrument has): window bg leaking where a
#             cell should be.
#   (2') GARBLE — a content-color probe: the composite over the SCROLL-INVARIANT region (sticky bands
#             for a matrix; the full frame for a returned round-trip) must equal the baseline. Catches
#             wrong-content-right-place (row39's actual symptom) that black-pixels alone cannot see.
#   (3) NON-VACUITY — via the REAL per-frame counters
#       (LayerRenderer.frame_full_recenter_count / frame_blit_shift_count / frame_realloc_count) plus a
#       non-empty rendered-layer sample set and a proof the cv validator actually ran this phase. A phase
#       that renders nothing / recenters nothing where it should is a FAILURE, not a silent green.
#
# Config is the OUTERMOST axis: ONE SFMLRenderer.run session, ONE window; the adapter/root is swapped
# via rebuild between config groups (App#build branches on @config).
#   CONFIG A: default compound+sticky VM (ConfigurableMatrixAdapter(2,2,3,3,10,10), like immediate_mode)
#             — diagonal, pure-V multi-recenter round-trip (10 down + 10 up), pure-V deep scroll into the
#             row-39 band.
#   CONFIG B: TaskBoard-style merged-cell adapter with custom col/row sizes (ported from
#             sticky_scroll_autotest) — pure-H hops (shift+wheel) + a Ctrl+0 reset phase.
#   CONFIG C: plain ScrollView (StatusIndicator + Text, ported from buffer_recenter_autotest) — a small
#             sub-recenter scroll down+up (must NOT recenter — that is its point).
#
# Build (shards has no autotest targets):
#   crystal build --release -Dcache_validation spec/autotest/sfml_parity_autotest.cr -o /tmp/sfml_parity_bin
#   DISPLAY=:0 timeout 180 /tmp/sfml_parity_bin
#   cat /tmp/sfml_parity/summary.txt
# Exit code 0 = all phases green, 1 = at least one phase failed (or a hard error). See tools/sfml-parity.sh.

{% unless flag?(:cache_validation) %}
  {{ raise "sfml_parity_autotest requires -Dcache_validation (the cv validator must actually run)" }}
{% end %}

# ── Session-accumulating counter hook ────────────────────────────────────────────────────────────
# The frame_* counters are RESET at the tail of every SFMLRenderer#render_frame, so a scheduled phase
# callback (which fires between frames) can never read a meaningful per-frame value. We reopen the one
# reset seam to accumulate SESSION totals + a per-phase rendered-layer set BEFORE the zero, then delegate
# to the original via previous_def. This is a pure test-instrument hook: it touches no production storage
# and adds no production behaviour (the sweep binary is the only thing that requires this file).
module CrymbleUI
  module LayerRenderer
    class_property session_full_recenter : Int32 = 0
    class_property session_blit_shift : Int32 = 0
    class_property session_realloc : Int32 = 0
    class_property phase_rendered_layers : Set(String) = Set(String).new

    def self.reset_frame_counters
      @@session_full_recenter += @@frame_full_recenter_count
      @@session_blit_shift += @@frame_blit_shift_count
      @@session_realloc += @@frame_realloc_count
      @@rendered_layer_ids.each { |id| @@phase_rendered_layers.add(id) }
      previous_def
    end
  end
end

# ── Fixtures ─────────────────────────────────────────────────────────────────────────────────────

# CONFIG B: minimal visible merged-cell for pixel scanning (ported from sticky_scroll_autotest).
class ParityCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@fill : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill)
    end
  end
end

# CONFIG B: TaskBoard merged-cell adapter (ported from sticky_scroll_autotest). Distinctive per-band
# solid colors so the GARBLE probe can see wrong-content-right-place in the sticky bands.
class ParityTaskBoardAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  CORNER = CrymbleUI::Color.new(150, 150, 150, 255)
  RHDR   = CrymbleUI::Color.new(120, 180, 240, 255) # blue-ish (row headers, sticky col band)
  CHDR   = CrymbleUI::Color.new(240, 190, 120, 255) # orange-ish (col headers, sticky row band)
  BODY   = CrymbleUI::Color.new(230, 230, 230, 255)

  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))

  def initialize
    define_merge({0, 1}, {0, 4})
    define_merge({0, 5}, {0, 8})
    define_merge({0, 9}, {0, 12})
    define_merge({1, 0}, {2, 0})
    define_merge({2, 1}, {2, 4})
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    fill = if row < 1 && col < 1
             CORNER
           elsif row < 1
             CHDR
           elsif col < 1
             RHDR
           else
             BODY
           end
    ParityCell.new(fill)
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

# CONFIG C: status indicator circle (ported from buffer_recenter_autotest).
class ParityStatusIndicator < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@active = false, @dia = 12.0)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@dia, @dia)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    color = @active ? CrymbleUI::Color.new(100, 255, 100, 255) : CrymbleUI::Color.new(255, 100, 100, 255)
    primitives do
      draw_circle(CrymbleUI::Vec2.new(bounds.width / 2, bounds.height / 2), @dia / 2, color, fill: true)
    end
  end
end

# ── The sweep app ────────────────────────────────────────────────────────────────────────────────
class SFMLParityAutoTest < CrymbleUI::App
  WINDOW_W = 1400
  WINDOW_H =  900
  REPORT   = "/tmp/sfml_parity"

  STEP        =    4 # composite sampling stride (px)
  STEP_MS     =   55 # ms between scroll steps
  SETTLE_MS   =  300 # ms to let the last render land before capture
  SWAP_MS     =  600 # ms after a config swap before baseline

  TOL             =   8 # per-channel pixel tolerance (above AA jitter)
  # GARBLE tolerance = max(floor, fraction): the floor absorbs the ~240px AA-text re-rasterization
  # noise that every re-render produces (measured identical across diagonal/multiV/deepV); the fraction
  # scales with the compared-region size. A real fault (RED-1 blit-shift ≈ 48%, a buffer drift ≈ a whole
  # band) is 10-50x this and trips regardless. Both must be exceeded to fail.
  GARBLE_FLOOR    = 500  # absolute AA-noise tolerance (px)
  GARBLE_FRACTION = 0.05 # + 5% of the compared region
  GAP_ABS_TOL     =  60 # a round-trip fails GAP if black-pixel delta exceeds this AND 25% of baseline

  # Distinctive window bg so a GAP shows as black (avg<43): (30,30,30) leaks through as "black".
  BG      = CrymbleUI::Color.new(30, 30, 30, 255)
  BG_RGBA = (30_u32 << 24) | (30_u32 << 16) | (30_u32 << 8) | 255_u32

  enum Config
    A
    B
    C
  end

  enum Phase
    A_Settle
    A_Baseline
    A_Diagonal
    A_MultiV
    A_DeepV
    B_Swap
    B_Settle
    B_Baseline
    B_HopsH
    B_Ctrl0
    C_Swap
    C_Settle
    C_Baseline
    C_SubRecenter
    Finish
    Done
  end

  @config = Config::A
  @phase = Phase::A_Settle
  @sub_step = 0
  @scheduled_first = false

  @adapter_a = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
  @adapter_b = ParityTaskBoardAdapter.new

  # Baseline composite for the CURRENT config (scroll 0), as {x,y}=>rgba + its black count.
  @baseline_composite = Hash(Tuple(Int32, Int32), UInt32).new
  @baseline_black = 0

  # Per-phase non-vacuity snapshots.
  @rec_full_before = 0
  @rec_shift_before = 0
  @realloc_before = 0
  @cv_failures_before = 0
  @cv_frame_before = 0

  # Move script for the active pattern phase.
  @moves = [] of Tuple(CrymbleUI::Vec2, Bool)

  # Report state.
  @report = [] of String
  @coverage = [] of Tuple(String, String, Bool)
  getter failed : Bool = false

  # Force a known dark window background so GAP detection is meaningful.
  def app_background_color : CrymbleUI::Color?
    BG
  end

  def build : CrymbleUI::Widget
    if @phase == Phase::A_Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!
      schedule(800) { run_phase }
    end

    window("SFML Parity Sweep", WINDOW_W, WINDOW_H) do
      case @config
      when Config::A
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(
            adapter: @adapter_a,
            id: "cfgA_matrix",
            cursor_highlight_delta: -30,
            content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
          ))
        end
      when Config::B
        # Fixed narrow viewport (720px) so the 13 columns OVERFLOW → shift+wheel actually
        # horizontal-scrolls (in the full 1400px window they would all fit → nothing to scroll).
        window_panel(title: "TaskBoard", x: 10.0, y: 10.0, width: 720.0, height: 860.0,
                     resizable: false, id: "cfgB_panel") do
          m = CrymbleUI::VirtualMatrix.new(adapter: @adapter_b, id: "cfgB_matrix")
          m.col_width(0, 4.0)
          m.row_height(0, 1.5)
          widget(m)
        end
      when Config::C
        window_panel(title: "Preview (ScrollView)", x: 20.0, y: 20.0, width: 400.0, height: 400.0,
                     resizable: true, id: "cfgC_panel") do
          vstack(spacing: 10.0, padding: 10.0) do
            text("Scroll test items:", font_scale: -1)
            expanded do
              scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "cfgC_sv") do
                vstack(spacing: 5.0) do
                  30.times do |i|
                    hstack(spacing: 8.0) do
                      widget ParityStatusIndicator.new(active: i.even?, dia: 10.0)
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
  end

  # ── scheduler plumbing ─────────────────────────────────────────────────────────────────────────
  private def scheduler_ready? : Bool
    CrymbleUI::Widget.scheduler
    true
  rescue
    false
  end

  private def schedule(delay_ms : Int32, &block)
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000), &block)
  end

  # ── layer / widget access (config-aware) ───────────────────────────────────────────────────────
  private def current_matrix : CrymbleUI::VirtualMatrix?
    id = @config == Config::A ? "cfgA_matrix" : "cfgB_matrix"
    find(id).as?(CrymbleUI::VirtualMatrix)
  end

  private def current_sv : CrymbleUI::ScrollView?
    case @config
    when Config::A, Config::B then current_matrix.try(&.content_scroll_view)
    else                           find("cfgC_sv").as?(CrymbleUI::ScrollView)
    end
  end

  private def content_layer : CrymbleUI::Layer?
    case @config
    when Config::A, Config::B then current_matrix.try(&.content_layer)
    else                           find("cfgC_sv").as?(CrymbleUI::ScrollView).try(&.content_layer)
    end
  end

  private def content_layer_id : String
    case @config
    when Config::A then "matrix_content_cfgA_matrix"
    when Config::B then "matrix_content_cfgB_matrix"
    else                "scrollview_cfgC_sv"
    end
  end

  private def config_tag : String
    "CONFIG #{@config}"
  end

  # ── capture / diff primitives (LayerCapture is the ONE toolkit) ─────────────────────────────────
  private def capture_composite : Array(Tuple(Int32, Int32, UInt32))
    sv = current_sv
    CrymbleUI::Testing::LayerCapture.capture_window_composite(
      content_layer,
      sv.try(&.sticky_col_layer),
      sv.try(&.sticky_row_layer),
      sv.try(&.sticky_corner_layer),
      WINDOW_W, WINDOW_H, BG_RGBA, step: STEP
    )
  end

  private def to_hash(px : Array(Tuple(Int32, Int32, UInt32))) : Hash(Tuple(Int32, Int32), UInt32)
    h = Hash(Tuple(Int32, Int32), UInt32).new
    px.each { |x, y, rgba| h[{x, y}] = rgba }
    h
  end

  # Positions covered by the given sticky layers, on the STEP grid.
  private def region_of(layers : Array(CrymbleUI::Layer?)) : Set(Tuple(Int32, Int32))
    s = Set(Tuple(Int32, Int32)).new
    layers.each do |l|
      next unless l
      b = l.bounds
      y = (b.y.to_i // STEP) * STEP
      while y < (b.y + b.height).to_i
        x = (b.x.to_i // STEP) * STEP
        while x < (b.x + b.width).to_i
          s << {x, y}
          x += STEP
        end
        y += STEP
      end
    end
    s
  end

  # The sticky band that is INVARIANT under scroll on the given axis (its pixels must equal baseline
  # no matter how far content scrolled — the GARBLE region for a one-way directional scroll):
  #   vertical scroll   → the col-header band (sticky_row, top) + corner stay put; the row-header band
  #                       (sticky_col, left) legitimately scrolls WITH the rows, so it is excluded.
  #   horizontal scroll → the row-header band (sticky_col, left) + corner stay put; sticky_row excluded.
  private def invariant_sticky_region(axis : Symbol) : Set(Tuple(Int32, Int32))
    sv = current_sv
    return Set(Tuple(Int32, Int32)).new unless sv
    case axis
    when :vertical   then region_of([sv.sticky_row_layer, sv.sticky_corner_layer])
    when :horizontal then region_of([sv.sticky_col_layer, sv.sticky_corner_layer])
    else                  Set(Tuple(Int32, Int32)).new
    end
  end

  # {mismatches, compared, first_mismatch_coord} of a capture vs the config baseline.
  private def diff_vs_baseline(now : Hash(Tuple(Int32, Int32), UInt32),
                               restrict : Set(Tuple(Int32, Int32))? = nil) : Tuple(Int32, Int32, Tuple(Int32, Int32)?)
    compared = 0
    mism = 0
    first : Tuple(Int32, Int32)? = nil
    @baseline_composite.each do |pos, brgba|
      next if restrict && !restrict.includes?(pos)
      nrgba = now[pos]?
      next unless nrgba
      compared += 1
      if CrymbleUI::Testing::LayerCapture.pixels_different?(brgba, nrgba, TOL)
        mism += 1
        first ||= pos
      end
    end
    {mism, compared, first}
  end

  # ── scroll drivers ─────────────────────────────────────────────────────────────────────────────
  private def apply_move(mv : Tuple(CrymbleUI::Vec2, Bool))
    delta, shift = mv
    case @config
    when Config::A, Config::B
      if m = current_matrix
        abs = m.absolute_bounds
        c = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
        m.on_mouse_wheel(delta, c, shift: shift)
      end
    when Config::C
      if sv = find("cfgC_sv").as?(CrymbleUI::ScrollView)
        abs = sv.absolute_bounds
        c = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
        sv.on_mouse_wheel(delta, c, shift: shift)
      end
    end
    rebuild if root.try(&.needs_layout?)
  end

  private def v_moves(down : Int32, up : Int32) : Array(Tuple(CrymbleUI::Vec2, Bool))
    Array.new(down) { {CrymbleUI::Vec2.new(0.0, -1.0), false} } +
      Array.new(up) { {CrymbleUI::Vec2.new(0.0, 1.0), false} }
  end

  private def diagonal_moves(out_steps : Int32, back_steps : Int32) : Array(Tuple(CrymbleUI::Vec2, Bool))
    moves = [] of Tuple(CrymbleUI::Vec2, Bool)
    out_steps.times do
      moves << {CrymbleUI::Vec2.new(-1.0, 0.0), false}
      moves << {CrymbleUI::Vec2.new(0.0, -1.0), false}
    end
    back_steps.times do
      moves << {CrymbleUI::Vec2.new(1.0, 0.0), false}
      moves << {CrymbleUI::Vec2.new(0.0, 1.0), false}
    end
    moves
  end

  # Shift+wheel horizontal hops right then (over-)back to 0 (clamp absorbs the overshoot).
  private def h_moves(right : Int32, left : Int32) : Array(Tuple(CrymbleUI::Vec2, Bool))
    Array.new(right) { {CrymbleUI::Vec2.new(0.0, -10.0), true} } +
      Array.new(left) { {CrymbleUI::Vec2.new(0.0, 10.0), true} }
  end

  # ── pattern phase runner ───────────────────────────────────────────────────────────────────────
  private def begin_pattern
    CrymbleUI::LayerRenderer.phase_rendered_layers.clear
    @rec_full_before = CrymbleUI::LayerRenderer.session_full_recenter
    @rec_shift_before = CrymbleUI::LayerRenderer.session_blit_shift
    @realloc_before = CrymbleUI::LayerRenderer.session_realloc
    @cv_failures_before = CrymbleUI::CacheValidation.failures.size
    @cv_frame_before = CrymbleUI::CacheValidation.frame_counter
    @sub_step = 0
  end

  # ── the check, shared by every pattern phase ────────────────────────────────────────────────────
  # round_trip:     content returned to the baseline scroll (compare the WHOLE composite).
  # recenter:       :require | :forbid | :ignore
  # invariant_axis: for a one-way (non-round-trip) scroll, which axis's sticky band stays put
  #                 (:vertical | :horizontal) — the GARBLE region. Ignored when round_trip.
  private def finalize_phase(pattern : String, round_trip : Bool, recenter : Symbol, invariant_axis : Symbol = :none)
    now_px = capture_composite
    now = to_hash(now_px)

    # non-vacuity: something rendered + the cv validator actually ran on the content layer this phase.
    sample = CrymbleUI::LayerRenderer.phase_rendered_layers
    sample_ok = !sample.empty?
    cv_ran = sample.includes?(content_layer_id) && CrymbleUI::CacheValidation.frame_counter > @cv_frame_before

    # (1) cv
    new_fails = CrymbleUI::CacheValidation.failures.size - @cv_failures_before
    cv_ok = new_fails == 0

    # (3) counters
    d_full = CrymbleUI::LayerRenderer.session_full_recenter - @rec_full_before
    d_shift = CrymbleUI::LayerRenderer.session_blit_shift - @rec_shift_before
    d_realloc = CrymbleUI::LayerRenderer.session_realloc - @realloc_before
    recenters = d_full + d_shift
    recenter_ok = case recenter
                  when :require then recenters > 0
                  when :forbid  then recenters == 0
                  else               true
                  end
    realloc_ok = d_realloc == 0

    # (2) GAP
    black = CrymbleUI::Testing::LayerCapture.count_black_pixels(now_px)
    d_black = black - @baseline_black
    gap_ok = if round_trip
               d_black <= GAP_ABS_TOL && d_black <= (@baseline_black // 4 + GAP_ABS_TOL)
             else
               true # a scrolled frame legitimately has different content; GARBLE(sticky) carries it
             end

    # (2') GARBLE
    restrict = round_trip ? nil : invariant_sticky_region(invariant_axis)
    mism, compared, first = diff_vs_baseline(now, restrict)
    garble_tol = {GARBLE_FLOOR, (compared * GARBLE_FRACTION).to_i}.max
    garble_ok = compared > 0 && mism <= garble_tol
    garble_nonvacuous = compared > 0

    ok = cv_ok && gap_ok && garble_ok && sample_ok && cv_ran && recenter_ok && realloc_ok && garble_nonvacuous
    @failed = true unless ok

    first_s = first ? "(#{first[0]},#{first[1]})" : "none"
    line = String.build do |s|
      s << (ok ? "PASS " : "FAIL ")
      s << config_tag << " / " << pattern << " / " << content_layer_id << " : "
      s << "cv=" << (cv_ok ? "OK" : "FAIL") << "(#{new_fails} new) "
      s << "garble=" << (garble_ok ? "OK" : "FAIL") << "(#{mism}/#{compared}#{round_trip ? "" : " sticky"} tol=#{garble_tol} first=#{first_s}) "
      s << "gap=" << (gap_ok ? "OK" : "FAIL") << "(Δblack=#{d_black >= 0 ? "+" : ""}#{d_black}, base=#{@baseline_black}) "
      s << "recenter=" << (recenter_ok ? "OK" : "FAIL") << "(full=#{d_full} shift=#{d_shift} want=#{recenter}) "
      s << "realloc=" << (realloc_ok ? "OK" : "FAIL") << "(#{d_realloc}) "
      s << "sample=" << (sample_ok && cv_ran ? "OK" : "FAIL") << "(#{sample.size} layers, cv_ran=#{cv_ran})"
    end
    @report << line
    log(line)

    unless ok
      # Quantified fault detail + artifact paths.
      detail = "     fault: garble_mismatch=#{mism}/#{compared} first=#{first_s}; " \
               "black_delta=#{d_black}; new_cv_failures=#{new_fails}; recenters(full/shift)=#{d_full}/#{d_shift}"
      @report << detail
      log(detail)
      if new_fails > 0
        CrymbleUI::CacheValidation.failures.last(new_fails).each do |f|
          fx, fy, cached, uncached = f.first_mismatch
          fl = "     cv: #{f.cache_level} layer=#{f.layer_id} frame=#{f.frame} mismatches=#{f.mismatch_count}/#{f.total_pixels} first=(#{fx},#{fy}) cached=0x#{cached.to_s(16)} fresh=0x#{uncached.to_s(16)}"
          @report << fl
          log(fl)
        end
      end
      save_layer_pngs("#{@config}_#{pattern}_FAIL")
      @report << "     artifacts: #{REPORT}/#{@config}_#{pattern}_FAIL_*.png"
    end

    @coverage << {config_tag, pattern, ok}
  end

  private def save_layer_pngs(label : String)
    CrymbleUI::Testing::LayerCapture.save_layer_image(content_layer, "#{REPORT}/#{label}_content.png")
    if sv = current_sv
      CrymbleUI::Testing::LayerCapture.save_layer_image(sv.sticky_col_layer, "#{REPORT}/#{label}_sticky_col.png")
      CrymbleUI::Testing::LayerCapture.save_layer_image(sv.sticky_row_layer, "#{REPORT}/#{label}_sticky_row.png")
      CrymbleUI::Testing::LayerCapture.save_layer_image(sv.sticky_corner_layer, "#{REPORT}/#{label}_sticky_corner.png")
    end
  end

  private def capture_baseline(label : String)
    @baseline_composite = to_hash(capture_composite)
    @baseline_black = CrymbleUI::Testing::LayerCapture.count_black_pixels(@baseline_composite.map { |(p, r)| {p[0], p[1], r} })
    v_inv = invariant_sticky_region(:vertical).size
    h_inv = invariant_sticky_region(:horizontal).size
    log("--- #{config_tag} BASELINE: composite=#{@baseline_composite.size} sampled, black=#{@baseline_black}, invariant(v=#{v_inv} h=#{h_inv}) ---")
  end

  private def do_swap(to : Config, next_phase : Phase)
    @config = to
    root.try(&.mark_needs_layout)
    rebuild
    @phase = next_phase
    schedule(SWAP_MS) { run_phase }
  end

  private def settle_and(next_phase : Phase)
    root.try(&.mark_needs_layout)
    rebuild if root.try(&.needs_layout?)
    content_layer.try(&.mark_needs_clear_and_render)
    @phase = next_phase
    schedule(SETTLE_MS) { run_phase }
  end

  # ── the state machine ──────────────────────────────────────────────────────────────────────────
  private def run_phase
    case @phase
    when Phase::A_Settle
      log("=== #{config_tag} SETTLE ===")
      settle_and(Phase::A_Baseline)

    when Phase::A_Baseline
      capture_baseline("A")
      @phase = Phase::A_Diagonal
      begin_pattern
      @moves = diagonal_moves(20, 20)
      schedule(STEP_MS) { run_phase }

    when Phase::A_Diagonal
      if @sub_step < @moves.size
        apply_move(@moves[@sub_step]); @sub_step += 1
        schedule(STEP_MS) { run_phase }
      else
        schedule(SETTLE_MS) do
          finalize_phase("diagonal", round_trip: true, recenter: :ignore)
          @phase = Phase::A_MultiV
          begin_pattern
          @moves = v_moves(10, 10)
          schedule(STEP_MS) { run_phase }
        end
      end

    when Phase::A_MultiV
      if @sub_step < @moves.size
        apply_move(@moves[@sub_step]); @sub_step += 1
        schedule(STEP_MS) { run_phase }
      else
        schedule(SETTLE_MS) do
          finalize_phase("pure_V_multi_recenter", round_trip: true, recenter: :require)
          @phase = Phase::A_DeepV
          begin_pattern
          @moves = v_moves(24, 0) # deep, one-way: reach the row-39 band
          schedule(STEP_MS) { run_phase }
        end
      end

    when Phase::A_DeepV
      if @sub_step < @moves.size
        apply_move(@moves[@sub_step]); @sub_step += 1
        schedule(STEP_MS) { run_phase }
      else
        schedule(SETTLE_MS) do
          finalize_phase("pure_V_deep_row39", round_trip: false, recenter: :require, invariant_axis: :vertical)
          @phase = Phase::B_Swap
          schedule(STEP_MS) { run_phase }
        end
      end

    when Phase::B_Swap
      log("=== SWAP → #{Config::B} (TaskBoard merged-cell) ===")
      do_swap(Config::B, Phase::B_Settle)

    when Phase::B_Settle
      log("=== #{config_tag} SETTLE ===")
      settle_and(Phase::B_Baseline)

    when Phase::B_Baseline
      capture_baseline("B")
      @phase = Phase::B_HopsH
      begin_pattern
      @moves = h_moves(3, 6)
      schedule(STEP_MS) { run_phase }

    when Phase::B_HopsH
      if @sub_step < @moves.size
        apply_move(@moves[@sub_step]); @sub_step += 1
        schedule(STEP_MS) { run_phase }
      else
        schedule(SETTLE_MS) do
          finalize_phase("pure_H_hops", round_trip: true, recenter: :require)
          @phase = Phase::B_Ctrl0
          schedule(STEP_MS) { run_phase }
        end
      end

    when Phase::B_Ctrl0
      log("=== #{config_tag} CTRL+0 RESET ===")
      begin_pattern
      CrymbleUI::FontSizing.reset_zoom
      root.try(&.mark_needs_layout)
      content_layer.try(&.mark_needs_clear_and_render)
      rebuild if root.try(&.needs_layout?)
      schedule(SETTLE_MS * 2) do
        finalize_phase("ctrl0_reset", round_trip: true, recenter: :ignore)
        @phase = Phase::C_Swap
        schedule(STEP_MS) { run_phase }
      end

    when Phase::C_Swap
      log("=== SWAP → #{Config::C} (plain ScrollView) ===")
      do_swap(Config::C, Phase::C_Settle)

    when Phase::C_Settle
      log("=== #{config_tag} SETTLE ===")
      settle_and(Phase::C_Baseline)

    when Phase::C_Baseline
      capture_baseline("C")
      @phase = Phase::C_SubRecenter
      begin_pattern
      @moves = v_moves(5, 5)
      schedule(STEP_MS) { run_phase }

    when Phase::C_SubRecenter
      if @sub_step < @moves.size
        apply_move(@moves[@sub_step]); @sub_step += 1
        schedule(STEP_MS) { run_phase }
      else
        schedule(SETTLE_MS) do
          finalize_phase("sub_recenter", round_trip: true, recenter: :forbid)
          @phase = Phase::Finish
          schedule(STEP_MS) { run_phase }
        end
      end

    when Phase::Finish
      write_summary
      @phase = Phase::Done
      schedule(300) { run_phase }

    when Phase::Done
      quit
    end
  end

  private def write_summary
    File.open("#{REPORT}/summary.txt", "w") do |f|
      f.puts "=== SFML PARITY SWEEP ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts "Build: -Dcache_validation --release   Window: #{WINDOW_W}x#{WINDOW_H}   step=#{STEP}px tol=#{TOL}"
      f.puts ""
      f.puts "PER-PHASE RESULTS (config x pattern x layer):"
      @report.each { |r| f.puts "  #{r}" }
      f.puts ""
      f.puts "WITNESSED COVERAGE MATRIX (config x pattern):"
      @coverage.each do |cfg, pat, ok|
        f.puts "  [#{ok ? "PASS" : "FAIL"}] #{cfg.ljust(9)} #{pat}"
      end
      f.puts ""
      total = @coverage.size
      passed = @coverage.count { |_, _, ok| ok }
      f.puts "SUMMARY: #{passed}/#{total} phases green"
      f.puts(@failed ? "*** SWEEP FAILED ***" : "*** SWEEP GREEN ***")
    end

    puts "\n=== SFML PARITY SWEEP SUMMARY ==="
    @coverage.each do |cfg, pat, ok|
      puts "  [#{ok ? "PASS" : "FAIL"}] #{cfg.ljust(9)} #{pat}"
    end
    puts(@failed ? "*** SWEEP FAILED — see #{REPORT}/summary.txt ***" : "*** SWEEP GREEN ***")
  end

  private def log(msg : String)
    File.open("#{REPORT}/trace.log", "a") { |f| f.puts msg }
    puts msg
  end
end

Dir.mkdir_p(SFMLParityAutoTest::REPORT)
File.write("#{SFMLParityAutoTest::REPORT}/trace.log", "")

app = SFMLParityAutoTest.new
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

exit(app.failed ? 1 : 0)
