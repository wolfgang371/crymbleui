require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Field report 2026-09-06 (image #44): "we have _three_ different vpositions in row 1: ruler, c1, c2".
#
# The ruler already held its number inside the visible band; nothing else did. A cell centred
# its ink in its own box, so once a tall row's centre scrolled past the top edge the cell's text went
# with it while the ruler's number stayed — two things naming the SAME row, disagreeing by tens of px.
#
# The rule is now one function (`centred_in_visible`) applied to whatever content a widget places:
# content sits centred in its region, moved the least amount needed to stay visible, and NOT moved at
# all when it is taller than the band (a value you scroll through keeps scrolling). Nothing in it asks
# what kind of cell it is — a ruler number, a row header and a value are placed alike.
class InkBandAdapter
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
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

private VIEWPORT_H = 300.0

private def ink_matrix(tall_units : Float64 = 12.0)
  adapter = InkBandAdapter.new(12, 3)
  heights = Array.new(12, 1.0)
  heights[0] = tall_units # ~243px, well over the visible band
  adapter.custom_row_heights = heights
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ink_band")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(600, VIEWPORT_H.to_i)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, VIEWPORT_H)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

# SCREEN y of the ruler's number for a row.
private def ruler_ink_y(matrix, label : String) : Float64?
  ruler = matrix.row_ruler_widget.not_nil!
  y = ruler.to_primitives(ruler.bounds).select(CrymbleUI::DrawText).find { |t| t.text == label }.try(&.position.y)
  y ? ruler.absolute_bounds.y + y : nil
end

# SCREEN y of a cell's ink. A CONTENT cell's box lives in CONTENT space (its scroll-independence is
# the viewport cache's validity condition), so the scroll is subtracted here rather than in the widget.
private def cell_ink_y(matrix, key) : Float64?
  cell = matrix.active_cells[key]?
  return nil unless cell
  y = cell.to_primitives(cell.bounds).select(CrymbleUI::DrawText).first?.try(&.position.y)
  y ? cell.absolute_bounds.y - matrix.scroll_offset.y + y : nil
end

describe "content stays inside the visible band, whatever kind of cell holds it" do
  it "puts a straddling row's cell ink at the same edge as its ruler number" do
    renderer, app, matrix = ink_matrix
    band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels

    # Scroll until row 0's centre is well past the top edge: the regime where the ruler pins.
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 160.0)
    renderer.settle_rendering(app)

    ruler_y = ruler_ink_y(matrix, "1").not_nil!
    cell_y = cell_ink_y(matrix, {0, 0}).not_nil!

    # The property from the report, not a position: #44/#45/#46 were "these two name the same
    # line and sit at different heights". Asserting a computed position instead means rewriting
    # this example every time the rule is refined, which is how it came to assert the flush
    # placement that WAS the defect in #48.
    band_hi = matrix.bounds.height
    ruler_y.should be >= band_lo - 1.0
    ruler_y.should be <= band_hi
    cell_y.should be >= band_lo - 1.0
    cell_y.should be <= band_hi
    (ruler_y - cell_y).abs.should be <= 2.8,
      "the ruler's number and the cell naming the same row sat #{(ruler_y - cell_y).abs.round(1)}px " \
      "apart (ruler #{ruler_y.round(1)}, cell #{cell_y.round(1)}); the known floor is 2.8px — " \
      "1.215px of font-scale difference plus the grid gutter"
  end

  it "agrees with the ruler for a tall row whose top is still inside the band" do
    # Images #45/#46, and the case the first example could not see: NOTHING is pinned here — the
    # row's top has not reached the band edge — yet the ruler centres its number in the VISIBLE
    # part of the row while a cell centred in the whole row sits tens of px lower. Measured at
    # ~28px in the running app. This is the at-rest half of the same rule.
    renderer, app, matrix = ink_matrix
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
    renderer.settle_rendering(app)

    ruler_y = ruler_ink_y(matrix, "1").not_nil!
    cell_y = cell_ink_y(matrix, {0, 0}).not_nil!
    # 2.8px is the KNOWN residual, spelled out so this cannot be loosened silently later:
    #   1.215px  the two draw at different font scales — RULER_LABEL_FONT_SCALE = -2 (11.57px)
    #            against a cell's scale 0 (14.0px), so their ink centres differ by half the
    #            difference even when both are placed by the same rule;
    #   1.5px    the ruler's region is the line PITCH while a cell's is its BOX (pitch minus
    #            grid_spacing) — deliberate, because using the box keeps the anchor identical
    #            either side of the band engaging, which is the continuity property.
    # Unifying the font scales is its own task; the defect THIS guards is 28px (images #45/#46),
    # so the assertion still discriminates by an order of magnitude.
    (ruler_y - cell_y).abs.should be <= 2.8,
      "ruler and cell disagree by #{(ruler_y - cell_y).round(1)}px on a tall row at rest " \
      "(ruler #{ruler_y.round(1)}, cell #{cell_y.round(1)})"
  end

  it "still lets a SHORT row's cell ink ride with its row" do
    # The control that must MOVE: only a straddling line is held. A row fully inside the band is
    # centred exactly as before, so an ordinary table does not acquire sticky text.
    renderer, app, matrix = ink_matrix
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 300.0)
    renderer.settle_rendering(app)
    first = cell_ink_y(matrix, {5, 0})
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 312.0)
    renderer.settle_rendering(app)
    second = cell_ink_y(matrix, {5, 0})
    if f = first
      if s = second
        (f - s).should be_close(12.0, 1.5),
          "a fully visible row's ink must ride with its row, not be held (moved #{(f - s).round(1)}px)"
      end
    end
  end
end
