require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Compound (merged) sticky headers whose constituent columns SHIFT OUT under a
# non-natural scroll order (embrace pivots: content scrolls out before its
# physically-left group header; shifted columns are compacted out of the grid, so
# their raw physical positions are meaningless). The compound's extent must
# exclude shifted-out constituents in BOTH positioning passes — the layout pass
# (reposition_sticky_cells) and the blit-plan fast path
# (reposition_compound_in_blit_plan) are EITHER/OR per frame, so any disagreement
# is user-visible as a header width/pin JUMP when the frame type flips.
#
# cv-coherency is BLIND to this class (both sticky checkers skip compound cells;
# cv skips sticky_ layers) — these specs are the sole guard.

# Expose the two positioning passes + the fast-path gate for direct-seam driving.
class CrymbleUI::VirtualMatrix
  def sticky_cells_can_use_blit_plan_for_spec
    sticky_cells_can_use_blit_plan?
  end

  def compute_sticky_blit_plans_for_spec
    compute_sticky_blit_plans
  end

  def reposition_sticky_cells_for_spec
    reposition_sticky_cells
  end
end

class ShiftedCompoundAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  property cols : Int32

  def initialize(@rows : Int32, @cols : Int32,
                 @col_order : Array(Int32), @row_order : Array(Int32),
                 @merges : Array(Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))))
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "#{row},#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # Filter by the CURRENT counts so a shrink (property setter + invalidate_all!)
    # yields a consistent order; filtering preserves the sticky tail.
    {@row_order.select { |r| r < @rows }, @col_order.select { |c| c < @cols }}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        # Clamp to the CURRENT counts (a real adapter derives merges from its
        # structure, so a shrink shrinks them too) — lets the shrink tripwire
        # go BELOW the compound's constituent range.
        return {tl, { {br[0], @rows - 1}.min, {br[1], @cols - 1}.min }}
      end
    end
    { {row, col}, {row, col} }
  end
end

class ShiftedCompoundApp < CrymbleUI::App
  class_property adapter : ShiftedCompoundAdapter?

  def build : CrymbleUI::Widget
    m = CrymbleUI::VirtualMatrix.new(ShiftedCompoundApp.adapter.not_nil!, id: "shifted_grid")
    m.show_rulers = false
    m
  end
end

# File-private (top-level constants collide across spec files in a group compile).
private def col_pitch
  CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
end

private def row_pitch
  CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
end

private def gspacing
  CrymbleUI::VirtualMatrix::GRID_SPACING.to_f64
end

# Col 4 — the compound's RIGHT-EDGE constituent — scrolls out FIRST while its raw
# physical position is still inside the viewport (the arming order).
private def edge_shift_setup(col_order : Array(Int32))
  ShiftedCompoundApp.adapter = ShiftedCompoundAdapter.new(5, 20,
    col_order, [1, 2, 3, 4, 0], [{ {0, 1}, {0, 4} }])
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 300)
  app = ShiftedCompoundApp.new
  app.build_tree
  renderer.settle_rendering(app) # textures cached → the fast path is reachable
  matrix = app.find("shifted_grid").as(CrymbleUI::VirtualMatrix)
  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 300.0))
  {renderer, app, matrix, constraints}
end

private def compound_cell(matrix)
  cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
  cell.should_not be_nil, "compound header cell missing from active_cells"
  cell.not_nil!
end

# Drive BOTH passes at the same scroll on the same warm fixture and return
# {layout_width, blit_width, layout_x, blit_x}.
private def both_passes(matrix, constraints, scroll_x : Float64)
  matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
  matrix.layout(constraints, CrymbleUI::Vec2.zero) # refresh StickyMath caches at this scroll
  matrix.sticky_cells_can_use_blit_plan_for_spec.should be_true,
    "fast path not reachable — the blit-pass reading would be vacuous"
  matrix.reposition_sticky_cells_for_spec
  c = compound_cell(matrix)
  w_layout, x_layout = c.bounds.width, c.bounds.x
  matrix.compute_sticky_blit_plans_for_spec
  c = compound_cell(matrix)
  {w_layout, c.bounds.width, x_layout, c.bounds.x}
end

