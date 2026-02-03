# Tutorial 11: Styling Widgets
# =============================
# Customizing colors and fonts.
#
# Key concepts:
# - text(..., color:, font_scale:) for styled text
# - button(..., background_color:, text_color:, border_color:)
# - font_scale: -2 to +5 (0 = base size, each step ~1.2x)
# - Color.new(r, g, b, a) or predefined colors
#
# Run with: shards build tutorial-11 && ./bin/tutorial-11

require "../src/crymble-ui"

class StylingDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Styling Demo", 450, 300) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("Small text", font_scale: -1)
        text("Normal text", font_scale: 0)
        text("Large text", font_scale: 2)
        text("Huge text", font_scale: 4)

        text("Colored text", color: CrymbleUI::Color.new(255, 100, 100, 255))

        hstack(spacing: 10.0) do
          button("Red",
            background_color: CrymbleUI::Color.new(200, 50, 50, 255),
            text_color: CrymbleUI::Color.new(255, 255, 255, 255)) { }

          button("Green",
            background_color: CrymbleUI::Color.new(50, 200, 50, 255),
            text_color: CrymbleUI::Color.new(255, 255, 255, 255)) { }

          button("Blue",
            background_color: CrymbleUI::Color.new(50, 50, 200, 255),
            text_color: CrymbleUI::Color.new(255, 255, 255, 255)) { }
        end
      end
    end
  end
end

CrymbleUI.run(StylingDemo.new)
