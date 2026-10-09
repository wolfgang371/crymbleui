require "./drag_types"

module CrymbleUI
  # Mixin for widgets that can be dragged
  # Include this in any widget class to make it a drag source
  #
  # ## Usage
  #
  # ```crystal
  # class MyCard < Widget
  #   include Draggable
  #
  #   def get_drag_data : DragData?
  #     TextDragData.new(@title)
  #   end
  # end
  # ```
  module Draggable
    # Override to provide drag data when drag starts
    # Return nil to cancel the drag
    #
    # The payload is the GESTURE's: DragManager asks when the drag starts - or, at the first rebuild while
    # the press is still below the threshold, asks THIS instance then, before a replacement can take its
    # place (neither a replacement's data nor this instance's later data replaces it).
    abstract def get_drag_data : DragData?

    # Optional: Override to customize ghost preview widget
    # Default: an opaque GhostWidget shown through the ghost layer's opacity
    # Return a FRESH widget, outside the tree: the drag owns it and releases it (dispose_subtree) when it ends.
    def create_ghost_preview : Widget?
      nil
    end


    # Optional: Override for custom drag threshold (pixels)
    def drag_threshold : Float64
      DragState::DRAG_THRESHOLD
    end

    # Override to provide custom ghost bounds (e.g., cell bounds instead of full widget)
    # Default: nil (uses widget.absolute_bounds)
    def drag_ghost_bounds : Rect?
      nil
    end

    # Called when drag starts from this widget - or on the widget a rebuild put in its place during the
    # drag: "you are the source now". So the instance that heard start may not be the one that hears end;
    # and a source a rebuild REMOVES mid-drag hears no end at all (the drag ends with it).
    def on_drag_start(data : DragData)
      # Default: do nothing, subclass can override
    end

    # Called when drag ends (regardless of drop success)
    def on_drag_end(data : DragData, dropped : Bool)
      # Default: do nothing, subclass can override
    end
  end
end
