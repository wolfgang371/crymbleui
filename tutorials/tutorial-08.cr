# Tutorial 08: ComboBox
# ======================
# Dropdown selection lists.
#
# Key concepts:
# - combo_box(items:, selected:) { |index, value| } for dropdown
# - items: array of strings to choose from
# - selected: currently selected index (0-based)
# - Block receives selected index and value
#
# Run with: shards build tutorial-08 && ./bin/tutorial-08

require "../src/crymble-ui"

class ComboBoxDemo < CrymbleUI::App
  state selected_index : Int32 = 0

  FRUITS = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]

  def build : CrymbleUI::Widget
    window("ComboBox Demo", 400, 400) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Select a fruit:")

        combo_box(items: FRUITS, selected: selected_index) do |index, value|
          self.selected_index = index
          puts "Selected: #{value} (index #{index})"
        end

        text("You selected: #{FRUITS[selected_index]}")
      end
    end
  end
end

CrymbleUI.run(ComboBoxDemo.new)
