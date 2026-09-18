require "../spec_helper"
require "../../src/widgets/text_input"

# SHIFT + UP/DOWN MUST EXTEND THE SELECTION, AS SHIFT + LEFT/RIGHT DOES.
#
# Wolfgang, 2026-09-18: "multiline-string-selection doesn't work, i.e. holding shift and cursor
# left/right works, but not w/ cursor up/down".
#
# The horizontal handlers branch on `shift` and call start_selection_if_needed; the vertical ones
# never looked at it and called clear_selection unconditionally, so Shift+Up moved the caret a line
# AND destroyed whatever was selected — worse than doing nothing.
#
# Only FullEdit is in question. In QuickEntry a cell inside a VirtualMatrix never sees these keys at
# all (wants_arrow_keys? is false there, so the matrix keeps them for its own cursor and its own
# shift-range selection over CELLS), and that division is deliberate and left alone.
describe "TextInput vertical selection" do
  it "extends the selection upward with Shift+Up" do
    input = CrymbleUI::TextInput.new(value: "alpha\nbravo\ncharlie", multiline: true)
    input.enter_edit_mode
    input.cursor_pos = 14 # inside "charlie", third line

    input.on_key_down(SF::Keyboard::Key::Up, false, true)

    input.has_selection?.should be_true, "Shift+Up did not start a selection at all"
    range = input.selection_range.not_nil!
    range[1].should eq(14), "the anchor moved: the selection should still end where the caret began"
    range[0].should be < 14, "the caret did not travel up a line"
  end

  it "extends the selection downward with Shift+Down" do
    input = CrymbleUI::TextInput.new(value: "alpha\nbravo\ncharlie", multiline: true)
    input.enter_edit_mode
    input.cursor_pos = 2 # inside "alpha", first line

    input.on_key_down(SF::Keyboard::Key::Down, false, true)

    input.has_selection?.should be_true, "Shift+Down did not start a selection at all"
    range = input.selection_range.not_nil!
    range[0].should eq(2)
    range[1].should be > 2
  end

  it "grows the selection across two lines, not just the last one" do
    # The anchor must survive a second press — this is what makes it a SELECTION rather than a
    # caret that happens to leave a one-line trail.
    input = CrymbleUI::TextInput.new(value: "alpha\nbravo\ncharlie", multiline: true)
    input.enter_edit_mode
    input.cursor_pos = 14

    input.on_key_down(SF::Keyboard::Key::Up, false, true)
    one = input.selection_range.not_nil!
    input.on_key_down(SF::Keyboard::Key::Up, false, true)
    two = input.selection_range.not_nil!

    two[1].should eq(one[1]), "the anchor moved between presses"
    two[0].should be < one[0], "the second Shift+Up did not extend the selection further"
  end

  it "still CLEARS the selection when Up/Down is pressed without shift" do
    # The other half of the contract, and the behaviour that was there before: a plain arrow is a
    # move, and a move drops the selection.
    input = CrymbleUI::TextInput.new(value: "alpha\nbravo\ncharlie", multiline: true)
    input.enter_edit_mode
    input.cursor_pos = 14
    input.on_key_down(SF::Keyboard::Key::Up, false, true)
    input.has_selection?.should be_true

    input.on_key_down(SF::Keyboard::Key::Up, false, false)

    input.has_selection?.should be_false, "a plain Up left the selection standing"
  end
end
