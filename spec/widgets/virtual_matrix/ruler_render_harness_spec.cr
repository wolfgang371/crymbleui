require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# FUNCTIONAL ruler-render harness.
#
# cv-coherency EXCLUDES sticky layers (its immediate-mode validator mis-positions them), and the other
# ruler specs assert dirty_widgets.size — an INTERNAL proxy that can't tell "ruler re-rendered correctly"
# from "stale cached pixels blitted." This harness closes that gap: it samples the ruler's RENDERED backend
# region before and after a scroll. The column ruler scrolls with X (labels shift), the row ruler with Y. A
# correct re-render SHIFTS the labels/borders → the sampled region DIFFERS; the ruler-desync bug (stale
# cache, no re-render) leaves it IDENTICAL. This is the guard that makes it safe to land the rulers'
# auto-capture (Dynamic + on_dirty) — without it, dirty_widgets.size==1 can pass while the pixels are stale.

private def setup_ruler_matrix(vw = 400.0, vh = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(rows: 40, cols: 40, id: "ruler_harness")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(vw, vh)), CrymbleUI::Vec2.zero)
  {matrix, app}
end

# 2 sticky header rows + cols (mirrors ruler_cursor_nav). With sticky cells, a scroll triggers
# reposition_sticky_cells → mark_needs_clear_and_render (render-all), which WIPES the auto-capture enqueue —
# so the rulers must re-render via render-all here, not via dirty_widgets. This is the case the
# dirty_widgets.size specs couldn't validate functionally.
class StickyRulerHarnessAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@data : Int32 = 30)
    @total = 2 + @data
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    order = (2...@total).to_a + [1, 0]
    {order, order}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("(#{row},#{col})")
  end
end

private def setup_sticky_ruler_matrix(vw = 600.0, vh = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter: StickyRulerHarnessAdapter.new, id: "sticky_ruler_harness")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(vw, vh)), CrymbleUI::Vec2.zero)
  {matrix, app}
end

# Flatten a rectangular region of a layer's rendered backend into a comparable pixel array.
private def capture(layer : CrymbleUI::Layer, x0 : Int32, y0 : Int32, w : Int32, h : Int32)
  backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
  region = [] of CrymbleUI::Color?
  (y0...y0 + h).each do |y|
    (x0...x0 + w).each { |x| region << backend.get_pixel(x, y) }
  end
  region
end

describe "rulers re-render on scroll (functional, sticky-aware)" do
  it "column ruler pixels SHIFT after a horizontal scroll (not stale)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    matrix, app = setup_ruler_matrix
    renderer.settle_rendering(app)

    sv = matrix.content_scroll_view.not_nil!
    col_ruler_layer = sv.sticky_row_layer.not_nil! # the COLUMN ruler lives here (top strip, scrolls X)

    # Sample the ruler's label/border band across the data area (past the corner).
    before = capture(col_ruler_layer, x0: 50, y0: 2, w: 250, h: 14)

    matrix.scroll_offset = CrymbleUI::Vec2.new(220.0, 0.0) # ~2 columns right (cols ~103px)
    renderer.settle_rendering(app)

    after = capture(col_ruler_layer, x0: 50, y0: 2, w: 250, h: 14)
    after.should_not eq(before), "column ruler did not re-render after a horizontal scroll (stale cache / desync)"
  end

  it "row ruler pixels SHIFT after a vertical scroll (not stale)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    matrix, app = setup_ruler_matrix
    renderer.settle_rendering(app)

    sv = matrix.content_scroll_view.not_nil!
    row_ruler_layer = sv.sticky_col_layer.not_nil! # the ROW ruler lives here (left strip, scrolls Y)

    before = capture(row_ruler_layer, x0: 2, y0: 50, w: 14, h: 200)

    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 120.0) # several rows down (rows ~23px)
    renderer.settle_rendering(app)

    after = capture(row_ruler_layer, x0: 2, y0: 50, w: 14, h: 200)
    after.should_not eq(before), "row ruler did not re-render after a vertical scroll (stale cache / desync)"
  end

  it "column ruler re-renders on horizontal scroll WITH sticky cells (the render-all path)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    matrix, app = setup_sticky_ruler_matrix
    renderer.settle_rendering(app)

    sv = matrix.content_scroll_view.not_nil!
    col_ruler_layer = sv.sticky_row_layer.not_nil!
    before = capture(col_ruler_layer, x0: 120, y0: 2, w: 300, h: 14) # past the sticky cols, in the data band

    matrix.scroll_offset = CrymbleUI::Vec2.new(300.0, 0.0)
    renderer.settle_rendering(app)

    after = capture(col_ruler_layer, x0: 120, y0: 2, w: 300, h: 14)
    after.should_not eq(before), "column ruler did not re-render on scroll with sticky cells (stale cache)"
  end

  it "a ruler that does NOT scroll stays IDENTICAL (the harness can detect no-change too)" do
    # Sanity: confirm the comparison isn't trivially always-different. With no scroll, a settled+re-settled
    # column ruler renders the same pixels.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    matrix, app = setup_ruler_matrix
    renderer.settle_rendering(app)

    sv = matrix.content_scroll_view.not_nil!
    col_ruler_layer = sv.sticky_row_layer.not_nil!
    before = capture(col_ruler_layer, x0: 50, y0: 2, w: 250, h: 14)
    renderer.settle_rendering(app) # no scroll between
    after = capture(col_ruler_layer, x0: 50, y0: 2, w: 250, h: 14)
    after.should eq(before)
  end
end
