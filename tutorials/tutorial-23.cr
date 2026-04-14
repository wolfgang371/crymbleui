# Tutorial 23: Theme Switcher
# ===========================
# Demonstrates runtime theme switching, custom app background color, and disabled buttons.
#
# Key concepts:
# - Theme.set(:light) / Theme.set(:dark) for runtime theme switching
# - All widgets pick up Theme.current colors on rebuild
# - Override app_background_color for custom window background
# - button.enabled controls clickability with visual feedback
#
# Run with: shards build tutorial-23 && ./bin/tutorial-23

require "../src/crymble-ui"

include CrymbleUI

class Tutorial23App < CrymbleUI::App
  state current_theme : Symbol = :light
  state notify : Bool = false
  state input_value : String = ""
  state bg_mode : Symbol = :theme  # :theme, :green, :blue

  # Custom window background color based on bg_mode
  def app_background_color : CrymbleUI::Color?
    case @bg_mode
    when :green then Color.new(0, 40, 0, 255)
    when :blue  then Color.new(0, 0, 40, 255)
    else             nil # use theme default
    end
  end

  def build : CrymbleUI::Widget
    window("Tutorial 23: Theme Switcher", 700, 550) do
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
          separator
          menu_item("Background: Theme Default", checked: bg_mode == :theme, checkable: true) do
            self.bg_mode = :theme
          end
          menu_item("Background: Dark Green", checked: bg_mode == :green, checkable: true) do
            self.bg_mode = :green
          end
          menu_item("Background: Dark Blue", checked: bg_mode == :blue, checkable: true) do
            self.bg_mode = :blue
          end
        end
      end

      vstack(padding: 15.0, spacing: 10.0, background_color: Theme.current.panel_background) do
        text("Current theme: #{current_theme}, background: #{bg_mode}")

        separator

        hstack(spacing: 10.0) do
          button("Click Me") { }
          button("Another Button") { }
          b = button("Disabled") { }
          b.enabled = false
        end

        separator

        text_input(value: input_value, placeholder: "Type here...") { |v| self.input_value = v }

        separator

        checkbox("Enable notifications", bind: notify)

        separator

        combo_box(items: ["Option A", "Option B", "Option C"], width: 200.0)

        separator

        text("Disabled buttons appear greyed out and don't respond to clicks.")
        text("Custom backgrounds are set via app_background_color override.")
        text("Try View menu to switch theme and background.")
      end

      statusbar("Theme: #{current_theme} | Background: #{bg_mode}")
    end
  end
end

CrymbleUI.run(Tutorial23App.new)
