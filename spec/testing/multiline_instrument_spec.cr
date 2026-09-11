require "../spec_helper"
require "../../src/testing/test_font"
require "../../src/testing/test_render_backend"

# The headless text instruments must model LINE STRUCTURE.
#
# Until they do, no multi-line pixel or metric claim is readable: `TestFont#measure_text`
# counts `\n` as a glyph and reports ONE line of height, and `TestRenderBackend#draw_text`
# lays every character on one row (`x += char_width`, y never advances), so a 3-line string
# inks a single line. An instrument that cannot contain the phenomenon reports its ABSENCE.
#
# Probe discipline: every "there is no ink here" claim is preceded by a REACHABILITY claim
# proving the probe region can be inked at all — a probe that misses the glyph model yields
# green examples that prove nothing. The character is derived from the backend's own stripe
# model rather than assumed: 'C' (0x43) has both low bits set, so it inks a LEFT stripe at
# the glyph origin and a RIGHT stripe at its far edge.

private ONE_LINE   = "Alice"
private THREE_LINE = "Alice\nBob\nCarol"

# The backend's stripe model, derived here rather than hard-coded, so a change to
# `draw_text`'s geometry breaks these examples loudly instead of silently missing the ink.
private def char_box(size : Float64) : Tuple(Int32, Int32, Int32)
  char_width = (size * CrymbleUI::Testing::TestFont::CHAR_WIDTH_RATIO).to_i.clamp(4, 20)
  # Mirrors the backend, INCLUDING the cap that keeps ink from exceeding the line slot —
  # they are equal at size 14 and diverge below 6, so a probe that omitted the cap would
  # measure the wrong rows exactly where the instrument is most fragile.
  char_height = size.to_i.clamp(6, 30)
  step = CrymbleUI::Testing::TestFont.line_step(size)
  char_height = step.to_i if step < char_height
  stripe_width = (char_width // 3).clamp(1, 4)
  {char_width, char_height, stripe_width}
end

private def inked_in_band?(backend, y_lo : Int32, y_hi : Int32) : Bool
  (y_lo...y_hi).any? do |y|
    next false if y < 0 || y >= backend.height
    (0...backend.width).any? { |x| backend.get_pixel(x, y) != CrymbleUI::Color.new(255, 255, 255, 255) }
  end
end

describe "the headless text instruments model line structure" do
  describe "TestFont#measure_text" do
    it "reports a 3-line string as 3 lines tall" do
      font = CrymbleUI::Testing::TestFont.new
      one = font.measure_text(ONE_LINE, 14.0)
      three = font.measure_text(THREE_LINE, 14.0)

      # Reachability: the single-line measurement must be non-degenerate, or "3x" is 0 == 0.
      one.height.should be > 0.0

      three.height.should eq(one.height * 3.0)
    end

    it "measures width as the WIDEST line, not the whole string" do
      font = CrymbleUI::Testing::TestFont.new
      # "Alice" is the widest of the three lines, so the block is exactly as wide as it.
      # Today the two `\n` are counted as glyphs, making the block wider than any line.
      font.measure_text(THREE_LINE, 14.0).width.should eq(font.measure_text(ONE_LINE, 14.0).width)
    end

    it "leaves every single-line string byte-identical" do
      # The whole cross-widget blast radius rests on this: only strings containing a break move.
      font = CrymbleUI::Testing::TestFont.new
      font.measure_text(ONE_LINE, 14.0).width.should eq(
        ONE_LINE.size * 14.0 * CrymbleUI::Testing::TestFont::CHAR_WIDTH_RATIO)
      font.measure_text(ONE_LINE, 14.0).height.should eq(14.0)
      font.measure_text("", 14.0).height.should eq(14.0) # one (empty) line, not zero
    end
  end

  describe "TestRenderBackend#draw_text" do
    it "advances y per line and resets x, so a 3-line string inks 3 separate bands" do
      size = 14.0
      _cw, ch, _sw = char_box(size)
      backend = CrymbleUI::Testing::TestRenderBackend.new(60, 60)

      # REACHABILITY FIRST: one line must ink its own band, or the "no ink" probes below
      # would pass on a backend that draws nothing at all.
      backend.draw_text("C", CrymbleUI::Vec2.new(0.0, 0.0), CrymbleUI::Color.new(0, 0, 0, 255), size)
      inked_in_band?(backend, 0, ch).should be_true

      backend2 = CrymbleUI::Testing::TestRenderBackend.new(60, 60)
      backend2.draw_text("C\nC\nC", CrymbleUI::Vec2.new(0.0, 0.0), CrymbleUI::Color.new(0, 0, 0, 255), size)

      # Three bands, one per line. Today all three glyphs land in the first band.
      inked_in_band?(backend2, 0, ch).should be_true
      inked_in_band?(backend2, ch, ch * 2).should be_true
      inked_in_band?(backend2, ch * 2, ch * 3).should be_true
    end

    it "restarts each line at the origin x rather than continuing across" do
      size = 14.0
      cw, ch, sw = char_box(size)
      backend = CrymbleUI::Testing::TestRenderBackend.new(60, 60)
      black = CrymbleUI::Color.new(0, 0, 0, 255)
      backend.draw_text("C\nC", CrymbleUI::Vec2.new(0.0, 0.0), black, size)

      # 'C' inks a LEFT stripe at the glyph origin. Line 2's must sit at the SAME x as
      # line 1's — the property `x += char_width` across a `\n` destroys.
      line1_left = (0...sw).any? { |x| backend.get_pixel(x, 0) == black }
      line2_left = (0...sw).any? { |x| backend.get_pixel(x, ch) == black }
      line1_left.should be_true
      line2_left.should be_true

      # And nothing from line 2 may appear on line 1's row past the first glyph.
      (cw...backend.width).each do |x|
        backend.get_pixel(x, 0).should_not eq(black)
      end
    end

    it "leaves a single-line string inking exactly where it does today" do
      size = 14.0
      cw, ch, sw = char_box(size)
      backend = CrymbleUI::Testing::TestRenderBackend.new(60, 60)
      black = CrymbleUI::Color.new(0, 0, 0, 255)
      backend.draw_text("CC", CrymbleUI::Vec2.new(0.0, 0.0), black, size)

      # Second glyph still advances by one char_width; nothing wraps or drops a row.
      (0...sw).any? { |x| backend.get_pixel(x, 0) == black }.should be_true
      (cw...(cw + sw)).any? { |x| backend.get_pixel(x, 0) == black }.should be_true
      inked_in_band?(backend, ch, ch * 2).should be_false
    end
  end
end
