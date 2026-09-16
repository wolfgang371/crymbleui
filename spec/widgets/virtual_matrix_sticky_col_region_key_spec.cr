require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Horizontal sibling of virtual_matrix_bounds_grow_cells_spec, which asserts the same invariant
# after a HEIGHT grow with uniform columns and therefore cannot reach this fault.
#
# Reported by Wolfgang 2026-09-15 with screenshots: paste a wide .tsv, switch Auto-size on, widen
# the Shape — the last column's header is drawn and everything under it is flat dark grey. Scrolling
# or zooming repairs it; Ctrl+0 does not.
#
# Root cause, measured on the reporter's own data:
#   compute_region_cached keys on `cumulative`, built in SCROLL order, while the filter that decides
#   the result compares `physical_cum`, in PHYSICAL order. The sticky Rank column is moved to the
#   TAIL of the scroll order, so every other column sits one sticky-width earlier in scroll space
#   than physically — 47px there. The huge column began at 1178 in scroll space and 1225 physically.
#   With the viewport edge at max_pos=1188 the two disagree: the key says "past its start" and fixes
#   ib, the filter says "not yet" and drops the column. Because that column is 3615px wide the key
#   cannot move until 4793, so widening the viewport from 1188 to 1988 changes the correct answer
#   while leaving the key identical — a cache hit returns the stale region and no cells are created.
#
# The geometry below reproduces that: one sticky column at the head of the PHYSICAL order and the
# tail of the SCROLL order, a few narrow columns, and one enormous trailing column.
class StickyColHugeLastAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  # Physical widths in px, mirroring the measured case.
  WIDTHS_PX = [47.0, 95.0, 63.0, 71.0, 103.0, 127.0, 719.0, 3615.0]

  def initialize(@rows : Int32)
  end

  # Sticky lines go at the TAIL of the scroll order (derive_sticky_count scans from the end), so
  # column 0 — the sticky one — is last here while staying first physically. That reordering is the
  # offset between the two spaces.
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...@rows).to_a, [1, 2, 3, 4, 5, 6, 7, 0]}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    fh = CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE * CrymbleUI::FontSizing.zoom_factor
    {Array.new(@rows, 1.0), WIDTHS_PX.map { |px| px / fh }}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

describe "VirtualMatrix: widening the viewport must create cells for a column that comes into view" do
  it "the huge trailing column gets cells after a width grow (sticky column offsets the scroll order)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(2000, 800)
    app = TestApp.new
    adapter = StickyColHugeLastAdapter.new(30)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_huge")
    app.root_widget = matrix
    app.build_tree

    # Narrow: the huge column begins past the creation edge, so having no cells is CORRECT here.
    # The width matters to within ~50px: max_pos (viewport + CREATION_BUFFER) has to land in the
    # window between the huge column's SCROLL-space start (cumulative[5] = 1196) and its PHYSICAL
    # start (physical_cum[7] = 1246) — the gap being the sticky column's width. Outside it the two
    # spaces agree, `ib` moves with the resize, and the cache correctly recomputes. 1080 - 16px of
    # scrollbar + 150 of buffer = 1214, inside the window.
    narrow = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1080.0, 600.0))
    matrix.layout(narrow, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    last = StickyColHugeLastAdapter::WIDTHS_PX.size - 1
    matrix.@visible_cols.includes?(last).should be_false,
      "instrument: the huge column must start OUT of view at 1054px, or this spec proves nothing"

    # Wide: it now starts well inside the viewport.
    wide = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1854.0, 600.0))
    matrix.layout(wide, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    matrix.@visible_cols.includes?(last).should be_true,
      "instrument: after widening the huge column must be considered visible"

    # The invariant: every visible (row, col) pair has a live cell widget.
    missing = [] of Tuple(Int32, Int32)
    matrix.@visible_rows.each do |r|
      matrix.@visible_cols.each do |c|
        missing << {r, c} unless matrix.@active_cells.has_key?({r, c})
      end
    end
    missing.empty?.should be_true,
      "after widening, #{missing.size} visible cells have no widget — e.g. #{missing.first(6).inspect}. " \
      "Column #{last} missing entirely? #{missing.count { |m| m[1] == last } == matrix.@visible_rows.size}"
  end
end
