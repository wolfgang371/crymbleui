require "../spec_helper"
require "../../src/widgets/text_input"

# Test widget container for navigation testing
class EditModeTestContainer < CrymbleUI::Widget
  def initialize(id : String? = nil)
    super(id: id)
    @bounds = CrymbleUI::Rect.new(0.0, 0.0, 500.0, 500.0)
  end

  def add_test_child(child : CrymbleUI::Widget)
    add_child(child)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(500.0, 500.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 500.0, 500.0)
  end
end

describe CrymbleUI::TextInput do
  describe "TextInputMode enum" do
    it "has QuickEntry mode" do
      CrymbleUI::TextInputMode::QuickEntry.should be_a(CrymbleUI::TextInputMode)
    end

    it "has FullEdit mode" do
      CrymbleUI::TextInputMode::FullEdit.should be_a(CrymbleUI::TextInputMode)
    end
  end

  describe "#edit_mode" do
    it "defaults to FullEdit mode" do
      input = CrymbleUI::TextInput.new(value: "test")
      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    end

    it "can be created in QuickEntry mode" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    end

    it "can be set to FullEdit mode" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.enter_edit_mode
      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    end
  end

  describe "#wants_arrow_keys?" do
    it "returns false in QuickEntry mode" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.wants_arrow_keys?.should be_false
    end

    it "returns true in FullEdit mode" do
      input = CrymbleUI::TextInput.new(value: "test")
      input.wants_arrow_keys?.should be_true
    end
  end

  describe "QuickEntry mode behavior" do
    it "typing first character replaces entire content" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      # Simulate getting focus
      input.on_focus

      # First character typed should replace content
      input.on_text_input('x')

      input.value.should eq("x")
    end

    it "subsequent typing appends to content" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_text_input('a')  # Replaces with "a"
      input.on_text_input('b')  # Appends to "ab"

      input.value.should eq("ab")
    end

    it "pending_replace resets on focus" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_text_input('x')
      input.on_blur

      # Re-focus should reset pending_replace
      input.on_focus
      input.on_text_input('y')

      input.value.should eq("y")  # Replaced again
    end

    it "arrow keys do not consume input (allow focus navigation)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus

      # In QuickEntry mode, arrow keys should NOT be consumed
      # Return false = not handled = let FocusManager navigate
      result = input.on_key_down(SF::Keyboard::Key::Left, control: false, shift: false)
      result.should be_false

      result = input.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      result.should be_false
    end

    it "up/down arrow keys do not consume input" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus

      result = input.on_key_down(SF::Keyboard::Key::Up, control: false, shift: false)
      result.should be_false

      result = input.on_key_down(SF::Keyboard::Key::Down, control: false, shift: false)
      result.should be_false
    end

    it "Enter key switches to FullEdit mode" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus

      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)

      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    end

    it "Escape on a focused QuickEntry input cancels to the clean type-to-replace state (stays focused, no caret)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.request_focus     # actually focused
      input.on_text_input('x') # type -> pending_replace cleared, caret would show
      input.draws_edit_caret?.should be_true # precondition: caret showing

      input.on_key_down(SF::Keyboard::Key::Escape, control: false, shift: false)

      # A quick-entry input's resting state is type-to-replace: Escape returns to it and STAYS
      # focused (it does NOT blur), caret gone, value restored.
      input.focused?.should be_true
      input.draws_edit_caret?.should be_false
      input.pending_replace.should be_true
      input.value.should eq("hello")
    end
  end

  describe "FullEdit mode behavior" do
    it "arrow keys move cursor (consume input)" do
      input = CrymbleUI::TextInput.new(value: "hello")
      input.on_focus
      input.enter_edit_mode

      # Arrow keys should be consumed and move cursor
      result = input.on_key_down(SF::Keyboard::Key::Left, control: false, shift: false)
      result.should be_true

      result = input.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      result.should be_true
    end

    it "typing inserts at cursor (does not replace)" do
      input = CrymbleUI::TextInput.new(value: "hello")
      input.on_focus
      input.enter_edit_mode

      # Move cursor to position 2
      input.on_key_down(SF::Keyboard::Key::Home, control: false, shift: false)
      input.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      input.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)

      input.on_text_input('X')

      input.value.should eq("heXllo")
    end

    it "Enter key in FullEdit mode fires submit (stays in FullEdit if default)" do
      input = CrymbleUI::TextInput.new(value: "hello")  # FullEdit is default
      input.on_focus
      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)

      submitted = false
      input.on_event = ->(val : String, ev : CrymbleUI::TextInputEvent) { submitted = true if ev.submit? }
      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)

      submitted.should be_true
      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)  # Stays in FullEdit
    end

    it "Enter key exits FullEdit mode (returns to QuickEntry) if came from QuickEntry" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)  # Enter FullEdit
      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)

      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)  # Submit and exit

      input.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    end

    it "Escape key exits FullEdit mode (returns to QuickEntry)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.enter_edit_mode

      input.on_key_down(SF::Keyboard::Key::Escape, control: false, shift: false)

      input.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
      input.pending_replace.should be_true # re-armed to the clean type-to-replace resting state
    end

    it "up/down arrow keys are consumed (cursor movement)" do
      input = CrymbleUI::TextInput.new(value: "hello")
      input.on_focus
      input.enter_edit_mode

      # Up/Down can be used for Home/End or just consumed
      result = input.on_key_down(SF::Keyboard::Key::Up, control: false, shift: false)
      result.should be_true

      result = input.on_key_down(SF::Keyboard::Key::Down, control: false, shift: false)
      result.should be_true
    end
  end

  describe "double-click to enter FullEdit mode" do
    it "double-click enters FullEdit mode (from QuickEntry)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus

      input.on_double_click

      input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    end
  end

  describe "mode transitions (QuickEntry workflow)" do
    it "focus -> QuickEntry: pending_replace is set" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus

      # First char replaces
      input.on_text_input('a')
      input.value.should eq("a")
    end

    it "QuickEntry -> FullEdit (Enter): cursor at end, no pending replace" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)

      # Now in FullEdit, typing should insert at current position
      input.on_text_input('X')

      input.value.should eq("testX")  # Appended, not replaced
    end

    it "FullEdit -> QuickEntry (Enter): ready for next focus cycle" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.enter_edit_mode
      input.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)  # Exit FullEdit

      # Still focused, but now in QuickEntry
      input.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    end

    it "blur resets to QuickEntry mode (if started in QuickEntry)" do
      input = CrymbleUI::TextInput.new(value: "test", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.enter_edit_mode

      input.on_blur

      input.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    end
  end

  describe "state preservation during reconciliation" do
    it "preserves edit_mode during copy_state_from" do
      old_input = CrymbleUI::TextInput.new(value: "test", id: "input1", mode: CrymbleUI::TextInputMode::QuickEntry)
      old_input.on_focus
      old_input.enter_edit_mode

      new_input = CrymbleUI::TextInput.new(value: "test", id: "input1", mode: CrymbleUI::TextInputMode::QuickEntry)
      new_input.copy_state_from(old_input)

      new_input.edit_mode.should eq(CrymbleUI::TextInputMode::FullEdit)
    end

    it "preserves pending_replace during copy_state_from" do
      old_input = CrymbleUI::TextInput.new(value: "hello", id: "input1", mode: CrymbleUI::TextInputMode::QuickEntry)
      old_input.on_focus
      # Don't type anything, pending_replace should still be true

      new_input = CrymbleUI::TextInput.new(value: "hello", id: "input1", mode: CrymbleUI::TextInputMode::QuickEntry)
      new_input.copy_state_from(old_input)

      # First char should still replace
      new_input.on_text_input('x')
      new_input.value.should eq("x")
    end
  end

  # In a QuickEntry cell, Ctrl+X / Ctrl+V / Delete are cell-ops (decline -> the owner cell
  # cut/move/delete) ONLY while PARKED (not yet typed). Once you start typing (pending_replace
  # cleared, caret showing) they become TEXT-ops, editor-handled — like Backspace already is.
  # The return value IS the behavior: false = declined/bubbles-to-cell-op, true = editor-handled.
  describe "immediate-editing mode: cell-op keys become text-ops once you type" do
    it "PARKED QuickEntry declines Ctrl+X / Ctrl+V / Delete (they bubble to the cell owner)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.pending_replace.should be_true # parked (nothing typed yet)

      input.on_key_down(SF::Keyboard::Key::Delete, control: false, shift: false).should be_false
      input.on_key_down(SF::Keyboard::Key::X, control: true, shift: false).should be_false
      input.on_key_down(SF::Keyboard::Key::V, control: true, shift: false).should be_false
    end

    it "EDITING QuickEntry handles Ctrl+X / Ctrl+V / Delete as text-ops (no bubble to the cell owner)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_text_input('X')             # started typing -> pending_replace cleared, caret showing
      input.pending_replace.should be_false

      input.on_key_down(SF::Keyboard::Key::Delete, control: false, shift: false).should be_true
      input.on_key_down(SF::Keyboard::Key::X, control: true, shift: false).should be_true
      input.on_key_down(SF::Keyboard::Key::V, control: true, shift: false).should be_true
    end

    it "EDITING Delete forward-deletes a character rather than deleting the cell" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_text_input('a') # "a" (replace), caret at end
      input.on_text_input('b') # "ab"
      input.on_text_input('c') # "abc", editing
      # Home moves the caret to the start (forwarded to the editor since it's not a nav key here)
      input.on_key_down(SF::Keyboard::Key::Home, control: false, shift: false)
      input.on_key_down(SF::Keyboard::Key::Delete, control: false, shift: false).should be_true
      input.value.should eq("bc") # forward-deleted 'a' at the caret — NOT a cell delete
    end

    # SUPERSEDED RULE — a deliberate behaviour change, not a broken test. This used to
    # assert "Shift+Delete stays editor-handled in QuickEntry regardless (it carries no
    # cell-op)". Shift+Delete IS a cut, and the editor now touches the clipboard only
    # while it is actually editing text, so while PARKED it declines like every other
    # clipboard key and bubbles to the owner. The old rationale gated a generic widget
    # on which shortcuts one consumer happened to register — an application that grows
    # a grid-level cut would never see the key at all.
    it "PARKED Shift+Delete is not consumed — it is a cut, so it bubbles" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus # parked
      input.on_key_down(SF::Keyboard::Key::Delete, control: false, shift: true).should be_false
      input.value.should eq("hello")
    end

    it "EDITING Shift+Delete is editor-handled again (typing cleared parked)" do
      input = CrymbleUI::TextInput.new(value: "hello", mode: CrymbleUI::TextInputMode::QuickEntry)
      input.on_focus
      input.on_text_input('a') # typing started -> no longer parked
      input.on_key_down(SF::Keyboard::Key::Delete, control: false, shift: true).should be_true
    end
  end
end
