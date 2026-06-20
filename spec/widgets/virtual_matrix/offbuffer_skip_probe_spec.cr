require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# (REFUTED → kept as a regression guard): a cell dirtied (appearance change
# via mark_needs_render only) while it sits in the alive-but-off-buffer band
# [CACHE_EXTENT=100 .. DESTRUCTION_BUFFER=200] px outside the viewport is collected
# but PAINT-skipped at render_single_widget's off-buffer guard and then swept
# Clean. The audit asked whether that strands a stale cached texture. It does NOT:
# reaching such a cell requires a scroll > CACHE_EXTENT, which forces a buffer recenter
# that repaints the newly-covered region. This test pins that self-healing behaviour.

class ColorCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder
  reactive_property color : CrymbleUI::Color = CrymbleUI::Color.new(200_u8, 0_u8, 0_u8, 255_u8)

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 50.0
    h = constraints.max_height.finite? ? constraints.max_height : 24.0
    constraints.constrain(CrymbleUI::Size.new(w, h))
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), color) }
  end
end

class ColorAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    40
  end

  def col_count : Int32
    1
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    ColorCell.new
  end
end

private def has_blue?(widget : CrymbleUI::Widget) : Bool
  b = widget.widget_backend
  return false unless b.is_a?(CrymbleUI::Testing::TestRenderBackend)
  return false if b.width <= 0 || b.height <= 0
  b.get_pixels(0, 0, b.width, b.height).any? { |c| c.b > 180 && c.r < 80 }
end

describe "VirtualMatrix off-buffer dirty cell repaints fresh on scroll-in" do
  it "does not blit a stale cached texture for a cell dirtied while off-buffer" do
    matrix = CrymbleUI::VirtualMatrix.new(ColorAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 200)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # A cell alive but off-buffer: top 100..195 px below the 200px viewport bottom.
    band_rc = matrix.active_cells.keys.find { |rc| (t = matrix.active_cells[rc].bounds.y) > 300.0 && t < 395.0 }
    band_rc.should_not be_nil # the alive-but-off-buffer band must exist (else test is vacuous)
    rc = band_rc.not_nil!

    cell = matrix.active_cells[rc].as(ColorCell)
    cell.color = CrymbleUI::Color.new(0_u8, 0_u8, 220_u8, 255_u8) # appearance change → mark_needs_render
    renderer.render_frame(app) # off-buffer → paint-skipped + swept Clean

    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, rc[0] * cell.bounds.height - 50.0)
    renderer.settle_rendering(app)

    live = matrix.active_cells[rc]?
    live.should_not be_nil
    has_blue?(live.not_nil!).should be_true # fresh color, not the stale red
  end
end
