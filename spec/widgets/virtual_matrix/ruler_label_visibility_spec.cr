require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Field report 2026-09-05 (image #38): the row ruler's number for a row TALLER than the viewport is
# not drawn at all. `draw_labels` centres each label in the FULL cell, so once the cell's centre
# scrolls past, the number is emitted off the visible band and clipped away — the one label whose
# whole job is answering "which row am I on".
#
# The rule (Wolfgang, 2026-09-05): the label sits at its region's centre, moved the least amount
# needed to lie inside the part of the region you can see; a region taller than that band puts its
# label at the band's leading edge. One expression, continuous at the crossover:
#
#   anchor = region_pos + (min(region_size, band_size) - label_size) / 2, clamped into the band
#
class TallRowRulerAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

private VIEWPORT_H = 300.0

private def tall_row_matrix(tall_units : Float64 = 12.0)
  adapter = TallRowRulerAdapter.new(12, 3)
  heights = Array.new(12, 1.0)
  heights[0] = tall_units # 12 x frame_height ~ 243px, well over the visible band
  adapter.custom_row_heights = heights
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ruler_label_vis")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(600, VIEWPORT_H.to_i)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, VIEWPORT_H)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

private def row_label_y(matrix, label : String) : Float64?
  ruler = matrix.row_ruler_widget.not_nil!
  ruler.to_primitives(ruler.bounds)
    .select(CrymbleUI::DrawText).find { |t| t.text == label }.try(&.position.y)
end

describe "a ruler number stays inside the visible band" do
  it "keeps the number of a row taller than the viewport on screen" do
    renderer, app, matrix = tall_row_matrix
    band_top = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels

    at_top = row_label_y(matrix, "1")
    at_top.should_not be_nil # instrument: the label exists before scrolling

    # Scroll well inside the tall row: its centre is now far above the band.
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 150.0)
    renderer.settle_rendering(app)

    y = row_label_y(matrix, "1")
    y.should_not be_nil, "the row's number stopped being emitted at all"
    y.not_nil!.should be >= band_top,
      "the number was placed above the visible band (#{y}), where the corner strip covers it"
    y.not_nil!.should be < VIEWPORT_H,
      "the number was placed below the viewport (#{y})"
  end

  it "leaves an ordinary fully-visible row centred as before (control)" do
    renderer, app, matrix = tall_row_matrix
    sizes = matrix.@cached_row_sizes.not_nil!
    band_top = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels

    y = row_label_y(matrix, "2").not_nil! # row 1: an ordinary row, fully visible at scroll 0
    row_top = band_top + sizes[0]
    # Centred in the extent a CELL of that line occupies -- pitch MINUS the gutter -- because the
    # ruler is placed by the same rule as the cells beside it. Centring in the full pitch (what
    # this asserted until 2026-09-08) put every number half a gutter below its own line's cells,
    # at every scroll position; I9 measures that alignment directly now.
    centred = row_top + (sizes[1] - matrix.grid_spacing - CrymbleUI::FontSizing.calculate_size(-2)) / 2.0
    y.should be_close(centred, 1.0),
      "an ordinary row's number moved; only regions that do not fit should be adjusted"
  end

  it "moves continuously as the row grows past the band, with no jump" do
    # The property, not a nicety: vcentered_block_y carries the same guard because a three-regime
    # placement written as separate formulas made text jump a whole line in the running app, and a
    # spec that checks each regime separately cannot see a step between them.
    band_top = 0.0
    previous = nil.as(Float64?)
    biggest_step = 0.0
    (4..24).each do |units|
      _r, _a, m = tall_row_matrix(units.to_f)
      band_top = m.ruler_row_height_pixels + m.sticky_row_height_pixels
      m.scroll_offset = CrymbleUI::Vec2.new(0.0, 60.0)
      m.pre_render_flush
      y = row_label_y(m, "1").not_nil!
      if prev = previous
        biggest_step = {biggest_step, (y - prev).abs}.max
      end
      previous = y
    end
    biggest_step.should be < 12.0,
      "the label jumped #{biggest_step.round(1)}px as the row grew one step — a discontinuity at the fit/no-fit boundary"
  end

  it "never stacks two labels on the same spot at the trailing edge" do
    # Field report 2026-09-05 (image #40): "2" and "3" drawn on top of each other at the bottom of
    # the strip. Clamping a label into the band from BOTH ends pulls every line whose centre falls
    # past the trailing edge up to the same y, so the partially-visible rows there pile up. Only the
    # line straddling the LEADING edge may be clamped — and there is exactly one of those, which is
    # what makes this overlap-free by construction rather than by luck.
    renderer, app, matrix = tall_row_matrix
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 150.0)
    renderer.settle_rendering(app)

    ruler = matrix.row_ruler_widget.not_nil!
    ys = ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText).map { |t| {t.text, t.position.y} }
    ys.size.should be > 1 # instrument: several numbers really are drawn

    font = CrymbleUI::FontSizing.calculate_size(-2)
    collisions = ys.each_combination(2).select { |(a, b)| (a[1] - b[1]).abs < font * 0.8 }.to_a
    collisions.should be_empty,
      "labels overlap: #{collisions.map { |(a, b)| "#{a[0]}@#{a[1].round(1)} vs #{b[0]}@#{b[1].round(1)}" }}"
  end

  it "crosses the edge only while its own line is leaving" do
    # Field report 2026-09-05 (image #41): "scrolls out a bit too far (gets clipped)". Read wrongly
    # at first as "a label must never be clipped", which #42 then contradicted — a label that may
    # never cross the edge can only POP. The real complaint is narrower and is what this asserts:
    # the number went above the edge while its row was still mostly on screen, having detached from
    # the row and jumped to its natural centre. Under push-out it may cross the edge ONLY in the
    # last stretch, when its own line's bottom is within a label's height of the edge.
    renderer, app, matrix = tall_row_matrix
    band_top = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
    font = CrymbleUI::FontSizing.calculate_size(-2)
    row0 = matrix.@cached_row_sizes.not_nil![0].to_f64

    offenders = [] of String
    (0..60).each do |step|
      scroll = step * 4.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll)
      # flush, not settle: the matrix is already built and this only needs the scroll applied.
      # `settle_rendering` renders to quiescence — several full frames — 61 times over, which cost
      # these two tests 95 of the suite's 876 seconds.
      matrix.pre_render_flush
      ruler = matrix.row_ruler_widget.not_nil!
      y = ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText)
        .find { |t| t.text == "1" }.try(&.position.y)
      next unless y && y < band_top
      remaining = (band_top + row0 - scroll) - band_top # how much of row 0 is still below the edge
      offenders << "y=#{y.round(1)} with #{remaining.round(1)}px of the row still visible" if remaining > font + 1.0
    end
    offenders.should be_empty,
      "the number left the band while its row was still on screen: #{offenders.first(4)}"
  end

  it "is pushed out by its own line rather than vanishing at full brightness" do
    # Field report 2026-09-05 (image #42): "one px scroll and it's fully gone (doesn't scroll out
    # any further)". Dropping the label the moment its line could no longer hold it made the number
    # pop: pinned at the edge, pinned, pinned, gone. A sticky label leaves the way its line does —
    # pushed up past the edge, progressively clipped — so there must be frames where it sits
    # PARTLY outside the band, still attached to the line it belongs to.
    renderer, app, matrix = tall_row_matrix
    band_top = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
    font = CrymbleUI::FontSizing.calculate_size(-2)

    partly_out = 0
    last_seen = nil.as(Float64?)
    (0..60).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step * 4.0)
      matrix.pre_render_flush # not settle_rendering: see the note in the sibling loop above
      ruler = matrix.row_ruler_widget.not_nil!
      y = ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText)
        .find { |t| t.text == "1" }.try(&.position.y)
      next unless y
      last_seen = y
      partly_out += 1 if y < band_top && y + font > band_top
    end

    partly_out.should be > 0,
      "the number never crossed the edge — it was pinned and then vanished"
    last_seen.not_nil!.should be < band_top,
      "the last frame that drew the number still had it fully inside the band, i.e. it popped"
  end
end
