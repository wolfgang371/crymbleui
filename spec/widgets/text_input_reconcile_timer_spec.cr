require "../spec_helper"
require "../../src/widgets/text_input"

# A focused TextInput reconciled across a rebuild must reap its OLD instance's repeating
# cursor-blink timer. transfer_focus (inside Widget#copy_state_from) moves focus to the new
# instance WITHOUT firing the old one's on_blur, so without an explicit reap the old timer
# runs forever — pinning the discarded widget tree and forcing a redraw every tick. Mirrors
# VirtualMatrix's stop_cursor_flash_for_transfer.
#
# Measured via a DELTA on Scheduler#pending_count (baseline-agnostic): the shared focus-flash
# timer is TRANSFERRED (not duplicated) across reconcile, so it cancels out of the delta.

describe "TextInput reconcile — cursor-blink timer hygiene" do
  it "reaps the old blink timer when a FullEdit field is reconciled while focused" do
    sched = CrymbleUI::Widget.scheduler
    old = CrymbleUI::TextInput.new(value: "hi", id: "f") # FullEdit default
    old.request_focus                                    # on_focus -> blink running, pending_replace=false
    before = sched.pending_count

    new = CrymbleUI::TextInput.new(value: "hi", id: "f")
    new.copy_state_from(old)

    new.focused?.should be_true                          # precondition: focus transferred (else the test is vacuous)
    (sched.pending_count - before).should eq(0)          # -1 old blink + 1 new blink = 0 (without the fix: +1)
  end

  it "reaps the old blink timer even when the reconciled focused field is in pending_replace (no new caret)" do
    sched = CrymbleUI::Widget.scheduler
    old = CrymbleUI::TextInput.new(value: "hi", id: "q", mode: CrymbleUI::TextInputMode::QuickEntry)
    old.request_focus                                    # on_focus starts the blink UNCONDITIONALLY; pending_replace=true
    before = sched.pending_count

    new = CrymbleUI::TextInput.new(value: "hi", id: "q", mode: CrymbleUI::TextInputMode::QuickEntry)
    new.copy_state_from(old)

    new.focused?.should be_true
    # The new instance carries pending_replace (no caret -> no new blink), so the ONLY way the
    # old blink gets reaped is the UNCONDITIONAL stop. Delta drops by one (without the fix: 0).
    (sched.pending_count - before).should eq(-1)
  end

  it "adds no timer when a NON-focused field is reconciled (control — isolates the focused path)" do
    sched = CrymbleUI::Widget.scheduler
    old = CrymbleUI::TextInput.new(value: "hi", id: "n") # never focused -> no blink running
    before = sched.pending_count

    CrymbleUI::TextInput.new(value: "hi", id: "n").copy_state_from(old)

    (sched.pending_count - before).should eq(0) # passes with OR without the fix — proves the +1 above is the focused path
  end

  it "does not accumulate timers across repeated reconciles of a focused field" do
    sched = CrymbleUI::Widget.scheduler
    old = CrymbleUI::TextInput.new(value: "hi", id: "r")
    old.request_focus

    new1 = CrymbleUI::TextInput.new(value: "hi", id: "r"); new1.copy_state_from(old)
    c1 = sched.pending_count
    new2 = CrymbleUI::TextInput.new(value: "hi", id: "r"); new2.copy_state_from(new1)
    c2 = sched.pending_count

    c2.should eq(c1) # stable — each cycle reaps the prior old (without the fix it grows by one each time)
  end

  it "reaps a focused field's timers when it is REMOVED, not reconciled (the removed-path claim)" do
    fm = CrymbleUI::Widget.focus_manager
    sched = CrymbleUI::Widget.scheduler
    old = CrymbleUI::TextInput.new(value: "hi", id: "x")
    old.request_focus
    before = sched.pending_count

    # A rebuild that DROPS the focused field: reconcile_focus clears focus (old is not in the new
    # tree) -> focus(nil) -> on_blur -> stop_cursor_blink (+ stop_flash). No leak, no class hook.
    other_root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    other_root.add_child(CrymbleUI::Button.new("keep", id: "keep") { })
    fm.reconcile_focus(other_root)

    fm.focused_widget.should be_nil            # focus dropped
    sched.pending_count.should be < before     # the removed field's timer(s) reaped (not orphaned)
  end
end
