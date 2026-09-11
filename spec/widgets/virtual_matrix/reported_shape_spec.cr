require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# WOLFGANG'S SHAPE — the one pivot every placement report since 2026-09-05 came from.
#
# He used the same simple Shape for days while I kept building approximations of it, so it is a
# named fixture now and the placement claims are asserted against IT, not only against synthetic
# adapters. What his screenshots show:
#
#   ruler | c1        | c2  | c3
#   ------+-----------+-----+---------
#     1   | a  (spans | 1   | A B C D E F G H   <- one multiline value makes this row TALL
#     2   |  rows     | 2   |
#     3   |  1..4)    | 3   |
#     4   |           | 4   |
#     5   | b         | 5   |
#
# The parts that matter and that no synthetic fixture had together: a COMPOUND spanning several
# rows (c1's "a"), a row made TALL by a multiline sibling, single-line labels beside that block,
# and a row ruler — the four things whose vertical positions he kept finding disagreeing.
class ReportedShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@lines : Int32 = 8, @rows : Int32 = 9)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    4
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...4).to_a + [0]}
  end

  # c1 merges rows 1..4 into one compound ("a"); row 5 onwards is its own ("b")
  def cell_get_bounding_box(row : Int32, col : Int32)
    return { {1, 1}, {4, 1} } if col == 1 && row >= 1 && row <= 4
    { {row, col}, {row, col} }
  end

  def cell_natural_size(row : Int32, col : Int32)
    n = row == 1 && col == 3 ? @lines : 1
    {width: 60.0, height: n * 20.0, lines: n}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text =
      if row == 0
        col == 0 ? "" : "c#{col}"
      elsif col == 0
        "#{row}"
      elsif col == 1
        row <= 4 ? "a" : "b"
      elsif col == 3 && row == 1
        (0...@lines).map { |i| ('A' + i).to_s }.join("\n")
      elsif col == 3
        ""
      else
        "#{row}"
      end
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private record Ink, key : Tuple(Int32, Int32), text : String, top : Float64, lines : Int32,
  box_top : Float64, box_h : Float64, compound : Bool = false,
  region_pos : Float64 = 0.0, region_size : Float64 = 0.0

private def reported_matrix(vp_h = 300)
  matrix = CrymbleUI::VirtualMatrix.new(ReportedShape.new, id: "reported")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(700, vp_h)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(700.0, vp_h.to_f64)),
    CrymbleUI::Vec2.zero)
  matrix.pre_render_flush
  {renderer, app, matrix}
end

# IS THIS CELL A COMPOUND? Asked of the GRID, not of the ink region.
#
# `ink_region.compound` was the test until 2026-09-11, and it is not one: a region is an
# implementation signal that is legitimately ABSENT whenever the rule can do nothing to a cell, so
# an optimisation that withdraws it makes every compound look ordinary and silently rewrites what
# these examples measure. The span is a fact about the grid and is always there.
private def compound?(matrix, key) : Bool
  bb = matrix.get_bounding_box(key)
  bb[0][0] != bb[1][0]
end

private def inks(matrix) : Array(Ink)

  found = [] of Ink
  matrix.active_cells.each do |key, w|
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    next if prims.empty?
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_top = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
    r = w.ink_region
    found << Ink.new(key, p.text, box_top + p.position.y, prims.size, box_top, w.bounds.height,
      compound?(matrix, key), r ? r.pos : 0.0, r ? r.size : w.bounds.height)
  end
  found
end

