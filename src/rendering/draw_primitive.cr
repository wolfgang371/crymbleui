require "../core/types"
require "../core/font_sizing"

module CrymbleUI
  # Base type for all drawing primitives
  # Primitives are pure data structures that describe "what to draw"
  # They know nothing about rendering backends (SFML, OpenGL, etc.)
  abstract struct DrawPrimitive
    # This primitive drawn at factor `f`: every position and extent multiplied by it, about the widget's own
    # origin (a scaled layer puts that origin at the widget's scaled place). nil when nothing is left to draw.
    # Each is a COPY with its scaled fields set, so every other field (a colour, DrawText's zoom_epoch, a
    # FillRect's covers) is carried by construction. A primitive defined outside crymbleui must implement it.
    abstract def scaled(f : Float64) : DrawPrimitive?

    # `prims` for a widget drawn at factor `f` into a device span of `span_w` x `span_h` pixels: each scaled,
    # and a covering fill (FillRect#covers) made the span itself - covering by construction, where a fill
    # scaled from the widget's width could miss the last column by an ulp across a pixel edge. At factor 1 the
    # same array comes back (no allocation).
    def self.scaled_primitives(prims : Array(DrawPrimitive), f : Float64, span_w : Int32, span_h : Int32) : Array(DrawPrimitive)
      return prims if f == 1.0
      result = Array(DrawPrimitive).new(prims.size)
      prims.each do |prim|
        if prim.is_a?(FillRect) && prim.covers
          result << FillRect.new(Rect.new(0.0, 0.0, span_w.to_f64, span_h.to_f64), prim.color, covers: true)
        elsif drawn = prim.scaled(f)
          result << drawn
        end
      end
      result
    end

    def self.scale_rect(r : Rect, f : Float64) : Rect
      Rect.new(r.x * f, r.y * f, r.width * f, r.height * f)
    end

    def self.scale_point(p : Vec2, f : Float64) : Vec2
      Vec2.new(p.x * f, p.y * f)
    end
  end

  # Fill a rectangle with a solid color
  struct FillRect < DrawPrimitive
    property bounds : Rect
    property color : Color
    # Covers the widget's whole device span (a background - PrimitiveBuilder#fill_background): scaled, it becomes
    # that span itself (DrawPrimitive.scaled_primitives), and -Ddebug_fill_coverage checks it covers.
    property covers : Bool

    def initialize(@bounds : Rect, @color : Color, @covers : Bool = false)
    end

    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.bounds = DrawPrimitive.scale_rect(@bounds, f)
      copy
    end
  end

  # Draw text at a position
  struct DrawText < DrawPrimitive
    property text : String
    property position : Vec2
    property color : Color
    property size : Float64
    property zoom_epoch : UInt64  # Epoch when created, for DEBUG_ZOOM stale cache detection

    def initialize(@text : String, @position : Vec2, @color : Color, @size : Float64)
      @zoom_epoch = FontSizing.zoom_epoch
    end

    # Rasterised at the scaled size (crisp at any factor), the epoch kept. Below one pixel there is no glyph
    # to draw: dropped here, the one place a scaled size is decided.
    def scaled(f : Float64) : DrawPrimitive?
      size = @size * f
      return nil if size < 1.0
      copy = self
      copy.position = DrawPrimitive.scale_point(@position, f)
      copy.size = size
      copy
    end
  end

  # Draw a line between two points
  struct DrawLine < DrawPrimitive
    property from : Vec2
    property to : Vec2
    property color : Color
    property width : Float64

    def initialize(@from : Vec2, @to : Vec2, @color : Color, @width : Float64 = 1.0)
    end

    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.from = DrawPrimitive.scale_point(@from, f)
      copy.to = DrawPrimitive.scale_point(@to, f)
      copy.width = @width * f
      copy
    end
  end

  # Draw a circle (filled or outline)
  struct DrawCircle < DrawPrimitive
    property center : Vec2
    property radius : Float64
    property color : Color
    property fill : Bool

    def initialize(@center : Vec2, @radius : Float64, @color : Color, @fill : Bool = true)
    end

    # An outline stays one pixel wide: the backends draw it so.
    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.center = DrawPrimitive.scale_point(@center, f)
      copy.radius = @radius * f
      copy
    end
  end

  # Fill a triangle with a solid color
  struct FillTriangle < DrawPrimitive
    property p1 : Vec2
    property p2 : Vec2
    property p3 : Vec2
    property color : Color

    def initialize(@p1 : Vec2, @p2 : Vec2, @p3 : Vec2, @color : Color)
    end

    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.p1 = DrawPrimitive.scale_point(@p1, f)
      copy.p2 = DrawPrimitive.scale_point(@p2, f)
      copy.p3 = DrawPrimitive.scale_point(@p3, f)
      copy
    end
  end

  # Draw a rectangle outline
  struct DrawRect < DrawPrimitive
    property bounds : Rect
    property color : Color
    property width : Float64

    def initialize(@bounds : Rect, @color : Color, @width : Float64 = 1.0)
    end

    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.bounds = DrawPrimitive.scale_rect(@bounds, f)
      copy.width = @width * f
      copy
    end
  end

  # Push a clipping rectangle onto the stack
  # All subsequent primitives are clipped to this rectangle
  struct PushClip < DrawPrimitive
    property rect : Rect

    def initialize(@rect : Rect)
    end

    # Widget-local, like every position here: it scales about the widget's origin.
    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.rect = DrawPrimitive.scale_rect(@rect, f)
      copy
    end
  end

  # Pop the most recent clipping rectangle from the stack
  struct PopClip < DrawPrimitive
    def initialize
    end

    def scaled(f : Float64) : DrawPrimitive?
      self
    end
  end

  # A reference to an image: either compile-time-embedded bytes (produced by the
  # `embed_image` macro — self-contained, CWD-independent) or a plain disk path
  # loaded at render time. `key` is the texture-cache key (and the disk path when
  # `bytes` is nil).
  struct ImageSource
    getter key : String
    getter bytes : Bytes?

    def initialize(@key : String, @bytes : Bytes? = nil)
    end
  end

  # Draw an image at the given bounds. The renderer loads/caches the texture by
  # `source.key` (from embedded bytes when present, else from disk).
  # Color is used for tinting/alpha (White = no tint).
  struct DrawImage < DrawPrimitive
    getter source : ImageSource
    property bounds : Rect
    property color : Color

    def initialize(@source : ImageSource, @bounds : Rect, @color : Color = Color.white)
    end

    # Convenience: a plain disk path (loaded at render time, relative to CWD).
    def initialize(path : String, bounds : Rect, color : Color = Color.white)
      initialize(ImageSource.new(path), bounds, color)
    end

    # Texture-cache key — the embedded key or the disk path.
    def path : String
      @source.key
    end

    def scaled(f : Float64) : DrawPrimitive?
      copy = self
      copy.bounds = DrawPrimitive.scale_rect(@bounds, f)
      copy
    end
  end
end

# Embed an image file's bytes at COMPILE TIME and return an `ImageSource` that
# serves it from memory — so a standalone binary needs no external files. The path
# is resolved by the compiler relative to the build root (like `read_file`), and is
# reused as the runtime texture-cache key. Pair with `image(...)`:
#
#   LOGO = embed_image("tutorials/crystal_logo.png")
#   image(LOGO, width: 40.0, height: 40.0)
macro embed_image(path)
  ::CrymbleUI::ImageSource.new({{ path }}, {{ read_file(path) }}.to_slice)
end
