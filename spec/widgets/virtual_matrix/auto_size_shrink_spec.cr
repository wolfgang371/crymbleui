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

# THE SAME ON THE ROW AXIS, which Wolfgang asked for explicitly when he proposed remembering the
# runner-up: "also do this for row heights". A row made tall by a multi-line cell must fall back
# when that cell loses its lines, and must NOT fall back while another cell still needs the height.
private class TallAdapter
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
    CrymbleUI::TextInput.new(value: text_at(row, col), multiline: true)
  end
end

private def rendered_tall(adapter)
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 600)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "tall")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 600.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {matrix, app, renderer}
end

describe "auto-size row height after an ordinary cell edit" do
  it "shortens the row again when the cell that made it tall loses its lines" do
    adapter = TallAdapter.new(5, 3)
    adapter.set(0, 0, "one\ntwo\nthree\nfour\nfive")
    matrix, app, renderer = rendered_tall(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    tall = matrix.active_cells[{0, 0}].bounds.height
    plain = matrix.active_cells[{1, 0}].bounds.height
    # Instrument check: the multi-line value really did make row 0 taller than a single-line row.
    tall.should be > plain

    # The user deletes the extra lines. THE ADAPTER IS NOT UPDATED, deliberately and faithfully:
    # the live hook fires on every keystroke, long before the edit is committed, so the adapter
    # still reports the OLD value. Updating it first (as an earlier version of this spec did)
    # models a committed write and hides the bug this exists for.
    matrix.fit_cell_to_content(0, 0, 30.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.height.should be_close(plain, 1.0),
      "the row stayed #{matrix.active_cells[{0, 0}].bounds.height.round(1)}px tall after its only " \
      "multi-line cell became one line (a single-line row is #{plain.round(1)}px)"
  end

  it "keeps the row tall while ANOTHER cell in it still has the lines" do
    adapter = TallAdapter.new(5, 3)
    adapter.set(0, 0, "one\ntwo\nthree\nfour\nfive")
    adapter.set(0, 1, "a\nb\nc\nd\ne")
    matrix, app, renderer = rendered_tall(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    tall = matrix.active_cells[{0, 0}].bounds.height

    matrix.fit_cell_to_content(0, 0, 30.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.height.should be_close(tall, 1.0),
      "column 1 of this row still holds five lines, so the row must not have shortened"
  end
end

# THE SHRINK HAS TO SURVIVE A REBUILD.
#
# Wolfgang, 2026-09-21: "switch on auto-size, click 1/c2, 'enter', 'a', 'a' -> widens; BS ->
# shortens; 'Enter' to leave; same again: 'enter', 'a' -> widens; BS -> now does _not_ shorten!"
# - and the same for row heights, and for the revert on Escape.
#
# Everything above this line exercises ONE matrix instance. Committing an edit in embrace rebuilds
# the tree: the DSL builds a FRESH VirtualMatrix and reconciliation carries the old one's state
# into it. The carry takes the sizes and then cancels the re-measure as redundant - correct, and
# the whole point of carrying them. What it did not take was the pass-1 EXTENTS those sizes came
# from, so the new instance held every column's width and no record of the runner-up that lets it
# narrow one, and fit_cell_to_content fell back to its grow-only branch for the rest of that
# instance's life. One commit was enough to lose the shrink for the session.
private class RebuildingMatrixApp < CrymbleUI::App
  def initialize(@adapter : CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter, @matrix_id : String)
    super()
  end

  # A new widget per build, as a DSL consumer does - reconciliation then adopts the old one's
  # state. Setting the mode HERE is faithful too (embrace.cr:1180 assigns it on the fresh widget),
  # and it is what makes the carry's `@auto_size_explicit` branch the one under test.
  def build : CrymbleUI::Widget
    matrix = CrymbleUI::VirtualMatrix.new(@adapter, id: @matrix_id)
    matrix.auto_size = true
    matrix
  end
end

private def live_matrix(app, id) : CrymbleUI::VirtualMatrix
  app.find(id).not_nil!.as(CrymbleUI::VirtualMatrix)
end

private def rebuilding(adapter, id, w, h)
  renderer = CrymbleUI::Testing::TestRenderer.new(w, h)
  app = RebuildingMatrixApp.new(adapter, id)
  app.build_tree
  live_matrix(app, id).layout(
    CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(w.to_f, h.to_f)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {app, renderer}
end

describe "auto-size shrink after a rebuild" do
  it "narrows the column on an edit made after a rebuild, not only before one" do
    adapter = ShrinkAdapter.new(6, 3)
    adapter.set(0, 0, "a very considerably wider value than the rest")
    app, renderer = rebuilding(adapter, "rebuilt_cols", 900, 400)

    before = live_matrix(app, "rebuilt_cols")
    wide = before.active_cells[{0, 0}].bounds.width
    narrow_col = before.active_cells[{0, 1}].bounds.width
    wide.should be > narrow_col # instrument check: the long value really did widen the column

    app.request_rebuild
    renderer.settle_rendering(app)
    matrix = live_matrix(app, "rebuilt_cols")
    matrix.should_not be(before)                                    # control: widget replaced
    matrix.active_cells[{0, 0}].bounds.width.should be_close(wide, 1.0) # and its sizes carried

    # The same edit as the sibling example above, now on the far side of the rebuild.
    adapter.set(0, 0, "x")
    matrix.fit_cell_to_content(0, 0, 12.0, 20.0, 1)
    adapter.invalidate_cell!(0, 0)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.width.should be_close(narrow_col, 1.0),
      "the column stayed #{matrix.active_cells[{0, 0}].bounds.width.round(1)}px wide after its " \
      "widest value became \"x\" (a short column is #{narrow_col.round(1)}px) - the rebuild " \
      "carried the width without the measurement behind it"
  end

  it "shortens the row on an edit made after a rebuild, not only before one" do
    adapter = TallAdapter.new(5, 3)
    adapter.set(0, 0, "one\ntwo\nthree\nfour\nfive")
    app, renderer = rebuilding(adapter, "rebuilt_rows", 900, 600)

    before = live_matrix(app, "rebuilt_rows")
    tall = before.active_cells[{0, 0}].bounds.height
    plain = before.active_cells[{1, 0}].bounds.height
    tall.should be > plain # instrument check: the multi-line value really did make row 0 taller

    app.request_rebuild
    renderer.settle_rendering(app)
    matrix = live_matrix(app, "rebuilt_rows")
    matrix.should_not be(before)
    matrix.active_cells[{0, 0}].bounds.height.should be_close(tall, 1.0)

    matrix.fit_cell_to_content(0, 0, 30.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.height.should be_close(plain, 1.0),
      "the row stayed #{matrix.active_cells[{0, 0}].bounds.height.round(1)}px tall after its only " \
      "multi-line cell became one line (a single-line row is #{plain.round(1)}px)"
  end
end
