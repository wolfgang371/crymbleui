require "../spec_helper"
require "../../src/rendering/sfml_renderer"

# THE SHIPPED FONT, ASKED ABOUT DIRECTLY.
#
# resources/Cousine-Regular.ttf is not stock: glyphs have been merged into it (U+25C4/U+25BA from
# Cantarell, U+21BA from DejaVu Sans Mono — see resources/FONTS.md). Two properties have to survive
# every such merge, and until now both lived only in prose:
#
#   1. EQUAL WIDTH. The widget layer treats this font as monospaced. A donor glyph arrives with the
#      donor's advance, which will be close to Cousine's and not equal to it — DejaVu's U+21BA was
#      1233 against Cousine's 1229 — and a single odd advance is a column that will not line up.
#   2. INK. A cmap entry proves a MAPPING exists, not that anything is drawn. This bug class is
#      precisely "the character is fine everywhere except on screen", so the glyph a codepoint maps
#      to must actually have outlines.
#
# Read straight out of the file's own tables rather than through a renderer, so the spec is headless,
# has no GL context to lose, and fails on the artefact we actually ship.
private class TtfReader
  getter data : Bytes

  def initialize(path : String)
    @data = File.read(path).to_slice
    @tables = Hash(String, Tuple(Int32, Int32)).new
    num_tables = u16(4)
    num_tables.times do |i|
      off = 12 + i * 16
      tag = String.new(@data[off, 4])
      @tables[tag] = {i32(off + 8), i32(off + 12)}
    end
  end

  def u8(o : Int32) : Int32; @data[o].to_i; end
  def u16(o : Int32) : Int32; (@data[o].to_i << 8) | @data[o + 1].to_i; end
  def i16(o : Int32) : Int32; v = u16(o); v >= 0x8000 ? v - 0x10000 : v; end
  def i32(o : Int32) : Int32; (u16(o) << 16) | u16(o + 2); end
  def table(tag : String) : Int32; @tables[tag][0]; end
  def table?(tag : String) : Bool; @tables.has_key?(tag); end

  def units_per_em : Int32; u16(table("head") + 18); end
  def num_glyphs : Int32; u16(table("maxp") + 4); end
  def long_loca? : Bool; i16(table("head") + 50) == 1; end
  def num_h_metrics : Int32; u16(table("hhea") + 34); end

  # Advance for every glyph. Glyphs past numberOfHMetrics inherit the last advance, which is how a
  # monospaced font stores one value for a long tail.
  def advances : Array(Int32)
    hm = table("hmtx")
    n = num_h_metrics
    last = 0
    Array(Int32).new(num_glyphs) do |gid|
      if gid < n
        last = u16(hm + gid * 4)
      end
      last
    end
  end

  # cmap format 4, the Windows BMP subtable every text font carries.
  def glyph_id(cp : Int32) : Int32
    cm = table("cmap")
    n = u16(cm + 2)
    sub = -1
    n.times do |i|
      rec = cm + 4 + i * 8
      plat, enc = u16(rec), u16(rec + 2)
      sub = cm + i32(rec + 4) if (plat == 3 && enc == 1) || (plat == 0)
    end
    return 0 if sub < 0 || u16(sub) != 4
    seg2 = u16(sub + 6)
    ends = sub + 14
    starts = ends + seg2 + 2
    deltas = starts + seg2
    ranges = deltas + seg2
    (seg2 // 2).times do |s|
      next unless cp <= u16(ends + s * 2)
      st = u16(starts + s * 2)
      return 0 if cp < st
      ro = u16(ranges + s * 2)
      if ro == 0
        return (cp + i16(deltas + s * 2)) & 0xFFFF
      end
      gi_at = ranges + s * 2 + ro + (cp - st) * 2
      g = u16(gi_at)
      return g == 0 ? 0 : (g + i16(deltas + s * 2)) & 0xFFFF
    end
    0
  end

  # One `name` record, decoded. Platform 3 strings are UTF-16BE; platform 1 is MacRoman, and for the
  # ASCII these records hold the two coincide, so a byte-skip is enough for our purposes.
  def name_record(want_id : Int32) : String?
    return nil unless table?("name")
    nm = table("name")
    count = u16(nm + 2)
    storage = nm + u16(nm + 4)
    count.times do |i|
      rec = nm + 6 + i * 12
      next unless u16(rec + 6) == want_id
      len = u16(rec + 8)
      off = storage + u16(rec + 10)
      bytes = @data[off, len]
      plat = u16(rec)
      return plat == 3 ? String.new(bytes.each_slice(2).map { |p| p[1] }.to_a.to_unsafe, len // 2) : String.new(bytes)
    end
    nil
  end

  # Does this glyph draw anything? numberOfContours == 0 is an empty outline (what a space is).
  def contours(gid : Int32) : Int32
    lo = table("loca")
    a, b = long_loca? ? {i32(lo + gid * 4), i32(lo + gid * 4 + 4)} : {u16(lo + gid * 2) * 2, u16(lo + gid * 2 + 2) * 2}
    return 0 if b <= a
    i16(table("glyf") + a)
  end
end

# Overridable so the spec itself can be shown to fail: point it at the pre-merge font and the
# second example must report U+21BA missing. A tripwire nobody has watched fail is not known to work.
FONT_PATH = ENV["CUI_FONT"]? || "resources/Cousine-Regular.ttf"

describe "the shipped Cousine" do
  it "gives every glyph that occupies space the same advance" do
    f = TtfReader.new(FONT_PATH)
    f.units_per_em.should eq(2048)
    # Zero is legitimate — non-spacing marks. Everything else must agree, whatever the value is:
    # the spec pins the RULE, not a number someone would have to update deliberately.
    spacing = f.advances.reject(&.zero?).to_set
    spacing.size.should eq(1), "expected one advance width across the font, found #{spacing.to_a.sort}"
    spacing.first.should eq(1229)
  end

  it "draws every character merged into it, not merely maps one" do
    f = TtfReader.new(FONT_PATH)
    {0x21BA => "U+21BA revert (from DejaVu Sans Mono)",
     0x25C4 => "U+25C4 (from Cantarell)",
     0x25BA => "U+25BA (from Cantarell)",
     0x2190 => "U+2190, the left arrow U+21BA replaced"}.each do |cp, what|
      gid = f.glyph_id(cp)
      gid.should_not eq(0), "#{what} is not in the cmap at all"
      f.contours(gid).should_not eq(0), "#{what} maps to glyph #{gid}, which has no outline — it would render blank"
      f.advances[gid].should eq(1229), "#{what} carries the donor's advance instead of Cousine's"
    end
  end

  # THE TEXT AND THE FILE CANNOT DRIFT APART.
  #
  # FONT_ATTRIBUTION is what a consumer's About box shows, and it is a claim ABOUT this file. embrace
  # hardcoded its own version of it and the claim went stale the day the font was modified — it still
  # said "version 1.21, Apache 2.0" of a font that by then also carried a DejaVu glyph under the
  # Bitstream Vera license. So the claim is checked against the font's own name table rather than
  # against a human remembering to update it.
  it "says about the shipped font only what the shipped font says about itself" do
    f = TtfReader.new(FONT_PATH)
    text = CrymbleUI::SFMLRenderer::FONT_ATTRIBUTION.join(" ")

    version = f.name_record(5).not_nil!
    text.should contain("version 1.21"),
      "the attribution names no version matching the font's own #{version.inspect}"
    version.should contain("1.21")

    # The font carries a merged glyph, so the notice must name where it came from and under what.
    if f.glyph_id(0x21BA) != 0
      text.should contain("modified"),
        "the font is modified (it has U+21BA) but the attribution does not say so"
      text.should contain("DejaVu Sans Mono"),
        "U+21BA is in the font but its donor is not named in the attribution"
      text.should contain("Bitstream Vera"),
        "the DejaVu glyph is used under the Bitstream Vera license, which the attribution omits"
      f.name_record(0).not_nil!.should contain("Bitstream"),
        "the FONT ITSELF must carry the Bitstream notice — FONTS.md does not survive read_file embedding"
      f.name_record(3).not_nil!.should_not eq("1.21;MONO;Cousine-Regular"),
        "the modified font still claims upstream's unique identifier"
    end
  end
end
