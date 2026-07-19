require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# Two reported edit-mode gaps (embrace user feedback, 2026-07-16), reproduced at
# the generic VirtualMatrix + TextInput level where the mechanism lives.
#
# (1) EDIT MODE STICKS ACROSS NAVIGATION. Enter character-edit mode in a cell,
#     Tab away, then Shift+Tab (or an arrow) back — the cell must land in cell-NAV
#     mode, not resurrect the previous edit session (caret + remembered cursor
#     position). Today deactivate_proxy_focus tears down the caret/blink/selection
#     but leaves @edit_mode == FullEdit, so re-activating proxy focus on the way
#     back re-blinks and re-draws the caret (activate_proxy_focus, text_input.cr:474).
#
# (2) ESCAPE LEAVES A SELECTION. In edit mode, select a few characters WITHOUT
#     changing the value, press Escape — the mode exits but the selection must clear
#     too. Today the Escape handler only clears the selection when the value actually
#     changed (the `value_changed` guard, text_input.cr:769-774), so an unmodified
#     selection survives.
#
# GUI-behaviour tests: drive Tab through the real FocusManager path (press_tab) and
# arrows/Escape through the matrix's real on_key_down routing; assert on observable
# edit state (the cursor cell's edit caret, the field's selection), never internals.

private class EditableAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

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
    {row, col}
  end
end

private def build_editable_matrix(rows : Int32, cols : Int32)
  matrix = CrymbleUI::VirtualMatrix.new(EditableAdapter.new(rows, cols), id: "m")
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
  {app, matrix}
end

describe "VirtualMatrix edit-mode lifecycle (reported gaps)" do
  it "navigating away from an edited cell and back returns to cell-nav mode (no resurrected caret)" do
    app, matrix = build_editable_matrix(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix) # proxy-focuses {0,0} in QuickEntry (cell-nav) mode
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode                                  # F2 / Enter / double-click → FullEdit, caret shown
    matrix.cursor_cell_draws_edit_caret?.should be_true   # precondition: we ARE character-editing

    press_tab(app)                                        # Tab away → cursor {0,1}
    matrix.cursor_rc.should eq({0, 1})
    press_tab(app, shift: true)                           # Shift+Tab back → cursor {0,0}
    matrix.cursor_rc.should eq({0, 0})

    # DESIRED: landing back on the cell is cell-nav, NOT a resurrected edit session.
    matrix.cursor_cell_draws_edit_caret?.should be_false
    matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      .edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
  end

  it "Escape clears a character selection even when the value was not changed" do
    app, matrix = build_editable_matrix(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode # FullEdit; cursor sits at end of "R0C0"

    # Select a couple of characters via real key input, WITHOUT editing the value.
    2.times { matrix.on_key_down(SF::Keyboard::Key::Left, false, true) } # Shift+Left ×2
    cell.has_selection?.should be_true # precondition: characters are selected
    cell.value.should eq("R0C0")       # value untouched

    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false)

    # DESIRED: Escape leaves the field with no lingering selection.
    cell.has_selection?.should be_false
  end

  it "forgets the in-field cursor position when you navigate away (fresh caret on return)" do
    app, matrix = build_editable_matrix(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode
    2.times { matrix.on_key_down(SF::Keyboard::Key::Left, false, false) } # caret to index 2 of "R0C0"
    cell.cursor_pos.should eq(2) # precondition: caret parked mid-field

    press_tab(app)              # Tab away → cursor {0,1}
    press_tab(app, shift: true) # Shift+Tab back → cursor {0,0}

    # DESIRED: the remembered mid-field position is forgotten — the caret is at the end,
    # exactly as a freshly-entered cell, so a subsequent F2/enter_edit_mode starts clean.
    matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput).cursor_pos.should eq(cell.value.size)
  end

  it "Escape undoes the value AND clears the selection together (changed-value path)" do
    app, matrix = build_editable_matrix(3, 3)
    CrymbleUI::Widget.focus_manager.focus(matrix) # captures value_on_focus == "R0C0"
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode
    cell.value = "R0C0X"                                                  # edit the value
    2.times { matrix.on_key_down(SF::Keyboard::Key::Left, false, true) }  # Shift+Left ×2: select "0X"
    cell.has_selection?.should be_true                                    # precondition
    cell.value.should eq("R0C0X")                                         # precondition: value changed

    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false)

    cell.value.should eq("R0C0")        # value undone to value_on_focus
    cell.has_selection?.should be_false # AND the selection dropped (the was_quick_entry branch)
  end

  it "Escape after typing in a QuickEntry cell returns to clean cell-nav (no stuck caret)" do
    app, matrix = build_editable_matrix(3, 3)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix) # proxy-focus {0,0}: QuickEntry, pending_replace, no caret
    matrix.cursor_rc = {0, 0}

    cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
    # Type a char in QuickEntry via the real routing (focus manager -> matrix -> proxy cell): it
    # replaces the value and clears pending_replace, so a caret now shows while the mode stays
    # QuickEntry (arrows still accept-and-move). Do NOT commit it.
    fm.handle_text_input('Z')
    cell.value.should eq("Z")                            # precondition: typed
    matrix.cursor_cell_draws_edit_caret?.should be_true  # precondition: caret is showing

    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false) # cancel

    # DESIRED: back to the clean QuickEntry resting state, not a stuck "looks-like-FullEdit" caret.
    cell.value.should eq("R0C0")                          # edit cancelled, value restored
    matrix.cursor_cell_draws_edit_caret?.should be_false  # caret gone -> clean cell-nav

    # The reported "beliebig oft Escape, bleibe ich in diesem Modus": repeated Escape stays clean.
    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false)
    matrix.cursor_cell_draws_edit_caret?.should be_false

    fm.handle_text_input('Y')                             # and genuinely re-armed:
    cell.value.should eq("Y")                             # the next char replaces the whole value again
  end
end
