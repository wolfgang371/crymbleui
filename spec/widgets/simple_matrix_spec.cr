require "../spec_helper"
require "../../src/widgets/simple_matrix"

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

  it "reports sticky rows as a trailing contiguous set in row_order" do
    rows = Array.new(4) { |_| [] of CrymbleUI::Widget }
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: rows, sticky_row_count: 1)
    row_order, _ = adapter.get_scrollorder
    # Trailing set must be {0..K-1} = {0}. Non-sticky rows (1, 2, 3) first, then 0.
    row_order.should eq [1, 2, 3, 0]
  end

  it "reports sticky cols as a trailing contiguous set in col_order" do
    rows = [Array.new(4) { |_| CrymbleUI::Text.new("").as(CrymbleUI::Widget) }]
    adapter = CrymbleUI::SimpleMatrixAdapter.new(rows: rows, sticky_col_count: 2)
    _, col_order = adapter.get_scrollorder
    col_order.should eq [2, 3, 0, 1]
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
