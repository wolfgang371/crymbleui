require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# The harness this area should have had from the start.
#
# Every field report here has been a frame-level geometric fact — "it jumps", "it's clipped",
# "it's not there", "they're at different heights" — and every one was found by looking at the
# running app, because the specs asserted single positions in single regimes. This sweeps ONE
# PIXEL at a time and asserts invariants over every label in every frame, so a defect is caught
# wherever it lives rather than only where someone thought to look.
#
#   I4  no two ruler numbers stack                            (#40)
#
# TRIMMED 2026-09-09, and where each claim went — `placement_sweep_spec` asserts these over five
# fixtures and four inputs, where each named case asserted it over one:
#   I1  "nothing moves further than the input"        -> sweep J
#   I3  "never displaced outside its own box"         -> sweep X
#   I2, I8, I11, I12  four instances of "visible when the rule could place it there" -> sweep S
# I10 was trimmed too and RESTORED: breaking its bound left the sweep silent (see its own note).
# Their field reports are not lost: docs/PLACEMENT_CASES.md keeps every case with its origin, and
# the deletions were verified by breaking the rule and watching the sweep fail in their place.
#
# I1 sweeps THREE inputs, because jumps have come from all three: scrolling down, scrolling
# across, and resizing the panel (the multiline cell stepping when the viewport is roundabout its
# height). It reports EVERY violation, not the worst one — several distinct defects have hidden
# behind a single "worst offender" line.

private record Placed, text : String, x : Float64, y : Float64, box : CrymbleUI::Rect,
  region_top : Float64, region_size : Float64, held : Bool
private record Snapshot, input : Float64, items : Array(Placed)

private VP_W = 900
private VP_H = 600

private def demo_matrix(vp_h = VP_H)
  adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10) # the demo's own defaults
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "placement_invariants")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, vp_h)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, vp_h.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

# Every DrawText the matrix draws, in SCREEN coordinates, with the box that emitted it.
# Ruler labels are included and PREFIXED: the rulers live in `layer.widgets`, not `@active_cells`,
# so a harness built only on cells is blind to the very widget #40 was reported against — and the
# prefix keeps a ruler "5" from being matched against a cell whose text is also "5".
private def placed(matrix) : Array(Placed)
  out = [] of Placed
  matrix.active_cells.each do |key, w|
    row, col = key
    content_cell = row >= matrix.sticky_row_count && col >= matrix.sticky_col_count
    dx = content_cell ? matrix.scroll_offset.x : 0.0
    dy = content_cell ? matrix.scroll_offset.y : 0.0
    box = CrymbleUI::Rect.new(w.absolute_bounds.x - dx, w.absolute_bounds.y - dy,
      w.bounds.width, w.bounds.height)
    w.to_primitives(w.bounds).each do |p|
      next unless p.is_a?(CrymbleUI::DrawText)
      next if p.text.empty?
      r = w.ink_region
      r_top = r ? box.y + r.pos : box.y
      r_size = r ? r.size : box.height
      out << Placed.new("cell:#{p.text}", box.x + p.position.x, box.y + p.position.y, box,
        r_top, r_size, !r.nil?)
    end
  end
  {matrix.row_ruler_widget, matrix.col_ruler_widget}.each do |rw|
    next unless rw
    rw.to_primitives(rw.bounds).each do |p|
      next unless p.is_a?(CrymbleUI::DrawText)
      next if p.text.empty?
      out << Placed.new("ruler:#{p.text}", rw.absolute_bounds.x + p.position.x,
        rw.absolute_bounds.y + p.position.y, rw.bounds, rw.absolute_bounds.y, rw.bounds.height,
        false)
    end
  end
  out
end

private def sweep_scroll_y(steps = 120) : Array(Snapshot)
  renderer, app, matrix = demo_matrix
  (0..steps).map do |i|
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
    matrix.pre_render_flush
    Snapshot.new(i.to_f64, placed(matrix))
  end
end

private def sweep_scroll_x(steps = 120) : Array(Snapshot)
  renderer, app, matrix = demo_matrix
  (0..steps).map do |i|
    matrix.scroll_offset = CrymbleUI::Vec2.new(i.to_f64, 0.0)
    matrix.pre_render_flush
    Snapshot.new(i.to_f64, placed(matrix))
  end
end

