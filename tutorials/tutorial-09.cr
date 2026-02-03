# Tutorial 09: Expanded & Spacer
# ===============================
# Filling remaining space in layouts.
#
# Key concepts:
# - expanded { widget } makes widget fill remaining space
# - expanded(flex: N) for proportional sizing (2x flex = 2x space)
# - spacer() creates empty expanded space (pushes widgets apart)
#
# Run with: shards build tutorial-09 && ./bin/tutorial-09

require "../src/crymble-ui"

class ExpandedDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Expanded Demo", 500, 300) do
      vstack(spacing: 10.0, padding: 20.0) do
        text("Spacer pushes button to bottom:")

        spacer  # Takes all remaining vertical space

        button("I'm at the bottom!") { }

        text("---")
        text("Flex ratios (1:2:1):")

        hstack(spacing: 5.0) do
          expanded(flex: 1) do
            button("1x") { }
          end
          expanded(flex: 2) do
            button("2x (double width)") { }
          end
          expanded(flex: 1) do
            button("1x") { }
          end
        end
      end
    end
  end
end

CrymbleUI.run(ExpandedDemo.new)
