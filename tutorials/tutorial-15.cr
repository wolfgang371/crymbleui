# Tutorial 15: StatusBar
# ========================
# Information display at window bottom.
#
# Key concepts:
# - statusbar(text:) displays status at bottom
# - Commonly shows: current state, hints, coordinates
# - Can be updated dynamically via state
# - Pairs well with on_hover_change for context hints
#
# Run with: shards build tutorial-15 && ./bin/tutorial-15

require "../src/crymble-ui"

class StatusBarDemo < CrymbleUI::App
  state click_count : Int32 = 0
  state last_action : String = "Ready"

  def build : CrymbleUI::Widget
    window("StatusBar Demo", 500, 300) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Click buttons to update the status bar:")

        hstack(spacing: 10.0) do
          button("Action A") do
            self.click_count += 1
            self.last_action = "Action A"
          end

          button("Action B") do
            self.click_count += 1
            self.last_action = "Action B"
          end

          button("Reset") do
            self.click_count = 0
            self.last_action = "Reset"
          end
        end

        spacer
      end

      statusbar(text: "Clicks: #{click_count} | Last: #{last_action}")
    end
  end
end

CrymbleUI.run(StatusBarDemo.new)
