require "./types"

module CrymbleUI
  # Abstract font interface for text measurement
  # Allows decoupling from SFML - implementations can be SFML-based or headless
  abstract class Font
    # Measure the size of text at given font size
    # Returns bounding box size (width, height)
    abstract def measure_text(text : String, size : Float64) : Size

    # Get kerning offset between two characters
    # Returns horizontal offset to apply between characters
    abstract def get_kerning(first : Char, second : Char, size : UInt32) : Float64

    # Get text rendering offsets for position compensation
    # SFML has internal left/top offsets in local_bounds that need compensation
    # Headless fonts don't have these offsets and return (0, 0)
    # Returns (left_offset, top_offset)
    abstract def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)

    # Visual height of a representative line ("Ag": cap-top to descender-bottom), used to
    # vertically center text by its real ink extent rather than the em size. draw_text
    # anchors the cap-top, so centering this extent puts the line on the box's true centre.
    # Default = the em `size` (headless / metric-less fonts), which preserves the old
    # `(height - font_size) / 2` behaviour; SFMLFont overrides it with the real metric.
    def reference_height(size : Float64) : Float64
      size
    end
  end
end
