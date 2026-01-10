require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"

module CrymbleUI
  # Simple widget that fills its bounds with a color
  # Used for overlay highlights (drop zones, selections, etc.)
  class HighlightWidget < Widget
    include PrimitiveBuilder

    @width : Float64
    @height : Float64
    @color : Color

    def initialize(@width, @height, @color)
      super(id: "highlight")
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(@width, @height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, Size.new(@width, @height))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), @color)
      end
    end
  end
end