# The panel being resized — a change in the BAND, not in the scroll. This is the input behind the
# multiline cell stepping when the viewport is roundabout its own height, and no scroll sweep can
# reach it.
private def sweep_height(from = 240, to = 340) : Array(Snapshot)
  renderer, app, matrix = demo_matrix(from)
  matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 40.0)
  (from..to).map do |h|
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, h.to_f64)),
      CrymbleUI::Vec2.zero)
    matrix.pre_render_flush
    Snapshot.new(h.to_f64, placed(matrix))
  end
end

# Everything that moved further than the input did. Reports ALL of them, grouped by label, so one
# run gives the whole inventory instead of a single worst-offender line.
private def jumps(frames : Array(Snapshot), axis : Symbol, tol = 1.5) : Array(String)
  out = [] of String
  previous = nil.as(Snapshot?)
  frames.each do |snap|
    if prev = previous
      allowed = (snap.input - prev.input).abs + tol
      index = {} of String => Placed
      snap.items.each { |p| index[p.text] = p }
      prev.items.each do |old|
        next unless now = index[old.text]?
        moved = axis == :x ? (now.x - old.x).abs : (now.y - old.y).abs
        next if moved <= allowed
        out << "#{old.text} moved #{moved.round(1)}px for #{(snap.input - prev.input).abs.round(1)}px " \
               "at #{snap.input.round(0)}"
      end
    end
    previous = snap
  end
  out
end

private def report(list : Array(String)) : String
  by_label = list.group_by { |l| l.split(' ').first }
  summary = by_label.map { |name, hits| "#{name} (#{hits.size}x, first: #{hits.first})" }
  "#{list.size} violation(s) across #{by_label.size} label(s):\n  #{summary.first(8).join("\n  ")}"
end


# I5 needs a block that genuinely overflows the band — the demo's cells are single-line "(r,c)"
# text, so it cannot express the reported case at all. This mirrors the embrace shape the report
# came from: one tall row whose value is many lines.
class TallValueAdapter
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
    text = row == 0 && col == 0 ? (0...12).map { |i| ('A' + i).to_s }.join("\n") : "#{row},#{col}"
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private def tall_value_sweep(from = 200, to = 300) : Array(Snapshot)
  adapter = TallValueAdapter.new(10, 3)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "tall_value")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, from)
  renderer.settle_rendering(app) # once, to build the tree; the sweep below needs no pixels
  # AUTO-SIZE, not a hand-set height. The row's height is then DERIVED from its content, which is
  # the mechanism the report is about: resize the panel, auto-size re-fits the row, the box
  # changes, and content correctly placed inside a box that just changed size moves with it.
  # Embrace's own harness cannot express this — measure_text returns 0x0 there, so auto-size never
  # expands anything and a fixture built on the reported Shape silently contains no tall row at
  # all (verified: box h=20.0 for an eight-line value). crymbleui's harness has real metrics.
  matrix.auto_size = true
  (from..to).map do |h|
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, h.to_f64)),
      CrymbleUI::Vec2.zero)
    matrix.pre_render_flush
    Snapshot.new(h.to_f64, placed(matrix))
  end
end


# The case NONE of the sweeps crossed: a band that passes through the content's own extent.
#
# The jump lives exactly there — content ceasing to fit the band switches the rule from HELD
# (tracking the band) to NOT MOVED (static), and the two do not meet. Wolfgang's log caught it as
# `cell 0,2  vp_h 145->144  box_y +0  box_h +0  ink +6`: one pixel of viewport, six pixels of ink,
# with the box provably unchanged. Every earlier fixture either never crossed the boundary or had
# a box so much larger than its content that the two branches nearly agreed.
#
# Proportions are taken from that log, not invented: a block of ~8 lines in a box ~16px taller
# than it, and a sweep whose band passes straight through the block's extent.
private def band_crossing_sweep(from = 110, to = 230) : Array(Snapshot)
  adapter = TallValueAdapter.new(10, 3)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "band_crossing")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, from)
  matrix.auto_size = true
  renderer.settle_rendering(app)
  (from..to).map do |h|
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, h.to_f64)),
      CrymbleUI::Vec2.zero)
    matrix.pre_render_flush
    Snapshot.new(h.to_f64, placed(matrix))
  end
end

