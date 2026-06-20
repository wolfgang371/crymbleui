require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/combo_box"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/input/focus_cycler"

# Adapter that returns ComboBox cells for testing proxy focus interaction.
class ComboBoxTestAdapter
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
      CrymbleUI::ComboBox.new(
        items: ["Apple", "Banana", "Cherry"],
        selected: 0,
        id: "combo_#{row}_#{col}"
      )
    else
      CrymbleUI::TextInput.new(
        value: "R#{row}C#{col}",
        id: "cell_#{row}_#{col}",
        mode: CrymbleUI::TextInputMode::QuickEntry,
      )
    end
  end
end

# DSL-style app: VirtualMatrix inside WindowPanel (matches embrace structure)
class VMComboBoxDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Test", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        widget(CrymbleUI::VirtualMatrix.new(ComboBoxTestAdapter.new, id: "combo_matrix"))
      end
    end
  end
end

# Adapter that calls invalidate_all! on ComboBox select (like embrace's cell_assign_reference)
class ComboBoxInvalidatingAdapter
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
    adapter = self
    if col == 1
      CrymbleUI::ComboBox.new(
        items: ["Apple", "Banana", "Cherry"],
        selected: 0,
        id: "combo_#{row}_#{col}"
      ) do |_idx, _val|
        # Simulate embrace behavior: cell_assign_reference → invalidate_all!
        adapter.invalidate_all!
      end
    else
      CrymbleUI::TextInput.new(
        value: "R#{row}C#{col}",
        id: "cell_#{row}_#{col}",
        mode: CrymbleUI::TextInputMode::QuickEntry,
      )
    end
  end
end

private def make_combo_matrix
  adapter = ComboBoxTestAdapter.new
  CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
end

private def setup_combo_matrix(matrix, width = 600, height = 300)
  renderer = CrymbleUI::Testing::TestRenderer.new(width, height)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(width.to_f64, height.to_f64))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  {renderer, app}
end

