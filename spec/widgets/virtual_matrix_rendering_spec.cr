require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Tests that verify VirtualMatrix actually RENDERS cells, not just internal state.
# These tests catch "black screen" bugs where tests pass but nothing displays.

describe "VirtualMatrix rendering verification" do
  # === WIDGET BACKEND CHECKS ===
  # These verify cells actually render (catches "nothing renders" bugs)

  describe "widget_backend presence (basic rendering)" do
    it "visible cells have widget_backend after render" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "backend_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Get a visible cell widget from active_cells
      cell_widget = matrix.active_cells[{0, 0}]?
      cell_widget.should_not be_nil, "Cell (0,0) not in active_cells"
      cell_widget.not_nil!.widget_backend.should_not be_nil, "Cell (0,0) has no widget_backend (not rendered!)"
    end

    it "multiple visible cells have widget_backend" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "multi_backend")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Check multiple cells
      cells_with_backend = 0
      matrix.active_cells.each do |key, widget|
        cells_with_backend += 1 if widget.widget_backend != nil
      end

      cells_with_backend.should be > 0, "No cells have widget_backend (nothing rendered!)"
      # Most active cells should be rendered (buffer zone cells outside viewport may not have backends)
      cells_with_backend.should be >= (matrix.active_cell_count * 0.5), "Too few active cells have widget_backend"
    end

    it "newly visible cells after scroll have widget_backend" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "scroll_backend")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Scroll to make row 50 visible
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 1000.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Find a cell in the new visible area
      visible_rows = matrix.visible_cell_indices[:rows]
      visible_rows.should_not be_empty, "No visible rows after scroll"

      # Check a cell from the visible rows
      test_row = visible_rows.first
      cell_widget = matrix.active_cells[{test_row, 0}]?
      cell_widget.should_not be_nil, "Cell (#{test_row}, 0) not in active_cells after scroll"
      cell_widget.not_nil!.widget_backend.should_not be_nil, "Cell (#{test_row}, 0) has no widget_backend after scroll"
    end
  end

  describe "cell lifecycle (memory management)" do
    it "cells scrolled out are removed from active_cells" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "scroll_out")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Cell (0,0) is visible initially
      matrix.active_cells[{0, 0}]?.should_not be_nil, "Cell (0,0) should be visible initially"

      # Scroll down FAR past row 0 (enough that row 0 is definitely out)
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 2000.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Cell (0,0) should no longer exist (destroyed when scrolled out)
      matrix.active_cells[{0, 0}]?.should be_nil, "Cell (0,0) should be removed when scrolled out"
    end
  end

  describe "cell_screen_position helper" do
    it "returns correct position for cell (0,0)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "pos_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      pos = matrix.cell_screen_position(0, 0)
      # Cell (0,0) is offset by ruler dimensions (ruler_col_width_pixels=40, ruler_row_height_pixels=20)
      pos.x.should eq 40.0
      pos.y.should eq 20.0
    end

    it "cell position changes after scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "pos_scroll")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      pos_before = matrix.cell_screen_position(5, 0)

      # Scroll down
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 100.0)

      pos_after = matrix.cell_screen_position(5, 0)

      # Y position should decrease (cell scrolled up on screen)
      pos_after.y.should be < pos_before.y
    end
  end

  # === CLICK-BASED VERIFICATION ===
  # These verify hit-testing works (rendering + interaction)

  describe "hit testing (rendering + interaction)" do
    it "hit_test at cell position returns a widget" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "hit_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Get position of cell (1, 1) - offset from corner
      cell_pos = matrix.cell_screen_position(1, 1)
      # Add small offset to be inside the cell, not at edge
      test_point = CrymbleUI::Vec2.new(cell_pos.x + 5.0, cell_pos.y + 5.0)

      # Hit test should return something
      hit = app.root.not_nil!.hit_test(test_point)
      hit.should_not be_nil, "Hit test at cell position returned nil"
    end
  end

  # === LAYER RENDERING ===
  # Verify layer-based rendering is working

  describe "layer rendering" do
    it "content layer has widgets registered after layout" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "layer_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      layer = matrix.content_layer
      layer.should_not be_nil, "Content layer not created"
      layer.not_nil!.widgets.size.should be > 0, "Content layer has no widgets registered"
    end

    # Note: Header layer tests removed - architecture refactored to use adapter cell_paint with styling
    # instead of separate on_header_row/on_header_col/on_corner callbacks

    it "content layer bounds exclude scrollbar area when both scrollbars present" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      # Large matrix that overflows in both directions → needs both scrollbars
      matrix = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 100, id: "scrollbar_bounds")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      layer = matrix.content_layer.not_nil!
      scrollbar_w = CrymbleUI::ScrollView::SCROLLBAR_WIDTH

      # Content layer must NOT span into scrollbar area
      layer.bounds.width.should eq(400.0 - scrollbar_w),
        "Content layer width should exclude vertical scrollbar (expected #{400.0 - scrollbar_w}, got #{layer.bounds.width})"
      layer.bounds.height.should eq(300.0 - scrollbar_w),
        "Content layer height should exclude horizontal scrollbar (expected #{300.0 - scrollbar_w}, got #{layer.bounds.height})"
    end
  end
end
