require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# The matrix leg of the scroll-space sweep (spec/rendering/scroll_space_sweep_spec.cr covers the
# ScrollView legs). A VirtualMatrix is the one scroller that is NOT a ScrollView: it keeps its
# cells' laid-out bounds and paints them shifted itself. Anything anchored to a cell — a cell
# editor's dropdown, a drag ghost, a drop highlight — therefore needs the PAINTED position, which
# is what `paint_shift_for` teaches the walk.
#
# And the half that is easy to forget: a sticky row or column is PINNED. It must hold that axis
# still, or the fix for scrolled cells would misplace every header instead.
class SweepMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Stickiness is the TAIL of the scroll order (derive_sticky_count reads it backwards for the
  # trailing indices that form {0..n-1}), so every index is present and 0 comes last: row 0 and
  # column 0 are sticky, the rest scroll.
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

private def sweep_matrix(scroll : CrymbleUI::Vec2)
  adapter = SweepMatrixAdapter.new(20, 20)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sweep_matrix")
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  matrix.scroll_offset = scroll
  renderer.render_frame(app)
  {matrix, renderer, app}
end

describe "scroll-space sweep: VirtualMatrix" do
  it "paints a scrolling cell at absolute minus the matrix scroll" do
    matrix, _r, _a = sweep_matrix(CrymbleUI::Vec2.new(40.0, 30.0))
    applied = matrix.scroll_offset
    (applied.x > 0.0 || applied.y > 0.0).should be_true # instrument

    cell = matrix.active_cells.find { |(rc, _w)| rc[0] > 0 && rc[1] > 0 }
    cell.should_not be_nil
    widget = cell.not_nil![1]
    widget.viewport_bounds.x.should be_close(widget.absolute_bounds.x - applied.x, 0.5)
    widget.viewport_bounds.y.should be_close(widget.absolute_bounds.y - applied.y, 0.5)
  end

  it "holds a sticky column still on X and a sticky row still on Y" do
    matrix, _r, _a = sweep_matrix(CrymbleUI::Vec2.new(40.0, 30.0))
    applied = matrix.scroll_offset
    matrix.sticky_col_count.should be > 0 # instrument: stickiness really configured
    matrix.sticky_row_count.should be > 0

    # NOT `if` — a conditional assertion passes vacuously when the fixture stops producing the
    # cell, which is the same as no test at all.
    sticky_col = matrix.active_cells.find { |(rc, _w)| rc[1] == 0 && rc[0] > 0 }
    sticky_col.should_not be_nil
    w = sticky_col.not_nil![1]
    w.viewport_bounds.x.should be_close(w.absolute_bounds.x, 0.5)             # pinned on X
    w.viewport_bounds.y.should be_close(w.absolute_bounds.y - applied.y, 0.5) # still scrolls on Y

    sticky_row = matrix.active_cells.find { |(rc, _w)| rc[0] == 0 && rc[1] > 0 }
    sticky_row.should_not be_nil
    w2 = sticky_row.not_nil![1]
    w2.viewport_bounds.y.should be_close(w2.absolute_bounds.y, 0.5)             # pinned on Y
    w2.viewport_bounds.x.should be_close(w2.absolute_bounds.x - applied.x, 0.5) # still scrolls on X
  end

  it "is exact when the matrix is not scrolled" do
    matrix, _r, _a = sweep_matrix(CrymbleUI::Vec2.zero)
    matrix.active_cells.each do |_rc, w|
      w.viewport_bounds.x.should be_close(w.absolute_bounds.x, 0.5)
      w.viewport_bounds.y.should be_close(w.absolute_bounds.y, 0.5)
    end
  end
end

# The matrix's own drag ghost: its bounding box is built by hand (it spans several cells, so
# `viewport_bounds` cannot compute it), which is exactly the kind of hand-rolled conversion that
# forgets the OTHER scroller — the panel the matrix itself sits in.
describe "scroll-space sweep: a matrix inside a scrolled panel" do
  it "builds its drag ghost in window space" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("t", 400, 300)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "panel_sv")
    stack = CrymbleUI::VStack.new(spacing: 0.0)
    6.times { stack.add_child(CrymbleUI::Button.new("pad") { }) }
    matrix = CrymbleUI::VirtualMatrix.new(SweepMatrixAdapter.new(20, 20), id: "inner_matrix")
    stack.add_child(matrix)
    sv.set_content(stack)
    window.add_child(sv)
    app.root_widget = window
    app.build_tree
    renderer.settle_rendering(app)

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 60.0))
    renderer.render_frame(app)
    sv.scroll_offset.y.should be > 0.0 # instrument

    # The painted matrix is the panel scroll above its laid-out position.
    matrix.viewport_bounds.y.should be_close(matrix.absolute_bounds.y - sv.scroll_offset.y, 0.5)
  end
end
