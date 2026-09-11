require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

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

# An EDITABLE cell with a multi-line value, for the caret case: the snap has to follow the
# caret INSIDE a cell that is taller than the viewport, which needs a real editor to move it.
class TallEditableAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32, @tall_row : Int32 = 3)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def text_at(row : Int32, col : Int32) : String
    row == @tall_row && col == 1 ? (1..40).map { |i| "line#{i}" }.join("\n") : "#{row},#{col}"
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: text_at(row, col), multiline: true)
  end
end

# The same tall editable cell, but in a grid where EVERY column is sticky. That is not exotic: a
# 3-column pivot orders its columns [2,1,0], whose trailing run is the whole set, so
# derive_sticky_count returns 3 of 3 (embrace's ab/Rank/value Shape, field report 2026-09-05).
class AllStickyTallAdapter < TallEditableAdapter
  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows, _ = super
    {rows, (0...col_count).to_a.reverse}
  end
end


describe CrymbleUI::VirtualMatrix do
  # A cell BIGGER than the viewport satisfies both snap branches at once — "its top is above
  # the view" and "its bottom is below it" — so each snap re-arms the other and consecutive calls
  # alternate. Measured before the fix: scroll_y 392/46/392/46, scroll_x 552/206/552/206, with no
  # content sizing involved at all (plain dragged sizes). The rule that removes it: a cell that
  # exceeds the viewport aligns its LEADING edge — top, and left — whichever direction you came from.
  describe "the caret inside an oversized cell" do
    it "follows the caret to the END of a cell taller than the viewport" do
      # The UPWARD case is already satisfied by leading-edge alignment — every snap into an
      # oversized cell lands at its top — so it cannot tell caret tracking from no tracking. This
      # one can: opening an editor puts the caret at the END of the value (cursor_pos rests at
      # value.size), which in a 40-line cell is ~800px below a 300px viewport. Today the view stays
      # at the cell's top and you type where you cannot see.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      adapter = TallEditableAdapter.new(20, 5)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "caret_snap_test")
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree
      matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      matrix.auto_size = true         # the 40-line value sizes its row, exactly as in production
      renderer.settle_rendering(app)

      matrix.active_cells[{3, 1}].bounds.height.should be > 300.0 # instrument: it really is oversized
      matrix.set_cursor_from_cell({3, 1})
      matrix.snap_to_cursor
      at_cell_top = matrix.scroll_offset.y

      matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # open the editor
      matrix.cursor_cell_draws_edit_caret?.should be_true        # instrument: a caret is really drawn

      matrix.scroll_offset.y.should be > at_cell_top
    end
  end

    it "follows the caret back UP, not only down" do
      # Field report: "only scrolls down, never up". `cell.bounds` is already CONTENT space — cells
      # hold fixed content-space positions and the compositor scrolls — so adding the scroll offset
      # to them double-counted it. At offset 0 that is invisible (every test passed); once scrolled,
      # the caret always computed as far below the viewport, so the view could only go further down.
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      adapter = TallEditableAdapter.new(20, 5)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "caret_up_test")
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree
      matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      matrix.auto_size = true
      renderer.settle_rendering(app)

      matrix.set_cursor_from_cell({3, 1})
      matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # caret at the END, view follows down
      scrolled_down = matrix.scroll_offset.y
      scrolled_down.should be > 0.0 # instrument: it really did scroll down first

      30.times { matrix.on_key_down(SF::Keyboard::Key::Up, false, false) }

      matrix.scroll_offset.y.should be < scrolled_down
    end

    it "a double-click that OPENS the editor brings its caret into view" do
      # Field report: "double-clicking instead of Enter doesn't focus caret". It does focus — the
      # caret just opens at the END of the value, which in a cell taller than the viewport is off
      # screen, so the cell reads as dead. Scoping the mouse path out of the snap was wrong for the
      # click that opens an editor (a plain click puts the caret where you clicked, which is
      # visible by construction).
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      adapter = TallEditableAdapter.new(20, 5)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "caret_dblclick_test")
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree
      matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      matrix.auto_size = true
      renderer.settle_rendering(app)
      matrix.scroll_offset.y.should eq(0.0) # instrument: nothing scrolled yet

      cell = matrix.active_cells[{3, 1}]
      cell.bounds.height.should be > 300.0 # instrument: taller than the viewport
      point = CrymbleUI::Vec2.new(cell.absolute_bounds.x + 10.0, cell.absolute_bounds.y + 10.0)
      matrix.on_mouse_down(point); matrix.on_mouse_up(point)
      matrix.on_mouse_down(point); matrix.on_mouse_up(point) # the second click opens the editor

      matrix.scroll_offset.y.should be > 0.0
    end

  describe "oversized cells: the snap is idempotent and direction-independent" do
    it "snapping twice to the same cursor does not move the view (vertical)" do
      adapter = SnapCursorAdapter.new(20, 5)
      matrix, _, _ = setup_snap_matrix(adapter)
      matrix.row_height(3, 30.0) # ~600px in a 300px viewport: taller than the view
      matrix.set_cursor_from_cell({3, 1})
      matrix.snap_to_cursor
      first = matrix.scroll_offset.y
      matrix.snap_to_cursor
      matrix.scroll_offset.y.should eq(first)
    end

    it "snapping twice to the same cursor does not move the view (horizontal)" do
      adapter = SnapCursorAdapter.new(20, 5)
      matrix, _, _ = setup_snap_matrix(adapter)
      matrix.col_width(2, 40.0) # ~800px in a 400px viewport
      matrix.set_cursor_from_cell({1, 2})
      matrix.snap_to_cursor
      first = matrix.scroll_offset.x
      matrix.snap_to_cursor
      matrix.scroll_offset.x.should eq(first)
    end

    it "the control that must move: an OFF-SCREEN cell that FITS snaps once, then holds" do
      # A fitting cell already on screen never moves at all, so it cannot tell a working snap from a
      # broken one. This one has to travel first.
      adapter = SnapCursorAdapter.new(60, 5)
      matrix, _, _ = setup_snap_matrix(adapter)
      matrix.set_cursor_from_cell({40, 1})
      matrix.snap_to_cursor
      travelled = matrix.scroll_offset.y
      travelled.should be > 0.0 # it really did have to scroll
      matrix.snap_to_cursor
      matrix.scroll_offset.y.should eq(travelled)
    end

    it "an oversized cell looks the same whichever direction you arrive from" do
      adapter = SnapCursorAdapter.new(20, 5)
      matrix, _, _ = setup_snap_matrix(adapter)
      matrix.row_height(3, 30.0)

      matrix.set_cursor_from_cell({0, 1}) # arrive from ABOVE
      matrix.snap_to_cursor
      matrix.set_cursor_from_cell({3, 1})
      matrix.snap_to_cursor
      from_above = matrix.scroll_offset.y

      matrix.set_cursor_from_cell({19, 1}) # arrive from BELOW
      matrix.snap_to_cursor
      matrix.set_cursor_from_cell({3, 1})
      matrix.snap_to_cursor
      matrix.scroll_offset.y.should eq(from_above)
    end
  end

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
  it "follows the caret in a cell whose COLUMN is sticky but whose row still scrolls" do
    # Field report 2026-09-05: pressing Enter on a tall multi-line cell did nothing — no scroll, no
    # visible caret. `snap_to_caret` opened with
    #     return if row < sticky_row_count || col < sticky_col_count
    # which reads "either axis pinned -> nothing to do". But those are different axes: a sticky
    # COLUMN is pinned horizontally and says nothing about vertical scrolling, and here every
    # column is sticky while no row is, so the guard swallowed every snap in the grid.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    adapter = AllStickyTallAdapter.new(20, 3)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "caret_sticky_col_test")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.sticky_col_count.should eq(3)                        # instrument: the degenerate grid
    matrix.sticky_row_count.should eq(0)                        # ...pinned across, scrolling down
    matrix.active_cells[{3, 1}].bounds.height.should be > 300.0 # ...and the cell really is oversized

    matrix.set_cursor_from_cell({3, 1})
    matrix.snap_to_cursor
    at_cell_top = matrix.scroll_offset.y

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # caret opens at the value's END
    matrix.cursor_cell_draws_edit_caret?.should be_true

    matrix.scroll_offset.y.should be > at_cell_top,
      "the view never followed the caret into a cell taller than itself"
  end
end
