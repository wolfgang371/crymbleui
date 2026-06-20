require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# the matrix carries no cell-op vocabulary anymore (CellAction /
# on_key_action are gone). Cut/paste/delete are owned by the app, registered as
# cursor shortcuts. The matrix's only job for those keys is ROUTING: a
# proxy-focused editor gets first shot, and what it declines bubbles to the
# app's ShortcutManager.
#
#   QuickEntry cell + Ctrl+X -> editor declines (gated)   -> matrix bubbles (false)
#   FullEdit   cell + Ctrl+X -> editor cuts the selection -> matrix consumes (true)
#
private class RoutingAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32); end

  def row_count : Int32; @rows; end

  def col_count : Int32; @cols; end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

private def setup_routing_matrix
  matrix = CrymbleUI::VirtualMatrix.new(RoutingAdapter.new(5, 3), id: "routing_matrix")
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  matrix
end

describe "VirtualMatrix cell-key routing" do
  it "Ctrl+X on a QuickEntry cell is not consumed — it bubbles to the app" do
    matrix = setup_routing_matrix
    CrymbleUI::Widget.focus_manager.focus(matrix)

    # The gated TextInput declines Ctrl+X in QuickEntry, so the matrix returns
    # false and the app's cell-cut shortcut gets it.
    matrix.on_key_down(SF::Keyboard::Key::X, true, false).should be_false
  end

  it "Ctrl+X on a FullEdit cell is consumed — the editor cuts the selection" do
    matrix = setup_routing_matrix
    CrymbleUI::Widget.focus_manager.focus(matrix)

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode # -> FullEdit
    cell.on_key_down(SF::Keyboard::Key::Home, false, false)
    4.times { cell.on_key_down(SF::Keyboard::Key::Right, false, true) } # select "R0C0"
    cell.has_selection?.should be_true

    matrix.on_key_down(SF::Keyboard::Key::X, true, false).should be_true
    cell.value.should eq("") # text-level cut, not a cell op
  end
end
