require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/input/focus_cycler"

# Tests that VirtualMatrix supports TextInput cells with immediate text input
# via the proxy focus mechanism.
#
# Key behaviors:
# - TextInput cells receive text input when VirtualMatrix has focus
# - Arrow keys navigate the grid (QuickEntry mode), not the text cursor
# - Enter toggles FullEdit mode where arrows move within text
# - FocusCycler doesn't Tab into cell TextInputs (focus scope boundary)

# Adapter that returns TextInput cells in QuickEntry mode for proxy focus tests.
class TextInputTestAdapter
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
    CrymbleUI::TextInput.new(
      value: "R#{row}C#{col}",
      id: "cell_#{row}_#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry,
    )
  end
end

# Adapter with on_change callback that stores data + calls invalidate_cell!
# (reproduces the pattern used in virtual_matrix_demo.cr)
class CallbackTextInputTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  @data : Hash(Tuple(Int32, Int32), String) = {} of Tuple(Int32, Int32) => String

  def initialize(@rows : Int32, @cols : Int32)
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
    ) { |value|
      @data[{row, col}] = value
    }
  end
end

# Helper: create a matrix with TextInput cells in QuickEntry mode
private def make_ti_matrix(rows = 5, cols = 3)
  adapter = TextInputTestAdapter.new(rows, cols)
  CrymbleUI::VirtualMatrix.new(adapter, id: "ti_matrix")
end

# Helper: set up renderer/app and do initial layout+render
private def setup_ti_matrix(matrix, width = 600, height = 300)
  renderer = CrymbleUI::Testing::TestRenderer.new(width, height)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(width.to_f64, height.to_f64))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  renderer.render_frame(app)

  {renderer, app}
end

