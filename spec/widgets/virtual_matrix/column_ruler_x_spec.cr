require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# THE X AXIS. The regime matrix named it as the largest gap on 2026-09-11: every case in
# docs/PLACEMENT_CASES.md, and every instrument, is about Y.
#
# The gap is narrower than it looks, and worth stating so nobody widens this file by mistake:
# `InkRegion` is a Y-only record, so CELLS do no horizontal region placement at all. Exactly one
# caller places on X — the COLUMN RULER, whose `draw_labels(:col)` runs the same `centred_in` and
# `held_in_region` against the viewport's WIDTH. So that is what there is to guard.
#
# The case asserted is the X twin of #97/#98: a column WIDER than the viewport must still show its
# label. On Y that defect was real and cost 66 off-band placements.
private VP_W = 300
private VP_H = 220

private class WideColumnShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def row_count : Int32
    6
  end

  def col_count : Int32
    5
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...6).to_a + [0], (1...5).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    { {row, col}, {row, col} }
  end

  # column 2 is far wider than the 300px viewport
  def cell_natural_size(row : Int32, col : Int32)
    {width: col == 2 ? 520.0 : 60.0, height: 20.0, lines: 1}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text = row == 0 ? (col == 0 ? "" : "c#{col}") : "#{row},#{col}"
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private def wide_matrix
  matrix = CrymbleUI::VirtualMatrix.new(WideColumnShape.new, id: "widecol")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, VP_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  matrix.pre_render_flush
  {renderer, matrix}
end

describe "the column ruler, on the X axis" do
  it "keeps a column's label on screen while that column is, and never steps (#97/#98's twin)" do
    _r, matrix = wide_matrix
    ruler = matrix.col_ruler_widget.not_nil!
    offband = [] of String
    jumps = [] of String
    checked = 0
    worst_move = 0.0
    prev = {} of String => Float64

    (0..420).each do |sx|
      matrix.scroll_offset = CrymbleUI::Vec2.new(sx.to_f64, 0.0)
      matrix.pre_render_flush
      band_lo = matrix.ruler_col_width_pixels + matrix.sticky_col_width_pixels
      band_hi = matrix.bounds.width

      # where each column actually sits, so a label can be judged against its OWN slice
      widths = matrix.@cached_col_sizes
      acc = matrix.ruler_col_width_pixels + matrix.sticky_col_width_pixels
      spans = {} of String => Tuple(Float64, Float64)
      if widths
        (matrix.sticky_col_count...widths.size).each do |i|
          lo = acc - sx
          spans["c#{i + 1}"] = {lo, lo + widths[i].to_f64 - matrix.grid_spacing}
          acc += widths[i]
        end
      end

      ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText).each do |t|
        x = ruler.bounds.x + t.position.x
        w = CrymbleUI::Widget.measure_text(t.text, t.size).width
        span = spans[t.text]?
        next unless span
        col_lo, col_hi = span
        checked += 1
        # THE FAR EDGE ONLY, for the same reason as on Y: a column LEAVING at the leading edge
        # takes its label with it, and a label whose remaining slice is narrower than the glyph
        # goes out with the column rather than jamming against the sticky strip. Measured here:
        # 27 samples sit a pixel or two left of `band_lo`, every one of them a column on its way
        # out. What must never happen is the other end — a label placed past the right edge, where
        # it is clipped and the header simply looks empty (#97/#98 on Y).
        # ...and only where the column's visible slice can HOLD the label. A column arriving with
        # a sliver showing puts its label at the slice's start and lets it be clipped, appearing
        # progressively exactly as the cells below it do; forcing it wholly into view would make it
        # ride the edge, which is the 1:1 class of #74/#75 and #103/#104. `tall_row_visibility`
        # scopes its Y twin the same way and for the same reason.
        slice_lo = Math.max(col_lo, band_lo)
        slice_hi = Math.min(col_hi, band_hi)
        next if slice_hi - slice_lo < w
        unless x + w <= band_hi + 1.0
          offband << "scroll_x #{sx}: '#{t.text}' at #{x.round(1)}..#{(x + w).round(1)}, " \
                     "band #{band_lo.round(1)}..#{band_hi.round(1)}"
        end
        if was = prev[t.text]?
          moved = (x - was).abs
          worst_move = moved if moved > worst_move
          jumps << "scroll_x #{sx}: '#{t.text}' moved #{moved.round(1)}px for 1px" if moved > 1.0 + 0.6
        end
        prev[t.text] = x
      end
    end

    puts "\n  [col-ruler] labels sampled: #{checked}; off-band: #{offband.size}; " \
         "worst move for 1px of scroll: #{worst_move.round(2)}px"
    checked.should be > 500, "the ruler drew almost nothing — the fixture is wrong"
    offband.should be_empty,
      "a column label was placed where it cannot be seen:\n  #{offband.first(6).join("\n  ")}"
    jumps.should be_empty,
      "a column label stepped:\n  #{jumps.first(6).join("\n  ")}"
  end
end
