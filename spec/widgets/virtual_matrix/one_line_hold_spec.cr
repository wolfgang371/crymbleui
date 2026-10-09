require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# A REGION GIVES THE BAND NO MORE THAN IT EXCEEDS ONE LINE (PrimitiveBuilder#centred_in's `hold`).
#
# Reported 2026-09-30, embrace, the panel shrunk: "row 8 gets scrolled a few px up until it stays stuck
# and gets hidden by further shrinks; this is ugly". A label was centred in the part of its row still
# showing, so the band's edge walked a one-line row's label across its padding. Decided: a one-line row
# is CUT where it sits, like its background (UC-5); a taller row or a span slides its label by as much as
# it exceeds one line, then leaves with its last line (UC-26) - one continuous rule, no threshold.
#
# Read as the grid paints it: a cell's text against its row, a ruler number against its row, and - where
# the claim is about what the screen shows - pixels. The one-line offsets are MEASURED (a fully visible
# row of the same height in the same frame), never derived from the rule.

class HoldShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  # A sticky header row and a sticky column; `spans` are {top-left, bottom-right} merges.
  def initialize(@rows : Int32 = 30, @cols : Int32 = 6,
                 @spans = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)),
                 @texts = {} of Tuple(Int32, Int32) => String)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    @spans.each do |(tl, br)|
      return {tl, br} if tl[0] <= row <= br[0] && tl[1] <= col <= br[1]
    end
    { {row, col}, {row, col} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: @texts[{row, col}]? || "#{row}.#{col}", multiline: true)
  end
end

private HOLD_W = 600
private HOLD_H = 300

