# Tutorial 07: TextInput
# ========================
# Single-line text entry fields.
#
# Key concepts:
# - text_input(value:, placeholder:) { |value| } for simple change tracking
# - text_input(on_event: proc) for full event handling (Submit, Cancel, etc.)
# - Enter key fires Submit event
# - Supports selection, clipboard (Ctrl+C/X/V), Home/End
#
# Run with: shards build tutorial-07 && ./bin/tutorial-07

require "../src/crymble"

class TextInputDemo < CrymbleUI::App
  state name : String = ""
  state submitted : String = ""

  def build : CrymbleUI::Widget
    window("TextInput Demo", 450, 250) do
      vstack(spacing: 12.0, padding: 20.0) do
        text("Simple mode (block receives value on each change):")
        text_input(value: name, placeholder: "Type here...") do |value|
          self.name = value
        end
        text("Value: #{name}", font_scale: -1)

        spacer

        text("Event mode (press Enter to submit):")
        text_input(value: submitted, placeholder: "Type and press Enter...",
          on_event: ->(value : String, event : CrymbleUI::TextInputEvent) {
            self.submitted = value if event.submit?
          }
        )
        text("Submitted: #{submitted}", font_scale: -1)
      end
    end
  end
end

CrymbleUI.run(TextInputDemo.new)
