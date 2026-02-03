# Tutorial 05: State Management
# ==============================
# Reactive state with automatic UI updates.
#
# Key concepts:
# - state macro defines reactive properties
# - Changing state triggers rebuild (UI updates automatically)
# - Use self.property = value in callbacks to trigger setter
# - State is preserved across rebuilds
#
# Run with: shards build tutorial-05 && ./bin/tutorial-05

require "../src/crymble-ui"

class CounterApp < CrymbleUI::App
  # Reactive state - UI rebuilds when this changes
  state count : Int32 = 0

  def build : CrymbleUI::Widget
    window("Counter", 400, 200) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Count: #{count}", font_scale: 3)

        hstack(spacing: 10.0) do
          button("- Decrement") { self.count -= 1 }
          button("+ Increment") { self.count += 1 }
          button("Reset") { self.count = 0 }
        end
      end
    end
  end
end

CrymbleUI.run(CounterApp.new)
