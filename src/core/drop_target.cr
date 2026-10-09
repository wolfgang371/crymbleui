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
    # Called when mouse released over this target. `position` is in this widget's own space - the space
    # its bounds live in, as a mouse handler's point is - so `position - absolute_bounds` is correct.
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

    # Get highlight color for overlay layer: the theme's drag highlight, read live (follows Theme.set)
    # Override in concrete classes to customize (alpha applied during compositing)
    def highlight_color : Color
      Theme.current.drag_highlight
    end

    # Get highlight opacity for overlay layer (0.0-1.0)
    # Override in concrete classes to customize.
    # The value is the THEME's drag-feedback strength — the same number DragManager falls back to
    # for a target that is not a DropTarget, so both branches of that choice cannot drift apart.
    def highlight_opacity : Float64
      Theme.current.brightness_drag_opacity
    end

    # Called when drag enters this target - or on the widget a rebuild put in place of the hovered one
    # (it is the target now, and drag_hover? says so)
    # Highlight is now handled by overlay layer in DragManager
    def on_drag_enter(data : DragData)
      # Override for custom behavior
    end

    # Called when drag leaves this target
    # Highlight is now handled by overlay layer in DragManager
    def on_drag_leave(data : DragData)
      # Override for custom behavior
    end

    # Called while dragging over this target (for position feedback); `position` in its own space. Also once
    # a frame while the pointer is still (the tree may have moved under it) - keep it cheap and idempotent,
    # and never rebuild synchronously from it (it runs after the frame's layout); request_rebuild instead.
    # Override for custom behavior (e.g., insertion point preview)
    def on_drag_over(data : DragData, position : Vec2)
      # Default: do nothing
    end
  end
end
