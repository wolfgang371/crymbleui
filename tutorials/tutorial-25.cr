# Tutorial 25: TreeNode
# =====================
# Collapsible tree sections for hierarchical content.
#
# Key concepts:
# - tree_node(header, expanded:) { children } creates a collapsible section
# - Tree nodes can be nested to arbitrary depth
# - font_scale and text_color customize the header appearance
#
# Run with: shards build tutorial-25 && ./bin/tutorial-25

require "../src/crymble-ui"

include CrymbleUI

class Tutorial25App < CrymbleUI::App
  state click_count : Int32 = 0

  def build : CrymbleUI::Widget
    window("Tutorial 25: TreeNode", 500, 500) do
      vstack(padding: 15.0, spacing: 10.0) do
        text("Collapsible Tree Sections", font_scale: 1)

        expanded do scroll_view(direction: ScrollDirection::Vertical) do
          vstack(spacing: 4.0) do
            tree_node("Getting Started", expanded: true, font_scale: 1) do
              vstack(padding: 10.0, spacing: 5.0) do
                text("CrymbleUI is a declarative GUI framework for Crystal.")
                text("It uses a reactive state model for automatic UI updates.")
              end
            end

            tree_node("Widgets", expanded: true) do
              vstack(padding: 10.0, spacing: 4.0) do
                tree_node("Basic Widgets", expanded: true) do
                  vstack(padding: 10.0, spacing: 5.0) do
                    text("- Button: clickable actions")
                    text("- Text: display labels")
                    text("- TextInput: text entry")
                    text("- Checkbox: boolean toggles")
                    text("- ComboBox: dropdown selection")
                  end
                end

                tree_node("Layout Widgets") do
                  vstack(padding: 10.0, spacing: 5.0) do
                    text("- VStack: vertical arrangement")
                    text("- HStack: horizontal arrangement")
                    text("- Expanded: fill remaining space")
                    text("- ScrollView: scrollable content")
                    text("- RecursiveGrid: auto-spanning grids")
                  end
                end

                tree_node("Advanced Widgets") do
                  vstack(padding: 10.0, spacing: 5.0) do
                    text("- VirtualMatrix: large scrollable tables")
                    text("- WindowPanel: floating panels")
                    text("- TreeNode: collapsible sections (this!)")
                    text("- Image: display images")
                  end
                end
              end
            end

            tree_node("Interactive Example") do
              vstack(padding: 10.0, spacing: 8.0) do
                text("Buttons work inside tree nodes:")
                hstack(spacing: 10.0) do
                  button("Click me") { self.click_count += 1 }
                  text("Clicked: #{click_count} times")
                end
              end
            end

            tree_node("About", text_color: Color.new(150, 150, 150, 255)) do
              vstack(padding: 10.0, spacing: 5.0) do
                text("CrymbleUI v#{`shards version`.chomp}", font_scale: -1,
                     color: Color.new(150, 150, 150, 255))
              end
            end
          end
        end end
      end
    end
  end
end

CrymbleUI.run(Tutorial25App.new)
