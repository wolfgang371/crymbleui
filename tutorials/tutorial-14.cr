# Tutorial 14: Popup & Overlays
# ==============================
# Floating popup containers.
#
# Key concepts:
# - popup(x:, y:, width:, height:) { content }
# - Popups float above other content (high z-index)
# - Auto-sizing when width/height omitted
# - Click outside to close (with callback)
# - Use for tooltips, dropdowns, context menus
#
# Run with: shards build tutorial-14 && ./bin/tutorial-14

require "../src/crymble"

class PopupDemo < CrymbleUI::App
  state show_popup : Bool = false

  def build : CrymbleUI::Widget
    window("Popup Demo", 500, 350) do
      vstack(spacing: 20.0, padding: 20.0) do
        text("Click the button to show a popup:")

        button(show_popup ? "Hide Popup" : "Show Popup") do
          self.show_popup = !show_popup
        end

        text("The popup appears as an overlay.")
      end

      if show_popup
        popup(x: 150.0, y: 120.0, padding: 15.0) do
          vstack(spacing: 10.0) do
            text("I'm a popup!")
            text("I float above content.")
            button("Close me") { self.show_popup = false }
          end
        end
      end
    end
  end
end

CrymbleUI.run(PopupDemo.new)
