require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/testing/configurable_matrix_adapter"

# DSL-style app that rebuilds with a different row_hdr_levels configuration.
# On each build(), creates a NEW ConfigurableMatrixAdapter + NEW VirtualMatrix,
# exercising the reconciliation path (copy_state_from).
#
# Uses large leaf spans (20) so BOTH nrhl=2 and nrhl=1 produce content that
# exceeds the viewport on both axes. This ensures scrollbar visibility doesn't
# change and the content layer backend is NOT replaced during rendering.
class ReconfigDSLApp < CrymbleUI::App
  property nrhl : Int32 = 2

  def build : CrymbleUI::Widget
    adapter = ConfigurableMatrixAdapter.new(@nrhl, 1, 2, 2, 20, 20)
    CrymbleUI::VirtualMatrix.new(adapter, id: "reconfig_grid")
  end
end

# Mutable adapter for testing flush_invalidate_all path.
# Supports changing row/col count at runtime and calling invalidate_all!.
class MutableReconfigAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  property row_count_val : Int32
  property col_count_val : Int32

  def initialize(@row_count_val, @col_count_val)
  end

  def row_count : Int32
    @row_count_val
  end

  def col_count : Int32
    @col_count_val
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# Grid reconfiguration tests.
#
# When grid dimensions change (row/col count), stale pixels from the old layout
# can "shine through" in the content area if the layer backend isn't cleared.
# These tests verify that reconfiguration correctly clears the content layer.
describe "VirtualMatrix grid reconfiguration", tags: "slow" do
  # DSL rebuild path: copy_state_from preserves content_layer from old widget.
  # Without explicit clearing, old pixels persist in the reconciled buffer.
  it "clears content layer when grid dimensions change on DSL rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
    app = ReconfigDSLApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("reconfig_grid").as(CrymbleUI::VirtualMatrix)
    # ConfigurableMatrixAdapter(nrhl=2, nchl=1, rhs=2, chs=2, lrs=20, lcs=20):
    #   data_cols = chs^nchl * lcs = 2^1 * 20 = 40
    #   total_cols = nrhl + data_cols = 2 + 40 = 42
    matrix.cols.should eq 42

    # Grab content layer backend reference BEFORE rebuild.
    # The content_layer is @[Reconcile] so the same Layer + backend persist after rebuild.
    # Both configurations produce content larger than viewport, so the backend is NOT
    # replaced during rendering (same scrollbar visibility = same content area size).
    content_layer = matrix.content_layer.not_nil!
    content_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    content_backend.reset_counters

    # Reconfigure: reduce row header levels from 2 to 1
    app.nrhl = 1
    app.rebuild
    renderer.settle_rendering(app)

    # Verify grid dimensions changed (1 hdr + 40 data = 41)
    new_matrix = app.find("reconfig_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cols.should eq 41

    # Content layer must have been cleared to erase stale pixels from old layout.
    # Without the fix, copy_state_from doesn't clear the reconciled content layer,
    # so old header column pixels persist in the buffer.
    content_backend.clear_count.should be > 0
  end

  # Non-DSL path: adapter.invalidate_all! triggers flush_invalidate_all.
  # The layout cascade incidentally clears the content layer (via z-index propagation),
  # but this regression test ensures the behavior is preserved.
  it "clears content layer when adapter triggers invalidate_all! with changed dimensions" do
    adapter = MutableReconfigAdapter.new(20, 10)
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "reconfig_grid")
    app.root_widget = matrix
    app.build_tree
    renderer.settle_rendering(app)

    matrix.cols.should eq 10

    # Grab content layer backend reference
    content_layer = matrix.content_layer.not_nil!
    content_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    content_backend.reset_counters

    # Change dimensions and trigger full invalidation
    adapter.col_count_val = 8
    adapter.invalidate_all!
    renderer.settle_rendering(app)

    # Content layer must have been cleared to erase stale pixels
    content_backend.clear_count.should be > 0
  end

  # DSL rebuild path with non-zero scroll_offset: the needs_clear branch in
  # render_layer must update buffer_origin for viewport_cache layers.
  # Without this, buffer_origin stays at Vec2.zero while scroll_offset is large,
  # causing the compositor to sample the wrong region → gray band artifact.
  it "recenters buffer_origin after grid reconfiguration at non-zero scroll position", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
    app = ReconfigDSLApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("reconfig_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!

    # Scroll to a non-zero position (well beyond cache_extent=100)
    matrix.scroll_offset = CrymbleUI::Vec2.new(500.0, 300.0)
    renderer.settle_rendering(app)

    # Verify scroll position and buffer_origin are both non-zero
    content_layer.scroll_offset.x.should be > 0
    content_layer.buffer_origin.x.should be > 0
    pre_reconfig_offset = content_layer.scroll_offset

    # Reconfigure: change grid dimensions (nrhl 2→1) triggers copy_state_from
    # which resets buffer_origin to Vec2.zero and sets needs_clear=true
    app.nrhl = 1
    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("reconfig_grid").as(CrymbleUI::VirtualMatrix)
    new_layer = new_matrix.content_layer.not_nil!

    # scroll_offset should be preserved (reconcile property)
    new_layer.scroll_offset.x.should be > 0

    # CRITICAL: buffer_origin must NOT be Vec2.zero when scroll_offset is large.
    # The needs_clear branch must call quantized_buffer_origin to recenter.
    # Without the fix, buffer_origin=0 while scroll_offset≈500 → compositor
    # tries viewport_x=500 in a buffer that only extends ~cache_extent past 0.
    cache_extent = new_layer.cache_extent
    new_layer.buffer_origin.x.should be > 0,
      "buffer_origin.x should be recentered near scroll_offset, not stuck at 0"

    # buffer_origin should be within cache_extent of scroll_offset
    # (quantized_buffer_origin rounds to cache_extent grid)
    delta_x = (new_layer.scroll_offset.x - new_layer.buffer_origin.x).abs
    delta_x.should be <= cache_extent * 2,
      "buffer_origin.x should be within 2*cache_extent of scroll_offset " \
      "(got delta=#{delta_x}, cache_extent=#{cache_extent})"
  end

  # Row ruler visibility: the row ruler lives on the sticky_col_layer.
  # When nrhl=0, sticky_col_count=0 but the ruler should still be visible
  # (show_rulers=true by default). The sticky_col_layer must be created
  # whenever sticky_col_width > 0 (which includes ruler width).
  it "preserves row ruler when sticky_col_count is zero but rulers are on" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
    app = ReconfigDSLApp.new
    app.nrhl = 0
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("reconfig_grid").as(CrymbleUI::VirtualMatrix)
    matrix.sticky_col_count.should eq 0

    # The sticky_col_layer should still exist (for the ruler)
    scroll_view = matrix.content_scroll_view.not_nil!
    scroll_view.sticky_col_layer.should_not be_nil

    # The layer should have at least ruler width
    col_layer = scroll_view.sticky_col_layer.not_nil!
    col_layer.bounds.width.should be > 0
  end
end
