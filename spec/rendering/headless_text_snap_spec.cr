require "spec"
require "../../src/testing/test_render_backend"
require "../../src/testing/test_font"
require "../../src/rendering/pixel_snap"

# The headless backend must place text ink at the SAME device pixel the SFML backend
# does: PixelSnap.snap (half-up) of the draw position. It truncated instead, which
# put headless ink one pixel up/left of production whenever the position's fraction
# was ≥ .5 — making the whole ties-even/parity defect class invisible to headless
# specs (instrument-matches-production law).

describe "headless draw_text position snapping" do
  it "inks at PixelSnap.snap of a fractional draw position (not at its truncation)" do
    backend = CrymbleUI::Testing::TestRenderBackend.new(40, 30)
    color = CrymbleUI::Color.new(255_u8, 0_u8, 0_u8, 255_u8)
    # 'A' (0x41): LSB0 set → left stripe at the text origin. Fraction .5/.7 → snap
    # lands one pixel below/right of truncation.
    backend.draw_text("A", CrymbleUI::Vec2.new(10.7, 5.5), color, 12.0)

    sx = CrymbleUI::PixelSnap.snap(10.7).to_i # 11
    sy = CrymbleUI::PixelSnap.snap(5.5).to_i  #  6
    backend.get_pixel(sx, sy).should eq(color)      # ink at the snapped origin
    backend.get_pixel(sx - 1, sy - 1).should_not eq(color) # not at the truncated one

    # sub-.5 fraction rounds DOWN — pins snap uniquely against a ceil regression
    b2 = CrymbleUI::Testing::TestRenderBackend.new(40, 30)
    b2.draw_text("A", CrymbleUI::Vec2.new(10.3, 5.3), color, 12.0)
    b2.get_pixel(10, 5).should eq(color)      # snap(10.3)=10; ceil would leave row 5/col 10 empty
    b2.get_pixel(12, 5).should_not eq(color)  # right of the 2px stripe (10..11); ceil would ink 11..12
  end

  it "advances a hard break by the FONT's line slot, snapped from the origin, at every size" do
    # The y-advance belongs to this file because it is the same contract: where the headless
    # backend puts text ink. Swept at two sizes because the slot and the glyph's ink height
    # come from different formulas — equal at 14, divergent elsewhere — and a step taken from
    # the ink height instead would pass at one size and drift at the other.
    color = CrymbleUI::Color.new(255_u8, 0_u8, 0_u8, 255_u8)

    {12.0, 20.0}.each do |size|
      backend = CrymbleUI::Testing::TestRenderBackend.new(60, 90)
      origin = CrymbleUI::Vec2.new(3.4, 2.6)
      backend.draw_text("A\nA", origin, color, size)

      step = CrymbleUI::Testing::TestFont.line_step(size)
      sx = CrymbleUI::PixelSnap.snap(origin.x).to_i
      row0 = CrymbleUI::PixelSnap.snap(origin.y).to_i
      row1 = CrymbleUI::PixelSnap.snap(origin.y + step).to_i

      # Line 2 lands one SLOT down — snapped from the origin, not accumulated, so a long
      # block cannot drift a row from what the font's `k * step` predicts.
      backend.get_pixel(sx, row0).should eq(color)
      backend.get_pixel(sx, row1).should eq(color)

      # ...and back at the origin COLUMN. `x += char_width` across the break would put
      # line 2's stripe one glyph to the right, where nothing may be inked on its row.
      char_width = (size * 0.6).to_i.clamp(4, 20)
      backend.get_pixel(sx + char_width, row1).should_not eq(color)
    end
  end
end
