require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Adapter with 1 sticky row + 1 sticky col for resize tests
class ResizeTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # Sticky: row 0 and col 0 scroll out LAST → sticky_count = 1 each
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# DSL-style app — creates NEW widget instances on every build() (like real apps).
# This exercises reconciliation and exposes bugs where state isn't preserved.
class ResizeDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    adapter = ResizeTestAdapter.new(20, 10)
    CrymbleUI::VirtualMatrix.new(adapter, id: "resize_test")
  end
end

# Default cell sizes with frame_height=20:
#   col_width_pixels = GRID_SPACING + DEFAULT_COLUMN_WIDTH * frame_height = 3 + 5.0 * 20 = 103px
#   row_height_pixels = GRID_SPACING + DEFAULT_ROW_HEIGHT * frame_height = 3 + 1.0 * 20 = 23px
# Ruler dimensions (show_rulers=true by default):
#   ruler_col_width_pixels = 2.0 * 20 = 40px
#   ruler_row_height_pixels = 1.0 * 20 = 20px
# With rulers, resize detection only works in ruler strips:
#   Column resize: y < RULER_ROW_H (20px), border at x = RULER_COL_W + COL_W * n
#   Row resize: x < RULER_COL_W (40px), border at y = RULER_ROW_H + ROW_H * n
COL_W = 103.0 # default col_width_pixels
ROW_H =  23.0 # default row_height_pixels
RULER_COL_W = 40.0  # ruler_col_width_pixels
RULER_ROW_H = 20.0  # ruler_row_height_pixels

# Column border x positions (in ruler strip): RULER_COL_W + COL_W * (n+1)
COL_BORDER_0 = RULER_COL_W + COL_W       # 143.0 — col 0 right border
COL_BORDER_1 = RULER_COL_W + COL_W * 2   # 246.0 — col 1 right border

# Row border y positions (in ruler strip): RULER_ROW_H + ROW_H * (n+1)
ROW_BORDER_0 = RULER_ROW_H + ROW_H       # 43.0 — row 0 bottom border
ROW_BORDER_1 = RULER_ROW_H + ROW_H * 2   # 66.0 — row 1 bottom border

# TestApp-based setup (no rebuild) — used for cursor hover tests
private def make_resize_matrix
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app = TestApp.new
  adapter = ResizeTestAdapter.new(20, 10)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "resize_test")

  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 400.0))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)

  {renderer, app, matrix}
end

# DSL-style setup (rebuilds create NEW instances) — used for resize behavioral tests
private def make_resize_dsl
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app = ResizeDSLApp.new
  app.build_tree
  renderer.settle_rendering(app)

  matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
  {renderer, app, matrix}
end

