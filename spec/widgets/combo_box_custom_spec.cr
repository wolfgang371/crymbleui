require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"

# This file replaces combo_box_editable_spec.cr, which pinned `editable:` —
# a mode where the popup's filter box doubled as a value box.
#
# The old contract, faithfully specified and wrong by design: `select_highlighted`
# checked `@editable` FIRST, so any non-empty typed text committed as a custom value and
# the highlighted row — which `update_highlight` was actively flashing — was never
# consulted. Type a prefix to narrow the list, arrow onto the one match, press Enter, and
# you got the PREFIX. Once anything was typed there was no keyboard path to a filtered
# item at all.
#
# It cannot be fixed by a rule: "prefer the highlight when the filter narrowed to a match"
# silently picks a list item when the user meant a new value. One box cannot disambiguate
# two jobs, so the jobs get two controls — the filter filters, and wanting something the
# list lacks is its own row.
describe "ComboBox allow_custom mode" do
  describe "ComboBoxPopup#select_highlighted" do
    it "ENTER ALWAYS CONFIRMS THE HIGHLIGHT, even with a filter typed" do
      # The case with no green path under `editable:`.
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], allow_custom: true)
      got = nil
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      popup.text_input.value = "Ban"
      popup.filter_items("Ban") # narrows to exactly "Banana"
      popup.select_highlighted
      got.should eq({1, "Banana"})
    end

    it "the (custom...) row asks the consumer, carrying the filter text as a prefill" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], allow_custom: true)
      selected = nil
      asked = nil
      popup.on_select = ->(i : Int32, v : String) { selected = {i, v}; nil }
      popup.on_custom_requested = ->(prefill : String) { asked = prefill; nil }

      popup.text_input.value = "Cherry"
      popup.filter_items("Cherry")        # matches nothing; only the custom row remains
      popup.select_highlighted

      asked.should eq("Cherry")
      selected.should be_nil               # a custom request is NOT a selection
    end

    it "the (custom...) row is reachable by arrow, and comes last" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], allow_custom: true)
      asked = false
      popup.on_custom_requested = ->(_p : String) { asked = true; nil }
      popup.move_highlight(1) # Apple -> Banana
      popup.move_highlight(1) # Banana -> (custom...)
      popup.select_highlighted
      asked.should be_true
    end

    it "without allow_custom an unmatched submit cancels, and never selects" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"])
      got = nil
      cancelled = false
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      popup.on_cancel = -> { cancelled = true; nil }
      popup.text_input.value = "Cherry"
      popup.filter_items("Cherry")
      popup.select_highlighted
      got.should be_nil
      cancelled.should be_true
    end

    it "without allow_custom the arrows stop at the last real item" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"])
      got = nil
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      popup.move_highlight(1)
      popup.move_highlight(1) # would be the custom row if there were one
      popup.select_highlighted
      got.should eq({1, "Banana"})
    end
  end

  describe "ComboBox" do
    it "defaults to no custom row, and reflects the flag" do
      CrymbleUI::ComboBox.new(items: ["A"]).allow_custom?.should be_false
      CrymbleUI::ComboBox.new(items: ["A"], allow_custom: true).allow_custom?.should be_true
    end

    it "the LAZY ctor takes it too — a collapsed string AND a way to ask for a value" do
      # The pairing that had no constructor: the eager ctor takes items but has no
      # collapsed text, the lazy one had collapsed text but no way to offer a custom value.
      combo = CrymbleUI::ComboBox.new(
        selected_text: "Cust ¦ Customer",
        items_provider: -> : CrymbleUI::ComboBox::LazyItems {
          {items: ["Cust", "Customer"], colors: nil, selected: 0, payloads: [0, 1]}
        },
        allow_custom: true) { |_i, _v| }
      combo.allow_custom?.should be_true
      combo.selected_value.should eq("Cust ¦ Customer")
    end
  end
end