describe "VirtualMatrix TextInput proxy focus" do
  describe "text input forwarding" do
    it "TextInput cell receives typed characters when VirtualMatrix is focused" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      cell.should_not be_nil

      # Type a character — QuickEntry pending_replace replaces content
      fm.handle_text_input('X')

      cell.value.should eq "X"
    end

    it "subsequent characters append in QuickEntry after first keystroke" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)

      fm.handle_text_input('A')
      cell.value.should eq "A"

      fm.handle_text_input('B')
      cell.value.should eq "AB"
    end

    it "typing a SPACE inserts it, not wiping the cell (full keypress+text flow)" do
      # The real app delivers a space as BOTH a KeyPressed(Space) and a
      # separate TextEntered(' '). The matrix must treat Space on a
      # TextInput proxy as text, not activation — trigger_click would
      # re-focus the input and re-arm QuickEntry's replace-on-first-key,
      # wiping whatever preceded the space. Regression: "A B" became " B".
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)
      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)
      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)

      fm.handle_text_input('A')
      matrix.on_key_down(SF::Keyboard::Key::Space, false, false) # the KeyPressed
      fm.handle_text_input(' ')                                  # the TextEntered
      fm.handle_text_input('B')

      cell.value.should eq "A B"
    end

    it "characters append even when adapter callback triggers invalidate_cell!" do
      adapter = CallbackTextInputTestAdapter.new(5, 3)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ti_callback_matrix")
      renderer, app = setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      fm.handle_text_input('A')
      renderer.render_frame(app)  # flush invalidation

      fm.handle_text_input('B')
      renderer.render_frame(app)

      # The cell should show "AB", not "B"
      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      cell.value.should eq "AB"
    end
  end

  describe "grid navigation in QuickEntry mode" do
    it "arrow keys navigate grid, not text cursor" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      matrix.cursor_rc.should eq({0, 0})

      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
      matrix.cursor_rc.should eq({1, 0})

      fm.handle_key_down(SF::Keyboard::Key::Right, false, false)
      matrix.cursor_rc.should eq({1, 1})
    end

    it "typing into new cell after navigation replaces that cell's content" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)
      fm.handle_key_down(SF::Keyboard::Key::Right, false, false)

      cell_1_1 = matrix.active_cells[{1, 1}]?.as(CrymbleUI::TextInput)

      fm.handle_text_input('Z')
      cell_1_1.value.should eq "Z"
    end
  end

  describe "FullEdit mode (Enter to toggle)" do
    it "Enter switches TextInput from QuickEntry to FullEdit" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      cell.edit_mode.should eq CrymbleUI::TextInputMode::QuickEntry

      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)

      cell.edit_mode.should eq CrymbleUI::TextInputMode::FullEdit
    end

    it "arrow keys in FullEdit move text cursor, not grid" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)

      # Enter FullEdit
      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
      cell.edit_mode.should eq CrymbleUI::TextInputMode::FullEdit

      # Left arrow should move text cursor, NOT grid cursor
      old_cursor = matrix.cursor_rc
      fm.handle_key_down(SF::Keyboard::Key::Left, false, false)
      matrix.cursor_rc.should eq(old_cursor)
    end

    it "Enter in FullEdit commits and returns to QuickEntry" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
      fm.handle_text_input('X')
      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      cell.edit_mode.should eq CrymbleUI::TextInputMode::QuickEntry
    end

    it "Escape in FullEdit cancels and returns to QuickEntry" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      original_value = cell.value

      fm.handle_key_down(SF::Keyboard::Key::Enter, false, false)
      fm.handle_text_input('Z')
      cell.value.should_not eq original_value

      fm.handle_key_down(SF::Keyboard::Key::Escape, false, false)

      cell.edit_mode.should eq CrymbleUI::TextInputMode::QuickEntry
      cell.value.should eq original_value
    end
  end

  describe "proxy focus rendering" do
    it "TextInput cell reports effectively_focused? when it has proxy focus" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)

      cell.focused?.should be_false
      cell.effectively_focused?.should be_true
    end

    it "previous cell loses proxy focus when cursor moves" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      old_cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      old_cell.effectively_focused?.should be_true

      fm.handle_key_down(SF::Keyboard::Key::Down, false, false)

      old_cell.effectively_focused?.should be_false

      new_cell = matrix.active_cells[{1, 0}]?.as(CrymbleUI::TextInput)
      new_cell.effectively_focused?.should be_true
    end
  end

  describe "focus scope boundary" do
    it "FocusCycler does not collect TextInputs inside VirtualMatrix" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      cycler = CrymbleUI::FocusCycler.new
      focusables = cycler.collect_focusable_widgets(matrix)

      focusables.should contain(matrix)

      matrix.active_cells.each do |_key, widget|
        focusables.should_not contain(widget)
      end
    end
  end

  describe "on_blur cleanup" do
    it "deactivates proxy focus when VirtualMatrix loses focus" do
      matrix = make_ti_matrix
      setup_ti_matrix(matrix)

      fm = CrymbleUI::Widget.focus_manager
      fm.focus(matrix)

      cell = matrix.active_cells[{0, 0}]?.as(CrymbleUI::TextInput)
      cell.effectively_focused?.should be_true

      fm.clear_focus

      cell.effectively_focused?.should be_false
    end
  end

  describe "TextInput respects tight constraints (merged cells)" do
    it "fills tight height constraint for multi-row merged cells" do
      ti = CrymbleUI::TextInput.new(value: "Hello")
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 50.0))
      size = ti.measure(tight)

      # Must fill the full constraint height, not just natural height
      size.height.should eq 50.0
    end

    it "fills tight width constraint for multi-col merged cells" do
      ti = CrymbleUI::TextInput.new(value: "Hello")
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 50.0))
      size = ti.measure(tight)

      size.width.should eq 300.0
    end

    it "uses natural height for loose constraints" do
      ti = CrymbleUI::TextInput.new(value: "Hello")
      loose = CrymbleUI::BoxConstraints.new(
        min_width: 0.0, max_width: 400.0,
        min_height: 0.0, max_height: Float64::INFINITY
      )
      size = ti.measure(loose)

      # Natural height: font_size + padding*2 + border*2
      natural_height = ti.font_size + (4.0 * 2) + (1.0 * 2)
      size.height.should eq natural_height
    end

    it "clamps natural height to finite loose max" do
      ti = CrymbleUI::TextInput.new(value: "Hello")
      # Loose constraint with max smaller than natural height
      small_max = CrymbleUI::BoxConstraints.new(
        min_width: 0.0, max_width: 400.0,
        min_height: 0.0, max_height: 10.0
      )
      size = ti.measure(small_max)

      size.height.should eq 10.0
    end
  end

  describe "TextInput vertical text centering in tall cells" do
    # When TextInput is placed in a merged VirtualMatrix cell that is taller
    # than its natural height, the text, selection, and cursor should be
    # vertically centered within the content area — text_y = (bounds.height - font_size) / 2.
    #
    # Without centering:
    # - Row header text is top-aligned (ugly)
    # - Sticky-col compound cells don't "scroll out" — text stays visible
    #   in a tiny sliver as the cell shrinks behind the sticky row header

    it "text primitive is vertically centered when cell is taller than natural" do
      ti = CrymbleUI::TextInput.new(value: "Hello", padding: 4.0)
      # Layout at tall height (e.g., merged 2-row cell)
      tall_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 60.0))
      ti.perform_layout(tall_constraints, CrymbleUI::Vec2.zero)

      prims = ti.to_primitives(ti.bounds)
      text_prim = prims.find { |p| p.is_a?(CrymbleUI::DrawText) && p.as(CrymbleUI::DrawText).text == "Hello" }
      text_prim.should_not be_nil

      dt = text_prim.as(CrymbleUI::DrawText)
      font_size = ti.font_size
      border = 1.0  # TextInput::BORDER_WIDTH
      padding = 4.0
      content_y = border + padding       # 5.0
      content_h = 60.0 - 2 * (border + padding)  # 50.0

      # Text should be vertically centered in content area
      expected_text_y = content_y + (content_h - font_size) / 2.0
      dt.position.y.should be_close(expected_text_y, 1.0)
    end

    it "text is NOT offset when cell is at natural height (centering = no-op)" do
      ti = CrymbleUI::TextInput.new(value: "Hi", padding: 4.0)
      natural_h = ti.font_size + (4.0 * 2) + (1.0 * 2)  # font + 2*padding + 2*border
      natural_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, natural_h))
      ti.perform_layout(natural_constraints, CrymbleUI::Vec2.zero)

      prims = ti.to_primitives(ti.bounds)
      dt = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

      # At natural height, content_h ≈ font_size, so centering is ~0 offset
      content_y = 1.0 + 4.0  # border + padding = 5.0
      dt.position.y.should be_close(content_y, 1.0)
    end

    it "cursor is vertically centered to match text position" do
      ti = CrymbleUI::TextInput.new(value: "Test", padding: 4.0)
      tall_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 60.0))
      ti.perform_layout(tall_constraints, CrymbleUI::Vec2.zero)

      # Activate focus so cursor renders
      ti.activate_proxy_focus

      prims = ti.to_primitives(ti.bounds)

      # Find cursor rect (FillRect after text, with CURSOR_WIDTH=2.0 width)
      cursor_prim = prims.select { |p| p.is_a?(CrymbleUI::FillRect) }.map(&.as(CrymbleUI::FillRect))
        .find { |fr| fr.bounds.width <= 2.0 && fr.bounds.height < 60.0 }
      cursor_prim.should_not be_nil

      # Find text position for comparison
      text_prim = prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

      # Cursor Y should match text Y (both centered)
      cursor_prim.not_nil!.bounds.y.should be_close(text_prim.position.y, 1.0)
    end
  end
