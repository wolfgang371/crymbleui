require "../spec_helper"
require "../../src/widgets/menu_item"

describe CrymbleUI::MenuItem do
    describe "disabled state" do
        it "renders with dimmed text color when disabled" do
            item = CrymbleUI::MenuItem.new("Save file", "^S") { }
            bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 25.0)

            # Enabled: normal text color
            item.enabled = true
            enabled_prims = item.to_primitives(bounds)
            enabled_text = enabled_prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            # Disabled: dimmed text color
            item.enabled = false
            disabled_prims = item.to_primitives(bounds)
            disabled_text = disabled_prims.find { |p| p.is_a?(CrymbleUI::DrawText) }.as(CrymbleUI::DrawText)

            # Colors must differ
            disabled_text.color.should_not eq(enabled_text.color)

            # Disabled text should have lower alpha or different color
            disabled_text.color.a.should be < enabled_text.color.a
        end

        it "does not fire callback when disabled" do
            clicked = false
            item = CrymbleUI::MenuItem.new("Save file") { clicked = true }

            item.enabled = false
            item.on_click

            clicked.should be_false
        end

        it "fires callback when enabled" do
            clicked = false
            item = CrymbleUI::MenuItem.new("Save file") { clicked = true }

            item.enabled = true
            item.on_click

            clicked.should be_true
        end
    end
end
