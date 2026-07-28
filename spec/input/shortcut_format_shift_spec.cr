require "../spec_helper"
require "../../src/input/shortcut_format"
require "../../src/input/shortcut"

# The DISPLAY parser and the BINDING parser must agree on every modifier. They were separate
# implementations of the same format and had drifted: display parsed "shift" as shift=false, so a
# Shift shortcut bound correctly (Shortcut.parse) while its menu/button label rendered WITHOUT the
# Shift — the user saw "A" for a binding that needs Shift+A.
describe "shortcut display formatting agrees with the binding parser" do
  it "keeps the Shift modifier in the displayed label" do
    CrymbleUI::ShortcutFormat.to_display("Shift+A").not_nil!.should contain("Shift")
  end

  it "agrees with Shortcut.parse on every modifier" do
    {"Ctrl+S", "Alt+F4", "Shift+A", "Ctrl+Shift+Z"}.each do |s|
      parsed = CrymbleUI::Shortcut.parse(s)
      shown = CrymbleUI::ShortcutFormat.to_display(s).not_nil!
      shown.downcase.includes?("ctrl").should eq(parsed.ctrl), "ctrl mismatch for #{s}: #{shown}"
      shown.downcase.includes?("alt").should eq(parsed.alt), "alt mismatch for #{s}: #{shown}"
      shown.downcase.includes?("shift").should eq(parsed.shift), "shift mismatch for #{s}: #{shown}"
    end
  end
end
