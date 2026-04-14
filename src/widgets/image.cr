require "../core/widget"
require "../rendering/draw_primitive"

module CrymbleUI
  # Simple image widget that renders an image file
  # Uses DrawImage primitive — renderer handles texture loading/caching
  class Image < Widget
    property path : String
    property tint : Color
    @explicit_width : Float64?
    @explicit_height : Float64?

    def initialize(@path : String, id : String? = nil, @tint : Color = Color.white,
                   width : Float64? = nil, height : Float64? = nil)
      super(id: id)
      @explicit_width = width
      @explicit_height = height
    end

    def measure(constraints : BoxConstraints) : Size
      w = @explicit_width || constraints.max_width
      h = @explicit_height || constraints.max_height
      constraints.constrain(Size.new(w, h))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Use widget-local coordinates (0,0 origin), not parent-relative bounds
      local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)
      [DrawImage.new(@path, local_bounds, @tint).as(DrawPrimitive)]
    end

    def label : String
      "image"
    end
  end
end
