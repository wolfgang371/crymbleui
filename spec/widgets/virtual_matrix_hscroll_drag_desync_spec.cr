require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"

# Investigation of the horizontal scrollbar DESYNC bug (Wolfgang, 2026-05-29, observed in
# the real SFML app): dragging the horizontal scrollbar shifts the column-header RULER but
# the DATA appears not to follow, so data column separators stop lining up with the ruler.
#
# CONCLUSION OF THIS INVESTIGATION (2026-05-29):
#   The bug does NOT reproduce in the headless renderer. The earlier memory hypothesis
#   ("the scrollbar read-back path never forwards the offset into content_layer.scroll_offset")
#   is DISPROVEN: the real drag path (ScrollView#on_mouse_move → update_visibility_on_scroll →
#   on_scroll_changed → VirtualMatrix#sync_from_scroll_view) updates BOTH @scroll_offset AND
#   @content_layer.scroll_offset and marks the rulers dirty. The column ruler reads
#   matrix.scroll_offset.x (ruler_widget.cr:97/107); the data composites from
#   content_layer.scroll_offset — and both stay coherent.
#
#   Verified by the tests below: after a REAL horizontal scrollbar thumb drag (sticky-ruler
#   "[Commits]" config), the data column shown at every screen pixel matches the column the
#   scroll offset predicts (align_mismatches == 0), identical to the trusted wheel-scroll path,
#   both pre- and post-settle. So the headless TestRenderer renders the drag correctly.
#
#   The visible desync therefore appears to be SFML-backend-specific (per-widget RenderTexture
#   caching / viewport-cache recenter under the real renderer), NOT a logic bug reproducible
#   with the headless TestRenderBackend. Reproducing/fixing it needs the SFML autotest harness
#   or the real app — see memory `virtualmatrix-scroll-ruler-desync-resize-scrollbar-lag`.
#
# These tests are kept as GUARDS: they would catch a regression that broke headless horizontal
# scrollbar-drag rendering (the offset-sync + viewport-cache composite path). They PASS today.

# --- Column-distinct color cells: each column gets a unique color, so a palette lookup maps a
#     composited pixel unambiguously back to its column. Horizontal misplacement is detectable. ---
class HScrollColorCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@fill : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 100.0,
      constraints.max_height.finite? ? constraints.max_height : 20.0)
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

# r = 10,18,...,242 (strictly unique for cols 0..29) ⇒ exact pixel→column lookup.
def hscroll_color_for_col(col : Int32) : CrymbleUI::Color
  CrymbleUI::Color.new(10 + col * 8, 255 - col * 8, (col * 16 + 30) % 256, 255)
end

# Sticky row 0 + col 0 (the embrace [Commits] sticky-ruler config), color by column.
class HScrollStickyAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32 = 20, @cols : Int32 = 30)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # col 0 / row 0 scroll out LAST ⇒ sticky_count = 1 each.
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    HScrollColorCell.new(hscroll_color_for_col(col))
  end
end

class HScrollStickyApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  getter! adapter : HScrollStickyAdapter

  def build : CrymbleUI::Widget
    @adapter = HScrollStickyAdapter.new(rows: 20, cols: 30)
    m = CrymbleUI::VirtualMatrix.new(adapter: @adapter.not_nil!, id: "hsticky")
    # show_rulers defaults true — the [Commits] sticky-ruler configuration.
    m.content_background_color = CrymbleUI::Color.new(0, 0, 0, 255) # black — outside palette
    window("Test", 800, 600) do
      widget(m)
    end
  end
end

HSCROLL_COL_W = 103 # GRID_SPACING(3) + DEFAULT_COLUMN_WIDTH(5.0) * frame_height(20)

private def hscroll_palette : Hash(CrymbleUI::Color, Int32)
  h = {} of CrymbleUI::Color => Int32
  (0...30).each { |c| h[hscroll_color_for_col(c)] = c }
  h
end

