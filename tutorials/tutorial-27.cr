# Tutorial 27: MultiComboBox
# ==========================
# A multi-select dropdown: checkable items with a tristate "(select all)" header.
# Click a checkbox to toggle (the list stays open); click a row body to pick one
# and close.
#
# Key concepts:
# - combo_box(items:, selected: Set(Int32)) { |new_set| } builds a MultiComboBox
# - the block is handed the COMPLETE new selection on every change; the app stores it
# - summary: ->(Set(Int32)) { ... } customises the collapsed label

require "../src/crymble-ui"

include CrymbleUI

class Tutorial27App < CrymbleUI::App
  state selected : Set(Int32) = Set{0}

  FRUITS = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]

  def build : CrymbleUI::Widget
    window("Tutorial 27: MultiComboBox", 420, 420) do
      vstack(padding: 20.0, spacing: 12.0) do
        text("Pick some fruits:")

        # No custom `summary:` — the default labels the cell nicely: one pick shows the
        # name, several show "N of M (Apple, Ban…)" filling the width.
        combo_box(
          items: FRUITS,
          selected: selected,
          width: 240.0
        ) do |new_set|
          self.selected = new_set
        end

        text("Selected: #{selected.to_a.sort.map { |i| FRUITS[i] }.join(", ")}", font_scale: -1)
      end
    end
  end
end

CrymbleUI.run(Tutorial27App.new)
