require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/virtual_matrix/adapter"
require "../../../src/widgets/text_input"
require "../../../src/testing/test_renderer"

# Field report: with auto-size ON the column HEADER LABELS no longer sit over their
# columns — c3's label was left of its cells, c1's right of the green column. The ruler and the
# content disagree about the geometry, which no assertion on `bounds` alone can see.
#
# Both halves are observable headlessly: the ruler emits its labels as DrawText primitives with
# x positions in its own local space, and the cells carry laid-out bounds. With no scroll and no
# sticky columns the two frames coincide, so the label's centre must fall inside its column.

class RulerAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @texts : Array(String))
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @texts.size
  end

  def cell_read(row : Int32, col : Int32) : String
    @texts[col]
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: @texts[col])
  end
end

private def label_positions(matrix) : Hash(String, Float64)
  ruler = matrix.col_ruler_widget.not_nil!
  prims = ruler.to_primitives(ruler.bounds)
  out = {} of String => Float64
  prims.each do |p|
    if p.is_a?(CrymbleUI::DrawText)
      out[p.text] = p.position.x + CrymbleUI::Widget.measure_text(p.text, CrymbleUI::FontSizing.calculate_size(CrymbleUI::VirtualMatrix::RULER_LABEL_FONT_SCALE)).width / 2.0
    end
  end
  out
end

describe "auto-size keeps the ruler and the content in agreement" do
  before_each { CrymbleUI::Widget.font = CrymbleUI::Testing::TestFont.new }

  it "puts each column's label over that column's cells" do
    adapter = RulerAdapter.new(4, ["x", "a considerably wider value", "mid"])
    matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "ruler_align")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
    renderer.settle_rendering(app)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    labels = label_positions(matrix)
    labels.size.should be >= 3 # instrument: the ruler really did draw its labels

    (0...3).each do |col|
      cell = matrix.active_cells[{0, col}]?
      next unless cell
      centre = label_positions(matrix)["c#{col + 1}"]?
      centre.should_not be_nil
      left = cell.bounds.x
      right = cell.bounds.x + cell.bounds.width
      # The label must fall within the column it names.
      (centre.not_nil! >= left && centre.not_nil! <= right).should be_true,
        "label c#{col + 1} at #{centre} is outside its column #{left}..#{right}"
    end
  end
end
