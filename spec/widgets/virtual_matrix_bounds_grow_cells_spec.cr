require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/testing/configurable_matrix_adapter"
require "../../src/rendering/layer_renderer"

# Reproducer for the "Shape matrix columns inconsistent after Filter collapse"
# bug reported at /tmp/2026-04-18_21-39.png: after the VM's vertical viewport
# grows (e.g. a section above collapses, releasing height), some columns
# kept their stale cell widgets for newly visible rows while others had
# fresh cells, producing the characteristic "rank column shows 1-9 then
# blank, other columns show all 13" pattern.
#
# At the VM level this should NOT happen: every (visible_row, visible_col)
# pair must have a live cell widget in @active_cells after layout settles.

class GrowTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...@rows).to_a, (0...@cols).to_a}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

private def make_grow_matrix(rows : Int32, cols : Int32)
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 1000)
  app = TestApp.new
  adapter = GrowTestAdapter.new(rows, cols)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "grow_test")
  app.root_widget = matrix
  app.build_tree
  {renderer, app, matrix}
end

describe "VirtualMatrix: bounds grow must create cells for every new visible row" do
    it "after viewport height grows, every visible row has cells in every visible column" do
        # 20 data rows, 5 cols — enough rows that initially only some fit
        renderer, app, matrix = make_grow_matrix(20, 5)

        # Phase 1: small viewport — only a few rows fit
        small = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 200.0))
        matrix.layout(small, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        rows_small = matrix.@visible_rows.dup
        cols_small = matrix.@visible_cols.dup
        rows_small.size.should be > 0
        cols_small.size.should be > 0

        # Phase 2: grow viewport height — more rows become visible
        large = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 900.0))
        matrix.layout(large, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        rows_large = matrix.@visible_rows
        cols_large = matrix.@visible_cols
        rows_large.size.should be > rows_small.size, "viewport grew but visible_rows didn't expand"

        # Every (visible_row, visible_col) pair MUST have a live cell widget.
        missing = [] of Tuple(Int32, Int32)
        rows_large.each do |r|
          cols_large.each do |c|
            missing << {r, c} unless matrix.@active_cells.has_key?({r, c})
          end
        end
        missing.empty?.should be_true,
          "after viewport grow, #{missing.size} cells are missing from @active_cells: #{missing.first(10).inspect}…"
    end

    it "user scenario: invalidate_all THEN bounds grow keeps cell grid consistent" do
        # Mirrors the embrace filter bug: a filter toggle calls invalidate_all!
        # (triggers @pending_invalidate_all), then the Filter section collapses,
        # growing the matrix's viewport. The user saw column 0 showing rows 1-9
        # with rows 10-13 blank, while other columns showed all 13.
        renderer, app, matrix = make_grow_matrix(15, 5)

        # Start with a small viewport
        small = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 200.0))
        matrix.layout(small, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        # Simulate adapter.invalidate_all! (what embrace's filter_set_values does)
        matrix.@adapter.not_nil!.invalidate_all!

        # Immediately grow viewport (user's "collapse Filter section" action)
        large = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 900.0))
        matrix.layout(large, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        rows_visible = matrix.@visible_rows.dup
        cols_visible = matrix.@visible_cols.dup

        # Every visible (row, col) pair MUST have a cell — no per-column gaps
        per_col_counts = cols_visible.map do |c|
            rows_visible.count { |r| matrix.@active_cells.has_key?({r, c}) }
        end
        # All columns should report the same count (= rows_visible.size)
        per_col_counts.uniq.size.should eq(1),
          "cell count differs by column after invalidate_all + grow: #{cols_visible.zip(per_col_counts).inspect}"
        per_col_counts.first.should eq(rows_visible.size),
          "not all visible rows have cells (got #{per_col_counts.first}, expected #{rows_visible.size})"
    end

    it "sticky-column adapter: bounds grow after invalidate_all leaves no per-column gaps" do
        # Embrace-shaped setup but with NON-MERGED row-headers (each data row
        # has its own sticky-column cell, matching the observed Rank column
        # that shows distinct values per row). leaf_span = 1 → no merging.
        renderer = CrymbleUI::Testing::TestRenderer.new(1000, 1000)
        app = TestApp.new
        # nrhl=1 sticky col + nchl=1 sticky row; rhs=1 chs=1, lrs=1 lcs=1 with
        # 14^1=14 data rows doesn't work with this adapter's formula, so use
        # rhs=14 chs=4 nrhl=1 nchl=1 lrs=1 lcs=1 → 14 rows × 4 cols, no merge.
        adapter = ConfigurableMatrixAdapter.new(1, 1, 14, 4, 1, 1)
        matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_grow")
        app.root_widget = matrix
        app.build_tree

        # Phase 1: small viewport
        small = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 250.0))
        matrix.layout(small, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        # User's trigger: adapter invalidate_all then immediately grow viewport
        adapter.invalidate_all!
        large = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 900.0))
        matrix.layout(large, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        visible_rows = matrix.@visible_rows.dup
        visible_cols = matrix.@visible_cols.dup
        visible_rows.size.should be > 5    # should have expanded well past 5
        visible_cols.size.should be >= 3

        # Per-column cell count must be identical across all visible columns
        # (no merges → every (row,col) should be its own widget).
        per_col = visible_cols.map do |c|
            visible_rows.count { |r| matrix.@active_cells.has_key?({r, c}) }
        end
        per_col.uniq.size.should eq(1),
          "cell count differs by column after invalidate_all + grow: cols=#{visible_cols.inspect} counts=#{per_col.inspect}"
    end

    it "performance: a pure bounds-grow should not re-create cells that were already visible" do
        # Catches the opposite extreme — a "fix" that nukes all cells on every
        # layout (which would work but cripple 60fps). Cells that were already
        # in the viewport before the grow must survive the grow.
        renderer, app, matrix = make_grow_matrix(20, 5)

        small = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 200.0))
        matrix.layout(small, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        # Capture initial cells' object ids (proves survival across layout)
        prior_cells = matrix.@active_cells.dup

        large = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 900.0))
        matrix.layout(large, CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        # Every cell that was active before must still be the same object
        preserved = 0
        prior_cells.each do |key, widget|
          if current = matrix.@active_cells[key]?
            preserved += 1 if current.same?(widget)
          end
        end
        preserved.should eq(prior_cells.size),
          "bounds-grow destroyed previously-visible cells — would cripple 60fps resize"
    end
end
