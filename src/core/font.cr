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
  end
end
