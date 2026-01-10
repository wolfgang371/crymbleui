require "crsfml"
require "../core/font"

module CrymbleUI
  # SFML-based font implementation
  # Wraps SF::Font and delegates text measurement to SFML
  class SFMLFont < Font
    @font : SF::Font

    def initialize(@font : SF::Font)
    end

    # Measure text using SFML's text rendering
    # See: https://www.sfml-dev.org/documentation/2.5.1/classsf_1_1Font.php
    def measure_text(text : String, size : Float64) : Size
      sf_text = SF::Text.new(text, @font, size.round.to_u32)
      bounds = sf_text.local_bounds
      # Width: use actual text width from local_bounds
      # Height: use font's line spacing for CONSISTENT height across all text
      # (local_bounds.height varies per-glyph, causing buttons with different text to have different heights)
      line_height = @font.get_line_spacing(size.round.to_u32).to_f64
      Size.new(bounds.width.to_f64, line_height)
    end

    # Get kerning between two characters at given font size
    def get_kerning(first : Char, second : Char, size : UInt32) : Float64
      @font.get_kerning(first.ord.to_u32, second.ord.to_u32, size).to_f64
    end

    # Get SFML text offsets for position compensation
    # SFML's local_bounds has left/top offsets that need to be subtracted for accurate positioning
    def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
      sf_text = SF::Text.new(text, @font, size.round.to_u32)
      bounds = sf_text.local_bounds
      {bounds.left.to_f64, bounds.top.to_f64}
    end

    # Allow direct access to underlying SF::Font if needed
    def to_sf_font : SF::Font
      @font
    end
  end
end
