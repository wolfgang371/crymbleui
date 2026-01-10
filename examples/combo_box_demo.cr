require "../src/crymble"

# Demo application showcasing ComboBox widget (new architecture)
class ComboBoxDemo < CrymbleUI::App
  # Fruits selection
  state selected_fruit : String = ""
  state fruit_index : Int32 = 0

  # Priority selection
  state selected_priority : String = ""
  state priority_index : Int32 = 1  # Default to "Normal"

  # Countries selection
  state selected_country : String = ""
  state country_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("ComboBox Demo", 600, 600) do
      vstack(spacing: 15.0) do
        cpu_monitor
        text("ComboBox Widget Demo", font_scale: 5)

        # Basic fruits list with per-item background colors
        text("Select a Fruit:", font_scale: 0)
        combo_box(
          items: ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape"],
          selected: self.fruit_index,
          width: 250.0,
          id: "fruits",
          text_background_colors: [
            CrymbleUI::Color.new(255, 200, 200),  # Apple - light red
            CrymbleUI::Color.new(255, 255, 180),  # Banana - light yellow
            CrymbleUI::Color.new(255, 180, 180),  # Cherry - pink
            CrymbleUI::Color.new(220, 180, 140),  # Date - tan
            CrymbleUI::Color.new(200, 180, 220),  # Elderberry - light purple
            CrymbleUI::Color.new(180, 220, 180),  # Fig - light green
            CrymbleUI::Color.new(200, 180, 220),  # Grape - light purple
          ]
        ) do |idx, val|
          self.fruit_index = idx
          self.selected_fruit = val
        end

        # Priority list with single text background color
        text("Priority Level:", font_scale: 0)
        combo_box(
          items: ["Critical", "Normal", "Low"],
          selected: self.priority_index,
          width: 200.0,
          id: "priority",
          text_background_color: CrymbleUI::Color.new(255, 240, 200)  # Light orange for all
        ) do |idx, val|
          self.priority_index = idx
          self.selected_priority = val
        end

        # Countries list
        text("Select a Country:", font_scale: 0)
        combo_box(
          items: [
            "Argentina", "Australia", "Austria", "Belgium", "Brazil",
            "Canada", "Chile", "China", "Colombia", "Denmark",
            "France", "Germany", "India", "Japan", "Mexico"
          ],
          selected: self.country_index,
          width: 300.0,
          id: "countries"
        ) do |idx, val|
          self.country_index = idx
          self.selected_country = val
        end

        # Show current selections
        text("Current Selections:", font_scale: 2)
        text("Fruit: #{self.selected_fruit.empty? ? "(none)" : self.selected_fruit}", font_scale: -1)
        text("Priority: #{self.selected_priority.empty? ? "(none)" : self.selected_priority}", font_scale: -1)
        text("Country: #{self.selected_country.empty? ? "(none)" : self.selected_country}", font_scale: -1)

        # Instructions
        text("Instructions:", font_scale: 1)
        text("- Click a ComboBox to open dropdown", font_scale: -2)
        text("- Type to filter items", font_scale: -2)
        text("- Use Ctrl++/- to zoom", font_scale: -2)
      end
    end
  end
end

# Run the demo
CrymbleUI.run(ComboBoxDemo.new)
