require "../src/crymble-ui"

# Demo for the MultiComboBox (multi-select dropdown via `selected : Set(Int32)`).
# Validates the checkbox gutter (✓/☐), the tristate "(select all)" header (▣ when
# partial), the collapsed summary, and that the checked state survives the rebuild
# triggered when the app updates its reactive `state` on each toggle (the path
# embrace's request_rebuild also exercises).
#
# NB: an open dropdown overlays DOWNWARD, so each live readout is placed ABOVE its
# combo box — otherwise the dropdown hides the very feedback you're checking.
class MultiComboBoxDemo < CrymbleUI::App
  state fruits : Set(Int32) = Set(Int32).new
  state veggies : Set(Int32) = Set{1, 3}

  FRUITS  = ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig"]
  VEGGIES = ["Carrot", "Pea", "Bean", "Kale", "Leek"]

  def build : CrymbleUI::Widget
    window("MultiComboBox Demo", 640, 560) do
      vstack(spacing: 15.0) do
        cpu_monitor
        text("MultiComboBox (multi-select) Demo", font_scale: 5)

        text("What to check:", font_scale: 1)
        text("- Open the dropdown: preselected items show ✓, others ☐", font_scale: -2)
        text("- Click a ✓ gutter: that row's check flips, popup STAYS open", font_scale: -2)
        text("- Header '(select all)': ✓ all / ☐ none / ▣ partial (tristate)", font_scale: -2)
        text("- Click a row body: select-only-that and close", font_scale: -2)

        # Readout ABOVE the combo so the open dropdown doesn't hide it.
        text("Fruits — app updates state on toggle:", font_scale: 0)
        text("  fruits = #{self.fruits.to_a.sort.map { |i| FRUITS[i] }}", font_scale: -1)
        combo_box(
          items: FRUITS,
          selected: self.fruits,
          width: 280.0,
          id: "fruits",
          summary: ->(s : Set(Int32)) { s.empty? ? "(pick fruits)" : "#{s.size} of #{FRUITS.size}" }
        ) do |new_set|
          self.fruits = new_set
        end

        # Second combo with a non-empty initial selection (checks at open).
        text("Veggies — preselected {Pea, Kale}:", font_scale: 0)
        text("  veggies = #{self.veggies.to_a.sort.map { |i| VEGGIES[i] }}", font_scale: -1)
        combo_box(
          items: VEGGIES,
          selected: self.veggies,
          width: 280.0,
          id: "veggies",
          summary: ->(s : Set(Int32)) { s.empty? ? "(none)" : "#{s.size} of #{VEGGIES.size}" }
        ) do |new_set|
          self.veggies = new_set
        end
      end
    end
  end
end

CrymbleUI.run(MultiComboBoxDemo.new)
