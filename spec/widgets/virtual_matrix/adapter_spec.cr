require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/virtual_matrix/adapter"
require "../../../src/testing/test_renderer"

# Simple test adapter implementation
class TestMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  @data : Array(Array(String))

  def initialize(rows : Int32, cols : Int32)
    @data = Array.new(rows) { |r| Array.new(cols) { |c| "#{r},#{c}" } }
  end

  def row_count : Int32
    @data.size
  end

  def col_count : Int32
    @data.first?.try(&.size) || 0
  end

  def cell_read(row : Int32, col : Int32) : String
    @data[row]?.try(&.[col]?) || ""
  end

  def cell_write(row : Int32, col : Int32, value : String)
    if @data[row]?
      @data[row][col] = value
    end
  end

  def insert_row(at : Int32) : Int32
    cols = @data.first?.try(&.size) || 0
    new_row = Array.new(cols) { |c| "new,#{c}" }
    @data.insert(at, new_row)
    at
  end

  def delete_row(at : Int32)
    @data.delete_at(at) if at < @data.size
  end

  def cell_has_content?(row : Int32, col : Int32) : Bool
    !cell_read(row, col).empty?
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new(cell_read(row, col))
  end
end

# Helper: set up matrix with adapter and render it
private def setup_rendered_matrix(adapter, viewport_width = 400.0, viewport_height = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "adapter_test")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  renderer = CrymbleUI::Testing::TestRenderer.new(viewport_width.to_i, viewport_height.to_i)
  renderer.settle_rendering(app)

  {matrix, app, renderer}
end

describe CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter do
  describe "Basic Interface" do
    it "provides row and column counts via get_scrollorder" do
      adapter = TestMatrixAdapter.new(10, 5)
      row_order, col_order = adapter.get_scrollorder
      row_order.size.should eq(10)
      col_order.size.should eq(5)
    end

    it "reads cell values" do
      adapter = TestMatrixAdapter.new(10, 5)
      adapter.cell_read(3, 2).should eq("3,2")
    end

    it "writes cell values" do
      adapter = TestMatrixAdapter.new(10, 5)
      adapter.cell_write(3, 2, "modified")
      adapter.cell_read(3, 2).should eq("modified")
    end

    it "inserts rows" do
      adapter = TestMatrixAdapter.new(5, 3)
      initial_count = adapter.get_scrollorder[0].size

      adapter.insert_row(2)

      adapter.get_scrollorder[0].size.should eq(initial_count + 1)
      adapter.cell_read(2, 0).should eq("new,0")  # New row
      adapter.cell_read(3, 0).should eq("2,0")    # Old row 2 shifted down
    end

    it "deletes rows" do
      adapter = TestMatrixAdapter.new(5, 3)
      initial_count = adapter.get_scrollorder[0].size

      adapter.delete_row(2)

      adapter.get_scrollorder[0].size.should eq(initial_count - 1)
      adapter.cell_read(2, 0).should eq("3,0")  # Old row 3 shifted up
    end
  end

  describe "Push-Based Invalidation" do
    it "invalidate_cell! before matrix bound is safe (no crash)" do
      adapter = TestMatrixAdapter.new(5, 5)
      # Should not crash when called on unbound adapter
      adapter.invalidate_cell!(0, 0)
    end

    it "invalidate_all! before matrix bound is safe (no crash)" do
      adapter = TestMatrixAdapter.new(5, 5)
      # Should not crash when called on unbound adapter
      adapter.invalidate_all!
    end
  end
end

describe CrymbleUI::VirtualMatrix do
  describe "Adapter Integration" do
    it "can use adapter for data binding" do
      adapter = TestMatrixAdapter.new(100, 50)
      matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "adapter_matrix")

      matrix.rows.should eq(100)
      matrix.cols.should eq(50)
    end

    it "creates cells using adapter data" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, _app, _renderer = setup_rendered_matrix(adapter)

      # Cells should be created via adapter.cell_paint
      matrix.active_cells.should_not be_empty
      matrix.active_cells.size.should be > 0
    end
  end

  describe "Push-Based Cell Invalidation" do
    it "invalidate_cell! on visible cell recreates widget" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      # Cell (0,0) should be visible and active
      old_widget = matrix.active_cells[{0, 0}]?
      old_widget.should_not be_nil

      # Modify data and invalidate
      adapter.cell_write(0, 0, "CHANGED")
      adapter.invalidate_cell!(0, 0)

      # Flush: render a frame to process pending invalidations
      renderer.render_frame(app)

      # New widget should have been created
      new_widget = matrix.active_cells[{0, 0}]?
      new_widget.should_not be_nil
      new_widget.should_not eq(old_widget)
    end

    it "invalidate_cell! on non-visible cell is a no-op" do
      adapter = TestMatrixAdapter.new(100, 100)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      initial_count = matrix.active_cells.size

      # Cell (99,99) is far off-screen - should not be visible
      matrix.active_cells[{99, 99}]?.should be_nil

      # Invalidate non-visible cell
      adapter.invalidate_cell!(99, 99)
      renderer.render_frame(app)

      # Active cells should be unchanged
      matrix.active_cells.size.should eq(initial_count)
    end

    it "multiple invalidate_cell! calls to same cell are batched" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      old_widget = matrix.active_cells[{0, 0}]?
      old_widget.should_not be_nil

      # Call invalidate_cell! 10 times on the same cell before flushing
      10.times { adapter.invalidate_cell!(0, 0) }

      # All should be batched into single recreation
      renderer.render_frame(app)

      new_widget = matrix.active_cells[{0, 0}]?
      new_widget.should_not be_nil
      new_widget.should_not eq(old_widget)
    end
  end

  describe "Push-Based Full Invalidation" do
    it "invalidate_all! updates dimensions from adapter" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      initial_rows = matrix.rows

      # Insert a row via adapter
      adapter.insert_row(0)
      adapter.invalidate_all!

      # Flush: render to process pending invalidation
      renderer.render_frame(app)

      matrix.rows.should eq(initial_rows + 1)
    end

    it "invalidate_all! recreates all visible cells" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      old_widgets = matrix.active_cells.dup

      adapter.invalidate_all!
      renderer.render_frame(app)

      # All active cells should have been recreated (new widget instances)
      matrix.active_cells.should_not be_empty
      matrix.active_cells.each do |key, new_widget|
        if old_widget = old_widgets[key]?
          new_widget.should_not eq(old_widget)
        end
      end
    end

    it "invalidate_all! supersedes pending cell invalidations" do
      adapter = TestMatrixAdapter.new(10, 10)
      matrix, app, renderer = setup_rendered_matrix(adapter)

      # Queue some cell invalidations
      adapter.invalidate_cell!(0, 0)
      adapter.invalidate_cell!(1, 1)

      # Then queue a full invalidation (should supersede cell-level)
      adapter.insert_row(0)
      adapter.invalidate_all!

      # Should not crash - full invalidation clears cell queue
      renderer.render_frame(app)

      matrix.rows.should eq(11)
    end
  end
end
