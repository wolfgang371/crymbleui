# Tutorial 06: Checkbox
# ======================
# Boolean toggles and tristate checkboxes.
#
# Key concepts:
# - checkbox(label, toggle: state_var) for auto-toggle over a plain state Bool (recommended)
# - checkbox(label, checked: bool) { manual_toggle } for manual control
# - checkbox(label, state: CheckState) { } for tristate
# - Responds to click and keyboard (Space/Enter)
#
# Run with: shards build tutorial-06 && ./bin/tutorial-06

require "../src/crymble-ui"

class CheckboxDemo < CrymbleUI::App
  state option1 : Bool = false
  state option2 : Bool = true
  state tristate : CrymbleUI::CheckState = CrymbleUI::CheckState::Indeterminate

  def build : CrymbleUI::Widget
    window("Checkbox Demo", 400, 250) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Auto-toggle with toggle:")
        checkbox("Option 1 (#{option1})", toggle: option1)

        text("Manual toggle:")
        checkbox("Option 2 (#{option2})", checked: option2) do
          self.option2 = !option2
        end

        text("Tristate (cycles through states):")
        checkbox("Tristate (#{tristate})", state: tristate) do
          self.tristate = case tristate
          when CrymbleUI::CheckState::Unchecked     then CrymbleUI::CheckState::Checked
          when CrymbleUI::CheckState::Checked       then CrymbleUI::CheckState::Indeterminate
          when CrymbleUI::CheckState::Indeterminate then CrymbleUI::CheckState::Unchecked
          else CrymbleUI::CheckState::Unchecked
          end
        end
      end
    end
  end
end

CrymbleUI.run(CheckboxDemo.new)
