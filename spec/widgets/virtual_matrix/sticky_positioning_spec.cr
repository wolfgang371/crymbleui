require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Test adapter with configurable scroll_order for sticky positioning tests
class StickyPositioningAdapter
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
  # Stickiness derived from scroll_order.
end

# Helper to set up a matrix with adapter and layout it
private def setup_sticky_matrix(adapter, viewport_width = 400.0, viewport_height = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_pos_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  matrix
end

describe CrymbleUI::VirtualMatrix do
  describe "StickyMath-based Cell Positioning" do
    it "positions cells identically to legacy behavior for sequential scroll_order" do
      # Sequential scroll_order should produce identical positions to (0...col).sum
      adapter = StickyPositioningAdapter.new(10, 10)
      matrix = setup_sticky_matrix(adapter)

      # Check that cells are positioned correctly
      # Cell (0,0) should be at ruler offset (rulers are on by default)
      ruler_x = matrix.ruler_col_width_pixels
      ruler_y = matrix.ruler_row_height_pixels
      if cell = matrix.active_cells[{0, 0}]?
        cell.bounds.x.should eq(ruler_x)
        cell.bounds.y.should eq(ruler_y)
      else
        fail "Cell (0,0) not found"
      end

      # Cell (0,1) should be at ruler_offset + col_width_pixels(0)
      if cell = matrix.active_cells[{0, 1}]?
        expected_x = ruler_x + matrix.get_col_width(0) * 20.0 + CrymbleUI::VirtualMatrix::GRID_SPACING
        cell.bounds.x.should eq(expected_x)
      end

      # Cell (1,0) should be at ruler_offset + row_height_pixels(0)
      if cell = matrix.active_cells[{1, 0}]?
        expected_y = ruler_y + matrix.get_row_height(0) * 20.0 + CrymbleUI::VirtualMatrix::GRID_SPACING
        cell.bounds.y.should eq(expected_y)
      end
    end

    it "positions cells using StickyMath output with non-sequential scroll_order" do
      # scroll_order [2,3,4,1,0] means col 2 scrolls out first, col 0 last (sticky-like)
      adapter = StickyPositioningAdapter.new(5, 5,
        col_scroll_order: [2, 3, 4, 1, 0])
      matrix = setup_sticky_matrix(adapter, 600.0, 300.0)

      # At scroll_offset=0, all cols visible, positions should be same as sequential
      # because offset=0 and positions accumulate from index 0.
      # Col 0 is sticky (last in scroll_order), so new_x = true_x = ruler_col_width_pixels + 0
      # ruler_col_width_pixels = RULER_COL_WIDTH * frame_height = 2.0 * 20.0 = 40.0
      if cell_00 = matrix.active_cells[{0, 0}]?
        expected_ruler_x = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
        cell_00.bounds.x.should eq(expected_ruler_x)
      end

      # Now scroll to shift col 2 out (first in scroll_order)
      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)
      scroll_x = col_w + 5.0  # Scroll past one column width

      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      # Re-layout to pick up scroll
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Col 2 should be shifted out (first in scroll_order)
      # Remaining cols: 0, 1, 3, 4 should have positions based on StickyMath
      # The key: col 0 (last in scroll_order, sticky-like) should still be visible
      visible = matrix.visible_cell_indices
      visible[:cols].should contain(0)  # Col 0 is last to scroll out, should be visible
      visible[:cols].should contain(1)  # Col 1 is second-to-last
    end

    it "sticky col position is correct regardless of scroll_x" do
      # Col 0 is sticky (last in scroll_order)
      adapter = StickyPositioningAdapter.new(5, 5,
        col_scroll_order: [2, 3, 4, 1, 0])
      matrix = setup_sticky_matrix(adapter, 600.0, 300.0)

      # Cell (0,0) should exist at ruler_col_width_pixels initially (col 0 is sticky, new_x = true_x)
      # ruler_col_width_pixels = RULER_COL_WIDTH * frame_height = 2.0 * 20.0 = 40.0
      if cell = matrix.active_cells[{0, 0}]?
        expected_ruler_x = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
        cell.bounds.x.should eq(expected_ruler_x)
      end

      # After scrolling, sticky col 0 should still be visible
      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w * 2, 0.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Col 0 should still be in visible indices
      matrix.visible_cell_indices[:cols].should contain(0)
    end

    it "cell positions use offset + positions[index] for absolute content-space position" do
      # This test verifies the core StickyMath integration:
      # cell position = offset + positions[index] from StickyMath.sticky()
      adapter = StickyPositioningAdapter.new(5, 5)
      matrix = setup_sticky_matrix(adapter, 600.0, 300.0)

      # Verify positions match StickyMath output
      col_sizes = (0...5).map { |c|
        (CrymbleUI::VirtualMatrix::GRID_SPACING + matrix.get_col_width(c) * 20.0).to_i32
      }
      row_sizes = (0...5).map { |r|
        (CrymbleUI::VirtualMatrix::GRID_SPACING + matrix.get_row_height(r) * 20.0).to_i32
      }

      # StickyMath with no scroll should give same positions
      col_offset, col_positions, _, _, _ = CrymbleUI::Widgets::VirtualMatrix::StickyMath.sticky(
        col_sizes, (0...5).to_a, 0, 600)
      row_offset, row_positions, _, _, _ = CrymbleUI::Widgets::VirtualMatrix::StickyMath.sticky(
        row_sizes, (0...5).to_a, 0, 300)

      # Check that cell positions match ruler_offset + offset + positions[index]
      ruler_x = matrix.ruler_col_width_pixels
      ruler_y = matrix.ruler_row_height_pixels
      if cell_11 = matrix.active_cells[{1, 1}]?
        expected_x = ruler_x + (col_offset + col_positions[1]).to_f64
        expected_y = ruler_y + (row_offset + row_positions[1]).to_f64
        cell_11.bounds.x.should eq(expected_x)
        cell_11.bounds.y.should eq(expected_y)
      end

      if cell_22 = matrix.active_cells[{2, 2}]?
        expected_x = ruler_x + (col_offset + col_positions[2]).to_f64
        expected_y = ruler_y + (row_offset + row_positions[2]).to_f64
        cell_22.bounds.x.should eq(expected_x)
        cell_22.bounds.y.should eq(expected_y)
      end
    end

    it "shifting col content-space position accounts for offset" do
      # When scrolled, the shifting element's position = offset + positions[shifting_index]
      adapter = StickyPositioningAdapter.new(5, 5,
        col_scroll_order: [0, 1, 2, 3, 4])
      matrix = setup_sticky_matrix(adapter, 600.0, 300.0)

      col_sizes = (0...5).map { |c|
        (CrymbleUI::VirtualMatrix::GRID_SPACING + matrix.get_col_width(c) * 20.0).to_i32
      }

      # Scroll to fully shift col 0 out
      scroll_x = col_sizes[0].to_f64 + 5.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Col 0 should be shifted out, col 1 is shifting element
      # Cell (0,1) should be at offset + positions[1]
      min_x = scroll_x.floor.to_i32
      max_x = (scroll_x + 600.0).ceil.to_i32
      col_offset, col_positions, shifting_idx, _, _ = CrymbleUI::Widgets::VirtualMatrix::StickyMath.sticky(
        col_sizes, (0...5).to_a, min_x, max_x)

      if cell_01 = matrix.active_cells[{0, 1}]?
        expected_x = matrix.ruler_col_width_pixels + (col_offset + col_positions[1]).to_f64
        cell_01.bounds.x.should eq(expected_x)
      end
    end
  end
end
