require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Adapter with configurable scroll_order for snap_to_cursor tests
class SnapCursorAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @col_scroll_order : Array(Int32)
  @row_scroll_order : Array(Int32)

  def initialize(@rows : Int32, @cols : Int32,
                 col_scroll_order : Array(Int32)? = nil,
                 row_scroll_order : Array(Int32)? = nil)
    @col_scroll_order = col_scroll_order || (0...@cols).to_a
    @row_scroll_order = row_scroll_order || (0...@rows).to_a
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {@row_scroll_order, @col_scroll_order}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

# Helper to set up matrix with adapter
private def setup_snap_matrix(adapter, viewport_width = 400.0, viewport_height = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "snap_cursor_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "snap_to_cursor with scroll orders" do
    it "snap_to_cursor with sequential scroll_order behaves like before" do
      adapter = SnapCursorAdapter.new(100, 50)
      matrix, _, _ = setup_snap_matrix(adapter)

      # Move cursor far down (out of viewport)
      matrix.cursor_rc = {50, 0}
      matrix.snap_to_cursor

      # Scroll should have moved to show cursor
      matrix.scroll_offset.y.should be > 0.0
    end

    it "cursor on sticky col does not snap scroll back when already scrolled" do
      # scroll_order [1,2,...,9,0]: col 0 scrolls out LAST (always visible)
      adapter = SnapCursorAdapter.new(10, 10,
        col_scroll_order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
      matrix, _, _ = setup_snap_matrix(adapter)

      # Scroll right: cols 1,2 are shifted out but col 0 stays visible (sticky-like)
      col_w = matrix.get_col_width(0) * 20.0 + 3  # GRID_SPACING + width
      scroll_x = col_w * 2  # scroll past col 1 and col 2
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.mark_needs_layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cursor at col 0 — col 0 is still visible because it's last in scroll_order
      matrix.cursor_rc = {0, 0}
      matrix.snap_to_cursor

      # Scroll should NOT change because col 0 is already visible
      # With linear sum: cursor_x=0, scroll_x=206, → snaps to 0 (WRONG)
      # With visibility_range_min: col 0's min is at the end, so no snap needed
      matrix.scroll_offset.x.should eq(scroll_x)
    end

    it "cursor on sticky row does not snap scroll back when already scrolled" do
      # Row scroll_order: row 0 scrolls out LAST
      adapter = SnapCursorAdapter.new(100, 10,
        row_scroll_order: ([*(1..99), 0]))
      matrix, _, _ = setup_snap_matrix(adapter)

      # Scroll down past several rows
      row_h = matrix.get_row_height(0) * 20.0 + 3
      scroll_y = row_h * 5
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll_y)
      matrix.mark_needs_layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cursor at row 0 — still visible (sticky-like, last to scroll out)
      matrix.cursor_rc = {0, 0}
      matrix.snap_to_cursor

      # Scroll should NOT change because row 0 is still visible
      matrix.scroll_offset.y.should eq(scroll_y)
    end

    it "non-sequential row scroll_order snaps correctly for off-screen cursor" do
      adapter = SnapCursorAdapter.new(100, 10)
      matrix, _, _ = setup_snap_matrix(adapter)

      # Move cursor to row 50 (off screen)
      matrix.cursor_rc = {50, 0}
      matrix.snap_to_cursor

      # Scroll should have moved to show row 50
      matrix.scroll_offset.y.should be > 0.0
    end

    it "snap right: cell right edge is within viewport (accounts for ruler offset)" do
      # 50 columns, 100 rows → content wider than viewport → needs scrolling
      adapter = SnapCursorAdapter.new(100, 50)
      matrix, _, _ = setup_snap_matrix(adapter, viewport_width: 400.0, viewport_height: 300.0)

      content_layer = matrix.content_layer.not_nil!
      vp_w = content_layer.bounds.width

      # Move cursor to last column (far right, off-screen)
      matrix.cursor_rc = {0, 49}
      matrix.snap_to_cursor

      # After snap, cell's right edge must be within the viewport
      screen_pos = matrix.cell_screen_position(0, 49)
      col_width = matrix.get_col_width(49) * 20.0 + 3 # GRID_SPACING + size * frame_height
      cell_right_edge = screen_pos.x + col_width

      cell_right_edge.should be <= vp_w,
        "Cell (0,49) right edge at #{cell_right_edge} exceeds viewport width #{vp_w} — " \
        "snap_to_cursor doesn't account for ruler offset"
    end

    it "snap down: cell bottom edge is within viewport (accounts for ruler offset)" do
      adapter = SnapCursorAdapter.new(100, 50)
      matrix, _, _ = setup_snap_matrix(adapter, viewport_width: 400.0, viewport_height: 300.0)

      content_layer = matrix.content_layer.not_nil!
      vp_h = content_layer.bounds.height

      # Move cursor to last row (far down, off-screen)
      matrix.cursor_rc = {99, 0}
      matrix.snap_to_cursor

      # After snap, cell's bottom edge must be within the viewport
      screen_pos = matrix.cell_screen_position(99, 0)
      row_height = matrix.get_row_height(99) * 20.0 + 3
      cell_bottom_edge = screen_pos.y + row_height

      cell_bottom_edge.should be <= vp_h,
        "Cell (99,0) bottom edge at #{cell_bottom_edge} exceeds viewport height #{vp_h} — " \
        "snap_to_cursor doesn't account for ruler offset"
    end

    it "snap left: cell left edge is at sticky boundary (not beyond)" do
      adapter = SnapCursorAdapter.new(100, 50)
      matrix, _, _ = setup_snap_matrix(adapter, viewport_width: 400.0, viewport_height: 300.0)

      # Scroll far right first
      matrix.scroll_offset = CrymbleUI::Vec2.new(3000.0, 0.0)
      matrix.mark_needs_layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Now snap to a column near the left edge of the viewport
      # Col 2 is non-sticky (default scroll_order, no sticky)
      matrix.cursor_rc = {0, 2}
      matrix.snap_to_cursor

      # After snap-left, cell's left edge should be exactly at the sticky boundary
      # (ruler_col_w for no-sticky case), not ruler_col_w past it
      screen_pos = matrix.cell_screen_position(0, 2)
      ruler_col_w = matrix.ruler_col_width_pixels

      # The cell should be at or very near the boundary, not offset by an extra ruler_col_w
      screen_pos.x.should be <= ruler_col_w + 1.0,
        "Cell (0,2) left edge at #{screen_pos.x} is too far right after snap-left — " \
        "expected near ruler offset #{ruler_col_w}"
    end
  end
end
