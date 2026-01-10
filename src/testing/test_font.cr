require "../core/font"

module CrymbleUI
  module Testing
    # Headless font implementation for testing
    # Provides simple text measurement without requiring SFML
    class TestFont < Font
      # Simple heuristic: assume monospace-ish font
      # Width ≈ 0.6 * size per character (typical for most fonts)
      # Height = size
      def measure_text(text : String, size : Float64) : Size
        width = text.size * size * 0.6
        height = size
        Size.new(width, height)
      end

      # No kerning in test mode
      def get_kerning(first : Char, second : Char, size : UInt32) : Float64
        0.0
      end

      # No text offsets in test mode (SFML-specific feature)
      def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
        {0.0, 0.0}
      end
    end
  end
end
