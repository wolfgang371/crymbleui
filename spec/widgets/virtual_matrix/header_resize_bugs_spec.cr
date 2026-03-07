require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/rendering/layer_renderer"

# Adapter matching the demo: 2-level headers, 2×2 sticky rows/cols, compound cells.
#
# Grid layout (12×12):
#   Row 0: level-1 col headers (merged: spans 5 data cols each)
#   Row 1: level-2 col headers (individual cells)
#   Col 0: level-1 row headers (merged: spans 5 data rows each)
#   Col 1: level-2 row headers (individual cells)
#   Corner (rows 0-1, cols 0-1): merged per row across both header cols
#   Rows 2-11, Cols 2-11: data cells
class HeaderResizeAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # Sticky rows/cols: tail {1, 0} forms contiguous set → sticky_count = 2
    {(2...12).to_a + [1, 0], (2...12).to_a + [1, 0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    label = if row < 2 && col < 2
              "corner#{row}"
            elsif row < 2
              "ch#{row}c#{col}"
            elsif col < 2
              "rh#{col}r#{row}"
            else
              "d#{row - 2}_#{col - 2}"
            end
    TestVisibleCell.new(label)
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    # Corner: merge across both header cols per row
    if row < 2 && col < 2
      return { {row, 0}, {row, 1} }
    end
    # Level-1 col headers (row 0): span 5 data cols each
    if row == 0 && col >= 2
      group = (col - 2) // 5
      c_start = 2 + group * 5
      c_end = {c_start + 4, 11}.min
      return { {0, c_start}, {0, c_end} }
    end
    # Level-1 row headers (col 0): span 5 data rows each
    if col == 0 && row >= 2
      group = (row - 2) // 5
      r_start = 2 + group * 5
      r_end = {r_start + 4, 11}.min
      return { {r_start, 0}, {r_end, 0} }
    end
    # Default: single cell
    { {row, col}, {row, col} }
  end
end

# DSL-style app for header resize tests
class HeaderResizeDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(HeaderResizeAdapter.new, id: "header_resize_test")
  end
end

# Pixel constants (frame_height=20)
HR_RULER_COL_W = 40.0  # RULER_COL_WIDTH(2.0) * 20
HR_RULER_ROW_H = 20.0  # RULER_ROW_HEIGHT(1.0) * 20
HR_COL_W       = 103.0  # GRID_SPACING(3) + DEFAULT_COLUMN_WIDTH(5.0) * 20
HR_ROW_H       = 23.0   # GRID_SPACING(3) + DEFAULT_ROW_HEIGHT(1.0) * 20

private def make_header_resize_dsl
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app = HeaderResizeDSLApp.new
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("header_resize_test").as(CrymbleUI::VirtualMatrix)
  {renderer, app, matrix}
end

# Simulate drag on row border in ruler strip (x < 40).
# Returns the matrix reference (may differ after DSL rebuild).
private def drag_row_border(app, renderer, row_index : Int32, delta_y : Float64)
  # Row border screen Y = ruler_h + cumulative row heights through row_index
  border_y = HR_RULER_ROW_H + HR_ROW_H * (row_index + 1)
  x = 20.0 # Within ruler strip

  app.handle_mouse_down(CrymbleUI::Vec2.new(x, border_y))
  steps = {delta_y.abs.to_i, 1}.max
  steps.times do |i|
    new_y = border_y + delta_y * (i + 1) / steps
    app.handle_mouse_move(CrymbleUI::Vec2.new(x, new_y))
    renderer.render_frame(app)
  end
  app.handle_mouse_up(CrymbleUI::Vec2.new(x, border_y + delta_y))
  renderer.render_frame(app)

  app.find("header_resize_test").as(CrymbleUI::VirtualMatrix)
end

# Simulate drag on col border in ruler strip (y < 20).
private def drag_col_border(app, renderer, col_index : Int32, delta_x : Float64)
  border_x = HR_RULER_COL_W + HR_COL_W * (col_index + 1)
  y = 10.0 # Within ruler strip

  app.handle_mouse_down(CrymbleUI::Vec2.new(border_x, y))
  steps = {delta_x.abs.to_i, 1}.max
  steps.times do |i|
    new_x = border_x + delta_x * (i + 1) / steps
    app.handle_mouse_move(CrymbleUI::Vec2.new(new_x, y))
    renderer.render_frame(app)
  end
  app.handle_mouse_up(CrymbleUI::Vec2.new(border_x + delta_x, y))
  renderer.render_frame(app)

  app.find("header_resize_test").as(CrymbleUI::VirtualMatrix)
end

describe "VirtualMatrix header resize bugs" do
  describe "sticky layer bounds vs actual sticky dimensions" do
    # BUG: ScrollView.sticky_row_height is only set in perform_layout (line 664),
    # NOT during resize drag. So sticky layer bounds stay at pre-resize values,
    # clipping widgets that grew beyond them.

    it "corner layer height matches sticky dimensions after row 0 resize", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Pre-resize sanity: 2 sticky rows × 23px + ruler 20px = 66px
      sv = matrix.content_scroll_view.not_nil!
      corner = sv.sticky_corner_layer.not_nil!
      corner.bounds.height.should be_close(HR_RULER_ROW_H + 2 * HR_ROW_H, 1.0)

      # Resize row 0 (sticky): make 30px taller
      matrix = drag_row_border(app, renderer, row_index: 0, delta_y: 30.0)

      # After resize: row 0 = 53px, row 1 = 23px → sticky = 76px + ruler 20px = 96px
      sv = matrix.content_scroll_view.not_nil!
      corner = sv.sticky_corner_layer.not_nil!
      expected_h = matrix.sticky_row_height_pixels + matrix.ruler_row_height_pixels
      expected_h.should be > HR_RULER_ROW_H + 2 * HR_ROW_H # Sanity: actually grew

      corner.bounds.height.should be_close(expected_h, 1.0)
    end

    it "corner layer width matches sticky dimensions after col 0 resize", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Pre-resize sanity: 2 sticky cols × 103px + ruler 40px = 246px
      sv = matrix.content_scroll_view.not_nil!
      corner = sv.sticky_corner_layer.not_nil!
      corner.bounds.width.should be_close(HR_RULER_COL_W + 2 * HR_COL_W, 1.0)

      # Resize col 0 (sticky): make 40px wider
      matrix = drag_col_border(app, renderer, col_index: 0, delta_x: 40.0)

      sv = matrix.content_scroll_view.not_nil!
      corner = sv.sticky_corner_layer.not_nil!
      expected_w = matrix.sticky_col_width_pixels + matrix.ruler_col_width_pixels
      expected_w.should be > HR_RULER_COL_W + 2 * HR_COL_W # Sanity: actually grew

      corner.bounds.width.should be_close(expected_w, 1.0)
    end

    it "sticky row layer repositions when sticky col width changes", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Resize col 0 (sticky): make 40px wider
      matrix = drag_col_border(app, renderer, col_index: 0, delta_x: 40.0)

      sv = matrix.content_scroll_view.not_nil!
      row_layer = sv.sticky_row_layer.not_nil!

      # Row layer left edge should align with new sticky col boundary
      expected_x = matrix.absolute_bounds.x + matrix.sticky_col_width_pixels + matrix.ruler_col_width_pixels
      row_layer.bounds.x.should be_close(expected_x, 1.0)
    end

    it "sticky col layer repositions when sticky row height changes", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Resize row 0 (sticky): make 30px taller
      matrix = drag_row_border(app, renderer, row_index: 0, delta_y: 30.0)

      sv = matrix.content_scroll_view.not_nil!
      col_layer = sv.sticky_col_layer.not_nil!

      # Col layer top edge should align with new sticky row boundary
      expected_y = matrix.absolute_bounds.y + matrix.sticky_row_height_pixels + matrix.ruler_row_height_pixels
      col_layer.bounds.y.should be_close(expected_y, 1.0)
    end
  end

  describe "ruler labels clipped by undersized layer" do
    it "corner row strip labels fit within corner layer after row resize", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Resize row 0 (sticky): make 30px taller
      matrix = drag_row_border(app, renderer, row_index: 0, delta_y: 30.0)

      # Strip should produce both "1" and "2" labels
      strip = matrix.corner_row_strip_widget.not_nil!
      prims = strip.to_primitives(strip.bounds)
      texts = prims.select(CrymbleUI::DrawText).map(&.text)
      texts.should contain("1")
      texts.should contain("2")

      # Strip must fit inside the corner layer (strip sits at y=ruler_h)
      sv = matrix.content_scroll_view.not_nil!
      corner = sv.sticky_corner_layer.not_nil!
      available_h = corner.bounds.height - matrix.ruler_row_height_pixels
      strip.bounds.height.should be <= available_h
    end
  end

  describe "level-2 header cells clipped by undersized row layer" do
    it "row 1 header cells fit within sticky row layer after row 0 resize", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Resize row 0 (sticky): make 30px taller
      matrix = drag_row_border(app, renderer, row_index: 0, delta_y: 30.0)

      sv = matrix.content_scroll_view.not_nil!
      row_layer = sv.sticky_row_layer.not_nil!
      row_layer_h = row_layer.bounds.height

      # Row 1 cells on the sticky_row_layer (cols >= 2) should be within the layer bounds.
      # After resize, true_y for row 1 = ruler_h + row_height(0)_new = 20 + 53 = 73
      # These cells must end within the layer height.
      cell_12 = matrix.active_cells[{1, 2}]?
      cell_12.should_not be_nil, "Level-2 header cell (1,2) should be active"

      cell = cell_12.not_nil!
      cell_bottom = cell.bounds.y + cell.bounds.height
      cell_bottom.should be <= row_layer_h,
        "Cell (1,2) bottom #{cell_bottom.round(1)} exceeds row layer height #{row_layer_h.round(1)}"
    end
  end

  describe "header-data overlap" do
    it "no overlap: first data row starts at or below sticky boundary", tags: "slow" do
      renderer, app, matrix = make_header_resize_dsl

      # Resize row 0 (sticky): make 30px taller
      matrix = drag_row_border(app, renderer, row_index: 0, delta_y: 30.0)

      # Data cell (2,2) is on the content layer. Its position should be at or below
      # the sticky region bottom = ruler_h + sticky_row_height_pixels.
      data_cell = matrix.active_cells[{2, 2}]?
      data_cell.should_not be_nil, "First data cell (2,2) should be active"

      sticky_bottom = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
      data_cell.not_nil!.bounds.y.should be >= sticky_bottom,
        "Data cell (2,2) y=#{data_cell.not_nil!.bounds.y.round(1)} overlaps " \
        "sticky region bottom=#{sticky_bottom.round(1)}"
    end
  end
end
