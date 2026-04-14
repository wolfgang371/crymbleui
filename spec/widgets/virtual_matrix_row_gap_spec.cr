require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"
require "../../src/testing/configurable_matrix_adapter"

# Local subclass: use Text instead of TextInput for headless spec testing
class RowGapTextAdapter < ConfigurableMatrixAdapter
  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new(text: @data[{row, col}])
  end
end

# DSL-style app matching demo structure: window → vstack → expanded → VirtualMatrix
# Uses 1400×900 window like the real demo.
class RowGapDemoApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    adapter = RowGapTextAdapter.new(
      nrhl: 2, nchl: 2, rhs: 3, chs: 3, lrs: 10, lcs: 10
    )

    window("Test", 1400, 900) do
      vstack(padding: 10.0, spacing: 5.0) do
        text("VirtualMatrix Demo", color: CrymbleUI::Color.new(0, 0, 0, 255))
        hstack(spacing: 10.0) do
          text("col_hdr_levels: 2")
          text("row_hdr_levels: 2")
          text("row_hdr_span: 3")
        end
        hstack(spacing: 10.0) do
          text("col_hdr_span: 3")
          text("leaf_row_span: 10")
          text("leaf_col_span: 10")
        end
        text("Size: 92x92")
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(
            adapter: adapter,
            id: "gap_matrix",
            cursor_highlight_delta: -30,
            content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
          ))
        end
        hstack(spacing: 20.0) do
          text("Arrow keys: Navigate")
        end
      end
    end
  end
end

# Regression test: data rows at the level-0 row header group boundary (grid rows 30-33)
# are missing from the initial render of the demo-config VirtualMatrix (92×92 grid).
#
# The demo shows a gap: data row indices jump from 27 to 32, skipping rows 28-31
# (grid rows 30-33). This is at the boundary between level-0 row header group 1
# ({2,0}→{31,0}) and group 2 ({32,0}→{61,0}).
#
# Grid geometry (demo config):
#   nrhl=2, nchl=2, rhs=3, chs=3, lrs=10, lcs=10
#   92 rows × 92 cols (2 header + 90 data each)
#   frame_height=20, GRID_SPACING=3, default row=23px, header row (1.5×)=33px
#   ruler_row_height=20px
#   Grid row 30: y = ruler(20) + 2×33 + 28×23 = 730px in content space
#   Grid row 33: y = ruler(20) + 2×33 + 31×23 = 799px in content space
#   With 1400×900 window, vstack overhead reduces effective viewport to ~753px
#   → rows 31-33 fall at the viewport edge

describe "VirtualMatrix row gap at header boundary", tags: "slow" do
  it "data rows at level-0 header boundary are present in active_cells" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = RowGapDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("gap_matrix").as(CrymbleUI::VirtualMatrix)

    # Grid rows 30-33 (data rows 28-31) should exist as active cells.
    # Col 2 is the first data column.
    # Even if outside the viewport, the creation buffer should include them.
    boundary_rows = [30, 31, 32, 33]
    data_col = 2

    missing_rows = [] of Int32
    boundary_rows.each do |grid_row|
      unless matrix.active_cells.has_key?({grid_row, data_col})
        missing_rows << grid_row
      end
    end

    missing_rows.should be_empty,
      "Data cells missing at header boundary: grid rows #{missing_rows} col #{data_col}. " \
      "Active cells near boundary: #{matrix.active_cells.keys.select { |k| k[1] == data_col && k[0] >= 26 && k[0] <= 37 }.sort}"
  end

  it "visible_rows includes rows at header group boundary" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = RowGapDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("gap_matrix").as(CrymbleUI::VirtualMatrix)
    visible = matrix.visible_cell_indices

    # Grid rows 30-33 (data rows 28-31) straddle the level-0 header boundary.
    # Row 31 starts at y=733 in cell-space, exactly at the viewport's max_y.
    # The visible_rows filter uses <= so rows whose top edge touches max_y are included.
    # Rows 32-33 start beyond max_y (756, 779) and are correctly excluded.
    boundary_rows = [30, 31]
    missing_visible = boundary_rows.reject { |r| visible[:rows].includes?(r) }

    missing_visible.should be_empty,
      "Grid rows #{missing_visible} not in visible_rows. " \
      "visible_rows near boundary: #{visible[:rows].select { |r| r >= 26 && r <= 37 }.sort}"
  end

  it "data row indices are sequential across header group boundary" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = RowGapDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("gap_matrix").as(CrymbleUI::VirtualMatrix)
    data_col = 2

    # Collect all active data cells in col 2, sorted by grid row
    active_data_rows = matrix.active_cells.keys
      .select { |k| k[1] == data_col && k[0] >= 2 }
      .map { |k| k[0] }
      .sort

    active_data_rows.size.should be > 10,
      "Expected many active data rows, got #{active_data_rows.size}: #{active_data_rows}"

    # Check for gaps: consecutive rows should differ by exactly 1
    gaps = [] of Tuple(Int32, Int32)
    (0...active_data_rows.size - 1).each do |i|
      diff = active_data_rows[i + 1] - active_data_rows[i]
      if diff > 1
        gaps << {active_data_rows[i], active_data_rows[i + 1]}
      end
    end

    gaps.should be_empty,
      "Gaps found in data row sequence at col #{data_col}: " \
      "#{gaps.map { |g| "rows #{g[0]+1}..#{g[1]-1} missing (between #{g[0]} and #{g[1]})" }.join(", ")}. " \
      "All active rows: #{active_data_rows}"
  end

  it "no y-position gaps between consecutive data rows at header boundary" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = RowGapDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("gap_matrix").as(CrymbleUI::VirtualMatrix)
    data_col = 2

    # Collect data cells at col 2 with their y-position and height
    cell_positions = [] of {Int32, Float64, Float64}  # {grid_row, y, height}
    matrix.active_cells.each do |key, widget|
      row, col = key
      next unless col == data_col && row >= 2  # data cells only
      cell_positions << {row, widget.bounds.y, widget.bounds.height}
    end
    cell_positions.sort_by! { |cp| cp[1] }

    cell_positions.size.should be > 10,
      "Expected many data cells, got #{cell_positions.size}"

    # Check for visual gaps: end of one cell + GRID_SPACING should align with next cell's start.
    grid_spacing = 3.0
    tolerance = 1.0  # 1px tolerance for rounding
    visual_gaps = [] of {Int32, Int32, Float64}

    (0...cell_positions.size - 1).each do |i|
      row_a, y_a, h_a = cell_positions[i]
      row_b, y_b, _h_b = cell_positions[i + 1]
      expected_next_y = y_a + h_a + grid_spacing
      gap = y_b - expected_next_y
      if gap > tolerance
        visual_gaps << {row_a, row_b, gap}
      end
    end

    visual_gaps.should be_empty,
      "Visual y-position gaps found between data rows at col #{data_col}: " \
      "#{visual_gaps.map { |g| "row #{g[0]}→#{g[1]}: gap=#{g[2].round(1)}px" }.join(", ")}. " \
      "This indicates missing or mispositioned rows at header group boundary."
  end
end