# --- The three cases from docs/PLACEMENT_CASES.md that the hold got wrong. -----------------
#
# A shared fixture: row 0 is TALL because ONE of its cells is a 12-line block, and the other two
# cells in that row hold a single line each. That is #78 exactly — a box made tall by a sibling.
# A shape that actually PUSHES: a sticky header row, a compound spanning rows 1..3, and a 7-line
# block making row 1 tall — so scrolling drives a compound and its plain row-mates under the header
# together. Every other fixture in this file scrolls its rows clean off the top instead, which is
# why I14 examined 202 cells and asserted on none of them (measured 2026-09-10).
class PushedShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def row_count : Int32
    6
  end

  def col_count : Int32
    4
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...6).to_a + [0], (1...4).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    return { {1, 1}, {3, 1} } if col == 1 && row >= 1 && row <= 3 # c1 spans rows 1..3
    { {row, col}, {row, col} }
  end

  def cell_natural_size(row : Int32, col : Int32)
    lines = row == 1 && col == 3 ? 7 : 1
    {width: 40.0, height: lines * 20.0, lines: lines}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text =
      if row == 0
        col == 0 ? "" : "c#{col}"
      elsif col == 0
        "#{row}"
      elsif col == 1
        "a"
      elsif col == 3 && row == 1
        (0...7).map { |i| ('A' + i).to_s }.join("\n")
      else
        "#{row}"
      end
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private def pushed_matrix(vp_h = 160)
  matrix = CrymbleUI::VirtualMatrix.new(PushedShape.new, id: "pushed")
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

private def tall_row_matrix(vp_h = 300)
  matrix = CrymbleUI::VirtualMatrix.new(TallValueAdapter.new(6, 3), id: "tall_row")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, vp_h)
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

private def one_line_cells(matrix, &block)
  matrix.active_cells.each do |key, w|
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    next unless prims.size == 1
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    content_cell = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_y = w.bounds.y - (content_cell ? matrix.scroll_offset.y : 0.0)
    yield key, w, p, box_y
  end
end

