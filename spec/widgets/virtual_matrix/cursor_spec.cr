require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Test app for cursor preservation (must be outside describe block)
class CursorPreserveApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "cursor_preserve")
  end
end

describe CrymbleUI::VirtualMatrix do
  describe "Cursor and Cross-Highlight" do
    it "has cursor at (0,0) by default" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "cursor_default")
      matrix.cursor_rc.should eq({0, 0})
    end

    it "can set cursor position" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "cursor_set")
      matrix.cursor_rc = {5, 3}
      matrix.cursor_rc.should eq({5, 3})
    end

    it "clamps cursor to valid bounds" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "cursor_clamp")
      matrix.cursor_rc = {15, 20}  # Out of bounds

      # After layout, cursor should be clamped
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Should be clamped to max valid position
      matrix.cursor_rc[0].should be <= 9
      matrix.cursor_rc[1].should be <= 9
    end

    it "row highlight marks entire cursor row" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "row_highlight")
      matrix.cursor_rc = {3, 5}

      matrix.is_row_highlighted?(3).should be_true
      matrix.is_row_highlighted?(2).should be_false
      matrix.is_row_highlighted?(4).should be_false
    end

    it "column highlight marks entire cursor column" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "col_highlight")
      matrix.cursor_rc = {3, 5}

      matrix.is_col_highlighted?(5).should be_true
      matrix.is_col_highlighted?(4).should be_false
      matrix.is_col_highlighted?(6).should be_false
    end

    it "arrow keys move cursor" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "arrow_nav")
      matrix.cursor_rc = {5, 5}

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Move right
      matrix.move_cursor(:right)
      matrix.cursor_rc.should eq({5, 6})

      # Move down
      matrix.move_cursor(:down)
      matrix.cursor_rc.should eq({6, 6})

      # Move left
      matrix.move_cursor(:left)
      matrix.cursor_rc.should eq({6, 5})

      # Move up
      matrix.move_cursor(:up)
      matrix.cursor_rc.should eq({5, 5})
    end

    it "cursor stays within bounds on navigation" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "nav_bounds")
      matrix.cursor_rc = {0, 0}

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Try to move left (should stay at 0)
      matrix.move_cursor(:left)
      matrix.cursor_rc[1].should eq(0)

      # Try to move up (should stay at 0)
      matrix.move_cursor(:up)
      matrix.cursor_rc[0].should eq(0)

      # Go to bottom-right corner
      matrix.cursor_rc = {9, 9}

      # Try to move right (should stay at 9)
      matrix.move_cursor(:right)
      matrix.cursor_rc[1].should eq(9)

      # Try to move down (should stay at 9)
      matrix.move_cursor(:down)
      matrix.cursor_rc[0].should eq(9)
    end

    it "Ctrl+arrows jump to edge" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "ctrl_nav")
      matrix.cursor_rc = {5, 5}

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Ctrl+Right -> last column
      matrix.move_cursor(:right, ctrl: true)
      matrix.cursor_rc.should eq({5, 9})

      # Ctrl+Down -> last row
      matrix.move_cursor(:down, ctrl: true)
      matrix.cursor_rc.should eq({9, 9})

      # Ctrl+Left -> first column
      matrix.move_cursor(:left, ctrl: true)
      matrix.cursor_rc.should eq({9, 0})

      # Ctrl+Up -> first row
      matrix.move_cursor(:up, ctrl: true)
      matrix.cursor_rc.should eq({0, 0})
    end

    it "Home/End keys work" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "home_end")
      matrix.cursor_rc = {5, 5}

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Home -> first column of current row
      matrix.move_cursor(:home)
      matrix.cursor_rc.should eq({5, 0})

      # End -> last column of current row
      matrix.move_cursor(:end)
      matrix.cursor_rc.should eq({5, 9})

      # Ctrl+Home -> first cell
      matrix.move_cursor(:home, ctrl: true)
      matrix.cursor_rc.should eq({0, 0})

      # Ctrl+End -> last cell
      matrix.move_cursor(:end, ctrl: true)
      matrix.cursor_rc.should eq({9, 9})
    end

    it "Tab wraps to next row" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "tab_wrap")
      matrix.cursor_rc = {0, 9}  # End of first row

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Tab from end of row should wrap to next row
      matrix.move_cursor(:tab)
      matrix.cursor_rc.should eq({1, 0})

      # Shift+Tab should wrap back
      matrix.move_cursor(:tab, shift: true)
      matrix.cursor_rc.should eq({0, 9})
    end

    it "snap_to_cursor scrolls to show cursor" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "snap")
      matrix.cursor_rc = {0, 0}
      matrix.scroll_offset = CrymbleUI::Vec2.zero

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Move cursor far down (out of viewport)
      matrix.cursor_rc = {50, 0}
      matrix.snap_to_cursor

      # Scroll should have changed to show cursor
      matrix.scroll_offset.y.should be > 0.0
    end

    it "mouse click sets cursor position" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "click_cursor")
      matrix.cursor_rc = {0, 0}

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Simulate click on cell (3, 4) - need to calculate pixel position
      # For simplicity, test the method directly
      matrix.set_cursor_from_cell({3, 4})
      matrix.cursor_rc.should eq({3, 4})
    end

    it "click on merged cell stores exact cell, not top-left (WU4)" do
      adapter = MergeableTestAdapter.new(10, 10)
      adapter.add_merge({0, 3}, {0, 4})
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "cursor_exact")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Click on (0,4) inside merged region → should store exact cell (0,4)
      matrix.set_cursor_from_cell({0, 4})
      matrix.cursor_rc.should eq({0, 4})

      # Both cells in the merged region should report as cursored
      matrix.is_cell_cursored?({0, 3}).should be_true
      matrix.is_cell_cursored?({0, 4}).should be_true

      # Arrow right from (0,4) → (0,5)
      matrix.move_cursor(:right)
      matrix.cursor_rc.should eq({0, 5})
    end

    it "cursor position preserved on rebuild" do
      app = CursorPreserveApp.new
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)

      # Set cursor
      matrix = app.find("cursor_preserve").as(CrymbleUI::VirtualMatrix)
      matrix.cursor_rc = {25, 30}

      # Trigger rebuild
      app.rebuild

      # Cursor should be preserved
      new_matrix = app.find("cursor_preserve").as(CrymbleUI::VirtualMatrix)
      new_matrix.cursor_rc.should eq({25, 30})
    end
  end
end
