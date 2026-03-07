require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Reuse StickyPositioningAdapter from sticky_positioning_spec.cr
class StickyScrollAdapter
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

  # No sticky_row_count / sticky_col_count overrides!
  # Stickiness derived from scroll_order (row 0 / col 0 last → sticky).
end

private def setup_scroll_alignment_matrix(adapter, viewport_width = 400.0, viewport_height = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_align_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "sticky cell scroll alignment" do
    it "sticky_row cell x aligns with content cell x after hscroll" do
      # Row 0 sticky, Col 0 sticky (like the demo)
      adapter = StickyScrollAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0],
)
      matrix, _, constraints = setup_scroll_alignment_matrix(adapter, 600.0, 400.0)

      # Scroll horizontally past one column
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      scroll_x = col_w * 1.5  # 1.5 columns scrolled
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Find a shared column that has both a sticky_row cell and a content cell
      # Col 2 should be visible in both layers
      header_cell = matrix.active_cells[{0, 2}]?  # sticky_row cell (row 0)
      content_cell = matrix.active_cells[{1, 2}]?  # content cell (row 1)

      header_cell.should_not be_nil
      content_cell.should_not be_nil

      # After hscroll, sticky_row cell must pixel-align with the content cell.
      # Content layer compositor truncates scroll to integer (viewport_x = scroll.to_i),
      # so sticky header must use the same integer scroll for pixel-perfect borders.
      header_cell.not_nil!.bounds.x.should eq(content_cell.not_nil!.bounds.x - scroll_x.to_i.to_f64)
    end

    it "sticky_col cell y aligns with content cell y after vscroll" do
      adapter = StickyScrollAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0],
)
      matrix, _, constraints = setup_scroll_alignment_matrix(adapter, 600.0, 400.0)

      # Scroll vertically past one row
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      scroll_y = row_h * 1.5
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll_y)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Find a shared row that has both a sticky_col cell and a content cell
      # Row 2 should be visible
      sticky_col_cell = matrix.active_cells[{2, 0}]?  # sticky_col cell (col 0)
      content_cell = matrix.active_cells[{2, 1}]?      # content cell (col 1)

      sticky_col_cell.should_not be_nil
      content_cell.should_not be_nil

      # After vscroll, sticky_col cell must pixel-align with the content cell.
      # Content layer compositor truncates scroll to integer, so sticky must match.
      sticky_col_cell.not_nil!.bounds.y.should eq(content_cell.not_nil!.bounds.y - scroll_y.to_i.to_f64)
    end

    it "sticky_corner cell does not move on scroll" do
      adapter = StickyScrollAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0],
)
      matrix, _, constraints = setup_scroll_alignment_matrix(adapter, 600.0, 400.0)

      # Record corner cell position before scroll
      corner_cell = matrix.active_cells[{0, 0}]?
      corner_cell.should_not be_nil
      original_x = corner_cell.not_nil!.bounds.x
      original_y = corner_cell.not_nil!.bounds.y

      # Scroll both directions
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w * 2, row_h * 2)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Corner cell should NOT move (it's fixed in both directions)
      corner_cell_after = matrix.active_cells[{0, 0}]?
      corner_cell_after.should_not be_nil
      corner_cell_after.not_nil!.bounds.x.should eq(original_x)
      corner_cell_after.not_nil!.bounds.y.should eq(original_y)
    end

    it "sticky_row cells reposition on scroll even when visible indices unchanged" do
      adapter = StickyScrollAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0],
)
      matrix, _, constraints = setup_scroll_alignment_matrix(adapter, 600.0, 400.0)

      # Small scroll that doesn't change visible indices (within early-exit threshold)
      scroll_x = 10.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      header_cell = matrix.active_cells[{0, 2}]?
      content_cell = matrix.active_cells[{1, 2}]?
      header_cell.should_not be_nil
      content_cell.should_not be_nil

      # Even with small scroll, sticky_row cell should be repositioned
      header_cell.not_nil!.bounds.x.should eq(content_cell.not_nil!.bounds.x - scroll_x)
    end
  end
end
