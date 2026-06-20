require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# spreadsheet Tab / Shift+Tab. A focused VirtualMatrix round-robins its
# cell cursor — Tab advances (wrapping end-of-row to the next row's column 0,
# and the very last cell back to {0,0}); Shift+Tab reverses — and NEVER moves
# keyboard focus out of the matrix.
#
# These are GUI-behaviour tests: they drive Tab through the REAL dispatch
# (press_tab -> FocusManager#handle_tab_key, the same path the SFML renderer
# uses) and assert on observable state — which widget holds focus, where the
# cursor landed, what value got committed — never on internal flags.

# Editable adapter: TextInput cells + a recording cell_assign, so we can assert
# that a pending edit is COMMITTED before Tab advances the cursor (Excel: Tab
# commits and moves on).
private class EditableTabAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assigned = [] of Tuple(Int32, Int32, String)

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @assigned << {row, col, value}
    {row, col}
  end
end

# Build a root holding the matrix AND a focusable sibling button. The sibling is
# essential: a matrix-only root is itself a focus scope, so cycle_focus has a
# single focusable (the matrix) and "focus left the matrix" would be invisible.
# With a sibling present, leaving the matrix is observable as focus moving to it.
private def build_matrix_with_sibling(rows : Int32, cols : Int32, adapter = nil)
  matrix = if adapter
             CrymbleUI::VirtualMatrix.new(adapter, id: "m")
           else
             CrymbleUI::VirtualMatrix.new(rows: rows, cols: cols, id: "m")
           end
  sibling = CrymbleUI::Button.new("Sibling", id: "sibling") { }

  root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
  root.add_child(matrix)
  root.add_child(sibling)

  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  app = TestApp.new
  app.root_widget = root
  app.build_tree
  root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)

  {app, matrix, sibling}
end

describe "VirtualMatrix Tab/Shift+Tab round-robin" do
  it "Tab advances the cursor and keeps focus inside the matrix" do
    app, matrix, _sibling = build_matrix_with_sibling(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    press_tab(app)

    matrix.cursor_rc.should eq({0, 1})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  it "Tab at end of a row wraps to the next row's first column" do
    app, matrix, _sibling = build_matrix_with_sibling(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 2} # last column of first row

    press_tab(app)

    matrix.cursor_rc.should eq({1, 0})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  it "Tab on the very last cell round-robins back to {0,0} (does not leave)" do
    app, matrix, sibling = build_matrix_with_sibling(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {2, 2} # last cell

    press_tab(app)

    matrix.cursor_rc.should eq({0, 0})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
    CrymbleUI::Widget.focus_manager.focused_widget.should_not eq(sibling)
  end

  it "Shift+Tab retreats the cursor and keeps focus inside the matrix" do
    app, matrix, _sibling = build_matrix_with_sibling(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {1, 1}

    press_tab(app, shift: true)

    matrix.cursor_rc.should eq({1, 0})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  it "Shift+Tab on the first cell round-robins back to the last cell" do
    app, matrix, _sibling = build_matrix_with_sibling(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    press_tab(app, shift: true)

    matrix.cursor_rc.should eq({2, 2})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  it "Tab commits a pending cell edit before advancing the cursor" do
    adapter = EditableTabAdapter.new(3, 3)
    app, matrix, _sibling = build_matrix_with_sibling(3, 3, adapter)
    CrymbleUI::Widget.focus_manager.focus(matrix) # on_focus -> proxy focus on {0,0}, captures value_on_focus
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.value = "EDITED" # pending edit, differs from value_on_focus "R0C0"

    press_tab(app)

    matrix.cursor_rc.should eq({0, 1})           # advanced
    adapter.assigned.should contain({0, 0, "EDITED"}) # committed first
  end

  it "Tab moves the cursor even when a cell currently holds proxy focus" do
    adapter = EditableTabAdapter.new(3, 3)
    app, matrix, _sibling = build_matrix_with_sibling(3, 3, adapter)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    # A focusable TextInput cell at the cursor holds proxy focus; Tab must still
    # reach the grid-nav branch and move the cursor (the proxy block at
    # event_handlers.cr:482 deliberately falls through for Tab).
    press_tab(app)

    matrix.cursor_rc.should eq({0, 1})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  # --- Regression guards: normal Tab focus-cycling must still work ---

  it "Tab from a non-matrix widget still cycles focus to the next widget" do
    button_a = CrymbleUI::Button.new("A", id: "a") { }
    button_b = CrymbleUI::Button.new("B", id: "b") { }
    root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    root.add_child(button_a)
    root.add_child(button_b)
    app = TestApp.new
    app.root_widget = root
    app.build_tree
    root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 200.0)), CrymbleUI::Vec2.zero)

    CrymbleUI::Widget.focus_manager.focus(button_a)
    press_tab(app)
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(button_b)

    press_tab(app, shift: true)
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(button_a)
  end

  # --- Edge guards: degenerate grids must lay out and accept Tab safely ---

  it "Tab on an empty matrix (0 rows) lays out and is a safe no-op" do
    app, matrix, _sibling = build_matrix_with_sibling(0, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)

    press_tab(app) # must not raise (modulo guard + empty-grid layout)

    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end

  it "Tab on a 1x1 matrix keeps the cursor at {0,0} without crashing" do
    app, matrix, _sibling = build_matrix_with_sibling(1, 1)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    press_tab(app)

    matrix.cursor_rc.should eq({0, 0})
    CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix)
  end
end
