require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# Authoring a hard line break: Alt+Enter (Excel) and Ctrl+Enter (Calc), opt-in per instance.
#
# The assertions run at the COMMIT SEAM — the value the adapter is handed through
# `commit_proxy_edit` — not on the editor's own `value` field. A break inserted without the
# accompanying state changes still shows up in `value` and is then lost on commit, so an
# `input.value` assertion would pass on a broken implementation.
#
# The state every grid cell rests in is PARKED QuickEntry: focused, `pending_replace` still
# true, no caret drawn, and the next typed character REPLACES the whole value. Inserting a
# break there without first opening full edit destroys the cell — the user presses Alt+Enter,
# sees a blank-looking cell, types the second line, and loses both the break and the original
# value. So the chord opens full edit first, which is what every other editing key in the
# widget already does.

class MultilineCellAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assigned = [] of {Int32, Int32, String}
  property multiline : Bool = true

  def initialize(@seed : String = "Alice")
  end

  def row_count : Int32
    5
  end

  def col_count : Int32
    3
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: @seed, mode: CrymbleUI::TextInputMode::QuickEntry,
      multiline: @multiline)
  end

  def cell_assign(row : Int32, col : Int32, value : String)
    @assigned << {row, col, value}
    {row, col}
  end
end

private def multiline_matrix(seed = "Alice", multiline = true)
  adapter = MultilineCellAdapter.new(seed)
  adapter.multiline = multiline
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ml")
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  matrix.set_cursor_from_cell({1, 2})
  {matrix, adapter}
end

describe "TextInput multi-line authoring" do
  it "Alt+Enter on a PARKED cell breaks the line and keeps the existing value" do
    matrix, adapter = multiline_matrix

    # Parked: focused, nothing typed yet. This is where a naive insert loses the value.
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false, true)
    matrix.on_text_input('B')
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Alice\nB"})
  end

  it "Ctrl+Enter authors the same break, because Calc users press that one" do
    matrix, adapter = multiline_matrix

    matrix.on_key_down(SF::Keyboard::Key::Enter, true, false)
    matrix.on_text_input('B')
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Alice\nB"})
  end

  it "Shift+Enter authors the same break — the browser/editor convention" do
    matrix, adapter = multiline_matrix

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, true)
    matrix.on_text_input('B')
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Alice\nB"})
  end

  it "breaks AT the caret when already in full edit, not at the end" do
    # D7's rule is scoped to the parked transition. Applied unconditionally it would jump to
    # the end whenever the user is already editing mid-value — silently breaking mid-string
    # authoring, which the parked example above cannot see.
    matrix, adapter = multiline_matrix
    cell = matrix.active_cells[{1, 2}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode
    cell.on_key_down(SF::Keyboard::Key::Home, false, false)
    2.times { cell.on_key_down(SF::Keyboard::Key::Right, false, false) } # caret after "Al"

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false, true)
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Al\nice"})
  end

  it "breaks at the END when parked, even if a previous session left the caret mid-string" do
    # `copy_state_from` carries `cursor_pos` from the previous occupant of a widget path, and
    # Escape only resets it when the value CHANGED — so a parked cell can hold a stale
    # mid-string caret. Without pinning the caret on the parked transition, Alt+Enter on
    # "Alice" could produce "Al\nice" when the user expects a second line.
    matrix, adapter = multiline_matrix
    cell = matrix.active_cells[{1, 2}]?.as(CrymbleUI::TextInput)
    cell.enter_edit_mode                                                 # F2 into full edit
    cell.on_key_down(SF::Keyboard::Key::Home, false, false)
    2.times { cell.on_key_down(SF::Keyboard::Key::Right, false, false) } # caret after "Al"
    cell.on_key_down(SF::Keyboard::Key::Escape, false, false)            # value unchanged -> re-parks, caret STAYS
    cell.pending_replace.should be_true                                  # genuinely parked again

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false, true)
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Alice\n"})
  end

  it "leaves plain Enter committing and leaving the cell" do
    matrix, adapter = multiline_matrix
    matrix.on_text_input('Z')
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    adapter.assigned.should contain({1, 2, "Z"})
    matrix.cursor_cell_draws_edit_caret?.should be_false
  end

  it "does nothing of the sort in a NON-multiline instance" do
    matrix, adapter = multiline_matrix(multiline: false)

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false, true)
    matrix.on_text_input('B')
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    # Today's behaviour exactly: the chord is not an editing key, so the parked cell F2s and
    # the typed character is inserted — no break anywhere.
    adapter.assigned.any? { |a| a[2].includes?('\n') }.should be_false
  end
end

describe "TextInput multi-line paste" do
  it "keeps interior breaks and strips only the TRAILING terminator" do
    input = CrymbleUI::TextInput.new(value: "", multiline: true)
    CrymbleUI::Widget.clipboard.text = "a\nb\n"
    input.request_focus
    input.on_key_down(SF::Keyboard::Key::V, true, false)

    # The trailing break is a row terminator, not content. A LEADING blank line is content —
    # stripping both ends, as the single-line path does, would silently delete it.
    input.value.should eq("a\nb")
  end

  it "keeps a leading blank line" do
    input = CrymbleUI::TextInput.new(value: "", multiline: true)
    CrymbleUI::Widget.clipboard.text = "\na"
    input.request_focus
    input.on_key_down(SF::Keyboard::Key::V, true, false)

    input.value.should eq("\na")
  end

  it "still flattens to spaces in a single-line instance" do
    input = CrymbleUI::TextInput.new(value: "")
    CrymbleUI::Widget.clipboard.text = "a\nb"
    input.request_focus
    input.on_key_down(SF::Keyboard::Key::V, true, false)

    input.value.should eq("a b")
  end

  it "maps TAB to a space even when multi-line — it is the TSV field separator" do
    input = CrymbleUI::TextInput.new(value: "", multiline: true)
    CrymbleUI::Widget.clipboard.text = "a\tb"
    input.request_focus
    input.on_key_down(SF::Keyboard::Key::V, true, false)

    input.value.should eq("a b")
  end
