# Tutorial 10: ScrollView
# ========================
# Scrollable containers for large content.
#
# Key concepts:
# - scroll_view(direction:) { content } for scrollable area
# - Directions: Vertical (default), Horizontal, Both
# - Mouse wheel scrolls, scrollbar is draggable
# - Content can be larger than viewport
#
# Run with: shards build tutorial-10 && ./bin/tutorial-10

require "../src/crymble-ui"

class ScrollViewDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("ScrollView Demo", 400, 300) do
      vstack(spacing: 10.0, padding: 10.0) do
        text("Scroll down to see more items:")

        expanded do
          scroll_view(direction: CrymbleUI::ScrollDirection::Vertical) do
            vstack(spacing: 5.0) do
              30.times do |i|
                button("Item #{i + 1}") { puts "Clicked item #{i + 1}" }
              end
            end
          end
        end
      end
    end
  end
end

CrymbleUI.run(ScrollViewDemo.new)