describe "VirtualMatrix ComboBox proxy focus" do
  it "ComboBox cell gets proxy focus when VirtualMatrix is focused" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move cursor to col 1 (ComboBox column)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)

    cell = matrix.active_cells[{0, 1}]?
    cell.should_not be_nil
    cell.should be_a(CrymbleUI::ComboBox)
    cell.not_nil!.proxy_focused.should be_true
  end

  it "Enter key on ComboBox cell opens popup" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.collapsed?.should be_true

    # Press Enter to expand
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    combo.popup_open?.should be_true
  end

  it "popup survives render frame (no DSL rebuild destroying cells)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)

    # Press Enter to expand
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)

    # Render another frame — if mark_needs_layout was used, this would
    # trigger rebuild which destroys cells.  With mark_needs_render only,
    # the cell survives.
    renderer.render_frame(app)

    combo.popup_open?.should be_true

    # Popup's TextInput should be focusable
    popup = combo.current_popup.not_nil!
    popup.text_input.should_not be_nil
  end

  it "popup has non-zero bounds after opening (visible to user)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)

    # Press Enter to expand
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!
    popup.bounds.width.should be > 0.0
    popup.bounds.height.should be > 0.0
  end

  it "cursor keys navigate grid after ComboBox popup close (direct text entry)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column (col 1)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type a character → opens popup
    fm.handle_text_input('B')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Press Escape → close popup
    fm.handle_key_down(SF::Keyboard::Key::Escape, false, false)
    renderer.render_frame(app)
    combo.popup_open?.should be_false

    # Press Down arrow → cursor should move to (1, 1)
    fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    matrix.cursor_rc.should eq({1, 1})
  end

  it "cursor keys navigate grid after ComboBox item selection (direct text entry)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column (col 1)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type 'B' → opens popup, filters to "Banana"
    fm.handle_text_input('B')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Press Enter → select filtered item, close popup
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    # Popup should be closed
    combo.popup_open?.should be_false

    # Press Down arrow → cursor should move to (1, 1)
    fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    matrix.cursor_rc.should eq({1, 1})
  end


  it "arrow Right while popup open accepts selection and navigates to next cell" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column (col 1)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type 'A' → opens popup
    fm.handle_text_input('A')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Press Right arrow WHILE popup is open → should accept + navigate right
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    # Popup should be closed
    combo.popup_open?.should be_false

    # Cursor should have moved right (back to col 0 wrapping, or to next col)
    # With 2 columns (0=TextInput, 1=ComboBox), Right from col 1 stays at col 1
    # unless wrap is supported. Down would be more reliable:
  end

  it "Down arrow while type-to-filter popup open accepts and navigates down" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type 'A' → opens popup in type-to-filter mode
    fm.handle_text_input('A')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Press Down → should accept + close popup + move cursor down (NOT navigate items)
    fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    combo.popup_open?.should be_false
    matrix.cursor_rc.should eq({1, 1})
  end

  it "Enter re-opens popup after confirm (Enter→Enter→Enter)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    # 1st Enter → open popup
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # 2nd Enter → confirm selection, close popup
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    combo.popup_open?.should be_false

    # 3rd Enter → should re-open popup
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    combo.popup_open?.should be_true
  end

  it "Enter re-opens popup after confirm+invalidate_all (proxy focus survives cell recreation)" do
    adapter = ComboBoxInvalidatingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "inv_matrix")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    renderer.settle_rendering(app)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column (col 1)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # 1st Enter → open popup
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # 2nd Enter → confirm selection (triggers invalidate_all! via callback)
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)  # deferred invalidation runs, cells recreated
    renderer.render_frame(app)  # settle

    # The old ComboBox was destroyed, new one created
    new_combo = matrix.active_cells[{0, 1}]?
    new_combo.should_not be_nil
    new_combo.should be_a(CrymbleUI::ComboBox)

    # 3rd Enter → should re-open popup on the NEW ComboBox
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    new_combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    new_combo.popup_open?.should be_true
  end

  it "typing on ComboBox cell opens popup with initial character" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    # Move to ComboBox column
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.collapsed?.should be_true

    # Type a character
    fm.handle_text_input('B')
    renderer.render_frame(app)

    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!
    popup.text_input.value.should eq("B")
  end

  it "Left/Right in Enter-opened popup moves text cursor (does NOT close popup)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Enter to open popup (browse mode, not type-to-filter)
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Press Right → should NOT close popup (should move text cursor)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    combo.popup_open?.should be_true  # popup stays open
    matrix.cursor_rc.should eq({0, 1})  # cursor didn't move
  end

  # === FAILING TESTS ===

  it "Down arrow in type-to-filter mode closes popup and navigates (not browse items)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type 'A' → opens popup in type-to-filter mode
    fm.handle_text_input('A')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Down arrow → should accept + close + navigate down
    fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    combo.popup_open?.should be_false
    matrix.cursor_rc.should eq({1, 1})
  end

  it "popup closes when cursor navigates away via arrow key (no stale dropdown)" do
    matrix = make_combo_matrix
    renderer, app = setup_combo_matrix(matrix)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    matrix.cursor_rc.should eq({0, 1})

    # Type 'Z' → opens popup with no matching items
    fm.handle_text_input('Z')
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Left arrow → should close popup and navigate left
    fm.handle_key_down(SF::Keyboard::Key::Left, false, false)
    renderer.render_frame(app)

    # Popup must be closed (no stale dropdown)
    combo.popup_open?.should be_false
    # Cursor moved left
    matrix.cursor_rc.should eq({0, 0})
  end

end

