require "../spec_helper"
require "../../src/testing/driver"

# A HOST'S COMMITTED DRAG SOURCE - a cell the app marks from outside (embrace's cut, via
# `drag_source_cell=`) - survives the grid's own mouse handling: a press puts a provisional candidate
# in its place, and whatever does not end in a drop puts the committed one back. Each case names the
# mutation that turns it red.

# One grid in a panel; `configure` runs on every build, as a host's build does.
private class SourceApp < CrymbleUI::App
  def initialize(@adapter : MergeableTestAdapter, @kind : CrymbleUI::VirtualMatrix.class = CrymbleUI::VirtualMatrix,
                 &@configure : CrymbleUI::VirtualMatrix ->)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    vm = @kind.new(adapter: @adapter, id: "grid")
    @configure.call(vm)
    panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 380.0, 300.0, id: "panel")
    panel.add_child(vm)
    window.add_child(panel)
    window
  end
end

# A grid whose press requests a rebuild, as an app redrawing on a cursor move does - public, since the
# widget reconcile macro names the type.
class SourceRebuildingMatrix < CrymbleUI::VirtualMatrix
  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left) : Bool
    handled = super
    CrymbleUI::Widget.app?.not_nil!.request_rebuild
    handled
  end
end

# The press rebuilds, and every drag end is logged - to see a pending drag cancelled without one.
class DragEndLoggingMatrix < SourceRebuildingMatrix
  class_getter ends = [] of Bool

  def on_drag_end(data : CrymbleUI::DragData, dropped : Bool)
    @@ends << dropped
    super
  end
end

# A grid that takes no drop.
class RefusingMatrix < CrymbleUI::VirtualMatrix
  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    false
  end
end

# An adapter whose rows can be taken away, announced as its contract requires.
private class ShrinkingAdapter < MergeableTestAdapter
  def shrink_to(rows : Int32) : Nil
    @row_count = rows
    invalidate_all!
  end
end

# The source grid beside a second, refusing grid - a drop there reaches nothing that takes it.
private class RefusingNeighbourApp < CrymbleUI::App
  def initialize(@adapter : MergeableTestAdapter, &@configure : CrymbleUI::VirtualMatrix ->)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    vm = SourceRebuildingMatrix.new(adapter: @adapter, id: "grid")
    @configure.call(vm)
    panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 380.0, 300.0, id: "panel")
    panel.add_child(vm)
    window.add_child(panel)
    other = CrymbleUI::WindowPanel.new("Q", 400.0, 10.0, 380.0, 300.0, id: "other_panel")
    other.add_child(RefusingMatrix.new(adapter: MergeableTestAdapter.new(8, 4), id: "refuser"))
    window.add_child(other)
    window
  end
end

private def source_ui(adapter = MergeableTestAdapter.new(8, 4), kind = CrymbleUI::VirtualMatrix,
                      &configure : CrymbleUI::VirtualMatrix ->) : CrymbleUI::Testing::Driver
  CrymbleUI::Testing::Driver.new(SourceApp.new(adapter, kind, &configure), 800, 600)
end

private def source_ui(adapter = MergeableTestAdapter.new(8, 4)) : CrymbleUI::Testing::Driver
  source_ui(adapter) { }
end

private def grid(ui) : CrymbleUI::VirtualMatrix
  ui.find("grid").as(CrymbleUI::VirtualMatrix)
end

# The host marks a cell, as embrace's Ctrl+X does.
private def mark(ui, cell : {Int32, Int32}?) : Nil
  grid(ui).drag_source_cell = cell
end

# What the overlay draws: a committed source, never a provisional one.
private def marked(ui) : {Int32, Int32}?
  vm = grid(ui)
  vm.drag_source_provisional? ? nil : vm.drag_source_cell
end

# The centre of a cell on screen (brought into view first) - where real input presses it.
private def at_cell(ui, cell : {Int32, Int32}) : CrymbleUI::Vec2
  ui.focus_cell "grid", cell[0], cell[1]
  grid(ui).active_cells[cell].viewport_bounds.center
end

private BELOW = CrymbleUI::Vec2.new(0.0, 12.0) # a move past the drag threshold
private NOWHERE = CrymbleUI::Vec2.new(600.0, 500.0) # outside the panel: no drop target

