require "../spec_helper"
require "../../src/testing/driver"

# INPUT NEVER REACHES A GRID WHOSE CELLS ARE ABOUT TO BE REPLACED - covered or not.
#
# A grid's invalidate_all! announces structural work (its cells are rebuilt) and raises the input
# barrier: the events queued behind it wait for the frame that applies it. That frame lowers the barrier
# - but the work ran inside the grid's pre_render_flush, and occlusion culling skipped it for a grid
# fully covered by another panel. So the barrier came down with the work still pending, and the next
# keystroke met a grid with no cell editor to type into: the character was lost, and reported.
# The frame that lowers the barrier now applies that work for every grid, painted or not
# (App#finish_frame); culling skips painting only. Each case names the mutation that turns it red.

private K = CrymbleUI::Testing::Keys

# Editable cells: each a TextInput showing its value. Counts what the grid asks of it, and keeps the
# widget it painted last for each cell - to tell a rebuilt cell from the one it replaced.
private class EditGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter calls = [] of String
  getter painted = {} of {Int32, Int32} => CrymbleUI::Widget
  @values = {} of {Int32, Int32} => String

  def row_count : Int32
    6
  end

  def col_count : Int32
    3
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    @calls << "cell_paint"
    @painted[{row, col}] = CrymbleUI::TextInput.new(value: @values[{row, col}]? || "#{row},#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_read(row : Int32, col : Int32) : String
    @calls << "cell_read"
    @values[{row, col}]? || "#{row},#{col}"
  end

  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @values[{row, col}] = value
    {row, col}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    @calls << "get_sizes"
    {Array.new(row_count, DEFAULT_ROW_HEIGHT), Array.new(col_count, DEFAULT_COLUMN_WIDTH)}
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    @calls << "get_scrollorder"
    {(0...row_count).to_a, (0...col_count).to_a}
  end
end

# A grid that counts the flushes App#finish_frame asks of it - public: the reconcile macro names the type.
class CoveredCountingGrid < CrymbleUI::VirtualMatrix
  class_property flushes = 0

  def flush_before_input : Bool
    CoveredCountingGrid.flushes += 1
    super
  end
end

# Requests a blocking rebuild from inside its flush; records that it was flushed.
private class RebuildRequestingWidget < CrymbleUI::Widget
  getter? flushed = false

  def initialize(@app : CrymbleUI::App)
    super(id: "requester")
  end

  def flush_before_input : Bool
    @flushed = true
    @app.request_rebuild
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(1, 1)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(1, 1))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Raises from its flush.
private class RaisingFlushWidget < CrymbleUI::Widget
  def initialize
    super(id: "raising")
  end

  def flush_before_input : Bool
    raise "flush failed"
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(1, 1)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(1, 1))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A back panel holding the grid, and a front panel `cover` moves over the grid's content, leaving the
# back panel's title bar exposed.
private class CoveredGridApp < CrymbleUI::App
  getter adapter : EditGridAdapter

  def initialize(@kind : CrymbleUI::VirtualMatrix.class = CrymbleUI::VirtualMatrix, @auto_size = false)
    super()
    @adapter = EditGridAdapter.new
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    back = CrymbleUI::WindowPanel.new("Back", 20.0, 20.0, 380.0, 300.0, id: "back")
    vm = @kind.new(adapter: @adapter, id: "grid")
    vm.auto_size = true if @auto_size
    back.add_child(vm)
    front = CrymbleUI::WindowPanel.new("Front", 420.0, 20.0, 360.0, 300.0, id: "front")
    front.add_child(CrymbleUI::Text.new("front"))
    window.add_child(back)
    window.add_child(front)
    window
  end
end

private def grid(ui) : CrymbleUI::VirtualMatrix
  ui.find("grid").as(CrymbleUI::VirtualMatrix)
end

# The front panel over the back grid's content, the back panel's title bar left free.
private def cover(ui) : Nil
  back = ui.find("back").viewport_bounds
  front = ui.find("front").as(CrymbleUI::WindowPanel)
  front.x = back.x - 10.0
  front.y = back.y + 30.0
  front.width = back.width + 20.0
  front.height = back.height
  front.bring_to_front
  ui.settle
end

# One frame whose counters describe that frame (TestRenderer never resets them).
private def frame(ui) : Nil
  CrymbleUI::LayerRenderer.reset_frame_counters
  ui.renderer.render_frame(ui.app)
end

private def grid_content_rendered? : Bool
  CrymbleUI::LayerRenderer.rendered_layer_ids.includes?("matrix_content_grid")
end

