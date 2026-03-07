require "../core/widget"
require "../core/types"
require "../core/drop_target"
require "../dsl/primitive_builder"

module CrymbleUI
  # Container widget that accepts drops of specific data types
  # Used by the DSL to wrap content in a drop target container
  #
  # Has background_color that changes to hover_color when dragging over.
  # Don't set background on child widgets - let DropZoneBox handle it.
  #
  # ## Example
  # ```crystal
  # drop_zone(accept_types: ["text"], background_color: grey, hover_color: blue) do
  #   vstack(padding: 8.0) { text("Drop here") }
  # end
  # ```
  class DropZoneBox < Widget
    include DropTarget
    include PrimitiveBuilder

    @accept_types : Array(String)
    @on_drop_handler : Proc(DragData, Vec2, Nil)?
    @background_color : Color
    @hover_color : Color

    def initialize(
      @accept_types : Array(String),
      @on_drop_handler : Proc(DragData, Vec2, Nil)? = nil,
      @background_color : Color = Theme.current.dropzone_background,
      @hover_color : Color = Theme.current.dropzone_hover,
      id : String? = nil
    )
      super(id: id)
    end

    def accepts_drop?(data : DragData) : Bool
      @accept_types.includes?(data.data_type)
    end

    # Override to use configured hover_color for overlay highlight
    def highlight_color : Color
      @hover_color
    end

    def on_drop(data : DragData, position : Vec2)
      @on_drop_handler.try(&.call(data, position))
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

    # Draw background only - hover highlight is handled by overlay layer
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), @background_color)
      end
    end
  end
end