describe "Wolfgang's shape" do
  it "builds what the screenshots show: a compound, a tall row, a block, single lines" do
    _r, _a, m = reported_matrix
    all = inks(m)
    compound = all.find { |i| i.text == "a" }.not_nil!
    block = all.find { |i| i.lines > 1 }
    tall = all.select { |i| i.key[0] == 1 }
    puts "\n  compound 'a' box height #{compound.box_h.round(1)} (spans rows 1..4)"
    puts "  row 1 box height #{tall.first.box_h.round(1)}, block lines #{block.try(&.lines) || 0}"
    block.should_not be_nil, "the fixture must contain a MULTILINE cell, or it is not this shape"
    block.not_nil!.lines.should be > 1
    tall.first.box_h.should be > 60.0, "row 1 must be TALL — that is the whole point of the shape"
  end

  it "the labels of the tall row are level with each other, and with the ruler" do
    # Row 1's own cells and the ruler number beside them. The COMPOUND in c1 is excluded: it names
    # rows 1..4 and is centred in that span (I15), so it is 34.5px below this row's line by design.
    # Wolfgang, 2026-09-10: "of course vcentering was always for compound cells".
    _r, _a, m = reported_matrix
    worst = 0.0
    offenders = [] of String

    (0..40).each do |step|
      m.scroll_offset = CrymbleUI::Vec2.new(0.0, step.to_f64 * 2.0)
      m.pre_render_flush
      band_lo = m.ruler_row_height_pixels + m.sticky_row_height_pixels
      band_hi = m.bounds.height

      singles = inks(m).select { |i| i.lines == 1 && i.key[0] == 1 && !i.compound }
                       .select { |i| i.top + 14.0 > band_lo && i.top < band_hi }
      next unless singles.size > 1
      spread = singles.map(&.top).max - singles.map(&.top).min
      worst = spread if spread > worst
      next if spread <= 1.5
      offenders << "scroll #{step * 2}: " + singles.map { |i| "#{i.key[1]}:#{i.text}@#{i.top.round(1)}" }.join(", ")
    end

    puts "\n  [shape] worst spread among the tall row's labels: #{worst.round(2)}px"
    offenders.should be_empty,
      "the tall row's labels were not level:\n  #{offenders.first(6).join("\n  ")}"
  end

  # WEAK BY CONSTRUCTION, and said so rather than left to look strong: at rest these cells carry
  # NO ink region (ink_region_for returns nil while a region sits wholly inside the band), so their
  # centring comes from the widget's own anchor and not from the placement rule. Breaking the rule
  # outright — placing content at the region top — leaves this at 0.0px. It documents the at-rest
  # look; the LEVELNESS test above is the one that exercises the rule, because scrolling is what
  # brings regions into play.
  it "those labels are CENTRED in the tall row while it is fully visible" do
    _r, _a, m = reported_matrix
    size = CrymbleUI::FontSizing.calculate_size(0)
    line = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
    band_lo = m.ruler_row_height_pixels + m.sticky_row_height_pixels
    worst = 0.0

    # Row-height cells only. A COMPOUND's box spans four rows (230px here) but it centres in its
    # FIRST ROW — that is exactly what keeps it level with its row-mates — so measuring it against
    # its own box asks the wrong question and reports 34.5px of "off-centre" that is the design.
    row_h = inks(m).select { |i| i.key[0] == 1 }.map(&.box_h).min
    inks(m).select { |i| i.lines == 1 && i.key[0] == 1 && i.box_top >= band_lo }
           .select { |i| (i.box_h - row_h).abs < 0.5 }.each do |i|
      centre = i.box_top + (i.box_h - line) / 2.0
      d = (i.top - centre).abs
      worst = d if d > worst
    end

    puts "  [shape] worst off-centre in the tall row: #{worst.round(2)}px"
    worst.should be <= 1.5, "a label in the tall row was not centred (off by #{worst.round(1)}px)"
  end

  it "the tall row's block starts as far from the top as an ordinary row's text does" do
    # Wolfgang, 2026-09-10: "the top y position in the row w/ the multiline cell has more space to
    # the upper grid than other rows; this is a glitch in my eyes as well (but it's not violating
    # levelness, jumps, speed, direction etc.)".
    #
    # He is right, and it is invisible to every other check here: rows quantise to whole frame
    # units, so a row grown to fit a block carries slack, and centring the block put half of it
    # ABOVE. Measured on this shape before the fix: 24.5px above the block against 3px above an
    # ordinary row's text. Reading starts at line 1, so the slack belongs below.
    _r, _a, m = reported_matrix
    gaps = {} of String => Float64
    inks(m).each do |i|
      next if i.key[0] == 0 # the header strip has its own inset
      gaps[i.lines > 1 ? "block" : "single"] ||= i.top - i.box_top if i.lines > 1 || i.box_h < 60.0
    end
    block = gaps["block"]?
    single = gaps["single"]?
    block.should_not be_nil, "the fixture must contain a block"
    single.should_not be_nil, "the fixture must contain an ordinary row"
    puts "\n  [shape] gap above: block #{block.not_nil!.round(1)}px, ordinary row #{single.not_nil!.round(1)}px"
    # 2.5px, and the residue is named rather than rounded away: a block starts at the widget's own
    # inset (5px here) while an ordinary 20px row is TIGHTER than a line plus two insets, so its
    # text sits 2px above that inset. Closing the last 2px needs the default row geometry plumbed
    # into the rule; it was 21.5px before this and 2px after, which is the part that was visible.
    (block.not_nil! - single.not_nil!).abs.should be <= 2.5,
      "the block sits #{(block.not_nil! - single.not_nil!).round(1)}px further from its row's top " \
      "than an ordinary row's text does"
  end

  it "the COMPOUND's label is centred in the SPAN it names — through the rule, not around it" do
    # The strong centring guard. An ordinary cell inside the band carries NO ink region, so its
    # centring comes from the widget's own anchor and breaking the placement rule changes nothing
    # there — the at-rest test above is documentation, not a guard, and says so.
    #
    # A compound always carries a region, so this one runs the rule. It also pins the quantity the
    # arc got wrong for two days: the span (230px here), not the span's first row (161px). A
    # compound labels a GROUP of lines and sits in the middle of the group.
    _r, _a, m = reported_matrix
    size = CrymbleUI::FontSizing.calculate_size(0)
    line = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64

    compound = inks(m).find { |i| i.text == "a" }.not_nil!
    span = compound.region_size
    centre = compound.box_top + compound.region_pos + (span - line) / 2.0

    puts "\n  [shape] compound ink #{compound.top.round(1)}, its span's centre #{centre.round(1)} " \
         "(span #{span.round(1)}px, its first row #{inks(m).select { |i| i.key[0] == 1 }.map(&.box_h).min.round(1)}px)"
    (compound.top - centre).abs.should be <= 1.0,
      "the compound was not centred in its span: #{compound.top.round(1)} against #{centre.round(1)}"
  end
end
