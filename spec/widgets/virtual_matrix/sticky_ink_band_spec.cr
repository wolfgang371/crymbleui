require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/virtual_matrix/adapter"
require "../../../src/widgets/text_input"
require "../../../src/testing/test_renderer"

# THE BAND A CELL PLACES INK IN IS THE ONE IT LIVES IN.
#
# `update_ink_regions` tells each cell the band its ink has to stay inside, and `place_ink` holds
# the ink at the band's edge when the cell is partly outside it - that is how a half-scrolled cell
# keeps its value readable. The band it handed EVERY cell was the scrolling area, which by
# construction starts where the sticky strip ends. A pinned row lives in that strip, so it was
# declared entirely outside what can be seen, and the hold answered the only way it can: ink
# pinned to the cell's far edge.
#
# Field report 2026-09-21: a table with one record left drew its short values on the row's bottom
# edge, while the record-number column beside them stayed centred; deleting the second record was
# enough, and adding one back cured it. That grid reached it by deriving its only row as sticky
# (a one-row scroll order is [0], which reads exactly like "row 0 is pinned" - and an all-sticky
# grid is a legal, if inert, state: embrace's [Commits] view is one pinned row over an empty
# content layer). A header row pinned on purpose reaches the same place with no degenerate order
# at all, which is the second example here.
private class TallCellAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  # `order` overrides the natural row order, which is how a consumer pins a row: the sticky ones
  # go LAST (MATRIX_LAWS, "Stickiness is derived, not declared").
  def initialize(@rows : Int32, @order : Array(Int32)? = nil)
  end

  def row_count : Int32; @rows; end
  def col_count : Int32; 2; end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {@order || (0...@rows).to_a, (0...col_count).to_a}
  end

  def text_at(row : Int32, col : Int32) : String
    col == 1 ? "a\nbbb\nbbb\nbbb" : "#{row + 1}"
  end

  def cell_read(row : Int32, col : Int32) : String
    text_at(row, col)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: text_at(row, col), multiline: true)
  end
end

private def matrix_of(rows : Int32, order : Array(Int32)? = nil, height : Int32 = 500)
  renderer = CrymbleUI::Testing::TestRenderer.new(900, height)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(TallCellAdapter.new(rows, order), id: "sticky_degenerate")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 500.0)), CrymbleUI::Vec2.zero)
  matrix.auto_size = true
  renderer.settle_rendering(app)
  matrix
end

# Where the cell draws its value, relative to the cell's own top.
private def text_offset(cell : CrymbleUI::Widget) : Float64
  text = cell.to_primitives(cell.bounds).select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
  text.position.y
end

# The second door into the same wrong band, and the one that needs no degenerate order at all:
# a row that is pinned on purpose. `update_ink_regions` measured every cell against the SCROLLING
# area, which by construction starts below the sticky strip - so a pinned row's cells were
# declared entirely outside what can be seen, and the hold answered the only way it can.
describe "the band a pinned row places ink in" do
  it "centres a short cell in a tall PINNED row, the same as an unpinned one" do
    pinned = matrix_of(3, [1, 2, 0]) # row 0 pinned, two rows left to scroll under it
    plain = matrix_of(3)             # the same grid with nothing pinned

    pinned.sticky_row_count.should eq(1) # control: row 0 really is pinned here
    plain.sticky_row_count.should eq(0)  # ...and not here

    pinned_cell = pinned.active_cells[{0, 0}]
    plain_cell = plain.active_cells[{0, 0}]
    pinned_cell.bounds.height.should be_close(plain_cell.bounds.height, 0.5)

    text_offset(pinned_cell).should be_close(text_offset(plain_cell), 0.5),
      "the pinned row drew its short cell's value #{text_offset(pinned_cell).round(1)}px down a " \
      "#{pinned_cell.bounds.height.round(1)}px cell, where the unpinned row draws it at " \
      "#{text_offset(plain_cell).round(1)}px"
  end
end

describe "a one-row grid, whose only row derives as sticky" do
  it "centres a short cell's value in a tall row when that row is the only one" do
    # The field report, as the user meets it: what the cell DRAWS, not the count behind it.
    solo = matrix_of(1)
    pair = matrix_of(2)

    solo.sticky_row_count.should eq(1) # control: the only row DOES derive as pinned...
    pair.sticky_row_count.should eq(0) # ...and a second row is all it takes to stop

    solo_cell = solo.active_cells[{0, 0}]
    pair_cell = pair.active_cells[{0, 0}]
    # Control: the multi-line neighbour made row 0 the same height in both grids, so the two
    # offsets are comparable and a difference below is placement, not geometry.
    solo_cell.bounds.height.should be_close(pair_cell.bounds.height, 0.5)
    solo_cell.bounds.height.should be > 40.0 # and the row really is tall

    text_offset(solo_cell).should be_close(text_offset(pair_cell), 0.5),
      "the only row drew its short cell's value #{text_offset(solo_cell).round(1)}px down a " \
      "#{solo_cell.bounds.height.round(1)}px cell, where the same cell with a neighbouring row " \
      "draws it at #{text_offset(pair_cell).round(1)}px"
  end