# Self-consistent alignment check: across the SCROLLING region (right of the sticky band),
# count screen pixels where the SEEN column color != the column predicted by the current
# scroll offset + geometry + scrollorder. 0 ⇒ data is placed exactly where the offset (and
# therefore the ruler, which reads the same offset) says ⇒ ruler and data are aligned.
private def hscroll_align_mismatches(renderer, m : CrymbleUI::VirtualMatrix) : Int32
  layer = m.content_layer.not_nil!
  pal = hscroll_palette
  scroll_x = m.scroll_offset.x
  band = m.ruler_col_width_pixels + m.sticky_col_width_pixels
  x0 = (layer.bounds.x + band).to_i
  x1 = (layer.bounds.x + layer.bounds.width).to_i
  yscan = (layer.bounds.y + m.ruler_row_height_pixels + m.sticky_row_height_pixels).to_i + 8
  win = renderer.backend
  mismatches = 0
  (x0...x1).each do |px|
    next if px < 0 || px >= win.width || yscan < 0 || yscan >= win.height
    pixel = win.get_pixel(px, yscan)
    next unless pixel
    seen = pal[pixel]?
    next unless seen # skip inter-cell gaps / background
    content_x = scroll_x + (px - layer.bounds.x - band)
    # scrollorder = [1,2,...,29,0]: scrollable display position p ⇒ actual column p+1.
    expected = (content_x / HSCROLL_COL_W).to_i + 1
    mismatches += 1 if seen != expected
  end
  mismatches
end

private def drag_horizontal_thumb(sv : CrymbleUI::ScrollView, thumb_dx : Float64)
  abs = sv.absolute_bounds
  # Thumb sits at local x∈[ARROW_SIZE(16), 16+thumb_width(≥30)) at scroll=0; bottom 16px strip.
  press = CrymbleUI::Vec2.new(abs.x + 20.0, abs.y + abs.height - 8.0)
  sv.on_mouse_down(press)
  sv.on_mouse_move(CrymbleUI::Vec2.new(press.x + thumb_dx, press.y))
  sv.on_mouse_up(CrymbleUI::Vec2.new(press.x + thumb_dx, press.y))
end

describe "VirtualMatrix horizontal scrollbar drag — data stays aligned with ruler (headless guard)" do
  # CONTROL: trusted wheel path. Validates the geometry/scrollorder formula — must be 0.
  it "wheel scroll: every visible data column aligns with the scroll offset", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = HScrollStickyApp.new
    app.build_tree
    renderer.settle_rendering(app)

    center = CrymbleUI::Vec2.new(400.0, 300.0)
    8.times do
      app.find("hsticky").as(CrymbleUI::VirtualMatrix)
        .on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("hsticky").as(CrymbleUI::VirtualMatrix)
    matrix.scroll_offset.x.should be > 100.0
    hscroll_align_mismatches(renderer, matrix).should eq(0)
  end

  # The real gesture. Headless renders this correctly (symptom 1 is SFML-specific), so this
  # PASSES — but it guards against a regression that would break headless drag rendering.
  it "scrollbar thumb drag: every visible data column aligns with the scroll offset", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = HScrollStickyApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("hsticky").as(CrymbleUI::VirtualMatrix)
    sv = matrix.content_scroll_view.not_nil!
    drag_horizontal_thumb(sv, 200.0)
    renderer.render_frame(app)

    matrix = app.find("hsticky").as(CrymbleUI::VirtualMatrix)
    scroll_x = matrix.scroll_offset.x
    scroll_x.should be > 100.0,
      "Thumb drag did not register — scrollbar geometry wrong, fix the gesture not the test"

    # content_layer offset stays coherent with the ruler driver (matrix.scroll_offset)...
    matrix.content_layer.not_nil!.scroll_offset.x.should be_close(scroll_x, 0.5)
    # ...and the composited data columns land exactly where that offset predicts.
    mismatches = hscroll_align_mismatches(renderer, matrix)
    mismatches.should eq(0),
      "Headless drag desync: #{mismatches} pixels in the scrolling region show a column other " \
      "than the one scroll_x=#{scroll_x.round(1)} predicts. If this fails, symptom 1 has become " \
      "headless-reproducible — trace content_layer viewport-cache recenter on the drag path."
  end
end
