require "../core/widget"
require "../rendering/draw_primitive"

module CrymbleUI
  # Simple image widget. The image is either compile-time-embedded (pass an
  # `ImageSource` from `embed_image`) or loaded from a disk path at render time
  # (pass a String). Uses the DrawImage primitive — the renderer loads/caches.
  class Image < Widget
    property source : ImageSource
    property tint : Color
    @explicit_width : Float64?
    @explicit_height : Float64?

    def initialize(@source : ImageSource, id : String? = nil, @tint : Color = Color.white,
                   width : Float64? = nil, height : Float64? = nil)
      super(id: id)
      @explicit_width = width
      @explicit_height = height
    end

    # Convenience: a plain disk path (loaded at render time, relative to CWD).
    def initialize(path : String, id : String? = nil, tint : Color = Color.white,
                   width : Float64? = nil, height : Float64? = nil)
      initialize(ImageSource.new(path), id: id, tint: tint, width: width, height: height)
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
      [DrawImage.new(@source, local_bounds, @tint).as(DrawPrimitive)]
    end

    def label : String
      "image"
    end
  end
end
