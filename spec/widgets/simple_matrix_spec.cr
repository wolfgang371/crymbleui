require "../spec_helper"
require "../../src/widgets/simple_matrix"

private def derived_counts(rows, sticky_row_count = 0, sticky_col_count = 0) : {Int32, Int32}
  adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: rows,
    sticky_row_count: sticky_row_count, sticky_col_count: sticky_col_count)
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter)
  {matrix.sticky_row_count, matrix.sticky_col_count}
end

private def wide_row(n : Int32)
  [Array.new(n) { |_| CrymbleUI::Text.new("").as(CrymbleUI::Widget) }]
end

describe CrymbleUI::SimpleMatrixAdapter do
  it "returns the widget supplied for each cell" do
    w_00 = CrymbleUI::Text.new("A")
    w_01 = CrymbleUI::Text.new("B")
    w_10 = CrymbleUI::Text.new("C")
    w_11 = CrymbleUI::Text.new("D")
    adapter = CrymbleUI::SimpleMatrixAdapter.new(
      rows: [[w_00, w_01], [w_10, w_11]].map(&.map(&.as(CrymbleUI::Widget))),
    )
    adapter.cell_paint(0, 0).should be w_00
    adapter.cell_paint(1, 1).should be w_11
  end

  # Stickiness is DERIVED, never declared: VirtualMatrix#derive_sticky_count scans the order from
  # the end and keeps the run only while the accumulated set is {0..k-1} at EVERY step, breaking at
  # the first miss. So the tail must be DESCENDING — [.., 1, 0], not [.., 0, 1] — or the very first
  # element read is {1}, which is not {0}, and the count is zero.
  #
  # These examples assert what the MATRIX derives, not the array this adapter returns. Asserting the
  # array is asserting a proxy: it passed for years while `sticky_col_count: 2` silently produced a
  # matrix with no sticky columns at all (measured 2026-09-05).
  it "makes the requested number of columns actually sticky" do
    (1..3).each do |n|
      _, cols = derived_counts(wide_row(6), sticky_col_count: n)
      cols.should eq(n), "asked for #{n} sticky columns, matrix derived #{cols}"
    end
  end

  it "makes the requested number of rows actually sticky" do
    (1..3).each do |n|
      rows = Array.new(6) { [CrymbleUI::Text.new("").as(CrymbleUI::Widget)] }
      derived, _ = derived_counts(rows, sticky_row_count: n)
      derived.should eq(n), "asked for #{n} sticky rows, matrix derived #{derived}"
    end
  end

  it "puts the sticky columns at the tail, descending" do
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: wide_row(4), sticky_col_count: 2)
    _, col_order = adapter.get_scrollorder
    col_order.should eq [2, 3, 1, 0]
  end

  it "puts the sticky rows at the tail, descending" do
    rows = Array.new(4) { [CrymbleUI::Text.new("").as(CrymbleUI::Widget)] }
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: rows, sticky_row_count: 2)
    row_order, _ = adapter.get_scrollorder
    row_order.should eq [2, 3, 1, 0]
  end

  it "returns header_info truthy for header rows only" do
    rows = [[] of CrymbleUI::Widget, [] of CrymbleUI::Widget, [] of CrymbleUI::Widget]
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: rows, header_row_count: 1)
    adapter.cell_get_header_info(0, 0).should eq({true, 0})
    adapter.cell_get_header_info(1, 0).should be_nil
    adapter.cell_get_header_info(2, 0).should be_nil
  end

  it "returns an empty-text fallback for out-of-range cells" do
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: [] of Array(CrymbleUI::Widget))
    adapter.cell_paint(0, 0).should be_a(CrymbleUI::Text)
  end
end

describe CrymbleUI::SimpleMatrixBuilder do
  it "accumulates header + data rows in order" do
    b = CrymbleUI::SimpleMatrixBuilder.new
    b.header "Name", "Value"
    b.row { |r| r << CrymbleUI::Text.new("alpha").as(CrymbleUI::Widget); r << CrymbleUI::Text.new("1").as(CrymbleUI::Widget) }
    b.row { |r| r << CrymbleUI::Text.new("beta").as(CrymbleUI::Widget); r << CrymbleUI::Text.new("2").as(CrymbleUI::Widget) }
    b.rows.size.should eq 3           # 1 header + 2 data
    b.header_count.should eq 1
    b.rows[0].size.should eq 2        # header has 2 cells
    b.rows[1].size.should eq 2
    b.rows[2].size.should eq 2
  end
end
