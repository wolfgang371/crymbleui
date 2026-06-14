require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/combo_box"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/input/focus_cycler"

# Reproduction: leaving a ComboBox cell with cursor-Up also leaves the VirtualMatrix.
#
# When a ComboBox cell's dropdown is open in type-to-filter mode, Up/Down are
# intercepted (combo_box.cr expand(): popup.text_input.on_vertical_arrow) to commit
# the highlight and re-dispatch the arrow to the grid (move the cell cursor). That
# part works. BUT TextInput returns FALSE for a consumed arrow ("false-on-consume",
# on the assumption that handle_key_down's return is discarded), while the real
# input path (sfml_renderer.cr) treats a false return as "unhandled" and then calls
# FocusManager#navigate(direction) — a SPATIAL focus move that carries focus OUT of
# the matrix to whatever focusable sits in that direction (in embrace: the section
# above the data grid). So cursor-Up escapes the matrix entirely.
#
# This test asserts the correct behaviour (focus stays in the matrix) and therefore
# FAILS until fixed. It mirrors the real dispatch (handle_key_down, then
# navigate-on-false) because the headless framework's bare handle_key_down omits the
# navigate step and so cannot observe the leak.

class ComboArrowAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32 = 3, @cols : Int32 = 2)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if col == 1
      CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "combo_#{row}_#{col}")
    else
      CrymbleUI::TextInput.new(value: "R#{row}C#{col}", id: "cell_#{row}_#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
    end
  end
end

# Matrix with a focusable sibling ABOVE it (like embrace's data grid, which sits
# below other focusable panel sections) so an upward focus escape is observable.
private def setup_with_sibling_above
  adapter = ComboArrowAdapter.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
  sibling = CrymbleUI::Button.new("Above", id: "above") { }
  root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
  root.add_child(sibling)
  root.add_child(matrix)
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  app = TestApp.new
  app.root_widget = root
  app.build_tree
  root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  {renderer, app, matrix, sibling}
end

# Mirror sfml_renderer.cr key dispatch: send to focus manager; if NOT handled,
# do a spatial focus navigate in the arrow's direction.
private def press_arrow(fm, app, renderer, key : SF::Keyboard::Key, dir : Symbol)
  handled = fm.handle_key_down(key, false, false)
  if !handled && (root = app.root)
    fm.navigate(dir, root)
  end
  renderer.render_frame(app)
end

describe "ComboBox cell: cursor-Up must not escape the VirtualMatrix" do
  it "type-to-filter popup, Up commits + moves the cell cursor but keeps focus in the matrix" do
    renderer, app, matrix, sibling = setup_with_sibling_above
    fm = CrymbleUI::Widget.focus_manager

    # Put the cursor on a ComboBox cell in row 1 (so Up has a cell above to land on),
    # then open the dropdown by typing (type-to-filter mode).
    fm.focus(matrix)
    fm.handle_key_down(SF::Keyboard::Key::Down, false, false)  # -> row 1
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false) # -> col 1 (ComboBox)
    renderer.render_frame(app)
    fm.handle_text_input('B') # open popup filtered to "Banana"
    renderer.render_frame(app)
    matrix.active_cells[{1, 1}]?.as(CrymbleUI::ComboBox).popup_open?.should be_true

    # Leave the ComboBox upward.
    press_arrow(fm, app, renderer, SF::Keyboard::Key::Up, :up)

    # Focus must remain inside the matrix (moving the cell cursor up), NOT escape
    # to the focusable sitting above the grid.
    fm.focused_widget.should_not eq(sibling)
    fm.focused_widget.should eq(matrix)
  end
end
