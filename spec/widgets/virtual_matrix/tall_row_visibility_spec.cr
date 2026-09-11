require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Wolfgang's images #97 and #98, 2026-09-10: a row made TALLER THAN THE VIEWPORT by a multiline
# cell. "we have this potential issue where the ruler isn't staying in the viewport" — the row's
# number sits at the very bottom edge, half cut, because the rule centres content in the ROW and
# that row's centre is below the fold.
#
# The claim has two halves, and they have to hold together or neither is worth anything:
#   VISIBLE  — while any of a line is on screen, that line's content is on screen too.
#   LEVEL    — the ruler number and the cells of that same line stay on one line while it happens
#              (UC-15, #45: "'1', 'a' and '1' all at different vpos!!"). A bound measured in each
#              cell's OWN glyph height moves them by different amounts and breaks this.
private VP_W = 400
private VP_H = 160

private class TallerThanViewport
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def row_count : Int32
    40
  end

  def col_count : Int32
    3
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...5).to_a + [0], (1...3).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32)
    { {row, col}, {row, col} }
  end

  # row 2 carries a 12-line block: taller than the 160px viewport by design
  def cell_natural_size(row : Int32, col : Int32)
    lines = row == 2 && col == 2 ? 12 : 1
    {width: 40.0, height: lines * 20.0, lines: lines}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text =
      if row == 0
        col == 0 ? "" : "c#{col}"
      elsif col == 2 && row == 2
        (0...12).map { |i| ('A' + i).to_s }.join("\n")
      else
        "#{row}"
      end
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

private def tall_matrix
  matrix = CrymbleUI::VirtualMatrix.new(TallerThanViewport.new, id: "taller")
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
  {renderer, app, matrix}
end

private def line_height
  size = CrymbleUI::FontSizing.calculate_size(0)
  (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
end

describe "a row taller than the viewport" do
  it "keeps that line's content on screen, and on one line (#97/#98)" do
    _r, _a, matrix = tall_matrix
    invisible = [] of String
    unlevel = [] of String
    checked = 0
    worst_spread = 0.0

    (0..140).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step.to_f64)
      matrix.pre_render_flush
      band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      band_hi = matrix.bounds.height

      # every ONE-LINE cell of the tall row, by the region it names
      tops = [] of Tuple(Tuple(Int32, Int32), String, Float64, Float64, Float64)
      matrix.active_cells.each do |key, w|
        next unless key[0] == 2
        prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
        next unless prims.size == 1 # the block itself scrolls by design (UC-3)
        p = prims.first.as(CrymbleUI::DrawText)
        next if p.text.empty?
        content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
        box_y = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
        r = w.ink_region
        lo = r ? box_y + r.pos : box_y
        hi = r ? box_y + r.pos + r.size : box_y + w.bounds.height
        tops << {key, p.text, box_y + p.position.y, lo, hi}
      end
      next if tops.empty?

      # is the LINE on screen at all?
      line_lo, line_hi = tops.first[3], tops.first[4]
      next unless line_hi > band_lo + line_height && line_lo < band_hi - line_height
      checked += 1

      tops.each do |(key, text, top, _lo, _hi)|
        if top < band_lo - 0.5 || top + line_height > band_hi + 0.5
          invisible << "scroll #{step}: #{key} '#{text}' at #{top.round(1)} is outside the band " \
                       "#{band_lo.round(1)}..#{band_hi.round(1)} though its line spans " \
                       "#{line_lo.round(1)}..#{line_hi.round(1)}"
        end
      end
      spread = tops.map(&.[2]).max - tops.map(&.[2]).min
      worst_spread = spread if spread > worst_spread
      unlevel << "scroll #{step}: " + tops.map { |(k, t, y, _, _)| "#{k[1]}:#{t}@#{y.round(1)}" }.join(", ") if spread > 1.0
    end

    puts "\n  [tall-row] frames with the line on screen: #{checked}; " \
         "off-band placements: #{invisible.size}; worst spread within the line: #{worst_spread.round(2)}px"
    checked.should be > 50, "the sweep never had the tall line on screen — fixture is wrong"
    invisible.should be_empty,
      "content left the viewport while its own line was on screen:\n  #{invisible.first(6).join("\n  ")}"
    unlevel.should be_empty,
      "the cells of one line parted:\n  #{unlevel.first(6).join("\n  ")}"
  end

  # An example that asserted "no ruler number is drawn past the far edge" was here, for the blank
  # bottom-left cell of image #97. It is NOT in the suite because it could not be made to fail: in
  # this harness a matrix's content layer is sized to the viewport, so the ruler's own bounds and
  # the matrix's agree and the defect cannot arise. The ruler-band mismatch it was aimed at is real
  # — reinstating it costs 4.2px of ruler-to-cell levelness across 180 samples — and I9 is what
  # catches that, verified RED. A guard whose fixture cannot produce the situation is not a guard
  # (see docs/PLACEMENT_CASES.md), so it is recorded here rather than shipped green and trusted.
end
