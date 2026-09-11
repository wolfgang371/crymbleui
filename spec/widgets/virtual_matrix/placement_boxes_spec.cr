require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# TEXT BOUNDING BOXES — what is actually laid down, not where the rule thinks it goes.
#
# Every other placement spec compares a computed position against a model of where ink belongs, so
# when the model was wrong the test agreed with the bug. That is how a green suite kept shipping
# defects that were obvious on screen: I9 accused the code twice and was itself wrong both times,
# I13 once, the sweep's visibility check once, and I15 reported 0.0px for a misalignment worth 3px.
#
# The fix is to measure the BOX the text occupies — `position` plus `measure_text`, the same
# function the renderer uses — instead of trusting `ref_h`. A glyph clipped by the band, or by its
# own widget, or sitting on a different line from its neighbour, is then a fact about two
# rectangles, with no rule in the middle to be wrong.
#
#   B1  a text box that has room is not cut, by the band or by its own widget
#   B2  the text boxes of one row occupy the SAME rows (one line, not three)
#   B3  a text box never moves further than the input that moved it
#
# Blind spots, stated: headless metrics come from TestFont, so this measures extents and not
# letterforms; and it judges only cells whose text is a single line.

private BOX_W = 640
private BOX_H = 320

class BoxPivot < ConfigurableMatrixAdapter
  def initialize(@lines : Int32 = 6)
    super(1, 1, 1, 1, 5, 3)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return super unless row == 1 && col == 3
    CrymbleUI::TextInput.new(value: (0...@lines).map { |i| ('A' + i).to_s }.join("\n"), multiline: true)
  end
end


private record TextBox, key : Tuple(Int32, Int32), text : String,
  top : Float64, bottom : Float64, cell_top : Float64, cell_bottom : Float64,
  compound : Bool = false


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

private def text_boxes(matrix) : Array(TextBox)
  found = [] of TextBox
  matrix.active_cells.each do |key, w|
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    next unless prims.size == 1
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    # the box the RENDERER will occupy, from the same metric it uses
    extent = CrymbleUI::Widget.measure_text(p.text, p.size).height
    # ON SCREEN, which for a CONTENT cell means subtracting the scroll: `absolute_bounds.y` is the
    # scroll view's CONTENT space there, while a sticky cell's is already the screen. Comparing the
    # two raw made a pinned compound look 3px off its row-mates, growing with scroll — a defect
    # that existed only in this measurement (found 2026-09-09; the fourth time an instrument in
    # this arc accused the code and was itself wrong).
    content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    top = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
    found << TextBox.new(key, p.text, top + p.position.y, top + p.position.y + extent,
      top, top + w.bounds.height, compound?(matrix, key))
  end
  found
end

private def band_of(matrix)
  {matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels, matrix.bounds.height}
end

private def box_matrix
  matrix = CrymbleUI::VirtualMatrix.new(BoxPivot.new, id: "bx")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(BOX_W, BOX_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(BOX_W.to_f64, BOX_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

describe "placement, judged by text bounding boxes" do
  it "B1: a text box with room is not cut, by the band or by its own widget" do
    _r, _a, matrix = box_matrix
    band_lo, band_hi = band_of(matrix)
    cut = [] of String

    (0..90).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64 * 2.0)
      matrix.pre_render_flush
      text_boxes(matrix).each do |t|
        height = t.bottom - t.top
        # room in the band, and room in its own widget: if either cannot hold it, being cut is the
        # honest answer and the rule is not at fault
        visible_lo = Math.max(t.cell_top, band_lo)
        visible_hi = Math.min(t.cell_bottom, band_hi)
        next unless visible_hi - visible_lo >= height
        next if t.top >= visible_lo - 0.6 && t.bottom <= visible_hi + 0.6
        cut << "#{t.key} '#{t.text}' box #{t.top.round(1)}..#{t.bottom.round(1)} cut by " \
               "#{visible_lo.round(1)}..#{visible_hi.round(1)} at scroll #{i * 2}"
      end
    end

    cut.should be_empty, "text boxes cut although they had room:\n  #{cut.first(6).join("\n  ")}"
  end

  it "B2: the text boxes of one row sit on the same line" do
    _r, _a, matrix = box_matrix
    worst = 0.0
    offenders = [] of String

    (0..60).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64 * 2.0)
      matrix.pre_render_flush
      band_lo, band_hi = band_of(matrix)
      # COMPOUNDS EXCLUDED: a compound names a span of lines and is centred in that span
      # (I15), so it is level with its row-mates only while both are held at the band edge --
      # which is B4's question, not this one. Including it here asserted the design this arc
      # briefly had (a compound pushed onto its span's first row) and that Wolfgang rejected on
      # 2026-09-10: "of course vcentering was always for compound cells".
      text_boxes(matrix).reject(&.compound).group_by(&.key.[0]).each do |row, group|
        next unless group.size > 1
        # All in the SAME state — every cell at rest, or every cell pushed. Not "at rest only",
        # which is what this said until #87: the pushed case is where a compound was frozen FLUSH
        # to the band while its plain row-mates stopped a padding short, 12.5px apart, and scoping
        # it out meant the one instrument that could see it never looked. Mixed states are skipped
        # because a row half-pushed legitimately straddles.
        pushed = group.map { |g| g.cell_top < band_lo - 0.5 }
        next unless pushed.all? { |x| x == pushed.first }
        # ...and only among labels that are actually ON SCREEN. Once a row's plain cells have
        # scrolled off the top entirely (measured at y=-35) while its compound stays pinned, the
        # two are not on a line and were never meant to be. Alignment is a claim about what you
        # can see.
        group = group.select { |g| g.bottom > band_lo && g.top < band_hi }
        next unless group.size > 1
        tops = group.map(&.top)
        spread = tops.max - tops.min
        worst = spread if spread > worst
        # One pixel. This bound was 3.5 while a "3px defect" was thought to live here; the defect
        # was in this file — the text top was read from `absolute_bounds.y`, which is the scroll
        # view's CONTENT space for a content cell and the screen for a sticky one, so a pinned
        # compound looked further off its row-mates the further you scrolled. Corrected, the
        # spread is 0.0px across the sweep.
        next if spread <= 1.0
        offenders << "row #{row} at scroll #{i * 2}: " +
                     group.map { |g| "c#{g.key[1]}@#{g.top.round(1)}" }.join(", ")
      end
    end

    puts "\n  [boxes] worst top spread within a row: #{worst.round(2)}px"
    offenders.should be_empty,
      "a row's labels sit on different lines:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "B3: a text box never moves further than the input that moved it" do
    _r, _a, matrix = box_matrix
    previous = {} of Tuple(Int32, Int32) => Float64
    offenders = [] of String

    (0..120).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
      matrix.pre_render_flush
      text_boxes(matrix).each do |t|
        if was = previous[t.key]?
          moved = (t.top - was).abs
          offenders << "#{t.key} moved #{moved.round(1)}px for 1px at scroll #{i}" if moved > 2.5
        end
        previous[t.key] = t.top
      end
    end

    offenders.should be_empty, "text boxes moved further than the input:\n  #{offenders.first(6).join("\n  ")}"
  end
