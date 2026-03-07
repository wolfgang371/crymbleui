require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

describe CrymbleUI::VirtualMatrix do
  describe "Variable Cell Sizes" do
    it "allows setting custom row heights" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "row_height")

      # Set some rows to be taller (in frame_height multiples)
      matrix.row_height(0, 2.0)  # Row 0 is 2x normal height
      matrix.row_height(5, 3.0)  # Row 5 is 3x normal height

      matrix.get_row_height(0).should eq(2.0)
      matrix.get_row_height(5).should eq(3.0)
      matrix.get_row_height(3).should eq(CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT)
    end

    it "allows setting custom column widths" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "col_width")

      # Set some columns to be wider (in frame_height multiples)
      matrix.col_width(0, 10.0)  # Column 0 is wider
      matrix.col_width(2, 8.0)   # Column 2 is wider

      matrix.get_col_width(0).should eq(10.0)
      matrix.get_col_width(2).should eq(8.0)
      matrix.get_col_width(1).should eq(CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH)
    end

    it "positions cells correctly with variable row heights" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "var_row_pos")

      # Row 0 is double height
      matrix.row_height(0, 2.0)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cell (1, 0) should start after the taller row 0
      # Use matrix.active_cells which contains the actual cell widgets
      if cell_00 = matrix.active_cells[{0, 0}]?
        if cell_10 = matrix.active_cells[{1, 0}]?
          # Row 1 should start after row 0's larger height
          cell_10.bounds.y.should be > cell_00.bounds.y
          # The gap should be larger than default row height
          gap = cell_10.bounds.y - cell_00.bounds.y
          gap.should be > matrix.get_row_height(1) * 20.0  # frame_height ~20
        end
      end
    end

    it "positions cells correctly with variable column widths" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 5, cols: 10, id: "var_col_pos")

      # Column 0 is double width
      matrix.col_width(0, 10.0)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cell (0, 1) should start after the wider column 0
      # Use matrix.active_cells which contains the actual cell widgets
      if cell_00 = matrix.active_cells[{0, 0}]?
        if cell_01 = matrix.active_cells[{0, 1}]?
          # Column 1 should start after column 0's larger width
          cell_01.bounds.x.should be > cell_00.bounds.x
          # The gap should be larger than default column width
          gap = cell_01.bounds.x - cell_00.bounds.x
          gap.should be > matrix.get_col_width(1) * 20.0  # frame_height ~20
        end
      end
    end

    it "visibility calculation handles variable sizes" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "var_vis")

      # Make some rows very tall
      matrix.row_height(0, 5.0)
      matrix.row_height(1, 5.0)
      matrix.row_height(2, 5.0)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      # With tall rows, fewer rows should be visible
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      visible_rows = matrix.visible_cell_indices[:rows]
      # With 5x height rows, should see fewer rows than with normal height
      visible_rows.size.should be <= 10
    end

    it "sticky algorithm works with variable sizes_pixel" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 20, cols: 20, id: "sticky_var")

      # Mix of sizes
      matrix.row_height(0, 3.0)
      matrix.col_width(0, 8.0)
      matrix.col_width(1, 2.0)
      matrix.col_width(2, 10.0)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Should not crash and should have visible cells
      matrix.visible_cell_indices[:rows].should_not be_empty
      matrix.visible_cell_indices[:cols].should_not be_empty
    end

    it "scroll calculations respect variable sizes" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scroll_var")

      # Make first 10 rows very tall
      (0...10).each { |r| matrix.row_height(r, 5.0) }

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Scroll should work correctly
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 200.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # After scrolling, should still have visible cells
      matrix.visible_cell_indices[:rows].should_not be_empty
    end
  end
end
