require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Repro for the column-count vs custom_col_widths MISMATCH (Wolfgang, 2026-05-30):
# "blank, add [Commits], widen c2 → scrolling breaks (only the h-ruler scrolls)" + an intermittent
#   Index out of bounds (IndexError)
#     from virtual_matrix.cr:443 in 'get_col_width'   (@col_widths[col])
#     from ... 'total_content_width' → 'effective_content_size' → 'max_content_scroll_x'
#     from ... 'copy_state_from' (reconcile)
#
# Root cause: MatrixAdapter#get_sizes returned `custom_col_widths` verbatim without checking its
# length against the current `col_order.size`. custom_col_widths is persisted on a column resize
# (adapter.custom_col_widths = @col_widths.dup). When the column structure later changes (commits
# added/removed, fields added) the persisted array is the wrong length → @col_widths.size ≠ @cols.
# The ruler iterates 0...@cols and the data extent uses @col_widths → they desync (only the ruler
# scrolls), and indexing @col_widths past its end raises IndexError.

class CSMAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  property ncols : Int32
  property nrows : Int32

  def initialize(@nrows : Int32 = 3, @ncols : Int32 = 5)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...@nrows).to_a, (0...@ncols).to_a}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

describe "MatrixAdapter#get_sizes — custom size / order length mismatch" do
  it "returns col_widths matching col_order.size even when custom_col_widths is too short" do
    adapter = CSMAdapter.new(ncols: 5)
    # Persisted when there were only 3 columns (e.g. a widen on a smaller [Commits] view).
    adapter.custom_col_widths = [1.0, 2.0, 3.0]
    _, cols = adapter.get_sizes
    cols.size.should eq(5) # must match the CURRENT column count, not the stale custom length
    # Existing per-column widths are preserved; new slots take the default.
    cols[0].should eq(1.0)
    cols[1].should eq(2.0)
    cols[2].should eq(3.0)
  end

  it "truncates custom_col_widths when columns were removed" do
    adapter = CSMAdapter.new(ncols: 2)
    adapter.custom_col_widths = [1.0, 2.0, 3.0, 4.0] # 4 persisted, now only 2 columns
    _, cols = adapter.get_sizes
    cols.size.should eq(2)
    cols.should eq([1.0, 2.0])
  end

  it "normalizes custom_row_heights the same way" do
    adapter = CSMAdapter.new(nrows: 4)
    adapter.custom_row_heights = [1.0] # 1 persisted, now 4 rows
    rows, _ = adapter.get_sizes
    rows.size.should eq(4)
    rows[0].should eq(1.0)
  end
end

describe "VirtualMatrix — stale custom_col_widths must not crash or desync" do
  it "keeps @col_widths.size == @cols and computes content width without IndexError" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    adapter = CSMAdapter.new(ncols: 5)
    adapter.custom_col_widths = [1.0, 2.0] # stale: only 2 entries, but 5 columns
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "m")

    app.root_widget = matrix
    app.build_tree # matrix init reads get_sizes

    matrix.@col_widths.size.should eq(5) # invariant: widths array matches column count

    # The exact path that raised in the crash (total_content_width → get_col_width over 0...@cols).
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app) # must not raise IndexError
    (0...5).each { |c| matrix.get_col_width(c) } # every column index is addressable
  end
end
