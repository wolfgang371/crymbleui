# Tutorial 23: Theme Switcher
# ===========================
# Demonstrates runtime theme switching via a menubar.
#
# All widgets pick up Theme.current colors on rebuild.
# Run with: shards build tutorial-23 && ./bin/tutorial-23

require "../src/crymble-ui"

include CrymbleUI

class Tutorial23App < CrymbleUI::App
  state current_theme : Symbol = :light
  state notify : Bool = false
  state input_value : String = ""

  def build : CrymbleUI::Widget
    window("Tutorial 23: Theme Switcher", 700, 500) do
      menubar do
        menu("View") do
          menu_item("Light Theme", checked: current_theme == :light, checkable: true) do
            Theme.set(:light)
            self.current_theme = :light
          end
          menu_item("Dark Theme", checked: current_theme == :dark, checkable: true) do
            Theme.set(:dark)
            self.current_theme = :dark
          end
        end
      end

      vstack(padding: 15.0, spacing: 10.0, background_color: Theme.current.panel_background) do
        text("Current theme: #{current_theme}")

        separator

        hstack(spacing: 10.0) do
          button("Click Me") { }
          button("Another Button") { }
        end

        separator

        text_input(value: input_value, placeholder: "Type here...") { |v| self.input_value = v }

        separator

        checkbox("Enable notifications", bind: notify)

        separator

        combo_box(items: ["Option A", "Option B", "Option C"], width: 200.0)

        separator

        text("All widgets above respond to theme changes at runtime.")
      end

      statusbar("Theme: #{current_theme}")
    end
  end
end

CrymbleUI.run(Tutorial23App.new)
