require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/testing/keys"

# A keystroke is destroyed when it arrives in the same POLL BATCH as the commit that precedes it.
#
# Reported from the field (embrace, 2026-07-29): "enter a value, cursor down, repeat quickly — keys
# get lost". Present in the shipped build, load-dependent — clean when typing slowly, clean with one
# panel, lossy with ten. A live trace of the real app settled it:
#
#   received=16  accepted=8  REFUSED=8  NO_FOCUS=0
#   batch#1     -> accepted (8 of 8)
#   batch#2..#4 -> REFUSED  (8 of 8), every one while a rebuild was pending
#
# Batch members were 0.7-1.5 ms apart: not typing, but events QUEUED while a frame was in flight and
# delivered together once polling resumed. The run loop drains every queued event BEFORE it rebuilds:
#
#     while event = window.poll_event ; handle_event(event, app) ; end
#     ...
#     if app.needs_rebuild? -> app.rebuild
#
# So: the character is accepted; the cursor-down commits, and the adapter announces the change with
# invalidate_all! as the MatrixAdapter contract requires; that tears every cell out and nils
# @proxy_focused_widget; and the NEXT character of the same batch reaches on_text_input with no proxy
# and no rebuild yet, hits `return false`, and ceases to exist. Nothing above is embrace-specific —
# any adapter that honours the invalidation contract reproduces it, which is why this spec needs no
# application, no persistence layer and no pivot.
#
# TWO PLAUSIBLE MECHANISMS DIED ON THE WAY HERE; recorded so they are not retried:
#   * "reconcile clears focus" — it does not: focus sits on the VirtualMatrix, which is reconciled,
#     and transfer_focus carries it to the new instance.
#   * "the proxy is nil between the rebuild and the next layout" — that gap cannot receive an event,
#     because the loop polls at the TOP of an iteration and rebuild+layout are adjacent.
# The real window is earlier than both: between the commit's invalidation and the rebuild it queues.
#
# First fixed inside the matrix (text re-derived the proxy past the pending invalidation), which left
# navigation reading the stale row count. Now the announce raises the app's input barrier and the
# queued events wait for the frame that flushes it (EventBatch) - one rule for text, keys and any
# widget. The examples deliver the events the way the run loop batches them (TestRenderer#deliver).
private class CommitInvalidatingAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assigned = [] of Tuple(Int32, Int32, String)

  def initialize(@rows : Int32, @cols : Int32); end

  def row_count : Int32; @rows; end

  def col_count : Int32; @cols; end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  # The contract an editable adapter is REQUIRED to follow: announce the change. embrace does exactly
  # this on every cell commit (its version gate fires invalidate_all! on every open Shape), and it is
  # what empties the matrix's proxy mid-batch.
  def cell_assign(row : Int32, col : Int32, value : String)
    @assigned << {row, col, value}
    invalidate_all!
  end
end

private def setup_matrix
  matrix = CrymbleUI::VirtualMatrix.new(CommitInvalidatingAdapter.new(5, 3), id: "batch_matrix")
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  matrix
end

# An adapter whose commit GROWS the grid, as appending a record does: the next key queued behind
# the commit navigates by the matrix's row count, which a pending invalidation has not re-read yet.
private class GrowingAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assigned = [] of Tuple(Int32, Int32, String)

  def initialize(@rows : Int32, @cols : Int32); end

  def row_count : Int32; @rows; end

  def col_count : Int32; @cols; end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_assign(row : Int32, col : Int32, value : String)
    @assigned << {row, col, value}
    @rows += 1
    invalidate_all!
    {row, col}
  end
end

private def deliver_to(adapter) : {CrymbleUI::VirtualMatrix, CrymbleUI::Testing::TestRenderer, TestApp}
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "batch_matrix")
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  CrymbleUI::Widget.focus_manager.focus(matrix)
  {matrix, renderer, app}
end

private alias Keys = CrymbleUI::Testing::Keys

describe "VirtualMatrix text input arriving in one poll batch" do
  # All queued at once, as the run loop receives it when events pile up behind a slow frame.
  it "keeps a character typed after the commit in the same batch" do
    adapter = CommitInvalidatingAdapter.new(5, 3)
    matrix, renderer, app = deliver_to(adapter)
    renderer.deliver(app, Keys.typed("a") + Keys.tap(SF::Keyboard::Key::Down) + # commits -> invalidates
                          Keys.typed("b") + Keys.tap(SF::Keyboard::Key::Down))   # <- 'b' was destroyed

    adapter.assigned.should eq([{0, 0, "a"}, {1, 0, "b"}])
  end

  # The same window, for navigation: the queued Down read the row count from before the commit grew
  # the grid and stayed on the last old row, so the next value went over the one above it.
  it "navigates into a row that a commit earlier in the batch added" do
    adapter = GrowingAdapter.new(3, 3)
    matrix, renderer, app = deliver_to(adapter)
    matrix.set_cursor_from_cell({2, 0})
    renderer.deliver(app, Keys.typed("a") + Keys.tap(SF::Keyboard::Key::Tab) + # commit grows to 4 rows
                          Keys.tap(SF::Keyboard::Key::Down) +                  # into the new row 3
                          Keys.typed("b") + Keys.tap(SF::Keyboard::Key::Tab))

    adapter.assigned.should eq([{2, 0, "a"}, {3, 1, "b"}])
  end

  # CONTROL, and a record of what is NOT broken: give the matrix the frame the loop always runs
  # between iterations, and the character lands. Kept so the narrow batch case above is not mistaken
  # for "text input is broken".
  it "keeps a character typed after the commit has been serviced" do
    matrix = setup_matrix
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    app = TestApp.new
    app.root_widget = matrix
    CrymbleUI::Widget.focus_manager.focus(matrix)

    matrix.on_text_input('a').should be_true
    matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app) # the frame that re-derives the proxy
    matrix.on_text_input('b').should be_true
  end
end
