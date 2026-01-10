# Tutorial 19: Drag and Drop
# ===========================
# Type-safe drag and drop with accept_types filtering.
#
# Key concepts:
# - draggable(data: DragData) { content } for draggable items
# - drop_zone(accept_types:, on_drop:) { content } for drop targets
# - accept_types: array of type strings that the zone accepts
# - Built-in types: TextDragData ("text"), WidgetDragData ("widget")
# - Zones only highlight/accept matching types!
#
# Run with: shards build tutorial-19 && ./bin/tutorial-19

require "../src/crymble"

class DragDropDemo < CrymbleUI::App
  state last_drop : String = "(none)"

  def build : CrymbleUI::Widget
    window("Drag & Drop Demo", 550, 300) do
      vstack(spacing: 20.0, padding: 20.0) do
        text("Drag items to matching drop zones:")

        text("Draggable items:")
        hstack(spacing: 15.0) do
          # Text items (type: "text")
          draggable(data: CrymbleUI::TextDragData.new("Note A")) do
            hstack(padding: 8.0, background_color: CrymbleUI::Color.new(100, 150, 200, 255)) do
              text("Note A", color: CrymbleUI::Color.new(255, 255, 255, 255))
            end
          end

          draggable(data: CrymbleUI::TextDragData.new("Note B")) do
            hstack(padding: 8.0, background_color: CrymbleUI::Color.new(100, 150, 200, 255)) do
              text("Note B", color: CrymbleUI::Color.new(255, 255, 255, 255))
            end
          end

          # Widget items (type: "widget") - using a button as the widget reference
          draggable(data: CrymbleUI::WidgetDragData.new(CrymbleUI::Button.new("Item"))) do
            hstack(padding: 8.0, background_color: CrymbleUI::Color.new(200, 150, 100, 255)) do
              text("Widget", color: CrymbleUI::Color.new(50, 50, 50, 255))
            end
          end
        end

        text("Drop zones (only accept matching types):")
        hstack(spacing: 15.0) do
          # Only accepts "text" type
          drop_zone(accept_types: ["text"], on_drop: ->(data : CrymbleUI::DragData, pos : CrymbleUI::Vec2) {
            self.last_drop = "Text zone: #{data.display_text}"
          }) do
            vstack(padding: 10.0) do
              text("Text Zone")
              text("(accepts: text)", font_scale: -1)
            end
          end

          # Only accepts "widget" type
          drop_zone(accept_types: ["widget"], on_drop: ->(data : CrymbleUI::DragData, pos : CrymbleUI::Vec2) {
            self.last_drop = "Widget zone: #{data.display_text}"
          }) do
            vstack(padding: 10.0) do
              text("Widget Zone")
              text("(accepts: widget)", font_scale: -1)
            end
          end
        end

        text("Last drop: #{last_drop}")
      end
    end
  end
end

CrymbleUI.run(DragDropDemo.new)
