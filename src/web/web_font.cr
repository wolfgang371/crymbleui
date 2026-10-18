require "../core/font"
require "../core/embedded_font"
require "./js"

module CrymbleUI
  # The web flavour's Font: SFMLFont's model over the page's canvas text metrics. A text's size is the local bounds
  # sf::Text reports (glyph boxes; whitespace counts at the baseline), its line spacing FreeType's - computed here
  # from the embedded font's own tables with FreeType's fixed-point arithmetic, so the two flavours lay text out
  # on the same lines. The embedded font is monospace: no kerning.
  class WebFont < Font
    @line_spacing = Hash(Int32, Float64).new
    @reference = Hash(Int32, Tuple(Float64, Float64)).new # size => {top, height} of "Ag"
    @units_per_em : Int32
    @line_height_units : Int32

    def initialize(font_bytes : Bytes = EmbeddedFont::BYTES.to_slice)
      @units_per_em, @line_height_units = WebFont.vertical_metrics(font_bytes)
    end

    def measure_text(text : String, size : Float64) : Size
      bounds = local_bounds(text, size)
      Size.new(bounds[2], line_spacing(size) * (text.count('\n') + 1))
    end

    def get_kerning(first : Char, second : Char, size : UInt32) : Float64
      0.0
    end

    def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
      {local_bounds(text, size)[0], reference(size)[0]}
    end

    def reference_height(size : Float64) : Float64
      reference(size)[1]
    end

    # FreeType's size->metrics.height for a pixel size (what sf::Font::getLineSpacing returns):
    # FT_PIX_ROUND(FT_MulFix(hhea ascender - descender + lineGap, FT_DivFix(size * 64, units_per_EM))) / 64.
    def line_spacing(size : Float64) : Float64
      px = size.round.to_i
      @line_spacing[px] ||= begin
        y_scale = WebFont.div_fix(px.to_i64 * 64, @units_per_em.to_i64)
        height = WebFont.mul_fix(@line_height_units.to_i64, y_scale)
        ((height + 32) & ~63_i64) / 64.0
      end
    end

    # {left, top, width, height} of sf::Text's local bounds, measured by the page at the rounded size.
    private def local_bounds(text : String, size : Float64) : StaticArray(Float64, 4)
      bounds = StaticArray(Float64, 4).new(0.0)
      LibCrymbleWeb.measure(text.to_unsafe, text.bytesize, size.round, bounds.to_unsafe)
      bounds
    end

    private def reference(size : Float64) : Tuple(Float64, Float64)
      @reference[size.round.to_i] ||= begin
        b = local_bounds("Ag", size)
        {b[1], b[3]}
      end
    end

    # FreeType's FT_DivFix: (a << 16) / b, rounded half away from zero.
    def self.div_fix(a : Int64, b : Int64) : Int64
      ((a << 16) + b // 2) // b
    end

    # FreeType's FT_MulFix: (a * b) >> 16, rounded half away from zero.
    def self.mul_fix(a : Int64, b : Int64) : Int64
      product = a * b
      product >= 0 ? (product + 0x8000) >> 16 : -((-product + 0x8000) >> 16)
    end

    # units_per_EM (head) and the line height in font units (hhea ascender - descender + lineGap), read from the
    # TrueType table directory.
    def self.vertical_metrics(font : Bytes) : Tuple(Int32, Int32)
      tables = {} of String => Int32
      count = IO::ByteFormat::BigEndian.decode(UInt16, font[4, 2])
      count.times do |i|
        entry = 12 + 16 * i
        tables[String.new(font[entry, 4])] = IO::ByteFormat::BigEndian.decode(UInt32, font[entry + 8, 4]).to_i32
      end
      head = tables["head"]
      hhea = tables["hhea"]
      upem = IO::ByteFormat::BigEndian.decode(UInt16, font[head + 18, 2]).to_i32
      ascender = IO::ByteFormat::BigEndian.decode(Int16, font[hhea + 4, 2]).to_i32
      descender = IO::ByteFormat::BigEndian.decode(Int16, font[hhea + 6, 2]).to_i32
      line_gap = IO::ByteFormat::BigEndian.decode(Int16, font[hhea + 8, 2]).to_i32
      {upem, ascender - descender + line_gap}
    end
  end

  # The page's clipboard: it keeps the text, and a paste updates it from the browser's paste event before the
  # Ctrl+V reaches the app (Clipboard#text is read synchronously while the key is handled).
  class WebClipboard < Clipboard
    def text : String?
      length = LibCrymbleWeb.clipboard_get(Pointer(UInt8).null, 0)
      return nil if length == 0
      buf = Bytes.new(length)
      LibCrymbleWeb.clipboard_get(buf.to_unsafe, length)
      String.new(buf)
    end

    def text=(value : String)
      LibCrymbleWeb.clipboard_set(value.to_unsafe, value.bytesize)
    end
  end
end