describe "Compound header extent under shifted-out constituents", tags: "slow" do
  # scroll=160 with pitch 103: col 4 is shifted (scroll_rank 0, num_shifted 1)
  # while its raw physical span (412..515 − 160) still lands in the viewport.
  it "layout and blit-plan passes agree when an edge constituent has shifted out" do
    _renderer, _app, matrix, constraints = edge_shift_setup([4, 1, 2, 3] + (5...20).to_a + [0])
    w_layout, w_blit, x_layout, x_blit = both_passes(matrix, constraints, 160.0)
    w_blit.should eq(w_layout),
      "compound width differs between the two positioning passes " \
      "(layout #{w_layout} vs blit #{w_blit}) — the header jumps when the frame type flips"
    x_blit.should eq(x_layout)
  end

  it "the compound width excludes the shifted-out constituent (absolute pin)" do
    _renderer, _app, matrix, constraints = edge_shift_setup([4, 1, 2, 3] + (5...20).to_a + [0])
    s = 160.0
    # Included: cols 2,3 (col 1 fully behind the boundary, col 4 shifted out).
    # Extent = right edge of col 3 (4*col_pitch − s) minus the pin (col_pitch) minus spacing.
    expected = 4.0 * col_pitch - s - col_pitch - gspacing # 146.0
    w_layout, w_blit, _x, _x2 = both_passes(matrix, constraints, s)
    w_layout.should eq(expected)
    w_blit.should eq(expected)
  end

  # scroll=240: only col 3 remains visible (cols 1,2 behind the boundary, col 4
  # shifted out) → the single-col disposition: UNCLAMPED at its content position,
  # regular cell size. Pinned against independent geometry — never against the
  # other pass — so this stays discriminating after unification.
  it "single remaining constituent: absolute position and extent (both passes)" do
    _renderer, _app, matrix, constraints = edge_shift_setup([4, 1, 2, 3] + (5...20).to_a + [0])
    s = 240.0
    expected_x = 3.0 * col_pitch - s # cum[3] − s = 69
    expected_w = col_pitch - gspacing      # 100
    w_layout, w_blit, x_layout, x_blit = both_passes(matrix, constraints, s)
    x_layout.should eq(expected_x)
    w_layout.should eq(expected_w)
    x_blit.should eq(expected_x)
    w_blit.should eq(expected_w)
  end

  it "natural order: both passes give the physically-clipped width (equivalence lock)" do
    _renderer, _app, matrix, constraints = edge_shift_setup((1...20).to_a + [0])
    s = 160.0
    # Col 1 is both shifted AND physically behind the boundary (natural order:
    # the two notions coincide) — included: cols 2,3,4.
    expected = 5.0 * col_pitch - s - col_pitch - gspacing # 249.0
    w_layout, w_blit, _x, _x2 = both_passes(matrix, constraints, s)
    w_layout.should eq(expected)
    w_blit.should eq(expected)
  end

  it "a fast-path frame leaves the header where the layout pass put it (no flip jump)" do
    renderer, app, matrix, constraints = edge_shift_setup([4, 1, 2, 3] + (5...20).to_a + [0])
    matrix.scroll_offset = CrymbleUI::Vec2.new(160.0, 0.0)
    renderer.render_frame(app) # a fast-path frame
    CrymbleUI::LayerRenderer.frame_blit_plan_count.should be >= 1,
      "no blit-plan ran this frame — the fast-path reading would be vacuous"
    w_frame = compound_cell(matrix).bounds.width
    matrix.reposition_sticky_cells_for_spec # what a fallback frame would compute
    w_fallback = compound_cell(matrix).bounds.width
    w_frame.should eq(w_fallback),
      "header width flips between frame types (fast #{w_frame} vs fallback #{w_fallback})"
  end

  # Seam tripwire for the guards-dropped-by-proof decision: the proof rests on
  # flush_invalidate_all clearing size caches + active cells + forcing the full
  # rebuild TOGETHER. If a future edit splits that atomicity, this fails loudly
  # instead of becoming a release Heisenbug.
  it "announced column shrink with warm textures does not raise in the blit plan" do
    _renderer, app, matrix, constraints = edge_shift_setup((1...20).to_a + [0])
    adapter = ShiftedCompoundApp.adapter.not_nil!
    # Shrink BELOW the compound's constituent range (cols 1..4 → clamped to 1..2)
    # so the compound path itself indexes post-shrink data.
    adapter.cols = 3
    adapter.invalidate_all!
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    matrix.compute_sticky_blit_plans_for_spec # must not raise IndexError
    matrix.active_cells.should_not be_empty
  end

  it "Y axis (sticky-col compound): both passes agree on height (equivalence lock)" do
    ShiftedCompoundApp.adapter = ShiftedCompoundAdapter.new(20, 5,
      (1...5).to_a + [0], (1...20).to_a + [0], [{ {1, 0}, {4, 0} }])
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 300)
    app = ShiftedCompoundApp.new
    app.build_tree
    renderer.settle_rendering(app)
    matrix = app.find("shifted_grid").as(CrymbleUI::VirtualMatrix)
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 300.0))

    s = 40.0
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, s)
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    matrix.sticky_cells_can_use_blit_plan_for_spec.should be_true
    matrix.reposition_sticky_cells_for_spec
    cell = (1..4).each.compact_map { |r| matrix.active_cells[{r, 0}]? }.first?
    cell.should_not be_nil
    h_layout = cell.not_nil!.bounds.height
    matrix.compute_sticky_blit_plans_for_spec
    cell = (1..4).each.compact_map { |r| matrix.active_cells[{r, 0}]? }.first?
    h_blit = cell.not_nil!.bounds.height

    # Rows 2..4 visible below the sticky row (row 1 clipped behind it):
    # extent = bottom of row 4 (5*row_pitch − s) minus the pin (row_pitch) minus spacing.
    expected = 5.0 * row_pitch - s - row_pitch - gspacing # 49.0
    h_layout.should eq(expected)
    h_blit.should eq(expected)
  end
end