end

describe "VirtualMatrix cell-flash vs. caret (fresh cell / typing / full-edit)" do
  # The rule: cell-flash marks the cell while it's FRESH (just navigated to, not
  # yet typed); the caret appears the moment you START TYPING or enter full-edit.
  # Never both at once. `draws_edit_caret?` drives both (caret render + flash gate).

  it "a fresh cursor cell shows the cell-flash and NO caret" do
    matrix = make_ti_matrix
    setup_ti_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    cell = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)

    cell.draws_edit_caret?.should be_false               # no caret on a fresh cell
    matrix.cursor_cell_draws_edit_caret?.should be_false # → overlay draws the cell-flash
  end

  it "starting to type shows the caret and suppresses the cell-flash" do
    matrix = make_ti_matrix
    setup_ti_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    cell = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)

    fm.handle_text_input('X') # start typing (consumes pending_replace)
    cell.value.should eq("X")
    cell.draws_edit_caret?.should be_true               # caret appears
    matrix.cursor_cell_draws_edit_caret?.should be_true # → cell-flash suppressed
  end

  it "entering full-edit shows the caret and suppresses the cell-flash" do
    matrix = make_ti_matrix
    setup_ti_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    cell = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # enter full-edit
    cell.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    cell.draws_edit_caret?.should be_true
    matrix.cursor_cell_draws_edit_caret?.should be_true
  end

  it "leaving full-edit returns to a fresh cell (cell-flash, no caret)" do
    matrix = make_ti_matrix
    setup_ti_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # enter full-edit
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # leave full-edit
    live = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)

    live.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    live.draws_edit_caret?.should be_false               # no caret again (fresh)
    matrix.cursor_cell_draws_edit_caret?.should be_false # cell-flash back
  end
end

describe "VirtualMatrix Enter toggles full-edit (no cursor move, no dead cell)" do
  it "Enter enters full-edit; Enter again leaves it (commit) on the SAME cell, still live" do
    matrix = make_ti_matrix
    setup_ti_matrix(matrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    cell = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)

    # QuickEntry Enter → ENTER full-edit (F2-style).
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)
    cell.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)

    # Enter again → LEAVE full-edit: commit + re-arm QuickEntry on the SAME cell.
    # (Previously FullEdit+Enter dropped the proxy and left a dead cursored cell.)
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)
    matrix.cursor_rc.should eq({0, 0}) # Enter never moves the cursor
    live = matrix.active_cells[{0, 0}].as(CrymbleUI::TextInput)
    live.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    live.effectively_focused?.should be_true # live, not an un-proxied dead cell

    # Typing lands (QuickEntry replace) — proves it's not the old dead limbo.
    fm.handle_text_input('Z')
    live.value.should eq("Z")
  end
end
