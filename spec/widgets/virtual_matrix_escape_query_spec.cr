require "../spec_helper"
require "../../src/testing/driver"

# WILL THE FOCUSED WIDGET USE THIS ESCAPE? A host handles Escape before the focused widget (App#handle_escape
# runs first), so a host that means to act on Escape (embrace ends a pending cell cut) asks the focused
# widget first: Widget#consumes_escape?. A grid answers for its cell editor; an open list has taken the focus
# into its own filter field, which answers for itself. Each case names the mutation that turns it red.

private K = CrymbleUI::Testing::Keys

# Column 0: text cells; 1: combos; 2: multi-combos; 3: checkboxes.
private class EditorKindsAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    4
  end

  def col_count : Int32
    4
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    case col
    when 0 then CrymbleUI::TextInput.new(value: "v#{row}", mode: CrymbleUI::TextInputMode::QuickEntry)
    when 1 then CrymbleUI::ComboBox.new(items: ["a", "b"]) { }
    when 2 then CrymbleUI::MultiComboBox.new(items: ["a", "b"], selected: Set(Int32).new) { }
    else        CrymbleUI::Checkbox.new("", checked: false) { }
    end
  end
end

private class EditorGridApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    panel = CrymbleUI::WindowPanel.new("P", 20.0, 20.0, 600.0, 300.0, id: "panel")
    panel.add_child(CrymbleUI::VirtualMatrix.new(adapter: EditorKindsAdapter.new, id: "grid"))
    window.add_child(panel)
    window
  end
end

private def editor_ui : CrymbleUI::Testing::Driver
  CrymbleUI::Testing::Driver.new(EditorGridApp.new, 800, 600)
end

private def grid(ui) : CrymbleUI::VirtualMatrix
  ui.find("grid").as(CrymbleUI::VirtualMatrix)
end

# What a host asks.
private def focused_consumes_escape? : Bool
  CrymbleUI::Widget.focus_manager.focused_widget.try(&.consumes_escape?) || false
end

describe "Widget#consumes_escape? - will the focused widget use this Escape?" do
  # Mutation: invert the parked test in TextInput#consumes_escape?.
  it "is false on a parked text cell, true once typing began, false again after Escape re-parks it" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 0
    focused_consumes_escape?.should be_false
    ui.keys(K.typed("x")) # typed in QuickEntry, not committed
    focused_consumes_escape?.should be_true
    ui.press("Escape", on: "grid")
    focused_consumes_escape?.should be_false
  end

  # Mutation: invert the parked test (full edit clears the pending replace, so it must read as editing).
  it "is true in full edit, opened with Enter and nothing typed" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 0
    ui.press("Enter", on: "grid")
    focused_consumes_escape?.should be_true
  end

  # Mutation: VirtualMatrix answering false (not forwarding to its cell editor).
  it "answers for the grid from its cell editor" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 0
    ui.keys(K.typed("x"))
    CrymbleUI::Widget.focus_manager.focused_widget.should be(grid(ui)) # instrument: the grid has the focus
    grid(ui).consumes_escape?.should be_true
  end

  # The list is opened with ComboBox#expand, the call its key and click handlers make. Mutation: drop
  # TextInput's answer - the list's filter field is one.
  it "is true while a combo cell's list is open (its filter field has the focus), false while closed" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 1
    focused_consumes_escape?.should be_false
    grid(ui).active_cells[{1, 1}].as(CrymbleUI::ComboBox).expand
    focused_consumes_escape?.should be_true
  end

  # Mutation: as for the combo.
  it "is true while a multi-combo cell's list is open" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 2
    focused_consumes_escape?.should be_false
    grid(ui).active_cells[{1, 2}].as(CrymbleUI::MultiComboBox).expand
    focused_consumes_escape?.should be_true
  end

  # Mutation: Widget#consumes_escape? true by default.
  it "is false on a cell whose widget is no editor, and on a grid with no cell editor" do
    ui = editor_ui
    ui.focus_cell "grid", 1, 3
    focused_consumes_escape?.should be_false
    CrymbleUI::VirtualMatrix.new(adapter: EditorKindsAdapter.new, id: "loose").consumes_escape?.should be_false
  end
end
