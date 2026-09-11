require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Wolfgang's shape of 2026-09-10 (images #93-#96): a row-header column whose groups are SMALL --
# "a" over rows 1..2, "b" over rows 3..5 -- scrolled until each group leaves through the top.
#
# Two reports, one transition:
#   "see how 'a' stays sticky again before scrolling out entirely?"
#   "see how 'a' and '4' don't scroll out level at the end?"
#
# The second is the falsifiable one and it is what this file measures: while exactly ONE row of a
# group is still on screen, the group's label and that row's own cells name the same line, so they
# must sit on it together. Nothing here asserts the RATE of the transition; the sweep owns that.
private VP_W = 400
private VP_H = 220

private class ScrollOutShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def row_count : Int32
    9
  end

  def col_count : Int32
    3
  end

  # one sticky header row, one sticky header column — embrace's pivot in miniature
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...9).to_a + [0], (1...3).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    if col == 1
      return { {1, 1}, {2, 1} } if row >= 1 && row <= 2 # "a"
      return { {3, 1}, {5, 1} } if row >= 3 && row <= 5 # "b"
      return { {6, 1}, {8, 1} } if row >= 6 && row <= 8 # "c"
    end
    { {row, col}, {row, col} }
  end

  def cell_natural_size(row : Int32, col : Int32)
    {width: 40.0, height: 20.0, lines: 1}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text =
      if row == 0
        col == 0 ? "" : "c#{col}"
      elsif col == 0
        "#{row}"
      elsif col == 1
        row <= 2 ? "a" : (row <= 5 ? "b" : "c")
      else
        "#{row}"
      end
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private record Ink, key : Tuple(Int32, Int32), text : String, top : Float64,
  region_lo : Float64, region_hi : Float64, compound : Bool

private def scroll_out_matrix(vp_h = VP_H)
  matrix = CrymbleUI::VirtualMatrix.new(ScrollOutShape.new, id: "scrollout")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, vp_h)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, vp_h.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, vp_h.to_f64)),
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
    next unless prims.size == 1
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_y = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
    r = w.ink_region
    lo = r ? box_y + r.pos : box_y
    hi = r ? box_y + r.pos + r.size : box_y + w.bounds.height
    found << Ink.new(key, p.text, box_y + p.position.y, lo, hi, compound?(matrix, key))
  end
  found
end