private def line_height
  size = CrymbleUI::FontSizing.calculate_size(0)
  (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
end


describe "placement invariants, swept one pixel at a time" do
  it "I5: resizing the panel never moves content DISCONTINUOUSLY inside its box" do
    # Not "never moves": with auto-size on, a taller panel grows the rows, and content centred in
    # a taller box correctly sits further from its top. An earlier version of this example
    # asserted a CONSTANT offset and fired on exactly that legitimate re-centring — 2px of drift
    # over 18px of resize. Absolute where the property is a RATE, which is the same mistake that
    # let three earlier tests agree with a defect.
    #
    # What must hold is continuity: one pixel of resize may not move content inside its box by
    # more than the box itself changed. That permits re-centring and forbids the step reported as
    # "making shape less tall: 1/c3 gets scrolled up a bit, then stays sticky".
    offenders = [] of String
    previous = nil.as(Hash(String, Tuple(Float64, Float64))?)

    tall_value_sweep.each do |snap|
      current = {} of String => Tuple(Float64, Float64)
      snap.items.each do |p|
        next unless p.text.starts_with?("cell:")
        next if p.box.height <= 0.0
        current[p.text] = {p.y - p.box.y, p.box.height}
      end

      if prev = previous
        current.each do |text, (offset, box_h)|
          next unless old = prev[text]?
          allowed = (box_h - old[1]).abs + 1.5
          moved = (offset - old[0]).abs
          next if moved <= allowed
          offenders << "#{text} moved #{moved.round(1)}px inside its box at height " \
                       "#{snap.input.round(0)} while the box changed #{(box_h - old[1]).round(1)}px"
        end
      end
      previous = current
    end

    offenders.should be_empty,
      "content stepped inside its own cell on resize:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "I6: content does not step as the band crosses its own extent" do
    # The boundary itself, swept a pixel at a time. Reported 2026-09-07 from the running app:
    # the value's ink moved 6px for 1px of panel height with its box unchanged.
    offenders = [] of String
    previous = nil.as(Hash(String, Tuple(Float64, Float64, Float64))?)

    band_crossing_sweep.each do |snap|
      current = {} of String => Tuple(Float64, Float64, Float64)
      snap.items.each do |p|
        next unless p.text.starts_with?("cell:")
        next if p.box.height <= 0.0
        current[p.text] = {p.y - p.box.y, p.box.height, p.box.y}
      end
      if prev = previous
        current.each do |text, cur|
          next unless old = prev[text]?
          # What the box itself explains: half of any height change (content stays centred) plus
          # any movement of the box. Anything beyond that is the RULE stepping.
          explained = (cur[1] - old[1]).abs / 2.0 + (cur[2] - old[2]).abs + 1.5
          moved = (cur[0] - old[0]).abs
          next if moved <= explained
          offenders << "#{text} ink moved #{moved.round(1)}px at height #{snap.input.round(0)} " \
                       "(box_h #{(cur[1] - old[1]).round(1)}, box_y #{(cur[2] - old[2]).round(1)})"
        end
      end
      previous = current
    end

    offenders.should be_empty,
      "content stepped as the band crossed its extent:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "I7: ink that moved since the last frame is repainted on the frame it moves" do
    # The licence for update_ink_regions NOT repainting a cell. Until 2026-09-12 this asserted the
    # MECHANISM of the day -- "every cell entering the band is marked" -- which the pass no longer
    # does, and correctly: a cell can enter the band with ink that never moved, and repainting it
    # is waste. (Measured before weakening the claim: cell {25,2} enters at scroll 18 having held
    # local ink 0.0 since scroll 0.) So this asserts the property underneath both mechanisms.
    #
    # A cell's cached pixels are its own rendering. If its ink sits somewhere new this frame, the
    # cache drawn last frame shows the old place, and only `mark_needs_render` rebuilds it -- so
    # ink that moved unmarked is a stale cache, wherever the box happens to be. Visibility is
    # deliberately NOT a condition: `handle_viewport_cache_scroll` blit-shifts the content layer's
    # buffer, carrying pixels of cells outside the band back into view without re-rendering them.
    #
    # THE STEP SIZE IS PART OF THE FIXTURE. Swept 3px at a time this guard is green against the
    # very defect it exists for, because a cell reaches its clamp while still in the band and its
    # ink is already at rest by the time it leaves: measured over four sweep shapes, 0 off-band
    # moves in ~1100 moves. One wheel event is ~50px, and a cell crossing out in a single frame
    # takes its ink with it -- same fixture, step 50: 253 off-band moves. The pixel gate
    # (cache_validation_spec, -Dcache_validation) found the 2026-09-10 defect for exactly this
    # reason: it scrolls by wheel events. So the sweep below mixes both, and the counters at the
    # end fail the test if a future change flattens either class back to zero.
    #
    # Compared frame-to-frame, never against a re-render, so it cannot be satisfied by recomputing
    # both sides -- which left two earlier drafts green with `mark_needs_render` deleted outright.
    renderer, app, matrix = demo_matrix
    steps = [] of Tuple(Float64, Float64)
    (0..60).each { |i| steps << {0.0, i.to_f64 * 3.0} }          # fine: in-band movement
    (0..18).each { |i| steps << {0.0, i.to_f64 * 50.0} }         # wheel-sized: crossings
    (0..18).each { |i| steps << {i * 50.0, 900.0 - i * 50.0} }   # diagonal, and back up
    offenders = [] of String
    previous = {} of Tuple(Int32, Int32) => Float64
    moved_in_band = 0
    moved_off_band = 0

    steps.each do |(sx, sy)|
      matrix.scroll_offset = CrymbleUI::Vec2.new(sx, sy)
      matrix.pre_render_flush # marks; the render below then consumes them, as a real frame does
      lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      hi = matrix.bounds.height
      matrix.active_cells.each do |key, w|
        row, col = key
        next unless row >= matrix.sticky_row_count && col >= matrix.sticky_col_count
        marked = w.needs_render? # BEFORE to_primitives, which rebuilds and clears it
        ink = w.to_primitives(w.bounds).select(CrymbleUI::DrawText).first?.try(&.position.y)
        next unless ink
        ink -= w.bounds.y # local to the cell: what its own cached surface holds
        box_top = w.bounds.y - sy
        if (was = previous[key]?) && (was - ink).abs > 0.5
          if box_top >= hi || box_top + w.bounds.height <= lo
            moved_off_band += 1
          else
            moved_in_band += 1
          end
          unless marked
            offenders << "cell #{key} moved its ink #{was.round(1)} -> #{ink.round(1)} at scroll " \
                         "#{sx.to_i},#{sy.to_i} (box_top #{box_top.round(1)}) without being repainted"
          end
        end
        previous[key] = ink
      end
      renderer.render_frame(app)
    end

    moved_in_band.should be > 100, "no ink moved inside the band -- the sweep stopped exercising it"
    moved_off_band.should be > 20,
      "no ink moved OUTSIDE the band: the sweep can no longer express the defect this guards " \
      "(a cell leaving with its ink, whose pixels the viewport cache blits back into view)"
    offenders.should be_empty,
      "a cell kept a cache of ink it no longer draws:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "I9: a ruler number and the cells of the line it names sit on one line" do
    # The #45 defect itself -- "'1', 'a' and '1' all at different vpos!!" -- and until now NOTHING
    # asserted it. The holding rule was credited with this alignment (ARCHITECTURE.md called it
    # "the defect this rule was written for"), so when the hold was removed from single-line cells
    # the whole suite stayed green. Being in the same LINE is what aligns them, not being held;
    # this asserts that directly, against the eye's own measure -- the centre of the glyphs.
    renderer, app, matrix = demo_matrix
    ruler = matrix.row_ruler_widget
    ruler.should_not be_nil
    rw = ruler.not_nil!
    ruler_h = CrymbleUI::FontSizing.calculate_size(CrymbleUI::VirtualMatrix::RULER_LABEL_FONT_SCALE).to_f64
    size = CrymbleUI::FontSizing.calculate_size(0)
    cell_h = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64

    worst = 0.0
    seen = Hash(Float64, Int32).new(0)
    offenders = [] of String
    (0..60).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64 * 4.0)
      matrix.pre_render_flush

      marks = [] of Tuple(Float64, String)
      # THIS FIXTURE HAS NO PINNED ROW, so a row number here always comes from `row_ruler_widget`
      # (which draws `sticky_rows...size`). A PINNED row's number is drawn by the corner row strip
      # and is placed against a different band; reading the strip here was tried on 2026-09-21 and
      # reverted, because the mutation that breaks that placement left this invariant green -
      # 11918 pairs, all 0.0px. Pinned rows are guarded by `sticky_ink_band_spec` instead.
      rw.to_primitives(rw.bounds).each do |p|
        next unless p.is_a?(CrymbleUI::DrawText)
        next if p.text.empty?
        marks << {rw.absolute_bounds.y + p.position.y + ruler_h / 2.0, "ruler #{p.text}"}
      end
      next if marks.empty?

      matrix.active_cells.each do |key, w|
        # DATA rows only. The row ruler names those; a column-header cell lives in the top strip
        # and merely OVERLAPS a row-ruler label in y, which matched here and reported 13.5px of
        # "misalignment" between two things that are not on the same line at all.
        next if key[0] < matrix.sticky_row_count
        next if w.ink_region # a held compound names a SPAN, not this line
        prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
        next unless prims.size == 1
        p = prims.first.as(CrymbleUI::DrawText)
        next if p.text.empty?
        content_cell = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
        box_y = w.absolute_bounds.y - (content_cell ? matrix.scroll_offset.y : 0.0)
        centre = box_y + p.position.y + cell_h / 2.0
        inside = marks.select { |(c, _)| c > box_y && c < box_y + w.bounds.height }
        # A COMPOUND spans many lines, so many ruler marks fall in its box and it names none of
        # them singly. Only a cell holding exactly one mark names the line that mark labels.
        next unless inside.size == 1
        inside.each do |(ruler_centre, name)|
          delta = (centre - ruler_centre).abs
          seen[delta.round(1)] += 1
          worst = delta if delta > worst
          # A pixel and a half, because that is the grid the two are drawn on: a cell's ink is
        # pixel-snapped and a ruler label's is not, so snapping alone can separate them by a pixel
        # and a sub-pixel bound would be finer than the thing being measured. Every deviation
        # observed sits on a row at the viewport's bottom edge, which is where snapping bites.
        #
        # The DISTRIBUTION printed below is the real check, not this bound: it reads 0.0px for
        # 11529 of 11808 pairs, so a systematic drift would show as the tail growing rather than
        # as a single pair creeping over a threshold. Read it when changing this rule.
        next if delta <= 1.5
          offenders << "#{name} at #{ruler_centre.round(1)} vs cell #{key} '#{p.text}' at " \
                       "#{centre.round(1)} (#{delta.round(1)}px apart), scroll #{i * 4}"
        end
      end
    end

    puts "\n  [I9] ruler-to-cell centre differences: " \
         "#{seen.to_a.sort_by(&.[0]).map { |(d, n)| "#{d}px x#{n}" }.join(", ")}"
    offenders.should be_empty,
      "a ruler number and its own line's cells were not on one line:\n  #{offenders.first(5).join("\n  ")}"
  end

  # RESTORED after being trimmed 2026-09-09. The sweep's T check asserts the same bound over five
  # fixtures, so this looked redundant — but breaking the bound (`top = paint_lo`) left the sweep at
  # ZERO violations and only this test, plus I9 incidentally, noticed. A wider domain is not the
  # same as a sharper one: the sweep's fixtures never enter the regime where the pull engages.
  # Verify a deletion by breaking what it guarded, not by reading two tests and judging them alike.
  it "I10 (UC-5): content is never moved further toward the top than top-alignment" do
    # Wolfgang's own statement of the rule (2026-09-08): "every cell should be visible as long as
    # possible, but not scrolled more to the top or left than normal top/left aligned".
    #
    # This replaced "does not move at all", which was the previous attempt at the same complaint.
    # That version was wrong in both directions: it forbade the movement that keeps a label visible
    # (#78), and it did not forbid the movement that actually looked broken. What looked broken was
    # UNBOUNDED movement -- content chasing the viewport edge 1:1 with no stopping point (#74/#75).
    # Bounded at top-alignment, content slides until it reaches that bound and then stops.
    _, _, matrix = tall_row_matrix
    offenders = [] of String

    (150..300).reverse_each do |h|
      matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, h.to_f64)),
        CrymbleUI::Vec2.zero)
      matrix.pre_render_flush
      one_line_cells(matrix) do |key, w, p, box_y|
        r = w.ink_region
        # TOP-ALIGNMENT, literally: the top of the region itself. Wolfgang's own words are the
        # bound -- "not scrolled more to the top or left than normal top/left aligned" -- and that
        # is `region_pos`, not the centred position. Deriving it as "centred" made this a copy of
        # the rule rather than a bound ON the rule, and it went red the moment the rule started
        # clamping content into the band at the far edge (2026-09-10), which moves content UP and
        # is exactly what keeps a tall row's number on screen.
        top = r ? box_y + r.pos : box_y
        next if box_y + p.position.y >= top - 0.6
        offenders << "#{key} '#{p.text}' at #{(box_y + p.position.y).round(1)} is above " \
                     "top-alignment #{top.round(1)} at panel height #{h}"
      end
    end

    offenders.should be_empty,
      "content was pulled above top-alignment:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "I13 (UC-6): a one-line label is CENTRED in its row" do
    # Was "sits on its row's FIRST LINE, level with a multiline neighbour" — the design until
    # 2026-09-10, when Wolfgang, seeing the labels pinned to the top of a tall row, said: "seems
    # level, now, finally, but I see no vcentering at all". Level was never level-with-the-BLOCK;
    # it is the LABELS that must agree, and they do (B2, B4, I9 all read 0.0px).
    #
    # So the claim is now centring, and the block is deliberately not part of it: a block centres
    # as a block, so its first line sits above a one-line label in the same row.
    _, _, matrix = tall_row_matrix
    size = CrymbleUI::FontSizing.calculate_size(0)
    line = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
    worst = 0.0
    offenders = [] of String

    (0..30).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      one_line_cells(matrix) do |key, w, p, box_y|
        next if box_y < band_lo # pushed: centring yields to visibility, judged by I12's successor
        # ...and only while the ROW ITSELF fits on screen. A row taller than the band is centred in
        # the part of it you can SEE (#97/#98) -- that is the whole point of the clamp, and this
        # example asks a different question: where content sits when nothing is in its way.
        next unless box_y + w.bounds.height <= matrix.bounds.height + 0.5
        centred = box_y + (w.bounds.height - line) / 2.0
        delta = (box_y + p.position.y - centred).abs
        worst = delta if delta > worst
        next if delta <= 1.5
        offenders << "#{key} '#{p.text}' at #{(box_y + p.position.y).round(1)}, centre #{centred.round(1)}"
      end
    end

    puts "\n  [I13] worst off-centre at rest: #{worst.round(2)}px"
    offenders.should be_empty,
      "a one-line label was not centred in its row:\n  #{offenders.first(5).join("\n  ")}"
  end

  it "I14 (UC-19): a frozen label keeps its row's padding, and does not jam the band edge" do
    # Field report #82: "'1' in this case is clipped a bit at top — the freezing is a couple of
    # bits too high". A label pushed under the sticky header was landing with its ink exactly ON
    # band_lo, which is 5.5px higher than the SAME label sits in a row that merely begins there —
    # nowhere a label ever sits otherwise, and it reads as shaved against the header.
    #
    # So the assertion is a comparison against the label's own unfrozen offset, not a magic gap:
    # freezing may change WHERE a line is, never how a line sits in it.
    #
    # THE COUNTERS ARE PART OF THE GUARD. This example was DEAD until 2026-09-10 -- it ran on
    # `tall_row_matrix`, whose content is shorter than its viewport, so nothing ever scrolled and
    # it asserted on 0 of the 202 cells it looked at. Reinstating the defect left it green. It now
    # runs on `pushed_matrix` and prints what it actually reached; if `push-BINDING` ever drops to
    # 0 again the example is dead again, whatever its colour. Verified RED at the same time:
    # `pad = 0.0` takes the closest approach from 14.0px to 0.0px and names its offenders.
    _, _, matrix = pushed_matrix
    offenders = [] of String
    resting = {} of Tuple(Int32, Int32) => Float64
    with_region = 0
    pushed_seen = 0
    compounds_seen = 0
    binding_push = 0
    binding_compounds = 0
    held_small = [] of String
    closest = Float64::INFINITY

    (0..80).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      band_hi = matrix.bounds.height
      one_line_cells(matrix) do |key, w, p, box_y|
        r = w.ink_region
        next unless r
        with_region += 1
        compounds_seen += 1 if compound?(matrix, key)
        # COMPOUNDS PASS THROUGH, and are expected to contribute nothing: since 2026-09-10 a
        # compound is not held at the leading edge in ANY form, so the push cannot make it flush
        # and #87's defect has no way back. That claim now lives in `compound_scroll_out_spec`,
        # which asserts the stronger thing -- a compound's label rides its group exactly.
        offset = box_y + p.position.y - (box_y + r.pos) # where the line sits inside its region
        if box_y >= band_lo
          resting[key] = offset # not pushed: this is the label's own answer
          next
        end
        next unless rest = resting[key]?
        pushed_seen += 1
        ink = box_y + p.position.y
        natural = box_y + r.pos + rest
        if natural < band_lo - 0.5
          binding_push += 1
          if compound?(matrix, key)
            binding_compounds += 1
            # A COMPOUND MAY BE HELD AT THE LEADING EDGE, but ONLY when its span is taller than the
            # band: a group you cannot see the middle of has to centre in the part you can, or its
            # label parks against an edge and stays there (image #99). A group SMALLER than the
            # screen is never held — it rides its span and leaves with it (#93-#96).
            held_small << "#{key} '#{p.text}' held at the edge with a span of " \
                          "#{r.size.round(1)} in a band of #{(band_hi - band_lo).round(1)}" \
              unless r.size > band_hi - band_lo + 0.5
          end
        end
        # COUNTED ABOVE, ASSERTED ON BELOW ONLY IF IT IS ONE LINE. A compound is not held at the
        # leading edge at all now, so it slides smoothly out through the header with its group and
        # legitimately passes `band_lo + padding` on the way (measured: 'a' at 55.5, 54.5, 53.5 as
        # it left). That IS the fix of images #93-#96; asserting the padding on it would forbid it.
        next if compound?(matrix, key)
        gap = ink - band_lo
        closest = gap if gap < closest
        # NOT JAMMED ON THE EDGE (#82): however far its row has scrolled, a label keeps at least a
        # line-capped padding below the band's top. It is not required to BE there — while its
        # centred position is still lower, that is where it sits, and it slides down to this bound
        # only as the band climbs past it.
        floor = band_lo + Math.min(rest, line_height)
        next if ink >= floor - 0.6
        offenders << "#{key} '#{p.text}' jammed at #{ink.round(1)}, band_lo #{band_lo.round(1)} " \
                     "+ padding #{Math.min(rest, line_height).round(1)} = #{floor.round(1)} (scroll #{i})"
      end
    end

    puts "\n  [I14] regions #{with_region} (compound #{compounds_seen}); pushed #{pushed_seen}, " \
         "of them push-BINDING #{binding_push} (compound #{binding_compounds}); " \
         "closest ink came to band_lo: #{closest.round(2)}px"
    binding_push.should be > 20, "I14 examined no frozen label — the example is dead"
    held_small.should be_empty,
      "a compound smaller than the band was held at the leading edge:\n  #{held_small.first(4).join("\n  ")}"
    offenders.should be_empty,
      "a frozen label lost its row's padding:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "I15 (UC-1/UC-20): a compound is centred in its span, and never sits below the screen" do
    # TWO observable claims, because the rule has exactly two things to say about a compound:
    #
    #   (a) it is CENTRED IN ITS SPAN -- "of course vcentering was always for compound cells"
    #       (Wolfgang, 2026-09-10). Asserted where it is unambiguous: the whole span on screen.
    #   (b) it is never below the band's far edge -- #45 and #50, a label sitting under the
    #       viewport with its own cluster in view, and a group arriving from below showing
    #       nothing until it is half in.
    #
    # There is deliberately no third claim about the LEADING edge. Holding it there is what made a
    # small group's label linger while its rows left (images #93-#96), and no report ever asked
    # for it; `compound_scroll_out_spec` guards its absence.
    _, _, matrix = demo_matrix
    size = CrymbleUI::FontSizing.calculate_size(0)
    line = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
    centred_checks = 0
    below_checks = 0
    worst_centre = 0.0
    worst_below = 0.0
    offenders = [] of String

    (0..40).each do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      band_hi = matrix.bounds.height
      one_line_cells(matrix) do |key, w, p, box_y|
        r = w.ink_region
        next unless compound?(matrix, key)
        ink = box_y + p.position.y
        # THE SPAN, from the region when it carries one and from the BOX when it does not. A
        # compound withdraws its region when its box already IS its span and all of it is on
        # screen, precisely because the two are then the same arithmetic — so reading the box is
        # not a fallback here, it is the same number by construction.
        r = w.ink_region
        span_lo = r ? box_y + r.pos : box_y
        span_hi = r ? span_lo + r.size : box_y + w.bounds.height

        if span_lo >= band_lo - 0.5 && span_hi <= band_hi + 0.5 # (a) the whole span is on screen
          centred_checks += 1
          centre = span_lo + (span_hi - span_lo - line) / 2.0
          d = (ink - centre).abs
          worst_centre = d if d > worst_centre
          offenders << "#{key} '#{p.text}' at #{ink.round(1)}, its span's centre #{centre.round(1)}" if d > 1.5
        elsif span_hi > band_hi && ink < band_hi - 0.5 # (b) part of it hangs below the screen
          below_checks += 1
          over = ink + line - band_hi
          worst_below = over if over > worst_below
          offenders << "#{key} '#{p.text}' at #{ink.round(1)} runs past the screen at #{band_hi.round(1)}" if over > 1.0
        end
      end
    end

    puts "\n  [I15] centred-in-span checks #{centred_checks} (worst #{worst_centre.round(2)}px); " \
         "hangs-below checks #{below_checks} (worst overshoot #{worst_below.round(2)}px)"
    centred_checks.should be > 20, "I15 never saw a whole span on screen — the example is dead"
    offenders.should be_empty,
      "a compound was misplaced:\n  #{offenders.first(5).join("\n  ")}"
  end
  it "I4: no two ruler numbers stack on one another" do
    ink = CrymbleUI::FontSizing.calculate_size(-2)
    offenders = [] of String
    sweep_scroll_y.each do |snap|
      rulers = snap.items.select { |p| p.text.starts_with?("ruler:") }
      rulers.each_with_index do |a, i|
        rulers.each_with_index do |b, j|
          next unless j > i
          next unless (a.x - b.x).abs < ink
          next if (a.y - b.y).abs >= ink
          offenders << "#{a.text} and #{b.text} at #{snap.input.round(0)}: " \
                       "y=#{a.y.round(1)} vs #{b.y.round(1)}"
        end
      end
    end
    offenders.should be_empty, "ruler numbers stacked:\n  #{offenders.first(5).join("\n  ")}"
  end
end
