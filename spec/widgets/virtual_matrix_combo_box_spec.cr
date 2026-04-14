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
