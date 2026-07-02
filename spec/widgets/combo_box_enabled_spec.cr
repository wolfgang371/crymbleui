require "../spec_helper"
require "../../src/widgets/combo_box"

# A disabled ComboBox must render DIMMED and must NOT open its
# popup on click — so a caller can grey the control in place (embrace's
# merge-source picker when no branch is mergeable) instead of letting it vanish.
describe "ComboBox honours enabled?" do
  it "renders dimmer text when disabled" do
    bounds = CrymbleUI::Rect.new(0.0, 0.0, 130.0, 24.0)
    enabled = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
    disabled = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
    disabled.enabled = false
    etxt = enabled.to_primitives(bounds).find(&.is_a?(CrymbleUI::DrawText)).not_nil!.as(CrymbleUI::DrawText)
    dtxt = disabled.to_primitives(bounds).find(&.is_a?(CrymbleUI::DrawText)).not_nil!.as(CrymbleUI::DrawText)
    dtxt.color.a.should be < etxt.color.a # greyed (lower alpha)
  end

  it "does NOT open its popup on click when disabled" do
    disabled = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
    disabled.enabled = false
    disabled.popup_open?.should be_false
    disabled.on_mouse_up(CrymbleUI::Vec2.new(10.0, 10.0)) # a left-click
    disabled.popup_open?.should be_false                   # stays closed
  end
end
