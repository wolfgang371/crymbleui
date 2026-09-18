require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/virtual_matrix/adapter"
require "../../../src/widgets/text_input"
require "../../../src/testing/test_renderer"

# AUTO-SIZE SHRINK AFTER AN ORDINARY EDIT.
#
# Wolfgang, 2026-09-17: "when I edit a cell, it automatically widens (correct), but if I make it
# shorter, it doesn't shorten."
#
# The widen is fit_cell_to_content, which is deliberately GROW-ONLY — one cell's measurement can
# prove a column must get wider but never that it may get narrower, since another row may still hold
# the widest value. Its sibling spec ("grows only") pins that on purpose and says where the shrink
# is supposed to happen instead: "The shrink belongs to the next structural re-measure."
#
# This asserts that the next structural re-measure actually ARRIVES after an ordinary edit. Only
# flush_invalidate_all and a zoom change arm @auto_size_pending, while embrace announces a plain
# in-place write with invalidate_cell! (core announce_write, shape.cr:524) — precisely so an edit
# does not pay for a structural rebuild. So the shrink has no trigger at all in normal editing.
class ShrinkAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
    @text = {} of Tuple(Int32, Int32) => String
  end

  def row_count : Int32; @rows; end
  def col_count : Int32; @cols; end

  def text_at(row : Int32, col : Int32) : String
    @text[{row, col}]? || "x"
  end

  def set(row : Int32, col : Int32, value : String) : Nil
    @text[{row, col}] = value
  end

  def cell_read(row : Int32, col : Int32) : String
    text_at(row, col)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: text_at(row, col))
  end
end

private def rendered(adapter)
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "shrink")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 400.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {matrix, app, renderer}
end

describe "auto-size after an ordinary cell edit" do
  it "narrows the column again when the widest value is edited shorter" do
    adapter = ShrinkAdapter.new(6, 3)
    adapter.set(0, 0, "a very considerably wider value than the rest")
    matrix, app, renderer = rendered(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    # The OBSERVABLE, not the model number: what the laid-out cell actually occupies.
    wide = matrix.active_cells[{0, 0}].bounds.width

    # Instrument check: the long value really did widen the column, so a failure below is the
    # shrink not happening rather than the widen never having happened.
    narrow_col = matrix.active_cells[{0, 1}].bounds.width
    wide.should be > narrow_col

    # The user edits that cell down to something short. This is what embrace does on a plain
    # in-place write: the live grow pass, then a PER-CELL announcement.
    adapter.set(0, 0, "x")
    matrix.fit_cell_to_content(0, 0, 12.0, 20.0, 1)
    adapter.invalidate_cell!(0, 0)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.width.should be_close(narrow_col, 1.0)
  end
end
