require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"

# T-016: opt-in editable ComboBox. A normal ComboBox can only commit one of its
# list items; an *editable* one also commits free-typed text that is not in the
# list (the merge-conflict resolver offers the candidate values but the resolved
# value may be neither side). Default (non-editable) behaviour is unchanged:
# typed text only filters, and an unmatched submit cancels.
describe "ComboBox editable mode (T-016)" do
  describe "ComboBoxPopup#select_highlighted" do
    it "editable: a submitted value not in the list commits as custom (index -1)" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], editable: true)
      got = nil
      cancelled = false
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      popup.on_cancel = -> { cancelled = true; nil }
      popup.text_input.value = "Cherry"
      popup.filter_items("Cherry") # no item matches → filtered list empty
      popup.select_highlighted
      got.should eq({-1, "Cherry"})
      cancelled.should be_false
    end

    it "non-editable (default): an unmatched submit cancels, never selects" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"])
      selected = false
      cancelled = false
      popup.on_select = ->(i : Int32, v : String) { selected = true; nil }
      popup.on_cancel = -> { cancelled = true; nil }
      popup.text_input.value = "Cherry"
      popup.filter_items("Cherry")
      popup.select_highlighted
      selected.should be_false
      cancelled.should be_true
    end

    it "editable: typed text matching an item exactly selects that item, not a custom value" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], editable: true)
      got = nil
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      popup.text_input.value = "Banana"
      popup.filter_items("Banana")
      popup.select_highlighted
      got.should eq({1, "Banana"})
    end

    it "editable: empty text falls through to the highlighted item" do
      popup = CrymbleUI::ComboBoxPopup.new(items: ["Apple", "Banana"], editable: true, selected_index: 1)
      got = nil
      popup.on_select = ->(i : Int32, v : String) { got = {i, v}; nil }
      # nothing typed → @text_input.value == ""
      popup.select_highlighted
      got.should eq({1, "Banana"})
    end
  end

  describe "ComboBox editable display" do
    it "defaults to non-editable; reflects the editable flag" do
      CrymbleUI::ComboBox.new(items: ["A"]).editable?.should be_false
      CrymbleUI::ComboBox.new(items: ["A"], editable: true).editable?.should be_true
    end

    it "shows a committed custom value (not only list items)" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], editable: true)
      combo.select_and_close(-1, "Cherry") # custom commit
      combo.selected_value.should eq("Cherry")
    end

    it "a normal pick clears any prior custom value" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], editable: true)
      combo.select_and_close(-1, "Cherry")
      combo.select_and_close(0, "Apple")
      combo.selected_value.should eq("Apple")
    end
  end
end
