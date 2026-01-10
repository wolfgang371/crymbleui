# Tutorial 16: Keyboard Focus
# ============================
# Tab navigation between focusable widgets.
#
# Key concepts:
# - Tab/Shift+Tab cycles through focusable widgets
# - Buttons, TextInputs, Checkboxes are focusable by default
# - Focused widget shows highlight border
# - Enter/Space activates focused buttons
# - Arrow keys navigate within some widgets
#
# Run with: shards build tutorial-16 && ./bin/tutorial-16

require "../src/crymble"

class FocusDemo < CrymbleUI::App
  state value1 : String = ""
  state value2 : String = ""
  state checked : Bool = false

  def build : CrymbleUI::Widget
    window("Focus Demo", 450, 300) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Press Tab to move between widgets:")
        text("(Focus is shown with a highlight border)")

        text_input(value: value1, placeholder: "First input") do |val|
          self.value1 = val
        end

        text_input(value: value2, placeholder: "Second input") do |val|
          self.value2 = val
        end

        checkbox("A checkbox", checked: checked) do
          self.checked = !checked
        end

        hstack(spacing: 10.0) do
          button("Button A") { puts "A pressed" }
          button("Button B") { puts "B pressed" }
          button("Button C") { puts "C pressed" }
        end
      end
    end
  end
end

CrymbleUI.run(FocusDemo.new)
