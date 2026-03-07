require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Adapter that provides scroll_order but does NOT override sticky_*_count.
# After refactor, VirtualMatrix should derive sticky counts from scroll_order.
class DerivedStickyTestAdapter
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

  # NOTE: No sticky_row_count / sticky_col_count overrides!
  # Stickiness should be derived from scroll_order.
end

private def setup_derived_sticky_matrix(adapter, viewport_width = 600.0, viewport_height = 400.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "derived_sticky_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "derive sticky counts from scroll_order" do
    it "derives sticky_row_count=1 when row 0 is last in scroll_order" do
      adapter = DerivedStickyTestAdapter.new(3, 3,
        row_scroll_order: [1, 2, 0])
      matrix, _, _ = setup_derived_sticky_matrix(adapter)

      matrix.sticky_row_count.should eq 1
    end

    it "derives sticky_col_count=1 when col 0 is last in scroll_order" do
      adapter = DerivedStickyTestAdapter.new(3, 3,
        col_scroll_order: [1, 2, 0])
      matrix, _, _ = setup_derived_sticky_matrix(adapter)

      matrix.sticky_col_count.should eq 1
    end

    it "derives sticky_count=2 when rows 0,1 are at the tail" do
      adapter = DerivedStickyTestAdapter.new(4, 3,
        row_scroll_order: [2, 3, 1, 0])
      matrix, _, _ = setup_derived_sticky_matrix(adapter)

      matrix.sticky_row_count.should eq 2
    end

    it "derives sticky_count=0 for default sequential scroll_order" do
      adapter = DerivedStickyTestAdapter.new(3, 3)
      # Default: [0, 1, 2] — last element is 2, not {0}, so sticky_count=0
      matrix, _, _ = setup_derived_sticky_matrix(adapter)

      matrix.sticky_row_count.should eq 0
      matrix.sticky_col_count.should eq 0
    end

    it "derives sticky_count=0 when tail doesn't form contiguous-from-0 set" do
      # scroll_order [0, 2, 1] — tail: 1→{1}≠{0}→0 sticky
      adapter = DerivedStickyTestAdapter.new(3, 3,
        row_scroll_order: [0, 2, 1])
      matrix, _, _ = setup_derived_sticky_matrix(adapter)

      matrix.sticky_row_count.should eq 0
    end

    it "sticky row cell stays fixed on vertical scroll (via scroll_order only)" do
      # 20 rows, row 0 is last in scroll_order → should be sticky
      adapter = DerivedStickyTestAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0])
      matrix, _, constraints = setup_derived_sticky_matrix(adapter, 600.0, 400.0)

      # Record corner cell position
      corner_cell = matrix.active_cells[{0, 0}]?
      corner_cell.should_not be_nil
      original_x = corner_cell.not_nil!.bounds.x
      original_y = corner_cell.not_nil!.bounds.y

      # Scroll vertically
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, row_h * 2)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Corner cell should stay at same position (sticky in both directions)
      corner_after = matrix.active_cells[{0, 0}]?
      corner_after.should_not be_nil
      corner_after.not_nil!.bounds.x.should eq(original_x)
      corner_after.not_nil!.bounds.y.should eq(original_y)
    end

    it "sticky row cell x-aligns with content cell after hscroll (via scroll_order only)" do
      adapter = DerivedStickyTestAdapter.new(20, 10,
        col_scroll_order: (1...10).to_a + [0],
        row_scroll_order: (1...20).to_a + [0])
      matrix, _, constraints = setup_derived_sticky_matrix(adapter, 600.0, 400.0)

      # Scroll horizontally
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      scroll_x = col_w * 1.5
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Sticky row cell and content cell in same column should x-align
      header_cell = matrix.active_cells[{0, 2}]?
      content_cell = matrix.active_cells[{1, 2}]?

      header_cell.should_not be_nil
      content_cell.should_not be_nil
      # Pixel alignment: content compositor truncates scroll to integer, sticky must match
      header_cell.not_nil!.bounds.x.should eq(content_cell.not_nil!.bounds.x - scroll_x.to_i.to_f64)
    end
  end
end
