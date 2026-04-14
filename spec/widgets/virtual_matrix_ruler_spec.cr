require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Adapter with 1 sticky row + 1 sticky col (same structure as ResizeTestAdapter)
class RulerTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Sticky: row 0 scrolls out LAST → sticky_row_count = 1
  # Sticky: col 0 scrolls out LAST → sticky_col_count = 1
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# DSL-style app for ruler tests
class RulerDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    adapter = RulerTestAdapter.new(20, 10)
    CrymbleUI::VirtualMatrix.new(adapter, id: "ruler_test")
  end
end

# Default cell sizes with frame_height=20:
#   col_width_pixels = GRID_SPACING + DEFAULT_COLUMN_WIDTH * frame_height = 3 + 5.0 * 20 = 103px
#   row_height_pixels = GRID_SPACING + DEFAULT_ROW_HEIGHT * frame_height = 3 + 1.0 * 20 = 23px
#
# Ruler dimensions (show_rulers=true by default):
#   ruler_row_height_pixels = 1.0 * frame_height = 20px
#   ruler_col_width_pixels  = 2.0 * frame_height = 40px
#
# With rulers, sticky data cells shift:
#   cell(0,0) at screen (ruler_col_w, ruler_row_h) = (40, 20)
#   cell(0,1) at screen (ruler_col_w + col_w, ruler_row_h) = (143, 20)
#   cell(1,0) at screen (ruler_col_w, ruler_row_h + row_h) = (40, 43)
#   cell(1,1) at screen (ruler_col_w + col_w, ruler_row_h + row_h) = (143, 43)
#
# Column borders in ruler strip (y < 20):
#   col 0 right border: x = ruler_col_w + col_w = 143
#   col 1 right border: x = ruler_col_w + 2*col_w = 246
#
# Row borders in ruler strip (x < 40):
#   row 0 bottom border: y = ruler_row_h + row_h = 43
#   row 1 bottom border: y = ruler_row_h + 2*row_h = 66
RULER_COL_W_PX = 40.0
RULER_ROW_H_PX = 20.0
R_COL_W = 103.0
R_ROW_H = 23.0

# DSL-style setup
private def make_ruler_dsl
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app = RulerDSLApp.new
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
  {renderer, app, matrix}
end

