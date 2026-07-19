require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/text_input"

# Adapter that returns TextInput cells for focus/proxy-focus testing.
class FocusTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter paint_coords = [] of Tuple(Int32, Int32)
  getter assign_coords = [] of Tuple(Int32, Int32)

  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    @paint_coords << {row, col}
    CrymbleUI::TextInput.new(value: "#{row},#{col}", id: "cell_#{row}_#{col}")
  end

  def add_merge(top_left : Tuple(Int32, Int32), bottom_right : Tuple(Int32, Int32))
    @merges << {top_left, bottom_right}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end

  # Record the coordinate a commit targets, and RETURN the merged region's canonical
  # top-left — mimicking embrace's pivot map_index, which normalizes any in-span sub-cell
  # to the same underlying cell. (An echo adapter that returns {row,col} would make the
  # commit-delta cancel and hide the cursor-misplacement symptom — validate-the-instrument.)
  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @assign_coords << {row, col}
    cell_get_bounding_box(row, col)[0]
  end
end

# Adapter that returns TextInput cells in QuickEntry mode.
class QuickEntryFocusTestAdapter < FocusTestAdapter
  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    @paint_coords << {row, col}
    CrymbleUI::TextInput.new(value: "#{row},#{col}", id: "cell_#{row}_#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

# Helper: set up a matrix with a compound region (rows 1-2, cols 1-3)
# and TextInput cells so proxy focus can activate.
private def setup_compound_focus_matrix
  adapter = FocusTestAdapter.new(10, 10)
  adapter.add_merge({1, 1}, {2, 3})
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_focus")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)

  # Give the matrix focus so proxy focus can activate
  CrymbleUI::Widget.focus_manager.focus(matrix)

  {matrix, adapter}
end

describe CrymbleUI::VirtualMatrix do
  describe "Compound Cell Proxy Focus" do
    it "cursor on handle cell of compound region activates proxy focus" do
      matrix, _ = setup_compound_focus_matrix

      # Set cursor to {1, 1} — the top-left/handle cell
      matrix.set_cursor_from_cell({1, 1})

      # The TextInput at the handle cell should be effectively focused
      cell_widget = matrix.active_cells[{1, 1}]?
      cell_widget.should_not be_nil
      cell_widget.not_nil!.effectively_focused?.should be_true
    end

    it "cursor on non-handle cell of compound region activates proxy focus" do
      matrix, _ = setup_compound_focus_matrix

      # Set cursor to {1, 2} — a non-handle cell within the merged region
      matrix.set_cursor_from_cell({1, 2})

      # The TextInput at the handle cell {1,1} should be effectively focused
      # even though cursor is at {1,2}
      handle_widget = matrix.active_cells[{1, 1}]?
      handle_widget.should_not be_nil
      handle_widget.not_nil!.effectively_focused?.should be_true
    end

    it "typing into off-screen cell snaps viewport to cursor" do
      # Need enough rows so content exceeds viewport → scrolling is possible
      # Row height = 3 + 1.0*20 = 23px; 50 rows = 1150px > 200px viewport
      adapter = FocusTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "snap_text")
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 200.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Place cursor on row 2 (visible at top)
      matrix.set_cursor_from_cell({2, 2})

      # Scroll viewport far down so cursor cell {2,2} is off-screen
      # Each row = 23px, so scrolling 800px down puts row 2 well above viewport
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 800.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      scrolled_offset = matrix.scroll_offset
      scrolled_offset.y.should be > 0.0, "Should have scrolled down"

      # Simulate typing — should snap viewport back to cursor cell
      matrix.on_text_input('x')

      snapped_offset = matrix.scroll_offset
      snapped_offset.y.should be < scrolled_offset.y, "Viewport should snap back toward cursor cell"

      # Verify the TextInput actually received the character (GUI behavior)
      cell_widget = matrix.active_cells[{2, 2}]?
      cell_widget.should_not be_nil
      cell_widget.not_nil!.as(CrymbleUI::TextInput).value.should contain("x")
    end

    it "editing keys on off-screen cell snap viewport to cursor" do
      adapter = FocusTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "snap_keys")
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 200.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Place cursor and type something first
      matrix.set_cursor_from_cell({2, 2})
      matrix.on_text_input('A')
      matrix.on_text_input('B')

      # Scroll viewport far down so cursor is off-screen
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 800.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      scrolled_offset = matrix.scroll_offset

      # Press Backspace — should snap back AND delete a character
      matrix.on_key_down(SF::Keyboard::Key::Backspace, control: false, shift: false)

      snapped_offset = matrix.scroll_offset
      snapped_offset.y.should be < scrolled_offset.y, "Viewport should snap back on Backspace"
    end

    it "typing into off-screen compound cell snaps to show full merged region" do
      adapter = FocusTestAdapter.new(10, 10)
      adapter.add_merge({1, 1}, {2, 3})
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_snap")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Place cursor on non-handle cell {1, 2} within merged region
      matrix.set_cursor_from_cell({1, 2})

      # Scroll right so handle col 1 is entirely off-screen
      # col_width = GRID_SPACING + DEFAULT_COLUMN_WIDTH * frame_height = 3 + 5*20 = 103px
      # Col 1 spans 103..206 in data space; scroll 210 puts it off-screen
      matrix.scroll_offset = CrymbleUI::Vec2.new(210.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Type — should snap to show the full merged region (starting at col 1)
      matrix.on_text_input('x')

      # The handle cell at col 1 starts at data_pos_x = 103
      # For it to be visible, scroll_offset.x <= 103
      matrix.scroll_offset.x.should be <= 103.0,
        "Handle cell (col 1) should be visible after snap"
    end

    it "arrow-key navigation into merged cell does not snap to full region" do
      adapter = QuickEntryFocusTestAdapter.new(10, 10)
      adapter.add_merge({1, 1}, {2, 3})
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "nav_no_snap")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      # 400px viewport: col_width = 3 + 5*20 = 103px
      # Col 0: 0-103, Col 1: 103-206, Col 2: 206-309, Col 3: 309-412
      # Single cell {1,1}: screen_right = 103+103 = 206 < 400 → no scroll
      # Bounding box cols 1-3: screen_right = 103+309 = 412 > 400 → scroll to 12
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Verify content_layer exists (snap_to_cursor returns early if nil)
      matrix.content_layer.should_not be_nil, "content_layer must exist for snap_to_cursor"

      # Start at {1, 0}, navigate Right → lands on {1, 1} (start of merged region)
      matrix.set_cursor_from_cell({1, 0})
      matrix.scroll_offset.x.should eq(0.0), "precondition: no scroll before navigation"

      matrix.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)

      # Verify cursor actually moved to the merged cell
      matrix.cursor_rc.should eq({1, 1}), "cursor should have moved to {1,1}"

      # Navigation should only ensure the single cursor cell is visible,
      # NOT the full merged region. Cell {1,1} at 103-206 fits in 400px viewport.
      matrix.scroll_offset.x.should eq(0.0),
        "Navigation into merged cell should not scroll to fit entire merged region (got #{matrix.scroll_offset.x})"
    end

    it "adapter cell_paint receives top-left coordinates even after scroll shifts handle" do
      adapter = FocusTestAdapter.new(10, 10)
      adapter.add_merge({1, 1}, {2, 3})
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_coords")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Initial: handle is {1,1} (top-left), adapter should get {1,1}
      compound_paints = adapter.paint_coords.select { |rc| rc[0] >= 1 && rc[0] <= 2 && rc[1] >= 1 && rc[1] <= 3 }
      compound_paints.size.should eq(1)
      compound_paints[0].should eq({1, 1})

      # Now scroll right so col 1 is out of view — dynamic handle shifts to {1, 2}
      # col_width_pixels = GRID_SPACING + DEFAULT_COLUMN_WIDTH * frame_height = 3 + 5*20 = 103px
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      # Scroll past col 1: need scroll > col0_width + col1_width = 206px
      # But cells only re-created when old ones are destroyed (destruction buffer)
      # Force cell update by scrolling far enough, then back
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w * 4, 0.0)  # Scroll 4 cols right
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Scroll back so the compound region is partially visible (col 2-3 visible, col 1 out)
      adapter.paint_coords.clear
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w + 5.0, 0.0)  # Col 1 scrolled out
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # The dynamic handle should now be {1, 2} (first visible cell of region)
      # But cell_paint should STILL receive the canonical top-left {1, 1}
      compound_recreated = adapter.paint_coords.select { |rc| rc[0] >= 1 && rc[0] <= 2 && rc[1] >= 1 && rc[1] <= 3 }
      if compound_recreated.size > 0
        compound_recreated.each do |rc|
          rc.should eq({1, 1}), "cell_paint should receive canonical top-left {1,1}, got #{rc}"
        end
      else
        # If the cell wasn't recreated (still alive at {1,1}), that's also valid
        # but check that at least the active_cells key is correct
        has_compound = matrix.active_cells.keys.any? { |k| k[0] >= 1 && k[0] <= 2 && k[1] >= 1 && k[1] <= 3 }
        has_compound.should be_true, "Compound region should have an active cell"
      end
    end

    # Symmetric to the cell_paint canonical test above: a COMMIT from a non-handle sub-cell
    # of a merged region must target the region's canonical top-left (what the adapter expects
    # and what paint uses), not the raw sub-cell — otherwise commit_proxy_edit's delta math
    # mixes a raw-rc delta with the canonical returned coord and mislands the cursor.
    it "commits an edit from a non-handle sub-cell to the merged region's canonical coordinate (and lands the cursor where you navigated)" do
      matrix, adapter = setup_compound_focus_matrix # merge {1,1}-{2,3}, FullEdit cells
      fm = CrymbleUI::Widget.focus_manager
      matrix.set_cursor_from_cell({1, 2}) # cursor on a NON-handle sub-cell of the region

      handle = matrix.active_cells[{1, 1}]?.as(CrymbleUI::TextInput)
      handle.effectively_focused?.should be_true # precondition: proxy activated on the handle widget

      fm.handle_text_input('X')     # edit the value ("1,1" -> "1,1X"), uncommitted
      matrix.move_cursor(:down)     # {2,2}: still inside the region -> no commit
      matrix.move_cursor(:down)     # {3,2}: leaves the region -> commit fires

      adapter.assign_coords.should eq([{1, 1}]) # wrote to the canonical top-left, NOT the raw {1,2}
      matrix.cursor_rc.should eq({3, 2})        # cursor followed the navigation (unfixed: {3,1})
    end

    it "commits an edit from the merged region's handle cell to the same canonical coordinate (idempotent)" do
      matrix, adapter = setup_compound_focus_matrix
      fm = CrymbleUI::Widget.focus_manager
      matrix.set_cursor_from_cell({1, 1}) # cursor ON the handle

      matrix.active_cells[{1, 1}]?.as(CrymbleUI::TextInput).effectively_focused?.should be_true

      fm.handle_text_input('X')
      matrix.move_cursor(:down)
      matrix.move_cursor(:down)

      adapter.assign_coords.should eq([{1, 1}]) # already canonical — no double-normalize
    end
  end
end