end

# FullEdit only. In QuickEntry the matrix owns the arrows (cell navigation), which is the
# commonest motion in the app — `wants_arrow_keys?` is what keeps these two apart.
private def editing(value : String)
  input = CrymbleUI::TextInput.new(value: value, multiline: true)
  input.request_focus
  input.enter_edit_mode
  input
end

describe "TextInput multi-line navigation" do
  it "Down moves to the same column on the next line" do
    input = editing("abcd\nefgh")
    input.on_key_down(SF::Keyboard::Key::Home, true, false) # Ctrl+Home: the VALUE start
    2.times { input.on_key_down(SF::Keyboard::Key::Right, false, false) } # column 2 of line 0
    input.on_key_down(SF::Keyboard::Key::Down, false, false)
    input.cursor_pos.should eq(7) # "abcd\n" is 5, + column 2
  end

  it "remembers the column it is aiming for across a SHORT line" do
    # Without a goal column the caret collapses to the short line's end and never recovers —
    # the dishonesty line navigation exists to remove, and it only shows up on the SECOND
    # move, which is why one Down is not enough to catch it.
    input = editing("abcdef\nxy\nabcdef")
    input.on_key_down(SF::Keyboard::Key::Home, true, false)               # Ctrl+Home: the VALUE start
    5.times { input.on_key_down(SF::Keyboard::Key::Right, false, false) } # column 5
    input.on_key_down(SF::Keyboard::Key::Down, false, false)
    input.cursor_pos.should eq(9) # clamped to the end of "xy"
    input.on_key_down(SF::Keyboard::Key::Down, false, false)
    input.cursor_pos.should eq(15) # back to column 5 of the third line, not column 2
  end

  it "ends the vertical run on any horizontal move" do
    input = editing("abcdef\nxy\nabcdef")
    input.on_key_down(SF::Keyboard::Key::Home, true, false) # Ctrl+Home: the VALUE start
    5.times { input.on_key_down(SF::Keyboard::Key::Right, false, false) }
    input.on_key_down(SF::Keyboard::Key::Down, false, false) # clamped into "xy"
    input.on_key_down(SF::Keyboard::Key::Left, false, false) # run ends here
    input.on_key_down(SF::Keyboard::Key::Down, false, false)
    input.cursor_pos.should eq(11) # column 1, the column the caret actually holds now
  end

  it "clamps the POSITION at the block edges, and still consumes the key" do
    # Clamping the LINE instead would make both no-ops for a single-line value — silently
    # changing every rename and save-as dialog, where nothing asserts the caret.
    input = editing("ab\ncd")
    input.on_key_down(SF::Keyboard::Key::Home, false, false)
    input.on_key_down(SF::Keyboard::Key::Up, false, false).should be_true
    input.cursor_pos.should eq(0)
    input.on_key_down(SF::Keyboard::Key::End, false, false)
    input.on_key_down(SF::Keyboard::Key::Down, false, false).should be_true
    input.cursor_pos.should eq(5)
  end

  it "Home and End work on the LINE, Ctrl+Home and Ctrl+End on the whole value" do
    input = editing("abc\ndef")
    input.on_key_down(SF::Keyboard::Key::Down, false, false)
    input.on_key_down(SF::Keyboard::Key::Home, false, false)
    input.cursor_pos.should eq(4)
    input.on_key_down(SF::Keyboard::Key::End, false, false)
    input.cursor_pos.should eq(7)
    input.on_key_down(SF::Keyboard::Key::Home, true, false)
    input.cursor_pos.should eq(0)
    input.on_key_down(SF::Keyboard::Key::End, true, false)
    input.cursor_pos.should eq(7)
  end

  it "leaves a SINGLE-line value's Up/Down and Home/End exactly as they were" do
    input = editing("hello")
    input.on_key_down(SF::Keyboard::Key::Up, false, false).should be_true
    input.cursor_pos.should eq(0)
    input.on_key_down(SF::Keyboard::Key::Down, false, false).should be_true
    input.cursor_pos.should eq(5)
    input.on_key_down(SF::Keyboard::Key::Home, false, false)
    input.cursor_pos.should eq(0)
  end

  it "declines Home/End while PARKED so the grid's own Home reaches the matrix" do
    parked = CrymbleUI::TextInput.new(value: "abc", mode: CrymbleUI::TextInputMode::QuickEntry,
      multiline: true)
    parked.request_focus # QuickEntry focus arms pending_replace
    parked.pending_replace.should be_true

    parked.on_key_down(SF::Keyboard::Key::Home, false, false).should be_false
    parked.on_key_down(SF::Keyboard::Key::End, true, false).should be_false
  end
end