describe "VirtualMatrix: a host's committed drag source" do
  # Mutation: clear the source on the release of a press that did not become a drag.
  it "survives a click on another cell" do
    ui = source_ui
    mark(ui, {1, 1})
    ui.click_cell "grid", 3, 2
    marked(ui).should eq({1, 1})
  end

  # Mutation: restore only where the press left a candidate (the old guard) - an empty cell leaves none.
  it "survives a click on an empty cell" do
    adapter = MergeableTestAdapter.new(8, 4)
    adapter.empty_cells << {3, 2}
    ui = source_ui(adapter)
    mark(ui, {1, 1})
    ui.click_cell "grid", 3, 2
    marked(ui).should eq({1, 1})
  end

  # Mutation: clear the source in on_drag_end whatever happened.
  it "survives a drag dropped nowhere" do
    ui = source_ui
    mark(ui, {1, 1})
    ui.focus_cell "grid", 3, 2
    from = grid(ui).active_cells[{3, 2}].viewport_bounds.center
    ui.renderer.simulate_drag(from.x, from.y, 600.0, 500.0) # past the panel: no drop target there
    marked(ui).should eq({1, 1})
  end

  # Mutation: restore after a drop too - the source cell moved, the old place holds another record.
  it "is gone after its own cell is dropped elsewhere" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter)
    mark(ui, {1, 1})
    ui.drag_cell "grid", 1, 1, onto: {"grid", 4, 1}
    adapter.moves.should eq([{ {1, 1}, {4, 1} }])
    marked(ui).should be_nil
  end

  # A click remembers the host's source; the host then clears it (a paste). A later press that meets
  # no left-button cell path must not put the old one back. Mutation: remember the source on left
  # presses only - the right press's release restores the stale one.
  it "does not come back after the host cleared it, on a right press" do
    ui = source_ui
    mark(ui, {1, 1})
    ui.click_cell "grid", 3, 2
    mark(ui, nil) # the host pasted: its cut is over
    vm = grid(ui)
    at = vm.active_cells[{2, 1}].viewport_bounds.center
    vm.on_mouse_down(vm.to_content(at), CrymbleUI::MouseButton::Right)
    vm.on_mouse_up(vm.to_content(at), CrymbleUI::MouseButton::Right)
    marked(ui).should be_nil
  end

  # Mutation: remember the source only where the press meets a cell - a ruler press then puts back
  # what an earlier click found.
  it "is unchanged by a press on the ruler, and not brought back by one" do
    ui = source_ui
    mark(ui, {1, 1})
    vm = grid(ui)
    at = vm.viewport_bounds.position + CrymbleUI::Vec2.new(3.0, 3.0) # the ruler corner
    vm.point_to_cell(vm.to_content(at)).should be_nil                 # instrument: no cell there
    vm.on_mouse_down(vm.to_content(at))
    vm.on_mouse_up(vm.to_content(at))
    marked(ui).should eq({1, 1})
    ui.click_cell "grid", 3, 2
    mark(ui, nil)
    vm = grid(ui)
    vm.on_mouse_down(vm.to_content(at))
    vm.on_mouse_up(vm.to_content(at))
    marked(ui).should be_nil
  end

  # Mutation: let the press's end overwrite the host's setter - its drop handler re-arms, then the drag's
  # end clears it (the drop comes first, on_drag_end after).
  it "keeps what the host sets while the press is in progress" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter) do |vm|
      vm.on_cell_drop_handler = -> { vm.drag_source_cell = {4, 1}; nil } # re-armed at the moved cell, no rebuild
    end
    mark(ui, {1, 1})
    ui.drag_cell "grid", 1, 1, onto: {"grid", 4, 1}
    marked(ui).should eq({4, 1})
  end

  # Mutation: restore on any instance - the grid built after the press never saw it, and its build
  # has just handed it the host's source.
  it "is kept when the press rebuilds the grid and the build marks it again" do
    ui = source_ui(kind: SourceRebuildingMatrix) { |vm| vm.drag_source_cell = {1, 1} }
    ui.click_cell "grid", 3, 2
    marked(ui).should eq({1, 1})
  end

  # The contract as before: without a host source, a click leaves none.
  it "is not invented by a plain click" do
    ui = source_ui
    ui.click_cell "grid", 3, 2
    marked(ui).should be_nil
    grid(ui).drag_source_cell.should be_nil
  end
