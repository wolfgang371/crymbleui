require "../src/crymble"

module CrymbleUI
  # Custom drag data for files (app-specific, not part of core)
  class FileDragData < DragData
    getter path : String
    def initialize(@path); end
    def data_type : String; "file"; end
    def display_text : String?; @path; end
  end

  # Custom widget class for the draggable items row
  # Tests that DSL works inside nested custom widget classes
  class DraggablesRow < HStack
    def initialize
      super(id: "draggables", spacing: 10.0)
    end

    def build
      # Task cards (text type)
      draggable(data: TextDragData.new("Task A")) do
        hstack(padding: 8.0, background_color: Color.new(100, 150, 200, 255)) do
          text("Task A", color: Color.new(255, 255, 255, 255))
        end
      end

      draggable(data: TextDragData.new("Task B")) do
        hstack(padding: 8.0, background_color: Color.new(100, 150, 200, 255)) do
          text("Task B", color: Color.new(255, 255, 255, 255))
        end
      end

      # File icons (file type)
      draggable(data: FileDragData.new("doc.txt")) do
        hstack(padding: 8.0, background_color: Color.new(200, 170, 100, 255)) do
          text("doc.txt", color: Color.new(50, 50, 50, 255))
        end
      end

      draggable(data: FileDragData.new("img.png")) do
        hstack(padding: 8.0, background_color: Color.new(200, 170, 100, 255)) do
          text("img.png", color: Color.new(50, 50, 50, 255))
        end
      end
    end
  end

  # Custom widget class for the drop zones row
  # Tests that DSL works inside nested custom widget classes
  class DropZonesRow < HStack
    def initialize
      super(id: "dropzones", spacing: 10.0)
    end

    def build
      # Task list - accepts text
      drop_zone(accept_types: ["text"], on_drop: ->(data : DragData, pos : Vec2) {
        puts "Task List received: #{data.display_text}"
      }) do
        vstack(padding: 8.0) do
          text("Task List")
          text("(text)", font_scale: -1, color: Color.new(120, 120, 120, 255))
        end
      end

      # Folder - accepts file
      drop_zone(accept_types: ["file"], on_drop: ->(data : DragData, pos : Vec2) {
        puts "Folder received: #{data.display_text}"
      }) do
        vstack(padding: 8.0) do
          text("Folder")
          text("(file)", font_scale: -1, color: Color.new(120, 120, 120, 255))
        end
      end

      # Archive - accepts file
      drop_zone(accept_types: ["file"], on_drop: ->(data : DragData, pos : Vec2) {
        puts "Archive received: #{data.display_text}"
      }) do
        vstack(padding: 8.0) do
          text("Archive")
          text("(file)", font_scale: -1, color: Color.new(120, 120, 120, 255))
        end
      end
    end
  end
end

class DragDropDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Drag & Drop Demo", 550, 280) do
      vstack(spacing: 15.0) do
        text("Drag items - zones only accept matching types", font_scale: 2)

        # Use nested custom widget classes
        widget(CrymbleUI::DraggablesRow.new)
        widget(CrymbleUI::DropZonesRow.new)
      end
    end
  end
end

CrymbleUI.run(DragDropDemo.new)
