require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/text_input"
require "../../../src/testing/test_renderer"
require "../../../src/rendering/layer_renderer"
require "../../../src/input/focus_cycler"

# CONFIRMATION test: after a DSL rebuild while a matrix
# cell editor holds proxy focus — with NO cursor move and NO adapter invalidation —
# @proxy_focused_widget (a bare @[Reconcile] ivar, virtual_matrix.cr:362) migrates a
# pointer to the OLD (now dead) cell, while @active_cells is recreated fresh (line
# 223). The nil-gated re-establish `if @proxy_focused_widget.nil? && focused?`
# (line 1644) is skipped because the migrated pointer is non-nil. So forwarded text
# should land in the orphaned old cell instead of the live cursor cell.
#
# This test asserts the USER-VISIBLE behaviour (typed text reaches the live cell).
# It must FAIL if the bug is real; if it passes, the finding is refuted.

private class ProxyLeakAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    5
  end

  def col_count : Int32
    3
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

# DSL-style app: build() returns a NEW VirtualMatrix instance each call, so
# app.rebuild exercises reconciliation (copy_state_from), like a real DSL app.
private class ProxyLeakApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(ProxyLeakAdapter.new, id: "m")
  end
end

# Adapter that PERSISTS edits (cell_assign → @data) and rebuilds cells from @data,
# so we can assert a pre-rebuild edit survived the rebuild (was committed).
private class RecordingAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter
  getter data = {} of Tuple(Int32, Int32) => String
  getter assigned = [] of Tuple(Int32, Int32, String)

  def row_count : Int32
    5
  end

  def col_count : Int32
    3
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: @data[{row, col}]? || "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @data[{row, col}] = value
    @assigned << {row, col, value}
    {row, col}
  end
end

# Shares ONE adapter instance across rebuilds, so persisted data survives.
private class RecordingApp < CrymbleUI::App
  getter adapter = RecordingAdapter.new

  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(adapter, id: "m")
  end
end

describe "VirtualMatrix proxy focus across rebuild" do
  it "forwards typed text to the LIVE cursor cell after a rebuild with no cursor move" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    app = ProxyLeakApp.new
    app.build_tree
    app.root.not_nil!.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}
    renderer.render_frame(app) # establishes proxy focus on the live {0,0} cell

    # Sanity: on the un-rebuilt matrix, typing reaches the live cell (control).
    pre = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    pre.should_not be_nil

    # Rebuild (NEW matrix instance) WITHOUT moving the cursor or invalidating.
    app.rebuild
    renderer.render_frame(app) # new matrix lays out + recreates @active_cells

    new_matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
    live_cell = new_matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    live_cell.should_not be_nil

    # Type into the focused matrix. QuickEntry: first keystroke replaces content.
    CrymbleUI::Widget.focus_manager.handle_text_input('X')

    # The LIVE cursor cell must receive it. With the leak, 'X' lands in the dead
    # old-tree cell and the live cell stays "R0C0".
    live_cell.value.should eq "X"
  end

  it "commits an in-flight edit when the matrix rebuilds (no cursor move)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    app = RecordingApp.new
    app.build_tree
    app.root.not_nil!.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}
    renderer.render_frame(app) # proxy on live {0,0}

    # Type into the live cell (QuickEntry replaces): value diverges from value_on_focus.
    CrymbleUI::Widget.focus_manager.handle_text_input('X')
    matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput).value.should eq "X"

    # Rebuild WITHOUT moving the cursor: the edit must be committed during reconciliation,
    # matching the other proxy-teardown paths — not silently dropped.
    app.rebuild
    renderer.render_frame(app)

    app.adapter.assigned.should contain({0, 0, "X"})
    new_matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
    new_matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput).value.should eq "X"
  end
end
