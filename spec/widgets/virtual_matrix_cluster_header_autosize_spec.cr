require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Content widths stated outright, so these examples do not depend on a font.
private class StatedCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@content_px : Float64, @lines : Int32 = 1)
    super()
  end

  def content_width : Float64
    @content_px
  end

  def content_line_count : Int32
    @lines
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@content_px, 20.0 * @lines)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Row 0 is a cluster header: ONE cell spanning columns 1..3, with a label far wider than the
# narrow data below it. Column 0 is an ordinary column and the control.
private class ClusterHeaderAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@group_px : Float64, @data_px : Float64 = 30.0)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...8).to_a + [0], (0...4).to_a}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {0, 1}, {0, 3} } if row == 0 && col >= 1
    { {row, col}, {row, col} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return StatedCell.new(@group_px) if row == 0 && col >= 1
    StatedCell.new(@data_px)
  end
end

private def cluster_matrix(group_px : Float64)
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(ClusterHeaderAdapter.new(group_px), id: "cluster_autosize")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 400.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

# How much content a span across cols c0..c1 can actually show: the painted box is the columns it
# crosses, less the one grid_spacing the box is inset by.
private def span_content_px(matrix, c0 : Int32, c1 : Int32) : Float64
  fh = CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE * CrymbleUI::FontSizing.zoom_factor
  (c0..c1).sum { |c| matrix.grid_spacing + matrix.get_col_width(c) * fh } - matrix.grid_spacing
end

describe "VirtualMatrix cluster-header content sizing" do
  it "widens the columns a cluster header spans, so its label fits" do
    # A spanning cell used not to vote at all — it would otherwise have dumped its whole width into
    # one of the columns it covers. The consequence was that a group label was simply cut, and
    # content sizing had nothing to say about it.
    renderer, app, matrix = cluster_matrix(400.0)
    before = (1..3).map { |c| matrix.get_col_width(c) }

    matrix.auto_size = true
    renderer.settle_rendering(app)

    span_content_px(matrix, 1, 3).should be >= 400.0,
      "the cluster header still does not fit across the columns it spans"
    (1..3).each do |c|
      matrix.get_col_width(c).should be > before[c - 1],
        "column #{c} did not take its share of the header's width"
    end
  end

  it "spreads the deficit rather than dumping it on one column" do
    renderer, app, matrix = cluster_matrix(400.0)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    widths = (1..3).map { |c| matrix.get_col_width(c) }
    (widths.max - widths.min).should be < 0.5,
      "the covered columns came out uneven (#{widths.map(&.round(2))}) — the width went to one of them"
  end

  it "leaves the columns alone when the span already fits" do
    # 60px of label across three 30px columns needs nothing: a header that fits must not inflate
    # the grid.
    renderer, app, matrix = cluster_matrix(60.0)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    (1..3).each do |c|
      matrix.get_col_width(c).should be_close(31.0 / 20.0, 0.2),
        "column #{c} grew for a header that already fitted"
    end
  end

  it "does not touch a column outside the span" do
    renderer, app, matrix = cluster_matrix(400.0)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    matrix.get_col_width(0).should be_close(31.0 / 20.0, 0.2),
      "the control column was widened by a header that does not cover it"
  end
end