private def cell_editor(ui, cell) : CrymbleUI::TextInput
  grid(ui).active_cells[cell].as(CrymbleUI::TextInput)
end

# The covered grid, focused on {2, 1}, with its cells announced as rebuilt and one culled frame run.
private def covered_and_announced(app) : CrymbleUI::Testing::Driver
  ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
  ui.focus_cell "grid", 2, 1
  cover(ui)
  app.adapter.invalidate_all!
  frame(ui)
  ui
end

describe "input to a grid another panel covers" do
  # Red before the fix: the runtime_assert in VirtualMatrix#handle_text_input. Mutation: an empty
  # App#finish_frame.
  it "reaches the cell editor after the grid's cells were rebuilt behind the cover" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.focus_cell "grid", 2, 1
    cover(ui)
    CrymbleUI::Widget.app?.should be(app) # instrument: the announce reaches this app's barrier

    app.adapter.invalidate_all!
    app.input_waits_for_frame?.should be_true # instrument: the announce raised the barrier
    frame(ui)
    grid_content_rendered?.should be_false # instrument: the covered content was culled

    ui.keys(K.typed("x"))
    cell_editor(ui, {2, 1}).value.should eq("x")
  end

  # The field case, in one batch of real events - no frame between the clicks and the typing: a press
  # on the back panel's title brings it to front, a click on the cell, the text. Mutation: an empty
  # finish_frame.
  it "takes a click on the uncovered title, a click on the cell and typing, all in one batch" do
    app = CoveredGridApp.new
    ui = covered_and_announced(app)
    title = ui.find("back").viewport_bounds
    cell = grid(ui).active_cells[{2, 1}].viewport_bounds.center
    ui.renderer.deliver(app, K.click_at(title.x.to_i + 60, title.y.to_i + 8) +
                             K.click_at(cell.x.to_i, cell.y.to_i) + K.typed("y"))
    cell_editor(ui, {2, 1}).value.should eq("y")
  end

  # A rebuild replaces the grid that announced; the one now in the tree inherited the work and must be
  # the one flushed. Mutation: no registration in copy_state_from.
  it "flushes the grid a rebuild put in place of the one that announced" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.focus_cell "grid", 2, 1
    cover(ui)
    before = grid(ui)
    app.adapter.invalidate_all!
    app.request_rebuild
    frame(ui)
    grid(ui).should_not be(before) # instrument: the rebuild replaced the grid
    grid(ui).input_flush_pending?.should be_false
    ui.keys(K.typed("z"))
    cell_editor(ui, {2, 1}).value.should eq("z")
  end

  # A scroll through the grid's scroll view while covered defers its cell update. Mutation: leave
  # flush_scroll out of flush_before_input.
  it "applies a scroll made while covered before the next input" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.focus_cell "grid", 2, 1
    cover(ui)
    grid(ui).content_scroll_view.not_nil!.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 12.0))
    grid(ui).input_flush_pending?.should be_true # instrument: the deferred path was taken
    frame(ui)
    grid(ui).input_flush_pending?.should be_false
  end

  # A per-cell invalidation of the cell being edited: the text must land in the widget painted after it,
  # not the one it replaced. Mutation: on_cell does not register.
  it "types into the cell widget a per-cell invalidation put in place, while covered" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.focus_cell "grid", 2, 1
    cover(ui)
    replaced = cell_editor(ui, {2, 1})
    app.adapter.invalidate_cell!(2, 1)
    frame(ui)
    ui.keys(K.typed("w"))
    fresh = cell_editor(ui, {2, 1})
    fresh.should_not be(replaced)
    fresh.should be(app.adapter.painted[{2, 1}])
    fresh.value.should eq("w")
  end

  # The sweep: whatever kept a grid from painting, after a frame no grid in the tree holds work while
  # the barrier is down.
  # (A closed panel and a panel shrunk to its title bar were tried as further cases: both still paint
  # their grid headless, so they are not cases of this. Covered and rebuilt-away are.)
  it "leaves no grid with pending work once the barrier is down - covered, or rebuilt away" do
    {:covered, :rebuilt}.each do |how|
      app = CoveredGridApp.new
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      ui.focus_cell "grid", 2, 1
      cover(ui) if how == :covered
      app.adapter.invalidate_all!
      app.request_rebuild if how == :rebuilt
      frame(ui)
      app.input_waits_for_frame?.should be_false
      grid(ui).input_flush_pending?.should be_false, "#{how}: work left behind the lowered barrier"
    end
  end

  # Guard, green before the fix: idle frames ask nothing of the grid; one registration costs exactly one
  # flush, and the frame after it is not skipped. Mutations: walk the tree calling flush_before_input;
  # carry registrations forward.
  it "costs nothing on idle frames, and one flush per registration" do
    app = CoveredGridApp.new(kind: CoveredCountingGrid)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    cover(ui)
    CoveredCountingGrid.flushes = 0
    app.adapter.calls.clear
    5.times { frame(ui) }
    CoveredCountingGrid.flushes.should eq(0)
    app.adapter.calls.should be_empty # no cell_read / cell_paint / get_scrollorder on idle frames

    app.adapter.invalidate_all!
    frame(ui)
    CoveredCountingGrid.flushes.should eq(1)
    ui.renderer.loop_would_render?(app).should be_true # not idle after it (the stamp-then-flush order is tripwire (j)'s)
    5.times { frame(ui) }
    CoveredCountingGrid.flushes.should eq(1)
  end

  # Guard, green before the fix: a grid that PAINTS keeps today's order - the change-animation scan
  # (cell_read) before the invalidation re-reads the sizes (get_sizes). Mutation: run the registry
  # flush before the frame renders.
  it "keeps the change scan before the invalidation on a grid that paints" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    app.adapter.calls.clear
    app.adapter.invalidate_all!
    frame(ui)
    calls = app.adapter.calls
    first_sizes = calls.index("get_sizes").should_not be_nil
    calls[0...first_sizes].should contain("cell_read")
  end

  # Mutation: drop the flag guards - finish_frame would rebuild a painted grid's cells a second time.
  it "does the work once for a grid that painted" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    visible = grid(ui).active_cells.size
    app.adapter.calls.clear
    app.adapter.invalidate_all!
    frame(ui)
    app.adapter.calls.count("cell_paint").should eq(visible)
  end

  # Fifty announces while covered: nothing piles up, and nothing stays registered. Mutation: carry
  # registrations forward.
  it "keeps its state bounded under repeated announces while covered" do
    app = CoveredGridApp.new(kind: CoveredCountingGrid)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    cover(ui)
    cells = grid(ui).active_cells.size
    children = grid(ui).children.size
    50.times do
      app.adapter.invalidate_all!
      ui.settle
      frame(ui)
    end
    grid(ui).active_cells.size.should eq(cells)
    grid(ui).children.size.should eq(children)
    CoveredCountingGrid.flushes = 0
    3.times { frame(ui) }
    CoveredCountingGrid.flushes.should eq(0) # nothing left registered
  end

  # A flush may raise the barrier again (a rebuild requested from inside it): that stands for the next
  # batch. Mutation: lower the barrier after the flushes instead of at the frame's start.
  it "keeps a barrier a flush raised for the next batch" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    requester = RebuildRequestingWidget.new(app)
    app.root.not_nil!.add_child(requester)
    app.register_input_flush(requester)
    frame(ui)
    requester.flushed?.should be_true
    app.input_waits_for_frame?.should be_true
  end

  # Registered, then out of the tree by the frame: skipped, and forgotten - put in the tree afterwards, it
  # is not flushed by a later frame. Mutation: flush without the in-tree check; carry it forward.
  it "skips a registered widget that is not in the tree, and forgets it" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    orphan = RebuildRequestingWidget.new(app)
    app.register_input_flush(orphan)
    frame(ui)
    orphan.flushed?.should be_false
    app.root.not_nil!.add_child(orphan)
    frame(ui)
    orphan.flushed?.should be_false
  end

  # A flush that raises: the flushes after it still run, and the failure comes out of the headless
  # frame (SFMLRenderer reports it instead - tripwire (j)). Mutations: stop at the raising flush;
  # swallow the failure.
  it "runs the other flushes when one raises, then raises it" do
    app = CoveredGridApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    failing = RaisingFlushWidget.new
    requester = RebuildRequestingWidget.new(app)
    app.root.not_nil!.add_child(failing)
    app.root.not_nil!.add_child(requester)
    app.register_input_flush(failing)
    app.register_input_flush(requester)
    expect_raises(Exception, "flush failed") { frame(ui) }
    requester.flushed?.should be_true
  end

  # With content sizing on, the first uncovered frame re-measures and rebuilds the cells: the typed value
  # must survive it. Mutation: an empty finish_frame.
  it "keeps what was typed through the first uncovered frame when the grid sizes its content" do
    app = CoveredGridApp.new(auto_size: true)
    ui = covered_and_announced(app)
    ui.keys(K.typed("v") + K.tap(SF::Keyboard::Key::Enter))
    ui.find("front").as(CrymbleUI::WindowPanel).x = 500.0 # uncover
    ui.settle
    cell_editor(ui, {2, 1}).value.should eq("v")
  end
end
