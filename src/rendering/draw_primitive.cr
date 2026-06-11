require "../core/types"
require "../core/font_sizing"

module CrymbleUI
  # Base type for all drawing primitives
  # Primitives are pure data structures that describe "what to draw"
  # They know nothing about rendering backends (SFML, OpenGL, etc.)
  abstract struct DrawPrimitive
  end

  # Fill a rectangle with a solid color
  struct FillRect < DrawPrimitive
    property bounds : Rect
    property color : Color

    def initialize(@bounds : Rect, @color : Color)
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
  end

  # Draw a line between two points
  struct DrawLine < DrawPrimitive
    property from : Vec2
    property to : Vec2
    property color : Color
    property width : Float64

    def initialize(@from : Vec2, @to : Vec2, @color : Color, @width : Float64 = 1.0)
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
  end

  # Fill a triangle with a solid color
  struct FillTriangle < DrawPrimitive
    property p1 : Vec2
    property p2 : Vec2
    property p3 : Vec2
    property color : Color

    def initialize(@p1 : Vec2, @p2 : Vec2, @p3 : Vec2, @color : Color)
    end
  end

  # Draw a rectangle outline
  struct DrawRect < DrawPrimitive
    property bounds : Rect
    property color : Color
    property width : Float64

    def initialize(@bounds : Rect, @color : Color, @width : Float64 = 1.0)
    end
  end

  # Push a clipping rectangle onto the stack
  # All subsequent primitives are clipped to this rectangle
  struct PushClip < DrawPrimitive
    property rect : Rect

    def initialize(@rect : Rect)
    end
  end

  # Pop the most recent clipping rectangle from the stack
  struct PopClip < DrawPrimitive
    def initialize
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
