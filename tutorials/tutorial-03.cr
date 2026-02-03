# Tutorial 03: VStack Layout
# ===========================
# Vertical stacking of widgets.
#
# Key concepts:
# - vstack arranges children top-to-bottom
# - spacing: gap between children (in pixels)
# - padding: space around all children
# - Children are laid out in order
#
# Run with: shards build tutorial-03 && ./bin/tutorial-03

require "../src/crymble-ui"

class VStackDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("VStack Demo", 400, 300) do
      vstack(spacing: 15.0, padding: 20.0) do
        text("First item (top)")
        text("Second item")
        text("Third item")
        text("Fourth item (bottom)")
      end
    end
  end
end

CrymbleUI.run(VStackDemo.new)
