require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# A cell with a content width it states outright, so these examples do not depend on a font.
private class StatedWidthCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@content_px : Float64)
    super()
  end

  def content_width : Float64
    @content_px
  end

  def content_line_count : Int32
    1
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@content_px, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# One sticky column (col 0 scrolls out last), whose content is WIDER than the default width.
private class PinnedWidthAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@pinned_content_px : Float64)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...12).to_a + [0], (1...6).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    StatedWidthCell.new(col == 0 ? @pinned_content_px : 40.0)
  end
end

private def pinned_matrix(content_px : Float64, viewport_w = 800.0)
  renderer = CrymbleUI::Testing::TestRenderer.new(viewport_w.to_i, 400)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(PinnedWidthAdapter.new(content_px), id: "pinned_autosize")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_w, 400.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

# Content sizing used to be SHRINK-ONLY on pinned lines, which made a too-narrow row-header column
# a dead end: the mode would not widen it, and while the mode is on the drag is refused too, so the
# label stayed cut with no way out (field report, 2026-09-13: "I cannot resize c1 and c2 if
# auto-size is active"). A pinned line may now grow to its content, bounded so that the pinned
# strip can never swallow the viewport — which is the thing shrink-only was protecting.
describe "VirtualMatrix pinned column content sizing" do
  it "grows a pinned column to its content instead of leaving the label cut" do
    renderer, app, matrix = pinned_matrix(150.0)
    before = matrix.get_col_width(0)
    matrix.sticky_col_count.should be > 0 # instrument: col 0 really is pinned here

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(0).should be > before,
      "the pinned column stayed at its old width, so its content is still cut"
    # 150px of content, at frame height 20 and one grid spacing of box inset.
    matrix.get_col_width(0).should be_close(151.0 / 20.0, 0.2)
  end

  it "still shrinks a pinned column whose content is narrow" do
    renderer, app, matrix = pinned_matrix(30.0)
    before = matrix.get_col_width(0)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    matrix.get_col_width(0).should be < before, "a pinned column must still compact to its content"
  end

  it "never lets the pinned strip swallow the viewport" do
    # The invariant shrink-only existed to protect: a pinned line does not scroll, so content
    # pushed past the viewport by a pinned column is unreachable by any gesture.
    viewport = 800.0
    renderer, app, matrix = pinned_matrix(5000.0, viewport)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    strip = matrix.sticky_col_width_pixels
    grid = viewport - matrix.ruler_col_width_pixels
    strip.should be < grid,
      "the pinned strip (#{strip.round(1)}px) fills the whole grid (#{grid.round(1)}px): nothing else is reachable"
    strip.should be <= grid * 0.5 + 1.0,
      "a pinned column took more than half the grid (#{strip.round(1)}px of #{grid.round(1)}px)"
  end
end
