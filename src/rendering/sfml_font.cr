require "../csfml3/wrapper"
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
      # Width: actual text width from local_bounds — for a multi-line string SFML already
      # reports the WIDEST line, which is what a block occupies.
      # Height: the font's line spacing for CONSISTENT height across all text
      # (local_bounds.height varies per-glyph, causing buttons with different text to have
      # different heights) — times the LINE COUNT. SFML renders `\n` natively, so a 3-line
      # string was being drawn three lines tall inside a box measured as one; the layout
      # reserved a third of what it painted. The per-glyph-consistency intent above is about
      # glyph variation, not line count, and multiplying preserves it exactly: a string with
      # no break is byte-identical.
      line_height = @font.get_line_spacing(size.round.to_u32).to_f64
      Size.new(bounds.width.to_f64, line_height * (text.count('\n') + 1))
    end

    # Get kerning between two characters at given font size
    def get_kerning(first : Char, second : Char, size : UInt32) : Float64
      @font.get_kerning(first.ord.to_u32, second.ord.to_u32, size).to_f64
    end

    # Get SFML text offsets for position compensation
    # SFML's local_bounds has left/top offsets that need to be subtracted for accurate positioning.
    # Top offset uses a cached reference glyph ("Ag") so all text aligns on the same baseline
    # regardless of content — "..." and "Add field" get the same vertical offset.
    def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
      sf_text = SF::Text.new(text, @font, size.round.to_u32)
      bounds = sf_text.local_bounds
      {bounds.left.to_f64, reference_top(size)}
    end

    @reference_tops = Hash(UInt32, Float64).new

    private def reference_top(size : Float64) : Float64
      key = size.round.to_u32
      @reference_tops[key] ||= begin
        ref = SF::Text.new("Ag", @font, key)
        ref.local_bounds.top.to_f64
      end
    end

    @reference_heights = Hash(UInt32, Float64).new

    # Real visual line extent (cap-top to descender-bottom of "Ag"), cached per size.
    # Used to vertically center text by its ink box instead of the em size.
    def reference_height(size : Float64) : Float64
      key = size.round.to_u32
      @reference_heights[key] ||= begin
        ref = SF::Text.new("Ag", @font, key)
        ref.local_bounds.height.to_f64
      end
    end

    # Allow direct access to underlying SF::Font if needed
    def to_sf_font : SF::Font
      @font
    end
  end
end