describe "VirtualMatrix rulers", tags: "slow" do
  describe "ruler visibility" do
    it "shifts cell (0,0) position by ruler dimensions" do
      renderer, app, matrix = make_ruler_dsl

      # With rulers, cell(0,0) should be shifted to (ruler_col_w, ruler_row_h)
      pos = matrix.cell_screen_position(0, 0)
      pos.x.should be_close(RULER_COL_W_PX, 1.0)
      pos.y.should be_close(RULER_ROW_H_PX, 1.0)
    end

    it "shifts cell (1,1) position by ruler dimensions" do
      renderer, app, matrix = make_ruler_dsl

      pos = matrix.cell_screen_position(1, 1)
      pos.x.should be_close(RULER_COL_W_PX + R_COL_W, 1.0)
      pos.y.should be_close(RULER_ROW_H_PX + R_ROW_H, 1.0)
    end

    it "column ruler widget produces non-sticky column labels" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.col_ruler_widget
      ruler.should_not be_nil

      # Non-sticky columns only (col 0 is sticky → on corner layer)
      prims = ruler.not_nil!.to_primitives(ruler.not_nil!.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)
      texts.should_not contain("c1")  # Sticky col → corner layer
      texts.should contain("c2")
      texts.should contain("c3")
    end

    it "row ruler widget produces non-sticky row labels" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.row_ruler_widget
      ruler.should_not be_nil

      # Non-sticky rows only (row 0 is sticky → on corner layer)
      prims = ruler.not_nil!.to_primitives(ruler.not_nil!.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)
      texts.should_not contain("1")  # Sticky row → corner layer
      texts.should contain("2")
      texts.should contain("3")
    end

    it "corner ruler widget produces sticky column labels" do
      renderer, app, matrix = make_ruler_dsl

      corner = matrix.corner_ruler_widget
      corner.should_not be_nil

      prims = corner.not_nil!.to_primitives(corner.not_nil!.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)
      texts.should contain("c1")  # Sticky col label on corner
    end

    it "corner row strip widget produces sticky row labels" do
      renderer, app, matrix = make_ruler_dsl

      strip = matrix.corner_row_strip_widget
      strip.should_not be_nil

      prims = strip.not_nil!.to_primitives(strip.not_nil!.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)
      texts.should contain("1")  # Sticky row label on corner
    end
  end

  describe "click exclusion in ruler area" do
    it "click in column ruler strip does not select cell" do
      renderer, app, matrix = make_ruler_dsl

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Move cursor to (2,2) first so we can detect if it changes
      click_at(app, RULER_COL_W_PX + R_COL_W * 2 + 20.0, RULER_ROW_H_PX + R_ROW_H * 2 + 5.0)
      renderer.render_frame(app)
      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      matrix.cursor_rc.should eq({2, 2})

      # Click in column ruler strip (y=10 < ruler_row_h=20)
      # x=200 is in the column label area, past ruler_col_w
      click_at(app, 200.0, 10.0)
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      # Cursor should NOT have changed — ruler clicks don't select cells
      matrix.cursor_rc.should eq({2, 2})
    end

    it "click in row ruler strip does not select cell" do
      renderer, app, matrix = make_ruler_dsl

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)
      initial_cursor = matrix.cursor_rc

      # Click at x=20 (in row ruler strip, x < ruler_col_w=40)
      # y=50 is past the ruler row height (20), in the row label area
      click_at(app, 20.0, 50.0)
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      matrix.cursor_rc.should eq initial_cursor
    end
  end

  describe "resize detection on ruler borders" do
    it "shows SizeHorizontal on column 0 border in ruler strip" do
      _renderer, app, _matrix = make_ruler_dsl

      # Column 0 right border at x = ruler_col_w + col_w = 143, y=10 in ruler strip
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(RULER_COL_W_PX + R_COL_W, 10.0))
      cursor.should eq CrymbleUI::CursorType::SizeHorizontal
    end

    it "shows SizeHorizontal on column 1 border in ruler strip" do
      _renderer, app, _matrix = make_ruler_dsl

      # Column 1 right border at x = ruler_col_w + 2*col_w = 246
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(RULER_COL_W_PX + R_COL_W * 2, 10.0))
      cursor.should eq CrymbleUI::CursorType::SizeHorizontal
    end

    it "shows SizeVertical on row 0 border in ruler strip" do
      _renderer, app, _matrix = make_ruler_dsl

      # Row 0 bottom border at y = ruler_row_h + row_h = 43, x=20 in ruler strip
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(20.0, RULER_ROW_H_PX + R_ROW_H))
      cursor.should eq CrymbleUI::CursorType::SizeVertical
    end

    it "shows SizeVertical on row 1 border in ruler strip" do
      _renderer, app, _matrix = make_ruler_dsl

      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(20.0, RULER_ROW_H_PX + R_ROW_H * 2))
      cursor.should eq CrymbleUI::CursorType::SizeVertical
    end
  end

  describe "no resize on sticky data cells" do
    it "shows Arrow cursor on column border in sticky data row (not ruler)" do
      _renderer, app, _matrix = make_ruler_dsl

      # y=25 is past ruler strip (ruler_row_h=20), in sticky data row area
      # x=143 is at column 0 right border
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(RULER_COL_W_PX + R_COL_W, 25.0))
      cursor.should eq CrymbleUI::CursorType::Arrow
    end

    it "shows Arrow cursor on row border in sticky data col (not ruler)" do
      _renderer, app, _matrix = make_ruler_dsl

      # x=50 is past ruler strip (ruler_col_w=40), in sticky data col area
      # y=43 is at row 0 bottom border
      cursor = app.get_cursor_for_point(CrymbleUI::Vec2.new(50.0, RULER_ROW_H_PX + R_ROW_H))
      cursor.should eq CrymbleUI::CursorType::Arrow
    end
  end

  describe "resize drag from ruler" do
    it "shifts cells during column resize drag from ruler strip" do
      renderer, app, matrix = make_ruler_dsl

      original_x = matrix.cell_screen_position(0, 1).x

      # Mouse down on col 0 border in ruler strip (x=143, y=10)
      border_x = RULER_COL_W_PX + R_COL_W
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))

      # Drag 40px right
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      matrix.cell_screen_position(0, 1).x.should be > original_x

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end

    it "shifts cells during row resize drag from ruler strip" do
      renderer, app, matrix = make_ruler_dsl

      original_y = matrix.cell_screen_position(1, 0).y

      # Mouse down on row 0 border in ruler strip (x=20, y=43)
      border_y = RULER_ROW_H_PX + R_ROW_H
      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, border_y))

      # Drag 30px down
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      matrix.cell_screen_position(1, 0).y.should be > original_y

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
    end
  end

  describe "ruler re-render on resize" do
    it "updates column ruler labels after non-sticky column resize" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.col_ruler_widget.not_nil!

      # Get initial c3 label position (c2 is first non-sticky col on this ruler)
      prims_before = ruler.to_primitives(ruler.bounds)
      c3_before = prims_before.select(CrymbleUI::DrawText).find { |t| t.text == "c3" }
      c3_before.should_not be_nil
      c3_x_before = c3_before.not_nil!.position.x

      # Resize col 1 (first non-sticky): border at ruler_w + sticky_w + col_w(1)
      # Screen: 40 + 103 + 103 = 246
      border_x = RULER_COL_W_PX + R_COL_W * 2
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      ruler_after = matrix.col_ruler_widget.not_nil!
      prims_after = ruler_after.to_primitives(ruler_after.bounds)
      c3_after = prims_after.select(CrymbleUI::DrawText).find { |t| t.text == "c3" }
      c3_after.should_not be_nil
      c3_after.not_nil!.position.x.should be > c3_x_before

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end
  end

  describe "label centering" do
    it "column ruler labels are vertically centered within the ruler strip" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.col_ruler_widget.not_nil!
      prims = ruler.to_primitives(ruler.bounds)
      c2_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "c2" }
      c2_text.should_not be_nil

      # Label should be approximately vertically centered in ruler_h (20px)
      # text_y is top-left of glyph, so for centered text: 10-50% of ruler_h
      text_y = c2_text.not_nil!.position.y
      text_y.should be > RULER_ROW_H_PX * 0.1  # Not at very top
      text_y.should be < RULER_ROW_H_PX * 0.5  # Top-left must be above center
    end

    it "row ruler labels are vertically centered within row height" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.row_ruler_widget.not_nil!
      prims = ruler.to_primitives(ruler.bounds)
      row2_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "2" }
      row2_text.should_not be_nil

      # Row 1 (label "2") is first non-sticky row, starts at acc_y = ruler_row_h + sticky_row_h
      # The label should be centered within its row_h (23px) cell
      text_y = row2_text.not_nil!.position.y
      # text_y is top-left of glyph; relative position within cell should be 10-50%
      row_start_y = RULER_ROW_H_PX + matrix.sticky_row_height_pixels  # start of first non-sticky row
      relative_y = text_y - row_start_y
      relative_y.should be > R_ROW_H * 0.1
      relative_y.should be < R_ROW_H * 0.5
    end

    it "row ruler labels are horizontally centered within ruler width" do
      renderer, app, matrix = make_ruler_dsl

      ruler = matrix.row_ruler_widget.not_nil!
      prims = ruler.to_primitives(ruler.bounds)
      row2_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "2" }
      row2_text.should_not be_nil

      # Label should be approximately horizontally centered in ruler_w (40px)
      text_x = row2_text.not_nil!.position.x
      text_x.should be > RULER_COL_W_PX * 0.3  # Not too left
      text_x.should be < RULER_COL_W_PX * 0.7  # Not too right
    end

    it "corner column labels are vertically centered" do
      renderer, app, matrix = make_ruler_dsl

      corner = matrix.corner_ruler_widget.not_nil!
      prims = corner.to_primitives(corner.bounds)
      c1_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "c1" }
      c1_text.should_not be_nil

      text_y = c1_text.not_nil!.position.y
      text_y.should be > RULER_ROW_H_PX * 0.1
      text_y.should be < RULER_ROW_H_PX * 0.5
    end

    it "corner row labels are vertically centered" do
      renderer, app, matrix = make_ruler_dsl

      strip = matrix.corner_row_strip_widget.not_nil!
      prims = strip.to_primitives(strip.bounds)
      row1_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "1" }
      row1_text.should_not be_nil

      text_y = row1_text.not_nil!.position.y
      # text_y is top-left of glyph; should be centered within row_h (23px)
      text_y.should be > R_ROW_H * 0.1
      text_y.should be < R_ROW_H * 0.5
    end
  end

  describe "border between sticky and non-sticky" do
    it "corner row strip has bottom border at sticky row boundary" do
      renderer, app, matrix = make_ruler_dsl

      strip = matrix.corner_row_strip_widget.not_nil!
      prims = strip.to_primitives(strip.bounds)
      lines = prims.select(CrymbleUI::DrawLine)

      # Last sticky row border should be at y = row_h (23px) = bottom of single sticky row
      # This border separates sticky row "1" from non-sticky row "2"
      bottom_border = lines.find { |l| l.from.y.round(0) == R_ROW_H.round(0) && l.to.y.round(0) == R_ROW_H.round(0) }
      bottom_border.should_not be_nil
    end

    it "corner ruler has right border at sticky col boundary" do
      renderer, app, matrix = make_ruler_dsl

      corner = matrix.corner_ruler_widget.not_nil!
      prims = corner.to_primitives(corner.bounds)
      lines = prims.select(CrymbleUI::DrawLine)

      # Last sticky col border at x = ruler_w + col_w (40 + 103 = 143)
      expected_x = RULER_COL_W_PX + R_COL_W
      right_border = lines.find { |l| l.from.x.round(0) == expected_x.round(0) && l.to.x.round(0) == expected_x.round(0) }
      right_border.should_not be_nil
    end
  end

  describe "corner ruler resize during drag" do
    it "corner ruler width updates when sticky column is resized" do
      renderer, app, matrix = make_ruler_dsl

      corner = matrix.corner_ruler_widget.not_nil!
      original_width = corner.bounds.width

      # Resize col 0 (sticky): drag border 40px right
      border_x = RULER_COL_W_PX + R_COL_W
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      # Corner ruler should grow to accommodate wider sticky column
      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      new_corner = matrix.corner_ruler_widget.not_nil!
      new_corner.bounds.width.should be > original_width

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end

    it "corner row strip height updates when sticky row is resized" do
      renderer, app, matrix = make_ruler_dsl

      strip = matrix.corner_row_strip_widget.not_nil!
      original_height = strip.bounds.height

      # Resize row 0 (sticky): drag border 30px down
      border_y = RULER_ROW_H_PX + R_ROW_H
      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, border_y))
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
      renderer.render_frame(app)

      # Corner row strip should grow to accommodate taller sticky row
      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      new_strip = matrix.corner_row_strip_widget.not_nil!
      new_strip.bounds.height.should be > original_height

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
    end

    it "corner ruler c1 label still visible after sticky column resize" do
      renderer, app, matrix = make_ruler_dsl

      # Resize col 0 (sticky): drag border 40px right
      border_x = RULER_COL_W_PX + R_COL_W
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      corner = matrix.corner_ruler_widget.not_nil!
      prims = corner.to_primitives(corner.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)

      # c1 label should still be present and within bounds
      texts.should contain("c1")

      # c1 label should be within the widget bounds (not clipped)
      c1_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "c1" }
      c1_text.not_nil!.position.x.should be < corner.bounds.width

      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 40.0, 10.0))
    end

    it "corner row strip row 1 label still visible after sticky row resize", tags: "slow" do
      renderer, app, matrix = make_ruler_dsl

      # Resize row 0 (sticky): drag border 30px down
      border_y = RULER_ROW_H_PX + R_ROW_H
      app.handle_mouse_down(CrymbleUI::Vec2.new(20.0, border_y))
      app.handle_mouse_move(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
      renderer.render_frame(app)

      matrix = app.find("ruler_test").as(CrymbleUI::VirtualMatrix)
      strip = matrix.corner_row_strip_widget.not_nil!
      prims = strip.to_primitives(strip.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)

      # Row "1" label should still be present and within bounds
      texts.should contain("1")

      # Row "1" label should be within the widget bounds (not clipped)
      row1_text = prims.select(CrymbleUI::DrawText).find { |t| t.text == "1" }
      row1_text.not_nil!.position.y.should be < strip.bounds.height

      app.handle_mouse_up(CrymbleUI::Vec2.new(20.0, border_y + 30.0))
    end
  end

  describe "performance" do
    it "ruler render count bounded during resize drag", tags: "slow" do
      renderer, app, matrix = make_ruler_dsl

      renderer.settle_rendering(app)
      renderer.reset_counters

      # Resize col 0 with 5 drag steps
      border_x = RULER_COL_W_PX + R_COL_W
      app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, 10.0))
      5.times do |i|
        app.handle_mouse_move(CrymbleUI::Vec2.new(border_x + (i + 1) * 10.0, 10.0))
        renderer.render_frame(app)
      end
      app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + 50.0, 10.0))

      # Layout count should be 0 during drag (resize doesn't trigger layout)
      renderer.layout_count.should eq 0
    end
  end
end
