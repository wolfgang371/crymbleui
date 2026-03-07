require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Test app for scroll preservation testing (must be declared outside describe block)
class ScrollPreserveTestApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scroll_preserve")
  end
end

describe CrymbleUI::VirtualMatrix do
  describe "Basic Grid" do
    it "creates matrix with specified rows and cols" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50)
      matrix.rows.should eq(100)
      matrix.cols.should eq(50)
    end

    it "computes visible cell indices from viewport" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "visible_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      # 400x300 viewport with default cell sizes should show subset of cells
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      visible = matrix.visible_cell_indices
      visible[:rows].size.should be < 100
      visible[:cols].size.should be < 50
      visible[:rows].first.should eq(0)  # First row visible at scroll=0
      visible[:cols].first.should eq(0)  # First col visible at scroll=0
    end

    it "creates cell widgets only for visible cells" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "cell_create")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Should create cells only for visible area + buffer, not all 5000
      matrix.active_cells.size.should be < 200
      matrix.active_cells.size.should be > 0
    end

    it "updates visible cells on scroll" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scroll_visible")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      initial_keys = matrix.active_cells.keys.to_set
      initial_keys.should_not be_empty

      # Scroll down significantly
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 500.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      current_keys = matrix.active_cells.keys.to_set
      # Should have new cells after scrolling
      new_keys = current_keys - initial_keys
      new_keys.should_not be_empty

      # New cells should be in lower rows
      new_keys.all? { |rc| rc[0] > 0 }.should be_true
    end

    it "destroys cells that scroll out of view" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scroll_destroy")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      initial_count = matrix.active_cell_count

      # Scroll down past initial cells
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 2000.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cell count should be similar (not accumulating)
      # Allow some variance for edge cells
      matrix.active_cell_count.should be_close(initial_count, initial_count * 0.5)
    end

    it "positions cells correctly at pixel coordinates" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "cell_pos")
      matrix.show_rulers = false

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cell (0,0) should start at origin (no header offsets)
      # Use matrix.active_cells which contains the actual cell widgets
      if cell = matrix.active_cells[{0, 0}]?
        cell.bounds.x.should eq 0.0  # Starts at origin
        cell.bounds.y.should eq 0.0  # Starts at origin
      end

      # Cell (0,1) should be further right than cell (0,0)
      if cell_01 = matrix.active_cells[{0, 1}]?
        if cell_00 = matrix.active_cells[{0, 0}]?
          cell_01.bounds.x.should be > cell_00.bounds.x
        end
      end
    end

    it "preserves scroll offset on DSL rebuild" do
      app = ScrollPreserveTestApp.new
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)

      # Set scroll offset
      matrix = app.find("scroll_preserve").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset = CrymbleUI::Vec2.new(100.0, 200.0)

      # Trigger rebuild
      app.rebuild

      # Scroll offset should be preserved
      new_matrix = app.find("scroll_preserve").as(CrymbleUI::VirtualMatrix)
      new_matrix.scroll_offset.x.should eq(100.0)
      new_matrix.scroll_offset.y.should eq(200.0)
    end

    it "handles mouse wheel scroll" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "wheel_scroll")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      initial_scroll = matrix.scroll_offset.y

      # Simulate mouse wheel down (negative delta = scroll down = content moves up)
      point = CrymbleUI::Vec2.new(200.0, 150.0)  # Inside matrix
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), point)

      matrix.scroll_offset.y.should be > initial_scroll
    end
  end
end
