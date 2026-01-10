require "../core/widget"
require "../core/types"
require "../core/draggable"

module CrymbleUI
  # Container widget that makes its child draggable
  # Used by the DSL to wrap content in a draggable container
  #
  # ## Example
  # ```crystal
  # draggable(data: TextDragData.new("Task A")) do
  #   hstack(padding: 8.0, background_color: blue) do
  #     text("Task A")
  #   end
  # end
  # ```
  class DraggableBox < Widget
    include Draggable

    @drag_data : DragData?

    def initialize(@drag_data : DragData?, id : String? = nil)
      super(id: id)
    end

    def get_drag_data : DragData?
      @drag_data
    end

    # Measure: delegate to single child
    def measure(constraints : BoxConstraints) : Size
      return Size.new(0.0, 0.0) if @children.empty?
      @children.first.measure(constraints)
    end

    # Layout: position child at (0,0)
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
      @children.first?.try { |child| child.layout(constraints, Vec2.new(0.0, 0.0)) }
    end
  end
end
