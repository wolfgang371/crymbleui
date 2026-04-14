require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/input/focus_cycler"

# Tests that VirtualMatrix commits TextInput edits via adapter.cell_assign
# when proxy focus transitions (cursor move, blur, cell destruction).

# Adapter that tracks cell_assign calls for verification.
class CellAssignTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assign_log : Array(Tuple(Int32, Int32, String)) = [] of Tuple(Int32, Int32, String)

  def initialize(@rows : Int32, @cols : Int32)
    @data = Hash(Tuple(Int32, Int32), String).new
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(
      value: @data[{row, col}]? || "R#{row}C#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry,
    )
  end

  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @assign_log << {row, col, value}
    @data[{row, col}] = value
    {row, col}
  end
end

# Helper: create adapter + matrix + renderer
private def setup_cell_assign_matrix(rows = 5, cols = 3, width = 600, height = 300)
  adapter = CellAssignTestAdapter.new(rows, cols)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ca_matrix")

  renderer = CrymbleUI::Testing::TestRenderer.new(width, height)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(width.to_f64, height.to_f64))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  renderer.render_frame(app)

  {adapter, matrix, renderer, app}
end

describe "VirtualMatrix cell_assign" do
  describe "commit on cursor move" do
    it "calls cell_assign when cursor moves away from edited cell" do
      adapter, matrix, _renderer, _app = setup_cell_assign_matrix

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Type into cell (0,0) — QuickEntry replaces content
      fm.handle_text_input('X')
      fm.handle_text_input('Y')

      adapter.assign_log.size.should eq 0

      # Move cursor down → should commit the edit
      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)

      adapter.assign_log.size.should eq 1
      adapter.assign_log[0].should eq({0, 0, "XY"})
    end

    it "does NOT call cell_assign when value unchanged" do
      adapter, matrix, _renderer, _app = setup_cell_assign_matrix

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Don't type anything, just move cursor
      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)

      adapter.assign_log.size.should eq 0
    end

    it "does NOT call cell_assign after Escape reverts edit" do
      adapter, matrix, _renderer, _app = setup_cell_assign_matrix

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Enter FullEdit, type, then Escape to revert
      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
      fm.handle_text_input('Z')
      fm.handle_key_down(SF::Keyboard::Key::Escape, false, false)

      # Now move away — value was reverted, so no assign
      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)

      adapter.assign_log.size.should eq 0
    end
  end

  describe "commit on blur" do
    it "calls cell_assign when VirtualMatrix loses focus" do
      adapter, matrix, _renderer, _app = setup_cell_assign_matrix

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      fm.handle_text_input('A')

      fm.clear_focus

      adapter.assign_log.size.should eq 1
      adapter.assign_log[0].should eq({0, 0, "A"})
    end
  end

  describe "tracks correct cell coordinates" do
    it "assigns to the cell that was edited, not the new cursor position" do
      adapter, matrix, _renderer, _app = setup_cell_assign_matrix

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      # Navigate to (1,2)
      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
      fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
      fm.handle_key_down(SF::Keyboard::Key::Right, false, false)

      # Type
      fm.handle_text_input('Q')

      # Move away
      fm.handle_key_down(SF::Keyboard::Key::Up, false, false)

      adapter.assign_log.size.should eq 1
      adapter.assign_log[0].should eq({1, 2, "Q"})
    end
  end
end