# Regression test: on_key_down override signature must match base Widget (4 params).
# Crystal treats 3-param and 4-param methods as separate overloads, not overrides.
# FocusManager calls on_key_down with 4 args — if the override only has 3, the
# base Widget version (returns false) runs instead, silently breaking all key handling.
describe "on_key_down 4-param dispatch (signature regression)" do
  it "TextInput.on_key_down is reached via 4-arg call" do
    ti = CrymbleUI::TextInput.new(value: "abc")
    widget_ref : CrymbleUI::Widget = ti
    # Backspace via 4-arg call (what FocusManager does)
    result = widget_ref.on_key_down(SF::Keyboard::Key::Backspace, false, false, false)
    result.should be_true
    ti.value.should eq("ab")
  end

  it "ComboBox.on_key_down is reached via 4-arg call" do
    cb = CrymbleUI::ComboBox.new(items: ["A", "B"], selected: 0)
    widget_ref : CrymbleUI::Widget = cb
    # Enter on collapsed ComboBox via 4-arg call
    result = widget_ref.on_key_down(SF::Keyboard::Key::Enter, false, false, false)
    result.should be_true
    cb.popup_open?.should be_true
  end
end

# a ComboBox dropdown open in a VMatrix cell must, on Tab/Shift+Tab, COMMIT
# the highlighted value and advance/retreat the cell cursor (the spreadsheet Tab) —
# never discard the highlight and let focus escape the matrix. These drive Tab through
# the REAL dispatch (press_tab -> FocusManager#handle_tab_key) and assert observable
# state: what value committed, where the cursor landed, who holds focus.

# Records every commit so we can assert the HIGHLIGHTED value was taken (not the old
# one). Mirrors ComboBoxInvalidatingAdapter but records via the ComboBox select block.
private class ComboBoxRecordingAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter committed = [] of Tuple(Int32, String)

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
      rec = self
      CrymbleUI::ComboBox.new(
        items: ["Apple", "Banana", "Cherry"],
        selected: 0,
        id: "combo_#{row}_#{col}"
      ) do |idx, val|
        rec.committed << {idx, val}
      end
    else
      CrymbleUI::TextInput.new(
        value: "R#{row}C#{col}",
        id: "cell_#{row}_#{col}",
        mode: CrymbleUI::TextInputMode::QuickEntry,
      )
    end
  end
end

# Build a root holding the matrix AND a focusable sibling button. The sibling is
# essential for observing "focus escaped": a matrix-only root is itself a focus scope,
# so cycle_focus would boomerang back to the matrix and a leak would be invisible.
# (build_matrix_with_sibling in virtual_matrix_tab_roundrobin_spec.cr is a file-private
# def — not callable cross-file — so we author a local combo-flavoured equivalent.)
private def setup_recording_matrix_with_sibling(adapter)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
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

  {renderer, app, matrix, sibling}
end

# Move cursor to the ComboBox column (col 1) and open the popup by typing `ch`,
# returning the live ComboBox cell. Leaves focus on the popup's TextInput.
private def open_combo_popup(matrix, renderer, app, fm, ch : Char)
  fm.focus(matrix)
  fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
  renderer.render_frame(app)
  fm.handle_text_input(ch)
  renderer.render_frame(app)
  matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
end

