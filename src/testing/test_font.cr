require "../core/font"

module CrymbleUI
  module Testing
    # Headless font implementation for testing
    # Provides simple text measurement without requiring SFML
    class TestFont < Font
      # A glyph's advance as a fraction of the font size — the monospace-ish heuristic this
      # headless font stands on. Published for the same reason `line_step` is: the render
      # backend spaces its stripes by exactly this, and a font and a backend that disagree
      # about glyph pitch make every horizontal pixel claim in the suite unreadable.
      CHAR_WIDTH_RATIO = 0.6

      # The per-line slot: what one line of text occupies vertically. Published because
      # TestRenderBackend#draw_text advances by exactly this between lines — the headless
      # font and the headless backend must not disagree about where line k sits, or a
      # multi-line pixel claim is unreadable in a way no example can see.
      def self.line_step(size : Float64) : Float64
        size
      end

      # Simple heuristic: assume a monospace-ish font, one CHAR_WIDTH_RATIO-wide advance per
      # character.
      #
      # Width is the WIDEST line and height is the line slot times the line count — the same
      # structure SFMLFont reports (SFML's local_bounds.width IS the widest line, its height
      # one get_line_spacing). Counting `\n` as a glyph, as this did, made a 3-line string
      # both too wide and one line tall. A string with no break is byte-identical to the old
      # arithmetic, which is what keeps the cross-widget blast radius nil.
      def measure_text(text : String, size : Float64) : Size
        widest = 0
        run = 0
        lines = 1
        text.each_char do |ch|
          if ch == '\n'
            lines += 1
            widest = run if run > widest
            run = 0
          else
            run += 1
          end
        end
        widest = run if run > widest
        Size.new(widest * size * CHAR_WIDTH_RATIO, TestFont.line_step(size) * lines)
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
