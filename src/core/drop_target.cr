require "./drag_types"

module CrymbleUI
  # Mixin for widgets that can accept drops
  # Include this in any widget class to make it a drop target
  #
  # ## Usage
  #
  # ```crystal
  # class MyDropZone < Widget
  #   include DropTarget
  #
  #   def accepts_drop?(data : DragData) : Bool
  #     data.is_a?(TextDragData)
  #   end
  #
  #   def on_drop(data : DragData, position : Vec2)
  #     if text_data = data.as?(TextDragData)
  #       handle_text_drop(text_data.text)
  #     end
  #   end
  # end
  # ```
  #
  # Use `drag_hover?` in `to_primitives` for automatic highlighting:
  #
  # ```crystal
  # def to_primitives(bounds : Rect) : Array(DrawPrimitive)
  #   primitives do
  #     fill_rect(local_rect, @background_color)
  #     if drag_hover?
  #       fill_rect(local_rect, HIGHLIGHT_COLOR)
  #     end
  #   end
  # end
  # ```
  module DropTarget
    # Check if this target accepts the given data type
    # Called during drag to determine highlighting
    abstract def accepts_drop?(data : DragData) : Bool

    # Handle the actual drop
    # Called when mouse released over this target
    abstract def on_drop(data : DragData, position : Vec2)

    # Track if currently being hovered during drag
    # Set by DragManager, can be used by widgets for additional feedback
    @drag_hover : Bool = false

    def drag_hover? : Bool
      @drag_hover
    end

    # Internal: Set drag hover state (called by DragManager)
    protected def drag_hover=(value : Bool)
      @drag_hover = value
    end

    # Get highlight color for overlay layer
    # Override in concrete classes to customize (alpha applied during compositing)
    def highlight_color : Color
      Color.new(180, 220, 255, 255)  # Default: blue
    end

    # Get highlight opacity for overlay layer (0.0-1.0)
    # Override in concrete classes to customize
    def highlight_opacity : Float64
      0.4  # Default: 40% opacity
    end

    # Called when drag enters this target
    # Highlight is now handled by overlay layer in DragManager
    def on_drag_enter(data : DragData)
      # Override for custom behavior
    end

    # Called when drag leaves this target
    # Highlight is now handled by overlay layer in DragManager
    def on_drag_leave(data : DragData)
      # Override for custom behavior
    end

    # Called while dragging over this target (for position feedback)
    # Override for custom behavior (e.g., insertion point preview)
    def on_drag_over(data : DragData, position : Vec2)
      # Default: do nothing
    end
  end
end