end

# UC-2 ("a ruler number, a row header and a value all name the SAME line") for a PINNED row.
#
# I9 asserts UC-2 across sixty scroll positions and cannot see this: it reads `row_ruler_widget`,
# which draws the SCROLLING rows only (`sticky_rows...size`), and skips every cell in a sticky
# row. A pinned row's number comes from `corner_row_strip_widget` instead - a widget that, unlike
# every other ruler, does not sit at the matrix's origin. `draw_labels` measured its band against
# the matrix's height regardless, so the band ran past the bottom of what can be seen and the
# number was placed lower than the row's own cells: with one record left and the panel shrunk,
# the "1" sat at the panel's bottom edge while its value stayed up in the visible part
# (Wolfgang, 2026-09-21, "ruler 1 doesn't move as it should").
describe "the number of a pinned row" do
  it "sits on the line of that row's own cells, with the panel shorter than the row" do
    matrix = matrix_of(1, height: 42) # one row derives as pinned; 42px cannot show a 67px row
    matrix.sticky_row_count.should eq(1) # control: this row really is pinned

    strip = matrix.corner_row_strip_widget.not_nil!
    label = strip.to_primitives(strip.bounds)
      .select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
    label.text.should eq("1") # control: the strip really drew the number
    ruler_h = CrymbleUI::FontSizing.calculate_size(
      CrymbleUI::VirtualMatrix::RULER_LABEL_FONT_SCALE).to_f64
    mark = strip.absolute_bounds.y + label.position.y + ruler_h / 2.0

    cell = matrix.active_cells[{0, 0}]
    size = CrymbleUI::FontSizing.calculate_size(0)
    cell_h = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
    value = cell.to_primitives(cell.bounds)
      .select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
    centre = cell.absolute_bounds.y + value.position.y + cell_h / 2.0

    # The same bound and the same measure as I9: the centre of the glyphs, 1.5px for the snapping
    # difference between a cell's pixel-snapped ink and a ruler label's unsnapped ink.
    (mark - centre).abs.should be <= 1.5,
      "the pinned row's number sits at #{mark.round(1)} while its own value sits at " \
      "#{centre.round(1)} (#{(mark - centre).abs.round(1)}px apart)"
  end
end

# THE SAME NUMBER, AFTER A RESIZE - which is the state every instrument above missed.
#
# Each example so far lays the matrix out once, at its final size, and the ruler's primitives are
# computed there. A user does not do that: they shrink the panel while the grid is on screen.
# `perform_layout` marks the sticky LAYERS for re-render then, which re-renders them from the
# widgets' CACHED primitives - so the numbers keep the placement they were given at the old size,
# while the cells beside them re-place into the band that is left. Measured in Wolfgang's own
# session (2026-09-21): the strip's last recompute used band 0..366 while the cells had already
# moved on to 0..46, and the number sat ~37px below its row's value.
describe "a ruler number after the panel is resized" do
  it "follows its row's value when the matrix is made shorter" do
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(TallCellAdapter.new(1), id: "resized")
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 400.0)), CrymbleUI::Vec2.zero)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    strip = matrix.corner_row_strip_widget.not_nil!
    # THE CACHED path, which is what the renderer draws from: `to_primitives` recomputes every
    # time and so cannot show a stale cache - the whole phenomenon here.
    tall_label = strip.get_primitives(strip.bounds)
      .select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
    tall_mark = strip.absolute_bounds.y + tall_label.position.y

    # THE RESIZE: the panel shrinks under a row that is taller than what is left.
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 66.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    strip = matrix.corner_row_strip_widget.not_nil!
    label = strip.get_primitives(strip.bounds)
      .select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
    mark = strip.absolute_bounds.y + label.position.y
    ruler_h = CrymbleUI::FontSizing.calculate_size(
      CrymbleUI::VirtualMatrix::RULER_LABEL_FONT_SCALE).to_f64

    cell = matrix.active_cells[{0, 0}]
    size = CrymbleUI::FontSizing.calculate_size(0)
    cell_h = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
    value = cell.get_primitives(cell.bounds)
      .select(&.is_a?(CrymbleUI::DrawText)).first.as(CrymbleUI::DrawText)
    centre = cell.absolute_bounds.y + value.position.y + cell_h / 2.0

    mark.should_not eq(tall_mark) # control: the number had to move at all
    ((mark + ruler_h / 2.0) - centre).abs.should be <= 1.5,
      "after the panel shrank, the number sits at #{(mark + ruler_h / 2.0).round(1)} while its " \
      "row's value sits at #{centre.round(1)} (#{((mark + ruler_h / 2.0) - centre).abs.round(1)}px apart); " \
      "it was at #{tall_mark.round(1)} before the resize"
  end
end
