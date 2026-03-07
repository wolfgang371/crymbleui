require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Adapter that returns TestVisibleCell widgets for pixel-level testing.
class VisibleCellTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("#{row},#{col}")
  end
end

# Regression test for black rows appearing after scroll in VirtualMatrix.
# Bug: After scrolling down, unrendered rows appear at the bottom of the
# visible area where newly scrolled-in cells should be.
#
# In SFML these appear as black rows. In the headless TestRenderBackend they
# appear as rows filled with the layer background color (40,40,40,255) —
# meaning the cells were not rendered into those positions.
#
# This test verifies USER-VISIBLE behavior by sampling pixels from the
# composited window buffer after scrolling. It detects contiguous bands of
# background-only rows wider than GRID_SPACING (3px), which indicates
# rendering gaps rather than normal cell spacing.

describe "VirtualMatrix black rows after scroll" do
  # Layer background color — indicates unrendered area (no cell content)
  layer_bg = CrymbleUI::Color.new(40_u8, 40_u8, 40_u8, 255_u8)
  # Window background (white) — indicates layer didn't cover area
  window_bg = CrymbleUI::Color.new(255_u8, 255_u8, 255_u8, 255_u8)

  # Max grid spacing between cells (GRID_SPACING = 3 in VirtualMatrix)
  # Any contiguous band of background-only rows wider than this is a bug.
  max_grid_gap = 3

  # NOTE: Tests previously used raw Text widgets, which are invisible to the pixel
  # scanner (TestRenderBackend skips DrawText, and Text emits no fill_rect).
  # TestVisibleCell emits fill_rect(DEFAULT_BG=45,50,55) — clearly distinguishable
  # from layer_bg(40,40,40) at every pixel within cell bounds.
  it "no rendering gaps after scrolling down" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    # 100-row matrix — enough to scroll significantly
    adapter = VisibleCellTestAdapter.new(100, 8)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "black_rows_test")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll down incrementally using on_mouse_wheel (exercises full scroll path)
    # Each step scrolls ~60px (delta.y=-2.0, SCROLL_SPEED=30)
    center = CrymbleUI::Vec2.new(200.0, 150.0)
    5.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -2.0), center)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)
    end

    # After scroll: scan rows for contiguous bands of background-only pixels.
    # Grid spacing creates 3px bands (normal). Rendering gaps create wider bands (bug).
    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    max_contiguous_gap = 0
    current_gap = 0
    (5...295).each do |y|
      next if y >= window_backend.height
      all_bg = true
      (10...390).step(20) do |x|
        next if x >= window_backend.width
        pixel = window_backend.get_pixel(x, y)
        next unless pixel
        if pixel != layer_bg && pixel != window_bg
          all_bg = false
          break
        end
      end
      if all_bg
        current_gap += 1
      else
        max_contiguous_gap = {max_contiguous_gap, current_gap}.max
        current_gap = 0
      end
    end
    max_contiguous_gap = {max_contiguous_gap, current_gap}.max

    # Grid spacing is 3px. Any contiguous gap > 3px indicates a rendering bug.
    max_contiguous_gap.should be <= max_grid_gap,
      "Found #{max_contiguous_gap}px contiguous background band after scroll (max grid spacing is #{max_grid_gap}px) — indicates rendering gap"
  end

  it "no rendering gaps after large scroll past cache extent" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = VisibleCellTestAdapter.new(1000, 8)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "black_rows_large")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll down significantly — past the viewport cache extent (100px)
    # to trigger buffer recenter
    center = CrymbleUI::Vec2.new(200.0, 150.0)
    15.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -2.0), center)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)
    end

    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    max_contiguous_gap = 0
    current_gap = 0
    (5...295).each do |y|
      next if y >= window_backend.height
      all_bg = true
      (10...390).step(20) do |x|
        next if x >= window_backend.width
        pixel = window_backend.get_pixel(x, y)
        next unless pixel
        if pixel != layer_bg && pixel != window_bg
          all_bg = false
          break
        end
      end
      if all_bg
        current_gap += 1
      else
        max_contiguous_gap = {max_contiguous_gap, current_gap}.max
        current_gap = 0
      end
    end
    max_contiguous_gap = {max_contiguous_gap, current_gap}.max

    max_contiguous_gap.should be <= max_grid_gap,
      "Found #{max_contiguous_gap}px contiguous background band after large scroll (max grid spacing is #{max_grid_gap}px) — indicates rendering gap"
  end

  it "no rendering gaps with small scroll steps (SFML-realistic delta=-1.0)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = VisibleCellTestAdapter.new(100, 8)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "black_rows_sfml")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # SFML mouse wheel sends delta.y=-1.0 (not -2.0) → 30px per step
    # With threshold=50px, each step is below threshold.
    # Bug: early-exit resets baseline, so full update never triggers.
    center = CrymbleUI::Vec2.new(200.0, 150.0)
    10.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)
    end

    window_backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    max_contiguous_gap = 0
    current_gap = 0
    (5...295).each do |y|
      next if y >= window_backend.height
      all_bg = true
      (10...390).step(20) do |x|
        next if x >= window_backend.width
        pixel = window_backend.get_pixel(x, y)
        next unless pixel
        if pixel != layer_bg && pixel != window_bg
          all_bg = false
          break
        end
      end
      if all_bg
        current_gap += 1
      else
        max_contiguous_gap = {max_contiguous_gap, current_gap}.max
        current_gap = 0
      end
    end
    max_contiguous_gap = {max_contiguous_gap, current_gap}.max

    max_contiguous_gap.should be <= max_grid_gap,
      "Found #{max_contiguous_gap}px contiguous background band with small scroll steps (max grid spacing is #{max_grid_gap}px) — indicates rendering gap"
  end
end