private def line_height
  size = CrymbleUI::FontSizing.calculate_size(0)
  (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
end

describe "a small group scrolling out through the top" do
  it "never stalls at the edge while its group leaves, and lands on its last visible row (#93-#96)" do
    # Wolfgang, images #93-#96: "see how 'a' stays sticky again before scrolling out entirely? see
    # how 'a' and '4' don't scroll out level at the end?"
    #
    # BOTH HALVES, and they are not in conflict — which took until 2026-09-11 to establish, because
    # the first half was operationalised wrongly. "Sticky" was read as "its offset inside its own
    # span changes", and the guard here asserted that offset was CONSTANT. That is a different
    # property, and asserting it forced the label to ride its span rigidly, which made it vanish
    # before its group did and therefore made the SECOND half unobservable.
    #
    # Sticky means STOPPED: the label halting at the band edge while the rows keep scrolling. That
    # is what a POSITION clamp does (`band_lo + pad`, the rule at the time of the report). Clamping
    # the REGION instead never halts anything — the label moves at half the scroll for as long as
    # its group is leaving, and arrives centred on whatever is left of it.
    #
    #   measured on this fixture: 50 steps at a mean rate of 0.5, 0 of them stalled, and the label
    #   lands within 1.5px — half a grid gutter — of its last visible row.
    _r, _a, matrix = scroll_out_matrix
    stalls = [] of String
    unlevel = [] of String
    moving = 0
    landings = 0
    prev = {} of String => Float64

    (0..120).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      band_hi = matrix.bounds.height
      all = inks(matrix)

      all.select(&.compound).each do |label|
        next unless label.top > band_lo && label.top < band_hi
        leaving = label.region_lo < band_lo - 0.5

        if leaving && (was = prev[label.text]?)
          moving += 1
          stalls << "scroll #{step}: '#{label.text}' did not move while its group left" \
            if (label.top - was).abs < 0.05
        end
        prev[label.text] = label.top

        # ...and where it ends up: with ONE row of the group still on screen, it is on that row.
        rows = all.reject(&.compound).select do |m|
          m.region_lo >= label.region_lo - 1.0 && m.region_hi <= label.region_hi + 1.0 &&
            m.region_hi > band_lo + 0.5 && m.region_lo < band_hi - 0.5
        end.group_by(&.key.[0])
        next unless rows.size == 1
        landings += 1
        mate = rows.first_value.first
        d = (label.top - mate.top).abs
        unlevel << "scroll #{step}: '#{label.text}' at #{label.top.round(1)}, its last row " \
                   "'#{mate.text}' at #{mate.top.round(1)} (#{d.round(1)}px)" if d > 2.0
      end
    end

    puts "\n  [leaving] steps while a group left: #{moving} (stalled: #{stalls.size}); " \
         "frames down to one row: #{landings} (off its line: #{unlevel.size})"
    moving.should be > 20, "no group was ever observed leaving — the fixture is wrong"
    landings.should be > 5, "no group was ever down to one visible row — the fixture is wrong"
    stalls.should be_empty, "a group's label stalled at the edge:\n  #{stalls.first(6).join("\n  ")}"
    unlevel.should be_empty,
      "a group's label did not land on its last visible row:\n  #{unlevel.first(6).join("\n  ")}"
  end

  it "a group TALLER than the screen centres in the part of it you can see (#99/#100)" do
    # Image #99: scrolled INTO a long group, its label sat hard against the top edge — "placed at
    # the very top, long before being scrolled out — this doesn't look nice". Image #100 is the
    # same clause at the other edge and reads correctly, which is the tell: the label should sit in
    # the middle of what you can SEE of the group, not against whichever edge it reached.
    #
    # Only groups bigger than the band get this. A group you can see all of is not held at all —
    # that is the example above, and it stays at 0.0px of drift.
    _r, _a, matrix = scroll_out_matrix(85)
    worst = 0.0
    checked = 0
    offenders = [] of String

    (0..120).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      band_hi = matrix.bounds.height

      inks(matrix).select(&.compound).each do |label|
        # the span covers the whole band: no part of its own middle is on screen
        next unless label.region_lo < band_lo - 0.5 && label.region_hi > band_hi + 0.5
        checked += 1
        want = band_lo + (band_hi - band_lo - line_height) / 2.0
        delta = (label.top - want).abs
        worst = delta if delta > worst
        next if delta <= 1.5
        offenders << "scroll #{step}: '#{label.text}' at #{label.top.round(1)}, the middle of what " \
                     "you can see of it is #{want.round(1)} (band #{band_lo.round(1)}..#{band_hi.round(1)})"
      end
    end

    puts "\n  [tall-group] frames with the group covering the band: #{checked}; " \
         "worst distance from the middle of the visible part: #{worst.round(2)}px"
    checked.should be > 20, "no group ever covered the band — fixture is wrong"
    offenders.should be_empty,
      "a group's label was not in the middle of what you can see of it:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "a group hanging off the far edge never rides that edge 1:1 as the panel grows (#103/#104)" do
    # Wolfgang, 2026-09-11, growing the Shape: "'a' moves all along the way, as long as its spanned
    # height gets bigger -> good"; "'b' only moves the first half of the full spanned height -> why?"
    #
    # Because 'b' was held by a POSITION cap at the far edge (`band_hi - content`) rather than by a
    # clamp on its REGION. A position cap makes the label ride the edge 1:1 with the panel and then
    # stop dead the instant the span's centre appears — which is, exactly, half the span. Measured
    # at +20px of label per +20px of panel, against +10 for a group whose span exceeds the band.
    #
    # THE RATE IS THE DISCRIMINATOR, and that is what this asserts: centring in a slice whose one
    # end moves gives HALF the input, always; only a position clamp can give the whole of it. 1:1
    # tracking of a viewport edge is the class #74/#75 reported at the other end.
    _r, _a, matrix = scroll_out_matrix(150)
    worst = 0.0
    checked = 0
    offenders = [] of String
    prev = {} of String => Float64

    (150..320).each do |h|
      matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, h.to_f64)),
        CrymbleUI::Vec2.zero)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels

      inks(matrix).select(&.compound).each do |label|
        was = prev[label.text]?
        prev[label.text] = label.top
        next unless was
        next unless label.top > band_lo # on screen at all
        moved = (label.top - was).abs
        next if moved < 0.01
        checked += 1
        worst = moved if moved > worst
        next if moved <= 0.5 + 0.6 # half of the 1px step, plus the drawing grid
        offenders << "panel #{h}: '#{label.text}' moved #{moved.round(1)}px for 1px of panel"
      end
    end

    puts "\n  [grow] label movements watched: #{checked}; worst for 1px of panel: #{worst.round(2)}px"
    checked.should be > 40, "no label ever moved as the panel grew — fixture is wrong"
    offenders.should be_empty,
      "a label tracked the panel edge instead of its own region:\n  #{offenders.first(6).join("\n  ")}"
  end
end