end

# The describe "placement, balance within a row" was here, holding B4 alone: "a compound and its
# plain row-mates are level". It asserted the design this arc briefly had and Wolfgang rejected on
# 2026-09-10 ("of course vcentering was always for compound cells"), and the ONE true claim inside
# it -- #87, a frozen compound going flush to the band while its row-mates stopped a padding short
# -- is now guarded by I14, which covers every region including compounds. Deleted rather than
# rescoped: two instruments for one claim is how the weaker one ends up believed.
#
# I14 could not carry it as it stood: it ran on a fixture too short to scroll and asserted on
# nothing at all. It moved onto PushedShape (this fixture, now in placement_invariants_spec) and
# was verified RED before this deletion was allowed to stand -- 60 frozen labels reached, 28 of
# them compounds, and `pad = 0.0` takes them flush to the band edge and names them.

private class LoggedFrame
  include CrymbleUI::PrimitiveBuilder

  # band 20..129 (109 tall), a 137-tall row, an 8-line block of ~100px, ref_h 14
  def compound_label
    CrymbleUI::Widget::InkRegion.new(-19.855670103092784, 206.0, 0.0, 109.0, true, true)
  end

  def block_cell
    CrymbleUI::Widget::InkRegion.new(0.0, 137.0, 19.0, 128.0, false, false)
  end

  def place(r, content, line)
    held_in_region(natural_in(r, content), r.pos, r.size, content, r.band_lo, r.band_hi,
      line, r.pinned)
  end
end

describe "placement, replayed from the running app" do
  it "B5: a block nearly filling the band shares a centre with a one-line label beside it" do
    # Wolfgang's logged region from the running app (#88/#89): a 100px block of 8 lines in a 109px
    # band, in a 137px row. The defect was that the block was pulled UP to keep it whole while the
    # single-line label beside it, needing no pull, stayed put — a CONSTANT gap at every scroll
    # from 3.3 to 82.7, which is how he spotted it ("it doesn't get any more when I scroll
    # further"). This example asserted "not held above the push target" while a push existed.
    #
    # There is no push now: both are centred in the SAME slice of the same region, so they share a
    # centre exactly, and that is the stronger claim — it is his own rule, "aligned when visible
    # blocks have same height", stated as an equality rather than as a bound.
    f = LoggedFrame.new
    line = 14.0
    r = f.block_cell

    block_top = f.place(r, 100.0, line)
    label_top = f.place(r, line, line)
    block_centre = block_top + 50.0
    label_centre = label_top + line / 2.0

    (block_centre - label_centre).abs.should be <= 1.0,
      "the block and the label beside it did not share a centre: block #{block_top.round(1)}" \
      "..#{(block_top + 100.0).round(1)} (centre #{block_centre.round(1)}) against label at " \
      "#{label_top.round(1)} (centre #{label_centre.round(1)})"
  end
end
