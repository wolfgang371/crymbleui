require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# TWO GAPS the regime matrix named on 2026-09-11, closed here.
#
# 1. A ROW's height changing UNDER A SPAN. Every other sweep varies the scroll or the panel; none
#    varies a row, which is what auto-size does the moment you type a newline into a cell — and it
#    is how half of this arc's defects were found (`-heightenshape->`, the 8-line block that makes
#    row 1 tall). The span's SIZE changes underneath the label, and that is the quantity the
#    "held only by its overflow" clause keys on, so a step there would show as a jumping label.
#
# 2. A MULTI-LINE label in a COMPOUND region. No fixture had ever given a compound anything but one
#    line, so the block branch had never run against a span at all.
private VP_W = 400
private VP_H = 260

private class ResizingSpanShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  property block_lines : Int32 = 1
  property group_lines : Int32 = 1

  def row_count : Int32
    7
  end

  def col_count : Int32
    3
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...7).to_a + [0], (1...3).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    return { {1, 1}, {3, 1} } if col == 1 && row >= 1 && row <= 3 # the group, spanning 3 rows
    { {row, col}, {row, col} }
  end

  def cell_natural_size(row : Int32, col : Int32)
    lines = 1
    lines = @block_lines if row == 2 && col == 2 # a cell INSIDE the span grows
    lines = @group_lines if row == 1 && col == 1 # the group's own label
    {width: 40.0, height: lines * 20.0, lines: lines}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text =
      if row == 0
        col == 0 ? "" : "c#{col}"
      elsif col == 1
        row <= 3 ? (0...@group_lines).map { |i| i == 0 ? "g" : "g#{i}" }.join("\n") : "z"
      elsif row == 2 && col == 2
        (0...@block_lines).map { |i| ('A' + i).to_s }.join("\n")
      else
        "#{row}"
      end
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private def resizing_matrix
  adapter = ResizingSpanShape.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "resizing")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, VP_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.pre_render_flush
  {adapter, matrix}
end

# Re-fit the rows after the adapter's natural sizes changed — what typing a newline does.
private def refit(matrix)
  matrix.auto_size = false
  matrix.auto_size = true
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  matrix.pre_render_flush
end

private def compound?(matrix, key) : Bool
  bb = matrix.get_bounding_box(key)
  bb[0][0] != bb[1][0]
end

private record Seen, key : Tuple(Int32, Int32), text : String, top : Float64,
  span_lo : Float64, span_hi : Float64, lines : Int32

private def group_ink(matrix) : Seen?
  matrix.active_cells.each do |key, w|
    next unless compound?(matrix, key)
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    next if prims.empty?
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_y = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
    r = w.ink_region
    lo = r ? box_y + r.pos : box_y
    hi = r ? lo + r.size : box_y + w.bounds.height
    return Seen.new(key, p.text, box_y + p.position.y, lo, hi, prims.size)
  end
  nil
end

private def line_height
  size = CrymbleUI::FontSizing.calculate_size(0)
  (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
end

describe "a row growing underneath a span" do
  it "moves the group's label smoothly, never further than the span's own end moved" do
    adapter, matrix = resizing_matrix
    worst_ratio = 0.0
    checked = 0
    offenders = [] of String
    prev = nil.as(Seen?)

    (1..12).each do |lines|
      adapter.block_lines = lines
      refit(matrix)
      now = group_ink(matrix)
      next unless now
      if was = prev
        grew = (now.span_hi - now.span_lo) - (was.span_hi - was.span_lo)
        moved = (now.top - was.top).abs
        if grew.abs > 0.01
          checked += 1
          ratio = moved / grew.abs
          worst_ratio = ratio if ratio > worst_ratio
          # The label is centred in the span, so it may move at most HALF of what the span's
          # extent changed by. More than that is a step, which is what #69-#73 reported.
          offenders << "#{lines} lines: the span grew #{grew.round(1)}px and '#{now.text}' " \
                       "moved #{moved.round(1)}px" if moved > grew.abs / 2.0 + 1.0
        end
      end
      prev = now
    end

    puts "\n  [span-resize] re-fits compared: #{checked}; worst move as a fraction of the growth: " \
         "#{worst_ratio.round(2)}"
    checked.should be > 6, "the span never changed size — the fixture does not re-fit"
    offenders.should be_empty,
      "a group's label stepped when its span was resized:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "keeps the group's label centred in its span at every size, at every scroll" do
    # SCROLLED AS WELL AS RESIZED. Without the scroll the group sits at the top of the content and
    # its LEADING edge is never crossed — so the clause that is gated on "is this span taller than
    # the band" never runs, and moving that threshold left this example green (verified 2026-09-11,
    # which is the only reason the scroll is here).
    adapter, matrix = resizing_matrix
    worst = 0.0
    checked = 0
    offenders = [] of String

    (1..12).each do |lines|
      adapter.block_lines = lines
      refit(matrix)
      [0, 20, 40, 60, 90, 120].each do |scroll|
        matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll.to_f64)
        matrix.pre_render_flush
        now = group_ink(matrix)
        next unless now
        band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
        band_hi = matrix.bounds.height
        size = now.span_hi - now.span_lo
        band = band_hi - band_lo
        # the rule, in full: centred in the part of the region you can see. No conditions.
        lo = Math.max(now.span_lo, band_lo)
        hi = Math.min(now.span_hi, band_hi)
        next unless hi - lo >= line_height
        checked += 1
        want = lo + (hi - lo - line_height) / 2.0
        d = (now.top - want).abs
        worst = d if d > worst
        offenders << "#{lines} lines at scroll #{scroll}: '#{now.text}' at #{now.top.round(1)}, " \
                     "want #{want.round(1)} (span #{now.span_lo.round(1)}..#{now.span_hi.round(1)}, " \
                     "band #{band_lo.round(1)}..#{band_hi.round(1)})" if d > 1.5
      end
    end

    puts "  [span-resize] size x scroll cases checked: #{checked}; worst off-centre: #{worst.round(2)}px"
    checked.should be > 40, "the fixture never produced a centred case"
    offenders.should be_empty,
      "a group's label was not centred in its span:\n  #{offenders.first(6).join("\n  ")}"
  end

  it "places a MULTI-LINE group label inside the span it names" do
    # The block branch had never run against a span. It anchors at the region's top rather than
    # centring, so the claim is containment and continuity, not a centre.
    adapter, matrix = resizing_matrix
    offenders = [] of String
    checked = 0

    (1..5).each do |lines|
      adapter.group_lines = lines
      refit(matrix)
      now = group_ink(matrix)
      next unless now
      next unless now.lines == lines # the label really is that many lines
      checked += 1
      extent = lines * line_height
      if now.top < now.span_lo - 1.0
        offenders << "#{lines}-line label starts at #{now.top.round(1)}, above its span's top #{now.span_lo.round(1)}"
      end
      if now.top + extent > now.span_hi + 1.0 && extent <= now.span_hi - now.span_lo
        offenders << "#{lines}-line label ends at #{(now.top + extent).round(1)}, past its span's end #{now.span_hi.round(1)} which had room"
      end
    end

    puts "  [span-resize] multi-line group labels checked: #{checked}"
    checked.should be > 3, "the group label never became multi-line — the fixture is wrong"
    offenders.should be_empty,
      "a multi-line group label left its span:\n  #{offenders.join("\n  ")}"
  end
end
