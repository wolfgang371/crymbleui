require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Bug: Rulers don't update when navigating with cursor keys.
# Root cause: snap_to_cursor changes scroll_offset but doesn't call
# mark_ruler_widgets_dirty (unlike on_mouse_wheel which does).

# Simple adapter with enough rows/cols to require scrolling
class RulerNavTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@data_rows : Int32 = 30, @data_cols : Int32 = 30)
    @total_rows = 2 + @data_rows   # 2 sticky header rows
    @total_cols = 2 + @data_cols   # 2 sticky header cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows = (2...@total_rows).to_a + [1, 0]
    cols = (2...@total_cols).to_a + [1, 0]
    {rows, cols}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    row_heights = Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 }
    col_widths = Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }
    {row_heights, col_widths}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("(#{row},#{col})")
  end
end

private def setup_ruler_nav_matrix(viewport_height = 200)
  adapter = RulerNavTestAdapter.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "ruler_nav")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  renderer = CrymbleUI::Testing::TestRenderer.new(600, viewport_height)
  renderer.settle_rendering(app)

  CrymbleUI::Widget.focus_manager.focus(matrix)

  {matrix, app, renderer}
end

describe CrymbleUI::VirtualMatrix do
  describe "Ruler update on cursor key navigation" do
    it "row ruler layer is marked dirty after cursor-key vertical scroll" do
      matrix, app, renderer = setup_ruler_nav_matrix(viewport_height: 200)

      sv = matrix.content_scroll_view.not_nil!
      col_layer = sv.sticky_col_layer.not_nil!

      initial_scroll_y = matrix.scroll_offset.y

      # Navigate down enough to force a scroll
      30.times do
        matrix.on_key_down(SF::Keyboard::Key::Down, control: false, shift: false)
      end

      # Scroll should have changed
      matrix.scroll_offset.y.should be > initial_scroll_y,
        "Cursor navigation should have scrolled down"

      # The sticky_col_layer (row ruler) should be dirty BEFORE render
      col_layer.dirty_widgets.size.should be > 0,
        "sticky_col_layer should have dirty widgets after cursor key navigation " \
        "(mark_ruler_widgets_dirty not called in snap_to_cursor)"

      renderer.settle_rendering(app)
    end

    it "column ruler layer is marked dirty after cursor-key horizontal scroll" do
      matrix, app, renderer = setup_ruler_nav_matrix(viewport_height: 400)

      sv = matrix.content_scroll_view.not_nil!
      row_layer = sv.sticky_row_layer.not_nil!

      initial_scroll_x = matrix.scroll_offset.x

      # Navigate right enough to force horizontal scroll
      30.times do
        matrix.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      end

      # Scroll should have changed
      matrix.scroll_offset.x.should be > initial_scroll_x,
        "Cursor navigation should have scrolled right"

      # The sticky_row_layer (column ruler) should be dirty BEFORE render
      row_layer.dirty_widgets.size.should be > 0,
        "sticky_row_layer should have dirty widgets after cursor key navigation " \
        "(mark_ruler_widgets_dirty not called in snap_to_cursor)"

      renderer.settle_rendering(app)
    end
  end
end
