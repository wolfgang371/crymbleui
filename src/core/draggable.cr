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
    abstract def get_drag_data : DragData?

    # Optional: Override to customize ghost preview widget
    # Default: uses a semi-transparent copy of the source widget
    def create_ghost_preview : Widget?
      nil
    end

    # Optional: Override for custom drag threshold (pixels)
    def drag_threshold : Float64
      DragState::DRAG_THRESHOLD
    end

    # Called when drag starts from this widget
    def on_drag_start(data : DragData)
      # Default: do nothing, subclass can override
    end

    # Called when drag ends (regardless of drop success)
    def on_drag_end(data : DragData, dropped : Bool)
      # Default: do nothing, subclass can override
    end
  end
end