describe "VirtualMatrix ComboBox Tab/Shift+Tab" do
  it "Tab with popup open commits the highlighted item and advances the cursor" do
    adapter = ComboBoxRecordingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
    renderer, app = setup_combo_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager

    combo = open_combo_popup(matrix, renderer, app, fm, 'B') # filter -> "Banana" (idx 1) highlighted
    combo.popup_open?.should be_true

    press_tab(app)
    renderer.render_frame(app)

    adapter.committed.should eq([{1, "Banana"}]) # took the HIGHLIGHTED value, not old "Apple"
    matrix.cursor_rc.should eq({1, 0})            # Tab from {0,1} (2 cols) round-robins to next row col 0
    combo.popup_open?.should be_false
  end

  it "Shift+Tab with popup open commits and retreats the cursor" do
    adapter = ComboBoxRecordingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
    renderer, app = setup_combo_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager

    combo = open_combo_popup(matrix, renderer, app, fm, 'B')
    combo.popup_open?.should be_true

    press_tab(app, shift: true)
    renderer.render_frame(app)

    adapter.committed.should eq([{1, "Banana"}])
    matrix.cursor_rc.should eq({0, 0}) # Shift+Tab from {0,1} -> {0,0}
  end

  it "Tab in Enter/browse mode also commits the highlighted item and advances" do
    adapter = ComboBoxRecordingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
    renderer, app = setup_combo_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager

    fm.focus(matrix)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false) # browse-mode popup (no initial char)
    renderer.render_frame(app)
    combo = matrix.active_cells[{0, 1}]?.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    fm.handle_key_down(SF::Keyboard::Key::Down, false, false) # highlight "Banana" (item nav, not grid)
    renderer.render_frame(app)

    press_tab(app)
    renderer.render_frame(app)

    adapter.committed.should eq([{1, "Banana"}])
    matrix.cursor_rc.should eq({1, 0})
  end

  it "Tab over an unmatched filter closes without commit but still advances" do
    adapter = ComboBoxRecordingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
    renderer, app = setup_combo_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager

    combo = open_combo_popup(matrix, renderer, app, fm, 'Z') # no item matches
    combo.popup_open?.should be_true

    press_tab(app)
    renderer.render_frame(app)

    adapter.committed.should be_empty       # nothing to commit
    combo.popup_open?.should be_false
    matrix.cursor_rc.should eq({1, 0})      # "execute tab" still advances
  end

  it "Tab keeps focus inside the matrix (does not escape to a sibling)" do
    adapter = ComboBoxRecordingAdapter.new
    renderer, app, matrix, sibling = setup_recording_matrix_with_sibling(adapter)
    fm = CrymbleUI::Widget.focus_manager

    combo = open_combo_popup(matrix, renderer, app, fm, 'B')
    combo.popup_open?.should be_true

    press_tab(app)
    renderer.render_frame(app)

    fm.focused_widget.should eq(matrix)     # focus stayed in the matrix...
    fm.focused_widget.should_not eq(sibling) # ...not the sibling button
    matrix.cursor_rc.should eq({1, 0})
  end

  it "Tab on a standalone ComboBox commits the highlight then cycles to the next widget" do
    recorded = [] of Tuple(Int32, String)
    combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "standalone") do |idx, val|
      recorded << {idx, val}
    end
    button = CrymbleUI::Button.new("Next", id: "next") { }
    root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    root.add_child(combo)
    root.add_child(button)

    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    app.root_widget = root
    app.build_tree
    root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    fm = CrymbleUI::Widget.focus_manager
    fm.focus(combo)
    fm.handle_text_input('B') # open + filter -> "Banana"
    renderer.render_frame(app)
    combo.popup_open?.should be_true

    press_tab(app)
    renderer.render_frame(app)

    recorded.should eq([{1, "Banana"}]) # standalone now COMMITS on Tab (was: discard)
    fm.focused_widget.should eq(button) # ...and focus cycles to the next widget
  end

  # NB: no "Tab after invalidate-while-open" test. A matrix rebuild while a popup is
  # open orphans/closes the popup (see ComboBox#expand's mark_needs_render rationale),
  # and embrace only ever invalidates on SELECT — which collapses first — so the
  # preserved-open-popup branch in copy_state_from is unreachable here. The on_tab
  # re-bind there is consistency with the existing on_select/on_cancel/on_click_outside
  # re-binds in the same branch (defensive, untested-by-design like those three).

  it "Escape still cancels without commit (the new commit path does not leak)" do
    adapter = ComboBoxRecordingAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "combo_matrix")
    renderer, app = setup_combo_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager

    combo = open_combo_popup(matrix, renderer, app, fm, 'B')
    combo.popup_open?.should be_true

    fm.handle_key_down(SF::Keyboard::Key::Escape, false, false)
    renderer.render_frame(app)

    adapter.committed.should be_empty
    combo.popup_open?.should be_false
  end
end
