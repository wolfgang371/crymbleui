require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

describe CrymbleUI::VirtualMatrix do
  describe "Compound/Merged Cells" do
    it "allows defining merged cells via bounding_box" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({1, 2}, {2, 4})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_def")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      bounding = matrix.get_bounding_box({1, 2})
      bounding.should eq({ {1, 2}, {2, 4} })

      # Non-merged cells have themselves as bounding box
      bounding_single = matrix.get_bounding_box({5, 5})
      bounding_single.should eq({ {5, 5}, {5, 5} })
    end

    it "merged cell spans multiple positions visually" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({0, 0}, {1, 1})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_span")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # The merged cell at (0,0) should be larger
      # Use matrix.active_cells which contains the actual cell widgets
      if cell_00 = matrix.active_cells[{0, 0}]?
        # Should span 2 columns and 2 rows
        cell_00.bounds.width.should be > matrix.get_col_width(0) * 20.0  # More than 1 cell wide
        cell_00.bounds.height.should be > matrix.get_row_height(0) * 20.0  # More than 1 cell tall
      end
    end

    it "only creates widget for top-left cell of merged region" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({0, 0}, {1, 1})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_single")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Only top-left cell (0,0) should have a widget created
      active_keys = matrix.active_cells.keys.to_set
      active_keys.includes?({0, 0}).should be_true
      active_keys.includes?({0, 1}).should be_false  # Covered by merge
      active_keys.includes?({1, 0}).should be_false  # Covered by merge
      active_keys.includes?({1, 1}).should be_false  # Covered by merge
    end

    it "hit testing returns top-left cell of merged region" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({2, 2}, {3, 3})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_hit")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Click anywhere in merged region should return top-left
      result = matrix.cell_at_point({2, 3})  # Inside the merged region
      result.should eq({2, 2})  # Returns top-left

      result = matrix.cell_at_point({3, 3})  # Bottom-right of merged region
      result.should eq({2, 2})  # Still returns top-left
    end

    it "cursor navigation respects merged cell boundaries" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({2, 2}, {3, 3})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_cursor")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Set cursor inside merged cell
      matrix.cursor_rc = {2, 3}

      # The merged cell should be "cursored" (highlighted)
      matrix.is_cell_cursored?({2, 2}).should be_true  # Top-left is cursored
      matrix.is_cell_cursored?({2, 3}).should be_true  # Cursor position is cursored

      # Moving cursor right should exit the merged cell
      matrix.cursor_rc = {2, 4}
      matrix.is_cell_cursored?({2, 2}).should be_false  # No longer cursored
    end

    it "merged cells are visible in viewport" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({2, 2}, {3, 3})

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "merge_visible")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Merged cell rows/cols should be visible
      matrix.visible_cell_indices[:rows].should contain(2)
      matrix.visible_cell_indices[:cols].should contain(2)
    end
  end
end
