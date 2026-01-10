module CrymbleUI
  # Abstract base for drag payloads
  # Subclass to create custom drag data types
  abstract class DragData
    # Type identifier for matching with drop targets
    abstract def data_type : String

    # Optional display text for ghost preview
    def display_text : String?
      nil
    end
  end

  # Simple text-based drag data
  class TextDragData < DragData
    property text : String

    def initialize(@text : String)
    end

    def data_type : String
      "text"
    end

    def display_text : String?
      @text
    end
  end

  # Widget reference drag data (for reordering)
  class WidgetDragData < DragData
    property widget : Widget
    property source_index : Int32?

    def initialize(@widget : Widget, @source_index : Int32? = nil)
    end

    def data_type : String
      "widget"
    end

    def display_text : String?
      @widget.label
    end
  end

  # Drag operation phases
  enum DragPhase
    Idle       # No drag in progress
    Pending    # Mouse down, waiting for threshold
    Active     # Threshold passed, actively dragging
  end

  # Complete drag state
  class DragState
    # Minimum movement before drag starts (prevents accidental drags)
    DRAG_THRESHOLD = 5.0

    property phase : DragPhase = DragPhase::Idle
    property data : DragData? = nil
    property source_widget : Widget? = nil
    property start_position : Vec2 = Vec2.zero
    property current_position : Vec2 = Vec2.zero
    property current_target : Widget? = nil  # Valid drop target under cursor

    def active? : Bool
      @phase == DragPhase::Active
    end

    def pending? : Bool
      @phase == DragPhase::Pending
    end

    def passed_threshold?(current : Vec2) : Bool
      dx = current.x - @start_position.x
      dy = current.y - @start_position.y
      Math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD
    end

    def reset
      @phase = DragPhase::Idle
      @data = nil
      @source_widget = nil
      @start_position = Vec2.zero
      @current_position = Vec2.zero
      @current_target = nil
    end
  end
end
