require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Adapter with grouped scroll_order simulating TaskBoard-like sticky headers.
# Col 0 is sticky (last in scroll_order), other cols are grouped.
class StickySnapAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @col_scroll_order : Array(Int32)
  @row_scroll_order : Array(Int32)

  def initialize(@rows : Int32, @cols : Int32,
                 @col_scroll_order : Array(Int32),
                 @row_scroll_order : Array(Int32))
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {@row_scroll_order, @col_scroll_order}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

private def setup_sticky_snap_matrix(viewport_width = 500.0, viewport_height = 300.0)
  # 20 rows x 8 cols, grouped scroll_order (col 0 sticky, rest grouped)
  col_scroll_order = [2, 3, 4, 1, 6, 7, 5, 0]
  row_scroll_order = (1..19).to_a + [0]

  adapter = StickySnapAdapter.new(20, 8, col_scroll_order, row_scroll_order)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_snap_test")

  # Col 0 = 83px (4.0 * 20 + 3), cols 1-7 = 103px each (5.0 * 20 + 3)
  matrix.col_width(0, 4.0)

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "snap_to_cursor with grouped scroll_order and sticky headers" do
    # Cell pixel sizes:
    #   Col 0: GRID_SPACING(3) + 4.0 * frame_height(20) = 83px (sticky)
    #   Cols 1-7: GRID_SPACING(3) + 5.0 * frame_height(20) = 103px each
    # Data positions (cumulative): col0=0, col1=83, col2=186, col3=289, ...
    # Sticky col 0 occupies screen x=[0, 83). Content behind it is hidden.

    it "navigating left to cell behind sticky header triggers snap" do
      matrix, _, constraints = setup_sticky_snap_matrix

      # Scroll right 100px, then re-layout
      matrix.scroll_offset = CrymbleUI::Vec2.new(100.0, 0.0)
      matrix.mark_needs_layout
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cursor at (3, 2), press left → cursor moves to (3, 1)
      matrix.cursor_rc = {3, 2}
      matrix.move_cursor(:left)
      matrix.cursor_rc[1].should eq(1)

      # Col 1 data_pos=83, at scroll=100: screen_pos = 83-100 = -17px (behind sticky header)
      # Snap should scroll left so col 1 is visible: target = data_pos - sticky_width = 83 - 83 = 0
      matrix.snap_to_cursor
      matrix.scroll_offset.x.should eq(0.0),
        "Expected snap to x=0 (col 1 hidden behind sticky header at scroll=100), got #{matrix.scroll_offset.x}"
    end

    it "navigating left to fully visible cell does not snap" do
      matrix, _, constraints = setup_sticky_snap_matrix

      # Scroll right only 5px, then re-layout
      matrix.scroll_offset = CrymbleUI::Vec2.new(5.0, 0.0)
      matrix.mark_needs_layout
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cursor at (3, 3), press left → cursor moves to (3, 2)
      matrix.cursor_rc = {3, 3}
      matrix.move_cursor(:left)
      matrix.cursor_rc[1].should eq(2)

      # Col 2 data_pos=186, at scroll=5: screen_pos = 186-5 = 181px > sticky_width(83)
      # Col 2 is fully visible → no snap should occur
      matrix.snap_to_cursor
      matrix.scroll_offset.x.should eq(5.0),
        "Expected no snap (col 2 fully visible at screen_pos=181 > sticky_width=83), got #{matrix.scroll_offset.x}"
    end
  end
end
