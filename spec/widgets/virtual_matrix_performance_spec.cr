require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Adapter with sticky headers for blit-plan performance tests
class StickyBlitTestAdapter
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

# Performance tests for VirtualMatrix
# Verifies O(visible) behavior, not O(total grid size)

describe "VirtualMatrix performance" do
  describe "virtual rendering (O(visible))" do
    it "active_cell_count is proportional to viewport, not total grid" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      # 1000x50 = 50,000 total cells, but only ~100 should be visible
      matrix = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 50, id: "big_grid")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Should have FAR fewer than 50,000 active cells
      # Viewport of 400x300 with ~100px cells should show maybe 4x12 = 48 cells max
      matrix.active_cell_count.should be < 200, "Too many active cells: #{matrix.active_cell_count} (expected < 200 for viewport)"
    end

    it "active_cell_count stays bounded during scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 50, id: "scroll_bound")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      initial_count = matrix.active_cell_count

      # Scroll multiple times
      10.times do |i|
        matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i * 100.0)
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)
      end

      # Active count should NOT have grown significantly (cells are recycled)
      # Allow 2x variance for buffer zone cells (creation_buffer creates cells beyond viewport)
      matrix.active_cell_count.should be <= (initial_count * 2).to_i, "Active cell count grew unbounded: #{matrix.active_cell_count} vs initial #{initial_count}"
    end
  end

  describe "scroll performance" do
    it "scroll does not scale with total grid size (primitive count)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Test with 100 rows
      app_100 = TestApp.new
      matrix_100 = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "grid_100")
      app_100.root_widget = matrix_100
      app_100.build_tree
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix_100.layout(constraints, CrymbleUI::Vec2.zero)

      renderer.settle_rendering(app_100)
      renderer.reset_counters
      matrix_100.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_100)
      prims_100 = renderer.primitive_count

      # Test with 1000 rows (10x more)
      app_1000 = TestApp.new
      matrix_1000 = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 10, id: "grid_1000")
      app_1000.root_widget = matrix_1000
      app_1000.build_tree
      matrix_1000.layout(constraints, CrymbleUI::Vec2.zero)

      renderer.settle_rendering(app_1000)
      renderer.reset_counters
      matrix_1000.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_1000)
      prims_1000 = renderer.primitive_count

      # O(visible) means primitive count should be similar (not 10x)
      # Allow 3x variance for edge effects, but definitely not 10x
      prims_1000.should be <= prims_100 * 3, "Primitive count scaled with grid size: #{prims_1000} vs #{prims_100} (expected similar)"
    end

    it "widget iteration count is O(visible), not O(total)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Test with 100 rows
      app_100 = TestApp.new
      matrix_100 = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "iter_100")
      app_100.root_widget = matrix_100
      app_100.build_tree
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix_100.layout(constraints, CrymbleUI::Vec2.zero)

      renderer.settle_rendering(app_100)
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix_100.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_100)
      iter_100 = CrymbleUI::LayerRenderer.frame_widgets_iterated

      # Test with 1000 rows (10x more)
      app_1000 = TestApp.new
      matrix_1000 = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 10, id: "iter_1000")
      app_1000.root_widget = matrix_1000
      app_1000.build_tree
      matrix_1000.layout(constraints, CrymbleUI::Vec2.zero)

      renderer.settle_rendering(app_1000)
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix_1000.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
      renderer.render_frame(app_1000)
      iter_1000 = CrymbleUI::LayerRenderer.frame_widgets_iterated

      # O(visible) means iteration count should be similar (not 10x)
      # Allow 3x variance, but definitely not 10x
      iter_1000.should be <= iter_100 * 3, "Widget iteration scaled with grid size: #{iter_1000} vs #{iter_100}"
    end
  end

  describe "layout performance" do
    # NOTE: This test documents current behavior - VirtualMatrix may need layout during scroll
    # to update visible cells. The key is that it's O(visible), not O(total).
    it "layout during scroll is bounded" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "layout_scroll")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll 10 times
      10.times do
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Layout count should be bounded (might be > 0 since scroll updates visible cells)
      # The key is it's not growing unbounded
      renderer.layout_count.should be <= 10, "Excessive layouts during scroll: #{renderer.layout_count}"
    end
  end

  describe "sticky layer blit-plan optimization" do
    # Adapter with sticky headers (row 0, col 0 are sticky)
    # Required for sticky layer tests - non-compound cells
    it "sticky layers use blit-plan on scroll, not full re-render" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      adapter = StickyBlitTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "blit_plan_test")
      matrix.show_rulers = false

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)

      # Reset counters after initial render is settled
      CrymbleUI::LayerRenderer.reset_frame_counters

      # Scroll one step (within same visible indices = early-exit path)
      center = CrymbleUI::Vec2.new(200.0, 150.0)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)

      # Sticky layers should have used blit-plan fast path (not full re-render)
      CrymbleUI::LayerRenderer.frame_blit_plan_count.should be >= 1,
        "Expected at least 1 blit-plan execution for sticky layers, got #{CrymbleUI::LayerRenderer.frame_blit_plan_count}"
    end

    it "does not re-render sticky cell primitives on scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      adapter = StickyBlitTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "no_rerender_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)

      # Count sticky cells for reference
      sticky_rows = matrix.sticky_row_count
      sticky_cols = matrix.sticky_col_count
      sticky_cell_count = matrix.active_cells.count { |key, _|
        key[0] < sticky_rows || key[1] < sticky_cols
      }
      sticky_cell_count.should be > 0, "Expected sticky cells to exist"

      renderer.reset_counters
      CrymbleUI::LayerRenderer.reset_frame_counters

      # Scroll one step
      center = CrymbleUI::Vec2.new(200.0, 150.0)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)

      # Primitive count should be low — sticky cells should NOT have re-rendered their primitives
      # Only newly-visible content cells at the edge should contribute primitives
      # With blit-plan, sticky cells are blitted (0 primitives each), so total should be
      # much less than if all sticky cells fully re-rendered
      max_expected_primitives = sticky_cell_count * 2  # Allow headroom for edge content cells
      renderer.primitive_count.should be <= max_expected_primitives,
        "Too many primitives on scroll: #{renderer.primitive_count} (sticky_cells=#{sticky_cell_count}, " \
        "expected <= #{max_expected_primitives} with blit-plan)"
    end

    it "sticky row cells appear at correct positions after vertical scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      adapter = StickyBlitTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "position_test")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)

      # Get sticky row layer
      scroll_view = matrix.content_scroll_view.not_nil!
      sticky_row_layer = scroll_view.sticky_row_layer
      sticky_row_layer.should_not be_nil, "Sticky row layer should exist"

      layer = sticky_row_layer.not_nil!
      backend = layer.backend
      backend.should_not be_nil, "Sticky row layer should have backend"

      # Scroll down
      center = CrymbleUI::Vec2.new(200.0, 150.0)
      3.times { matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center) }
      renderer.render_frame(app)

      # Verify sticky row layer has non-transparent pixels in header area
      # Row 0 header should be rendered at the top of the sticky layer
      test_backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
      # Sample pixels at y=5 (should be in first header row)
      non_transparent_count = 0
      (5..50).step(10) do |x|
        next if x >= test_backend.width
        pixel = test_backend.get_pixel(x, 5)
        next unless pixel
        non_transparent_count += 1 if pixel.a > 0
      end

      non_transparent_count.should be > 0,
        "Sticky row layer should have visible pixels at header position after scroll"
    end
  end

  describe "memory efficiency" do
    it "large grid does not allocate all cells upfront" do
      # This is mostly a sanity check - if it takes forever, we're allocating too much
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new

      matrix = CrymbleUI::VirtualMatrix.new(rows: 10000, cols: 100, id: "huge_grid")

      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # 10000x100 = 1,000,000 total cells
      # Should only create cells for visible area
      cells_created = matrix.active_cells.size
      cells_created.should be < 500, "Created too many cells: #{cells_created} (expected < 500 for viewport)"
    end
  end
end
