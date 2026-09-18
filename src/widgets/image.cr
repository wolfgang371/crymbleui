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
      ew = @explicit_width
      eh = @explicit_height

      # BOTH DIMENSIONS GIVEN = A DECLARED ASPECT RATIO, which a smaller box must not break.
      #
      # These axes used to be clamped independently, so a box narrower than the request kept the
      # requested HEIGHT and the picture was stretched to fill it. embrace's About dialog showed it:
      # a square 800x800 logo asked for at 655x655 came out 655x570 on a wide panel and 370x285 on a
      # narrow one — visibly squashed at every size, worst while being resized (Wolfgang, 2026-09-17:
      # "image gets distorted rather than either cropped or panel staying at minimum width").
      #
      # No knowledge of the file is needed to get this right, and deliberately so: ImageSource
      # carries a key and bytes, not dimensions, and decoding a header here would put image parsing
      # in the layout path for every format we might ever accept. A caller that passes width AND
      # height has already stated the ratio it wants — honour that and scale both axes by the same
      # factor to fit. Never ENLARGES: the factor is capped at 1.0, so an oversized box leaves the
      # image at its requested size rather than blowing it up.
      if ew && eh && ew > 0 && eh > 0
        scale = {constraints.max_width / ew, constraints.max_height / eh, 1.0}.min
        scale = 1.0 unless scale.finite? # an unbounded box asks for no scaling
        return constraints.constrain(Size.new(ew * scale, eh * scale))
      end

      # One-sided (or no) request: there is no declared ratio to keep, and the free axis takes what
      # is available — which is what fills a row or a column.
      w = ew || constraints.max_width
      h = eh || constraints.max_height
      constraints.constrain(Size.new(w, h))
    end

    # WHAT THIS IMAGE IS WILLING TO BE SQUEEZED TO, which is not the same question as what it does
    # when squeezed.
    #
    # WindowPanel derives how narrow it may be dragged from its content's min_intrinsic_width, and
    # Widget's default answers that by MEASURING with an unbounded width — which, now that measure
    # scales both axes together, returns a width limited by the available HEIGHT. So an image in a
    # short panel declared itself willing to be 284px wide when it had asked for 655, the panel's
    # floor collapsed with it, and the content reflowed on every drag. That reflow is what exposed
    # the layer-repair gap: a viewport_cache layer repairs SCROLL (recenter, blit-shift, per-slot
    # skip) and has nothing for reflow, so the vacated pixels stayed (Wolfgang, 2026-09-17 — first
    # a distorted logo, then a ghosted one).
    #
    # An image asked for a size does not volunteer to be narrower than it. It still SCALES to fit
    # when a container genuinely gives it less, so nothing is distorted; it simply stops inviting
    # the squeeze. Untouched for a one-sided request, which has no declared size to stand on.
    def min_intrinsic_width(height : Float64) : Float64
      ew = @explicit_width
      eh = @explicit_height
      return super unless ew && eh
      ew
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