private def hold_matrix(shape = HoldShape.new, heights = {} of Int32 => Float64)
  rows = Array.new(shape.row_count, 1.0)
  heights.each { |r, units| rows[r] = units }
  shape.custom_row_heights = rows
  matrix = CrymbleUI::VirtualMatrix.new(shape, id: "hold")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(HOLD_W, HOLD_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(HOLD_W.to_f64, HOLD_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

private def scroll_to(renderer, app, m, x : Float64, y : Float64) : Nil
  m.scroll_offset = CrymbleUI::Vec2.new(x, y)
  renderer.render_frame(app)
end

# Where a cell's FIRST line of text is painted, in the matrix's space (a content cell paints a whole
# scroll away from its box, which lives in content space).
private def ink_y(m, key) : Float64
  w = m.active_cells[key]
  content = key[0] >= m.sticky_row_count && key[1] >= m.sticky_col_count
  w.absolute_bounds.y - (content ? m.painted_scroll.y : 0.0) +
    w.to_primitives(w.bounds).select(CrymbleUI::DrawText).first.position.y
end

private def number_y(m, row : Int32) : Float64?
  ruler = m.row_ruler_widget.not_nil!
  ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText).find { |t| t.text == "#{row + 1}" }
    .try { |t| ruler.absolute_bounds.y + t.position.y }
end

private def band(m) : {Float64, Float64}
  {m.ruler_row_height_pixels + m.sticky_row_height_pixels, m.bounds.height}
end

# A row's painted BOX: {top, bottom} (the pitch less its gutter).
private def row_box(m, row : Int32) : {Float64, Float64}
  top, pitch = m.painted_row(row)
  {top, top + pitch - m.grid_spacing}
end

# Where a one-line label sits in a one-line row at rest, measured: {text, number} offsets from the row's top.
private def one_line_rest(m, col : Int32) : {Float64, Float64}
  lo, hi = band(m)
  row = (m.sticky_row_count...m.placed_row_sizes.size).find! do |r|
    top, bottom = row_box(m, r)
    top >= lo && bottom <= hi && bottom - top <= m.line_extent && m.active_cells.has_key?({r, col}) &&
      m.get_bounding_box({r, col}) == { {r, col}, {r, col} }
  end
  top = row_box(m, row)[0]
  {ink_y(m, {row, col}) - top, number_y(m, row).not_nil! - top}
end

private def merged?(m, key) : Bool
  bb = m.get_bounding_box(key)
  bb[0] != bb[1]
end

# THE ORDINARY-ROW CLAIM, swept down a grid: every one-line cell an edge cuts keeps its text, and its
# row keeps its number, where they sit in a fully visible row of the same height - and carries NO ink
# region (nothing can move it, so the per-frame region is withdrawn: the inert shortcut). Returns how many
# cuts it judged at each edge.
private def judge_ordinary_edges(renderer, app, m, scrolls : Range(Int32, Int32)) : {Int32, Int32}
  leading = trailing = numbers = 0
  scrolls.each do |s|
    scroll_to(renderer, app, m, 0.0, s.to_f64)
    lo, hi = band(m)
    rest = {} of Float64 => {Float64, Float64}
    cut = [] of {Int32, Int32}
    m.active_cells.each_key do |key|
      row, col = key
      next if row < m.sticky_row_count || col < m.sticky_col_count || merged?(m, key)
      top, bottom = row_box(m, row)
      next if bottom - top > m.line_extent + 0.0001
      if top >= lo && bottom <= hi
        rest[bottom - top] ||= {ink_y(m, key) - top, number_y(m, row).not_nil! - top}
      elsif top < lo < bottom || top < hi < bottom
        cut << key
      end
    end
    cut.each do |key|
      top, bottom = row_box(m, key[0])
      next unless r = rest[bottom - top]?
      leading += 1 if top < lo
      trailing += 1 if bottom > hi
      (ink_y(m, key) - top).should be_close(r[0], 0.001)
      if n = number_y(m, key[0])
        numbers += 1
        (n - top).should be_close(r[1], 0.001)
      end
      m.active_cells[key].ink_region.should be_nil
    end
  end
  (numbers > 0).should be_true # instrument: the cut rows' ruler numbers were judged too
  {leading, trailing}
end

# THE TALLER-ROW CLAIM for row `row` crossing both edges: its label is centred in what shows of the row
# while at least one line of it shows, and once less does, sits in that last line as a one-line label sits
# in its row (so it leaves with it). Exact - a hold taken from the content, or from the pitch, is off.
private def judge_taller_row(renderer, app, m, row : Int32, col : Int32, scrolls : Range(Int32, Int32))
  held = in_last_line = 0
  scroll_to(renderer, app, m, 0.0, 0.0)
  rest, _ = one_line_rest(m, col)
  hold = m.line_extent
  scrolls.each do |s|
    scroll_to(renderer, app, m, 0.0, s.to_f64)
    lo, hi = band(m)
    top, bottom = row_box(m, row)
    next unless m.active_cells.has_key?({row, col})
    shows_lo, shows_hi = Math.max(top, lo), Math.min(bottom, hi)
    next if shows_lo == top && shows_hi == bottom # at rest: not this claim
    next if shows_hi <= shows_lo
    ink = ink_y(m, {row, col})
    if shows_hi - shows_lo >= hold
      held += 1
      ink.should be_close(shows_lo + (shows_hi - shows_lo - hold) / 2.0 + rest, 0.001)
    else
      in_last_line += 1
      line_top = top < lo ? bottom - hold : top
      ink.should be_close(line_top + rest, 0.001)
    end
  end
  {held, in_last_line}
end

describe "a region gives the band no more than it exceeds one line" do
  after_each { CrymbleUI::FontSizing.reset_zoom }

  it "cuts a one-line row where it sits, text and number, at both edges - with no region to carry" do
    renderer, app, m = hold_matrix
    leading, trailing = judge_ordinary_edges(renderer, app, m, 0..60)
    (leading > 10 && trailing > 10).should be_true # instrument: both edges cut rows
  end

  it "holds one line at zoom 1.25 too (the hold scales with the line)" do
    2.times { CrymbleUI::FontSizing.zoom_in }
    CrymbleUI::FontSizing.zoom_factor.should eq(1.25) # instrument
    renderer, app, m = hold_matrix
    leading, trailing = judge_ordinary_edges(renderer, app, m, 0..60)
    (leading > 10 && trailing > 10).should be_true
  end

  it "keeps a row shorter than one line where it sits at rest when an edge cuts it" do
    renderer, app, m = hold_matrix(heights: (1...30).to_h { |r| {r, 0.7} })
    (row_box(m, 1)[1] - row_box(m, 1)[0] < m.line_extent).should be_true # instrument
    leading, trailing = judge_ordinary_edges(renderer, app, m, 0..60)
    (leading > 10 && trailing > 10).should be_true
  end

  it "slides a taller row's label only until one line of it is left, then leaves with that line" do
    renderer, app, m = hold_matrix(heights: {5 => 2.5})
    held, last = judge_taller_row(renderer, app, m, 5, 2, 0..200)
    (held > 10 && last > 10).should be_true
    # and from below: the same row arriving at the trailing edge
    renderer, app, m = hold_matrix(heights: {14 => 2.5})
    held, last = judge_taller_row(renderer, app, m, 14, 2, 0..300)
    (held > 10 && last > 10).should be_true
  end

  it "gives the band only the pixel a row exceeds one line by" do
    renderer, app, m = hold_matrix(heights: {5 => 1.05})
    (row_box(m, 5)[1] - row_box(m, 5)[0] - m.line_extent).should eq(1.0) # instrument: one pixel over
    held, last = judge_taller_row(renderer, app, m, 5, 2, 0..200)
    (held > 0 && last > 10).should be_true
  end

  it "moves a cut row's label continuously as the row is resized across one line" do
    previous = nil.as(Float64?)
    steps = 0
    (16..32).each do |px| # the row's box from 0.8 to 1.6 lines, a pixel at a time
      renderer, app, m = hold_matrix(heights: {5 => px / 20.0})
      top = m.placed_row_start(5) - band(m)[0] + 8.0 # the header cuts 8px off the row
      scroll_to(renderer, app, m, 0.0, top)
      ink = ink_y(m, {5, 2}) - band(m)[0]
      if was = previous
        steps += 1
        (ink - was).abs.should be <= 1.0 + 0.001
      end
      previous = ink
    end
    steps.should eq(16)
  end

  it "cuts a multi-line value in a one-line row with its row, first line included" do
    renderer, app, m = hold_matrix(HoldShape.new(texts: (1...30).to_h { |r| { {r, 2}, "A\nB\nC" } }))
    leading = trailing = 0
    scroll_to(renderer, app, m, 0.0, 0.0)
    rest = ink_y(m, {1, 2}) - row_box(m, 1)[0]
    (0..60).each do |s|
      scroll_to(renderer, app, m, 0.0, s.to_f64)
      lo, hi = band(m)
      m.active_cells.each_key do |key|
        next unless key[1] == 2 && key[0] >= m.sticky_row_count
        top, bottom = row_box(m, key[0])
        next unless top < lo < bottom || top < hi < bottom
        leading += 1 if top < lo
        trailing += 1 if bottom > hi
        (ink_y(m, key) - top).should be_close(rest, 0.001)
      end
    end
    (leading > 10 && trailing > 10).should be_true
  end

  it "cuts a one-row merged cell level with its row-mates" do
    merges = (1...30).map { |r| { {r, 2}, {r, 3} } }
    renderer, app, m = hold_matrix(HoldShape.new(spans: merges))
    judged = 0
    (0..60).each do |s|
      scroll_to(renderer, app, m, 0.0, s.to_f64)
      lo, hi = band(m)
      (m.sticky_row_count...m.placed_row_sizes.size).each do |row|
        top, bottom = row_box(m, row)
        next unless (top < lo < bottom || top < hi < bottom) && m.active_cells.has_key?({row, 2}) &&
                    m.active_cells.has_key?({row, 1})
        judged += 1
        (ink_y(m, {row, 2}) - top).should be_close(ink_y(m, {row, 1}) - top, 0.001)
      end
    end
    judged.should be > 20
  end

  # UC-26: a group's label lands on its last visible row and leaves with it. In a STICKY column the
  # box is pinned (StickyMath.compound_axis) - the pinned floor must give way as the span leaves, or the
  # label stalls at the edge while its last row's number goes on.
  it "lands a span's label on its last row and takes it out with that row, pinned or not" do
    spans = [{ {2, 0}, {4, 0} }, { {8, 2}, {10, 2} }]
    renderer, app, m = hold_matrix(HoldShape.new(spans: spans))
    rest, nrest = one_line_rest(m, 3)
    hold = m.line_extent
    leaving = {0 => 0, 2 => 0}
    (0..260).each do |s|
      scroll_to(renderer, app, m, 0.0, s.to_f64)
      lo, _ = band(m)
      spans.each do |(tl, br)|
        # a merged cell is keyed by whichever of its cells holds it (a handle), not by its top-left
        key = m.active_cells.each_key.find { |k| tl[0] <= k[0] <= br[0] && k[1] == tl[1] }
        next unless key
        bottom = row_box(m, br[0])[1]
        next unless lo < bottom && bottom - lo < hold # less than one line of the span left
        leaving[tl[1]] += 1
        ink = ink_y(m, key)
        ink.should be_close(bottom - hold + rest, 0.001)
        if n = number_y(m, br[0])
          (ink - n).should be_close(rest - nrest, 0.001) # level with its last row's number, as at rest
        end
      end
    end
    (leaving[0] > 10 && leaving[2] > 10).should be_true # instrument: the pinned and the unpinned span left
  end

  # Labels now cross the band's leading edge as their rows leave: the opaque strips over it must hide
  # them - the header row, the column ruler, the corner, the gutters between. Compared as pixels with a
  # frame where nothing is under the strip.
  # (The scrollbars are left out: their thumbs move with the scroll, as they should.)
  it "paints nothing of a leaving row over the sticky strips" do
    renderer, app, m = hold_matrix
    lo, _ = band(m)
    left = m.ruler_col_width_pixels + m.sticky_col_width_pixels
    bar = CrymbleUI::ScrollView::SCROLLBAR_WIDTH.to_i
    strip = ->(x1 : Int32, y1 : Int32) do
      (0...y1).flat_map { |y| (0...x1).map { |x| renderer.backend.get_pixel(x, y) } }
    end
    scroll_to(renderer, app, m, 0.0, 0.0)
    top_at_rest = strip.call(HOLD_W - bar, lo.to_i)
    left_at_rest = strip.call(left.to_i, HOLD_H - bar)
    (1..30).each do |s|
      scroll_to(renderer, app, m, 0.0, s.to_f64)
      strip.call(HOLD_W - bar, lo.to_i).should eq(top_at_rest)
    end
    (1..120).each do |s|
      scroll_to(renderer, app, m, s.to_f64, 0.0)
      strip.call(left.to_i, HOLD_H - bar).should eq(left_at_rest)
    end
  end

  # The ink region is per cell and the content layer is a viewport cache: a row resized to one line
  # while its label is slid must not keep showing the slid label from a stale cache when it comes back.
  it "shows a tall row resized to one line under the header at rest when it is scrolled back" do
    renderer, app, m = hold_matrix(heights: {3 => 2.5})
    lo, _ = band(m)
    top, bottom = row_box(m, 3)
    scroll_to(renderer, app, m, 0.0, 0.0)
    rest = ink_y(m, {3, 2}) - top
    scroll_to(renderer, app, m, 0.0, top - lo + 20.0) # 20px of the row under the header: its label slid
    (ink_y(m, {3, 2}) - row_box(m, 3)[0] > rest + 1.0).should be_true # instrument: the label had slid
    # drag its border up 30px, in the row ruler: 2.5 lines -> 1
    border = row_box(m, 3)[1] + m.grid_spacing / 2.0
    x = m.ruler_col_width_pixels / 2.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(x, border))
    30.times do |i|
      app.handle_mouse_move(CrymbleUI::Vec2.new(x, border - i - 1))
      renderer.render_frame(app)
    end
    app.handle_mouse_up(CrymbleUI::Vec2.new(x, border - 30.0))
    renderer.render_frame(app)
    (row_box(m, 3)[1] - row_box(m, 3)[0]).should eq(m.line_extent) # instrument: resized to one line
    scroll_to(renderer, app, m, 0.0, 0.0)
    shown = (row_box(m, 3)[0].to_i...row_box(m, 3)[1].to_i).flat_map do |y|
      (0...HOLD_W).map { |x| renderer.backend.get_pixel(x, y) }
    end
    fresh_r, fresh_a, fresh_m = hold_matrix
    scroll_to(fresh_r, fresh_a, fresh_m, 0.0, 0.0)
    expected = (row_box(fresh_m, 3)[0].to_i...row_box(fresh_m, 3)[1].to_i).flat_map do |y|
      (0...HOLD_W).map { |x| fresh_r.backend.get_pixel(x, y) }
    end
    shown.should eq(expected)
  end
  # A MULTI-LINE value anchors at its row's top plus the cell's padding and, when it does not fit below that,
  # overflows at the BOTTOM (UC-4: line 1 is never the cut one, and the padding above it is not eaten). A row cell
  # gets an ink region only at an edge, so the region's answer must be the same one - or the value jumps up into
  # its padding the frame an edge touches the row (measured: 5px).
  it "keeps a value overflowing a taller row where it sits at rest, cut by either edge" do
    six = (0...6).map { |i| ('A' + i).to_s }.join("\n")
    renderer, app, m = hold_matrix(HoldShape.new(texts: { {5, 2} => six, {14, 2} => six }), heights: {5 => 2.5, 14 => 2.5})
    rest = ink_y(m, {5, 2}) - row_box(m, 5)[0]
    leading = trailing = 0
    (0..300).each do |s|
      scroll_to(renderer, app, m, 0.0, s.to_f64)
      lo, hi = band(m)
      [5, 14].each do |row|
        next unless m.active_cells.has_key?({row, 2})
        top, bottom = row_box(m, row)
        next unless top < lo < bottom || top < hi < bottom
        leading += 1 if top < lo
        trailing += 1 if bottom > hi
        (ink_y(m, {row, 2}) - top).should be_close(rest, 0.001)
      end
    end
    (rest > 0.0).should be_true # instrument: a padding above the first line at rest
    (leading > 10 && trailing > 10).should be_true
  end

  it "keeps a value overflowing a cut row where it sits as the row is resized across one line" do
    three = "A\nB\nC"
    previous = nil.as(Float64?)
    steps = 0
    (18..26).each do |px|
      renderer, app, m = hold_matrix(HoldShape.new(texts: { {5, 2} => three }), heights: {5 => px / 20.0})
      scroll_to(renderer, app, m, 0.0, m.placed_row_start(5) - band(m)[0] + 4.0) # the header cuts 4px off the row
      offset = ink_y(m, {5, 2}) - row_box(m, 5)[0]
      if was = previous
        steps += 1
        offset.should be_close(was, 0.001)
      end
      previous = offset
    end
    steps.should eq(8)
  end

  # A SPAN's block is placed by its region at rest too (a compound always has one): it stays contained in its box,
  # pulled up into its padding when span less padding is too short for it - and a row's anchor rule must not reach it.
  it "keeps a compound's value that only fits its span by its padding contained" do
    three = "A\nB\nC"
    renderer, app, m = hold_matrix(HoldShape.new(spans: [{ {2, 2}, {3, 2} }], texts: { {2, 2} => three, {8, 2} => three }),
      heights: {8 => 3.0})
    plain = ink_y(m, {8, 2}) - row_box(m, 8)[0] # a row's block at rest: its anchor, the padding
    top = row_box(m, 2)[0]
    bottom = row_box(m, 3)[1]
    extent = CrymbleUI::TextLines.block_extent(3, CrymbleUI::FontSizing.calculate_size(0))
    (bottom - top - extent < plain).should be_true # instrument: the span less its padding cannot hold it
    rest = ink_y(m, {2, 2}) - top
    (rest < plain).should be_true # instrument: so at rest it is pulled up into the padding...
    (rest + extent <= bottom - top + 0.001).should be_true # ...and contained
  end
end