end

# A DRAG ACROSS A REBUILD. The pressed grid is replaced by the rebuild its press asks for (or a later one),
# and the new instance never saw the press: the drag is the GESTURE's - DragManager takes the payload from
# the old instance before letting it go, and the new one learns it is the source through on_drag_start.
describe "VirtualMatrix: a cell drag across a rebuild" do
  # Mutations: no capture (the new grid offers nothing); start_drag reading the source, not the payload.
  it "drags the pressed cell when the press rebuilds the grid" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter, kind: SourceRebuildingMatrix) { }
    ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
    adapter.moves.should eq([{ {1, 1}, {3, 1} }])
  end

  # Mutation: capture from the NEW instance - it offers the host's mark, 5,1.
  it "drags the pressed cell, not the one the rebuilt grid's host marks" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter, kind: SourceRebuildingMatrix) { |vm| vm.drag_source_cell = {5, 1} }
    ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
    adapter.moves.should eq([{ {1, 1}, {3, 1} }])
    marked(ui).should be_nil # dropped: the source is cleared, the host re-arms if it wants
  end

  # The drag is active when a rebuild replaces the grid. Mutations: no re-announce (the mid-drag decal is
  # the host's 5,1); no adoption (nothing restored after a drop nowhere).
  it "keeps the dragged cell marked through a rebuild during the drag, and the host's after" do
    ui = source_ui { |vm| vm.drag_source_cell = {5, 1} }
    app = ui.app
    ui.focus_cell "grid", 1, 1
    from = grid(ui).active_cells[{1, 1}].viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + BELOW)
    app.drag_manager.dragging?.should be_true # instrument: the drag is active
    before = grid(ui)
    app.request_rebuild
    ui.settle
    grid(ui).same?(before).should be_false # instrument: the rebuild replaced the grid
    marked(ui).should eq({1, 1})
    app.handle_mouse_move(NOWHERE)
    app.handle_mouse_up(NOWHERE) # past the panel: dropped nowhere
    marked(ui).should eq({5, 1})
  end

  # Mutation: the rebuild keeps no payload when the pressed grid offers none - the new grid offers the host's.
  it "starts no drag from an empty cell, whatever the rebuilt grid's host marks" do
    adapter = MergeableTestAdapter.new(8, 4)
    adapter.empty_cells << {2, 1}
    ui = source_ui(adapter, kind: SourceRebuildingMatrix) { |vm| vm.drag_source_cell = {5, 1} }
    from = at_cell(ui, {2, 1})
    ui.app.handle_mouse_down(from)
    ui.app.handle_mouse_move(from + BELOW)
    ui.app.drag_manager.dragging?.should be_false
    ui.app.handle_mouse_up(from + BELOW)
    adapter.moves.should be_empty
    marked(ui).should eq({5, 1})
  end

  # A payload taken for one press outlives it only if the next press does not start afresh. Mutation:
  # begin_drag_tracking keeps the old payload.
  it "drags the next press's cell after an interrupted press" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter, kind: SourceRebuildingMatrix) { }
    ui.app.handle_mouse_down(at_cell(ui, {1, 1})) # the press rebuilds: its payload is taken
    ui.app.reset_all_caches                       # recovery drops the press; the pending drag stays
    from = at_cell(ui, {2, 1})
    to = at_cell(ui, {3, 1})
    ui.app.handle_mouse_down(from)
    ui.app.handle_mouse_move(from + BELOW)
    ui.app.handle_mouse_move(to)
    ui.app.handle_mouse_up(to)
    adapter.moves.should eq([{ {2, 1}, {3, 1} }])
  end

  # The ghost is the dragged cell's - row 5, the host's, is taller. Mutation: size the ghost before the
  # source hears on_drag_start (the replacement still names the host's cell then).
  it "sizes the ghost from the pressed cell after a rebuild" do
    adapter = MergeableTestAdapter.new(8, 4)
    adapter.custom_row_heights = [1.0, 1.0, 1.0, 1.0, 1.0, 3.0, 1.0, 1.0]
    ui = source_ui(adapter, kind: SourceRebuildingMatrix) { |vm| vm.drag_source_cell = {5, 1} }
    ui.focus_cell "grid", 5, 1
    tall = grid(ui).active_cells[{5, 1}].viewport_bounds.height
    from = at_cell(ui, {1, 1})
    cell = grid(ui).active_cells[{1, 1}].viewport_bounds
    tall.should be > cell.height * 2                  # instrument: the host's row is three rows tall
    ui.app.handle_mouse_down(from)
    ui.app.handle_mouse_move(from + BELOW)
    ghost = ui.app.drag_manager.ghost_layer.not_nil!.bounds
    ghost.height.should be < cell.height * 1.5        # row 1's pitch (a little over its inset widget)
    ghost.y.should be_close(cell.y + BELOW.y, 4.0)    # row 1's top, followed by the move
    ui.app.handle_mouse_up(NOWHERE)
  end

  # A click across the press's rebuild, through real input: the release cancels the pending drag, which
  # never started. Mutation: cancel_drag calls on_drag_end for a pending drag holding a payload.
  it "ends a click across the press's rebuild without a drag end" do
    DragEndLoggingMatrix.ends.clear
    ui = source_ui(MergeableTestAdapter.new(8, 4), kind: DragEndLoggingMatrix) { |vm| vm.drag_source_cell = {5, 1} }
    from = at_cell(ui, {1, 1})
    ui.app.handle_mouse_down(from)
    ui.app.handle_mouse_up(from)
    DragEndLoggingMatrix.ends.should be_empty
    marked(ui).should eq({5, 1})
  end

  # Mutation: get_drag_data offering a cell the adapter no longer has.
  it "starts no drag from a cell a data change took away" do
    adapter = ShrinkingAdapter.new(8, 4)
    ui = source_ui(adapter) { }
    from = at_cell(ui, {3, 1})
    ui.app.handle_mouse_down(from)
    adapter.shrink_to(2)
    ui.app.request_rebuild
    ui.settle
    ui.app.handle_mouse_move(from + BELOW)
    ui.app.drag_manager.dragging?.should be_false
    ui.app.handle_mouse_up(from + BELOW)
    adapter.moves.should be_empty
  end

  # The host sets its source while the button is held (Ctrl+X during a press): the drag carries it, and the
  # grid takes the gesture over - after the drop nothing is marked, as after any drop. Red before: the
  # setter ended the press, and the host's cell stayed marked on a moved row.
  it "clears a source the host set during the press, once that drag dropped" do
    adapter = MergeableTestAdapter.new(8, 4)
    ui = source_ui(adapter) { }
    from = at_cell(ui, {1, 1})
    to = at_cell(ui, {3, 1})
    ui.app.handle_mouse_down(from)
    grid(ui).drag_source_cell = {5, 1}
    ui.app.handle_mouse_move(from + BELOW)
    ui.app.handle_mouse_move(to)
    ui.app.handle_mouse_up(to)
    adapter.moves.should eq([{ {5, 1}, {3, 1} }])
    marked(ui).should be_nil
  end

  # Refused where it lands, the drag carried the PRESSED cell (the refusal is the drop's, not carried!'s),
  # and the host's source comes back. Mutation: no adoption - the replacement restores nothing.
  it "puts the host's source back after a drag across a rebuild is refused" do
    adapter = MergeableTestAdapter.new(8, 4)
    app = RefusingNeighbourApp.new(adapter) { |vm| vm.drag_source_cell = {5, 1} }
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    expect_raises(CrymbleUI::Testing::Driver::Refusal, /was refused/) do
      ui.drag_cell "grid", 1, 1, onto: {"refuser", 2, 1}
    end
    adapter.moves.should be_empty
    marked(ui).should eq({5, 1})
  end

  # Characterization - no mutation of this design turns it red: a root the app keeps across rebuilds
  # (its build returns the same tree) is its own replacement, and a click marks nothing.
  it "marks nothing after a click when the rebuild keeps the same grid" do
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 380.0, 300.0, id: "panel")
    panel.add_child(SourceRebuildingMatrix.new(adapter: MergeableTestAdapter.new(8, 4), id: "grid"))
    window.add_child(panel)
    app.root_widget = window
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.click_cell "grid", 3, 2
    marked(ui).should be_nil
  end
end
