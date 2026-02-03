# Tutorial 04: HStack Layout
# ===========================
# Horizontal stacking of widgets.
#
# Key concepts:
# - hstack arranges children left-to-right
# - spacing: gap between children (in pixels)
# - padding: space around all children
# - Combine with vstack for complex layouts
#
# Run with: shards build tutorial-04 && ./bin/tutorial-04

require "../src/crymble-ui"

class HStackDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("HStack Demo", 500, 200) do
      vstack(spacing: 20.0, padding: 20.0) do
        text("Buttons in a row:")

        hstack(spacing: 10.0) do
          button("Left") { puts "Left clicked" }
          button("Middle") { puts "Middle clicked" }
          button("Right") { puts "Right clicked" }
        end
      end
    end
  end
end

CrymbleUI.run(HStackDemo.new)
