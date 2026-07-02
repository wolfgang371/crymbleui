require "../spec_helper"
require "../../src/widgets/menu_item"

# step 5 (user option B): checkable menu items render the REAL checkbox
# (box + tristate) via the shared draw_check_glyph, and AUTO-CYCLE their own state
# on click. Existing `checked: Bool` callers are unchanged (back-compat).

private def menu_prims(item)
  item.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, 200.0, 28.0))
end

private def menu_lines(item) : Int32
  menu_prims(item).count(&.is_a?(CrymbleUI::DrawLine))
end

describe "MenuItem checkbox (box + tristate auto-cycle)" do
  it "a checkable item draws a REAL box (>=4 edge fill_rects), not a bare checkmark" do
    item = CrymbleUI::MenuItem.new("Toggle", checked: false) { }
    menu_prims(item).count(&.is_a?(CrymbleUI::FillRect)).should be >= 4 # box edges
    menu_lines(item).should eq(0)                                       # unchecked → no mark
  end

  it "a checked item draws the checkmark (2 lines + junction) inside the box" do
    item = CrymbleUI::MenuItem.new("Toggle", checked: true) { }
    menu_lines(item).should eq(2)
    menu_prims(item).count(&.is_a?(CrymbleUI::DrawCircle)).should eq(1)
  end

  it "check_state: Indeterminate renders the dash" do
    item = CrymbleUI::MenuItem.new("Tri", check_state: CrymbleUI::CheckState::Indeterminate, tristate: true) { }
    menu_lines(item).should eq(1) # the indeterminate dash
  end

  it "auto-cycles a non-tristate checkable item Unchecked<->Checked on click" do
    item = CrymbleUI::MenuItem.new("Toggle", checked: false) { }
    item.checked.should be_false
    item.trigger_click
    item.checked.should be_true # widget advanced its OWN state
    item.trigger_click
    item.checked.should be_false
  end

  it "auto-cycles a tristate item Unchecked->Checked->Indeterminate->Unchecked (rendered)" do
    item = CrymbleUI::MenuItem.new("Tri", tristate: true) { }
    menu_lines(item).should eq(0) # Unchecked
    item.trigger_click
    menu_lines(item).should eq(2) # Checked
    item.trigger_click
    menu_lines(item).should eq(1) # Indeterminate
    item.trigger_click
    menu_lines(item).should eq(0) # back to Unchecked
  end

  it "back-compat: a non-checkable item draws no box/mark and still fires its block" do
    fired = false
    item = CrymbleUI::MenuItem.new("Plain") { fired = true }
    menu_lines(item).should eq(0)
    item.trigger_click
    fired.should be_true
  end
end