# Interactive column/row resize via ruler border drag
describe "VirtualMatrix interactive resize", tags: "slow" do
  describe "cursor changes on column border hover" do
    it "shows SizeHorizontal cursor near column 0 right border" do
      _renderer, app, _matrix = make_resize_matrix

      # Column 0 right border at x=143, in ruler strip (y=10 < 20)
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      cursor.should eq CrymbleUI::CursorType::SizeHorizontal
    end

    it "shows SizeHorizontal cursor near column 1 right border" do
      _renderer, app, _matrix = make_resize_matrix

      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(COL_BORDER_1, 10.0))
      cursor.should eq CrymbleUI::CursorType::SizeHorizontal
    end

    it "shows Arrow cursor away from any border" do
      _renderer, app, _matrix = make_resize_matrix

      # Middle of column 0, in ruler strip (y=10)
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(RULER_COL_W + 50.0, 10.0))
      cursor.should eq CrymbleUI::CursorType::Arrow
    end

    it "shows Arrow cursor in ruler strip outside tolerance" do
      _renderer, app, _matrix = make_resize_matrix

      # 10px away from col 0 border (tolerance is 4px)
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(COL_BORDER_0 - 10.0, 10.0))
      cursor.should eq CrymbleUI::CursorType::Arrow
    end
  end

  describe "cursor changes on row border hover" do
    it "shows SizeVertical cursor near row 0 bottom border" do
      _renderer, app, _matrix = make_resize_matrix

      # Row 0 bottom border at y=43, in ruler strip (x=20 < 40)
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))
      cursor.should eq CrymbleUI::CursorType::SizeVertical
    end

    it "shows SizeVertical cursor near row 1 bottom border" do
      _renderer, app, _matrix = make_resize_matrix

      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(20.0, ROW_BORDER_1))
      cursor.should eq CrymbleUI::CursorType::SizeVertical
    end

    it "shows Arrow cursor away from row border" do
      _renderer, app, _matrix = make_resize_matrix

      # Middle of row 0, in ruler strip (x=20)
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(20.0, RULER_ROW_H + 5.0))
      cursor.should eq CrymbleUI::CursorType::Arrow
    end
  end

  describe "column resize by dragging" do
    it "shifts cell positions during drag" do
      renderer, app, matrix = make_resize_dsl

      original_x = matrix.cell_screen_position(0, 1).x

      # Mouse down on column 0 right border in ruler strip (x=143, y=10)
      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))

      # Drag 40px right
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      # Re-find matrix after potential rebuild
      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Cell (0,1) should have moved right by ~40px
      matrix.cell_screen_position(0, 1).x.should be > original_x

      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
    end

    it "persists resize after explicit rebuild", tags: "slow" do
      renderer, app, matrix = make_resize_dsl

      # Resize col 0
      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)
      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      pos_after_resize = matrix.cell_screen_position(0, 1).x

      # Force rebuild (simulates DSL app state change)
      app.rebuild
      renderer.settle_rendering(app)

      # Re-find on new widget instance
      new_matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      new_matrix.cell_screen_position(0, 1).x.should eq pos_after_resize
    end

    it "makes column narrower during drag" do
      renderer, app, matrix = make_resize_dsl

      original_x = matrix.cell_screen_position(0, 1).x

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))

      # Drag 60px left
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 - 60.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      matrix.cell_screen_position(0, 1).x.should be < original_x

      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 - 60.0, 10.0))
    end

    it "clamps column width to minimum" do
      renderer, app, matrix = make_resize_dsl

      # MIN_COL_WIDTH = 0.5 → min pixels = 3 + 0.5*20 = 13
      min_col_pixels = RULER_COL_W + 3.0 + 0.5 * 20.0

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))

      # Drag far left — should clamp
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 - 200.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Cell (0,1) x should be at ruler_col_w + min_col_pixels (clamped, not negative)
      matrix.cell_screen_position(0, 1).x.should be_close(min_col_pixels, 1.0)

      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 - 200.0, 10.0))
    end

    it "resizes column 1 without shifting column 0 cells" do
      renderer, app, matrix = make_resize_dsl

      col0_pos = matrix.cell_screen_position(0, 0).x
      border_x = COL_BORDER_1 # Column 1 right border

      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))

      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 20.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Column 0 position unchanged
      matrix.cell_screen_position(0, 0).x.should eq col0_pos
      # Column 2 shifted right
      matrix.cell_screen_position(0, 2).x.should be > (RULER_COL_W + COL_W * 2)

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 20.0, 10.0))
    end
  end

  describe "row resize by dragging" do
    it "shifts cell positions during drag" do
      renderer, app, matrix = make_resize_dsl

      original_y = matrix.cell_screen_position(1, 0).y

      # Mouse down on row 0 bottom border in ruler strip (x=20, y=43)
      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))

      # Drag 40px down
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Cell (1,0) should have moved down by ~40px
      matrix.cell_screen_position(1, 0).y.should be > original_y

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
    end

    it "persists resize after explicit rebuild", tags: "slow" do
      renderer, app, matrix = make_resize_dsl

      # Resize row 0
      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
      renderer.render_frame(app)
      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      pos_after_resize = matrix.cell_screen_position(1, 0).y

      # Force rebuild
      app.rebuild
      renderer.settle_rendering(app)

      new_matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      new_matrix.cell_screen_position(1, 0).y.should eq pos_after_resize
    end

    it "makes row shorter during drag" do
      renderer, app, matrix = make_resize_dsl

      original_y = matrix.cell_screen_position(1, 0).y

      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))

      # Drag 5px up
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 - 5.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      matrix.cell_screen_position(1, 0).y.should be < original_y

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 - 5.0))
    end

    it "clamps row height to minimum" do
      renderer, app, matrix = make_resize_dsl

      # MIN_ROW_HEIGHT = 0.5 → min pixels = 3 + 0.5*20 = 13
      min_row_pixels = RULER_ROW_H + 3.0 + 0.5 * 20.0

      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))

      # Drag far up — should clamp
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 - 200.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Cell (1,0) y should be at ruler_row_h + min_row_pixels
      matrix.cell_screen_position(1, 0).y.should be_close(min_row_pixels, 1.0)

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 - 200.0))
    end
  end

  describe "cell click not affected by resize" do
    it "clicking in cell area selects cell (no resize)" do
      renderer, app, matrix = make_resize_dsl

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Click in middle of cell (1,1) — well away from any border
      # Cell (1,1) starts at x=143, y=43 — click at (195, 55) = center-ish
      click_x = RULER_COL_W + COL_W + 12.0   # 155.0
      click_y = RULER_ROW_H + ROW_H + 12.0   # 55.0
      app.handle_mouse_down(CrymbleUI::Vec2.new(click_x, click_y))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      matrix.resize_axis.should eq CrymbleUI::VirtualMatrix::ResizeAxis::None
      matrix.cursor_rc.should eq({1, 1})

      app.handle_mouse_up(CrymbleUI::Vec2.new(click_x, click_y))
    end
  end

  describe "multi-step drag" do
    it "tracks incremental mouse moves via cell position", tags: "slow" do
      renderer, app, matrix = make_resize_dsl

      border_x = COL_BORDER_0

      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))

      # First move: +20px
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 20.0, 10.0))
      renderer.render_frame(app)
      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      pos1 = matrix.cell_screen_position(0, 1).x

      # Second move: +40px total from start (further right)
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)
      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      pos2 = matrix.cell_screen_position(0, 1).x
      pos2.should be > pos1

      # Move back: +10px total from start (less than first move)
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 10.0, 10.0))
      renderer.render_frame(app)
      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      pos3 = matrix.cell_screen_position(0, 1).x
      pos3.should be < pos1

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 10.0, 10.0))
    end
  end

  describe "resize drag performance" do
    it "shifts content cell actual bounds during column resize drag" do
      renderer, app, matrix = make_resize_dsl

      cell = matrix.active_cells[{1, 1}]?
      cell.should_not be_nil
      original_x = cell.not_nil!.absolute_bounds.x

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_after = matrix.active_cells[{1, 1}]?
      cell_after.should_not be_nil
      # Content cell to the RIGHT of resized col must shift ~40px
      cell_after.not_nil!.absolute_bounds.x.should be_close(original_x + 40.0, 2.0)

      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
    end

    it "updates content cell width in resized column during drag" do
      renderer, app, matrix = make_resize_dsl

      # Resize col 1 (content column). Col 1 right border at x = COL_BORDER_1
      border_x = COL_BORDER_1
      cell = matrix.active_cells[{1, 1}]?
      cell.should_not be_nil
      original_w = cell.not_nil!.bounds.width

      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_after = matrix.active_cells[{1, 1}]?
      cell_after.should_not be_nil
      cell_after.not_nil!.bounds.width.should be > original_w

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end

    it "shifts content cell actual bounds during row resize drag" do
      renderer, app, matrix = make_resize_dsl

      cell = matrix.active_cells[{1, 1}]?
      cell.should_not be_nil
      original_y = cell.not_nil!.absolute_bounds.y

      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_after = matrix.active_cells[{1, 1}]?
      cell_after.should_not be_nil
      cell_after.not_nil!.absolute_bounds.y.should be_close(original_y + 40.0, 2.0)

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, ROW_BORDER_0 + 40.0))
    end

    it "does not trigger layout during drag but updates all cell bounds", tags: "slow" do
      renderer, app, matrix = make_resize_dsl
      renderer.reset_counters

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      5.times do |i|
        app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + (i + 1) * 8.0, 10.0))
        renderer.render_frame(app)
      end

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Performance: no layout during drag
      renderer.layout_count.should eq 0

      # Correctness: content cells rendered with correct bounds
      cell = matrix.active_cells[{1, 1}]?
      cell.should_not be_nil
      assert_rendered(cell.not_nil!)

      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
    end
  end

  describe "sticky cell bounds during resize" do
    it "updates sticky row cell width when its column is resized" do
      renderer, app, matrix = make_resize_dsl

      # (0, 1) is a sticky row cell (row 0 = sticky, col 1 = content)
      cell_0_1 = matrix.active_cells[{0, 1}]?
      cell_0_1.should_not be_nil
      original_width = cell_0_1.not_nil!.bounds.width

      # Resize col 1 (border at COL_BORDER_1) by +40px
      border_x = COL_BORDER_1
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_0_1_after = matrix.active_cells[{0, 1}]?
      cell_0_1_after.should_not be_nil

      # Sticky row cell width should increase by ~40px
      cell_0_1_after.not_nil!.bounds.width.should be > original_width

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end

    it "shifts sticky row cells right of resized column" do
      renderer, app, matrix = make_resize_dsl

      # (0, 2) is a sticky row cell right of col 1
      cell_0_2 = matrix.active_cells[{0, 2}]?
      cell_0_2.should_not be_nil
      original_x = cell_0_2.not_nil!.absolute_bounds.x

      # Resize col 1 (border at COL_BORDER_1) by +40px
      border_x = COL_BORDER_1
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_0_2_after = matrix.active_cells[{0, 2}]?
      cell_0_2_after.should_not be_nil

      # Sticky row cell position should shift right by ~40px
      cell_0_2_after.not_nil!.absolute_bounds.x.should be_close(original_x + 40.0, 2.0)

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end
  end

  describe "resize completion (mouse up)" do
    it "does not trigger layout on mouse up after resize" do
      renderer, app, matrix = make_resize_dsl

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      renderer.reset_counters
      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      # Mouse up should NOT trigger full layout (causes rebuild and data loss in DSL apps)
      renderer.layout_count.should eq 0
    end

    it "preserves cell widget instances after resize completes" do
      renderer, app, matrix = make_resize_dsl

      cell_11 = matrix.active_cells[{1, 1}]?
      cell_11.should_not be_nil
      cell_id = cell_11.not_nil!.object_id

      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)
      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)
      cell_after = matrix.active_cells[{1, 1}]?
      cell_after.should_not be_nil

      # Same widget instance means state is preserved (no rebuild/recreate)
      cell_after.not_nil!.object_id.should eq cell_id
    end

    it "updates scroll view content size after resize without layout" do
      renderer, app, matrix = make_resize_dsl

      # Resize col 0 wider by +40px
      app.handle_mouse_down(CrymbleUI::Vec2.new(COL_BORDER_0, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)
      app.handle_mouse_up(CrymbleUI::Vec2.new(COL_BORDER_0 + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("resize_test").as(CrymbleUI::VirtualMatrix)

      # Column positions should still reflect the resize after mouse up
      matrix.cell_screen_position(0, 1).x.should be_close(RULER_COL_W + COL_W + 40.0, 2.0)
    end
  end
end

# (Finding 3a): growing the viewport of a SCROLLED VirtualMatrix must leave the content layer's
# buffer_origin whole-valued and fitting (so the composite never clamps → no content shift), and the
# sticky header row must stay pinned to the top. (Sticky layers are excluded from the cv gate, so the
# sticky assertion lives here as a normal find-by-cell bounds check.)
describe "VirtualMatrix grow-while-scrolled keeps a whole, fitting content origin", tags: "slow" do
  it "content layer fits at a whole origin after a scrolled grow; sticky header stays pinned" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 1000)
    app = TestApp.new
    adapter = ResizeTestAdapter.new(60, 12) # tall + wide enough to scroll both ways
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "grow_scroll")
    app.root_widget = matrix
    app.build_tree

    # Phase 1: a small viewport, scrolled down past the cache margin.
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    center = CrymbleUI::Vec2.new(400.0, 150.0)
    12.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    cl = matrix.content_layer.not_nil!
    cl.buffer_origin.y.should_not eq(0.0) # precondition: genuinely scrolled past the cache margin

    # Phase 2: grow the viewport height (e.g. a section above collapsed, releasing height).
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 850.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    cl = matrix.content_layer.not_nil!
    b = cl.backend.not_nil!
    cl.viewport_fits_buffer?(b.width, b.height).should be_true # composite won't clamp ⇒ no content shift
    cl.buffer_origin.x.should eq(cl.buffer_origin.x.round)
    cl.buffer_origin.y.should eq(cl.buffer_origin.y.round)

    # The sticky header row (row 0) stays pinned to the top of the matrix, not scrolled off.
    sticky = matrix.active_cells[{0, 1}]?
    sticky.should_not be_nil
    (sticky.not_nil!.absolute_bounds.y - matrix.absolute_bounds.y).abs.should be < (RULER_ROW_H + ROW_H)
  end
end
