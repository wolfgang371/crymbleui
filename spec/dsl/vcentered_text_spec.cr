require "../spec_helper"

# Text vertical centering. Widgets used `(box_height - font_size) / 2` -- but font_size
# is the em size, while draw_text anchors the cap-top and measure_text sizes by the line
# height. The reserved (font_size-tall) slot over-counts the empty descender space, so
# text sat visually high. `vcentered_text_y` centers the font's REAL visual extent
# (SFML "Ag".local_bounds.height); the headless default is font_size (behaviour preserved).

# A font whose reference_height differs from the em size, to prove the helper reads it.
private class StubRefFont < CrymbleUI::Font
  def measure_text(text : String, size : Float64) : CrymbleUI::Size
    CrymbleUI::Size.new(text.size * size * 0.6, size)
  end

  def get_kerning(first : Char, second : Char, size : UInt32) : Float64
    0.0
  end

  def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
    {0.0, 0.0}
  end

  def reference_height(size : Float64) : Float64
    size * 0.5 # deliberately != size
  end
end

private class VCenterProbe
  include CrymbleUI::PrimitiveBuilder
end

describe "vcentered_text_y" do
  it "centers the font's reference visual extent, not the em font_size" do
    old = CrymbleUI::Widget.font.not_nil!
    CrymbleUI::Widget.font = StubRefFont.new
    begin
      probe = VCenterProbe.new
      size = CrymbleUI::FontSizing.calculate_size(0)
      ref_h = size * 0.5

      probe.vcentered_text_y(30.0, 0).should eq((30.0 - ref_h) / 2.0)
      # The old em-size formula would land elsewhere:
      probe.vcentered_text_y(30.0, 0).should_not eq((30.0 - size) / 2.0)
      # band_top offsets the centering band (content area / padding):
      probe.vcentered_text_y(20.0, 0, 5.0).should eq(5.0 + (20.0 - ref_h) / 2.0)
    ensure
      CrymbleUI::Widget.font = old
    end
  end

  it "falls back to font_size when the font reports no special metric (headless default)" do
    # TestFont inherits Font#reference_height => size, so headless math is unchanged.
    probe = VCenterProbe.new
    size = CrymbleUI::FontSizing.calculate_size(0)
    probe.vcentered_text_y(30.0, 0).should eq((30.0 - size) / 2.0)
  end
end

describe "PrimitiveBuilder#vcentered_block_y" do
  # Reported from the running app: growing a row by a pixel made a multi-line cell's text
  # JUMP by a whole line. The anchor was computed by two different formulas either side of
  # "does the block fit" — centred-block above, single-line-centred below — and those differ
  # by (block_extent - ref_h)/2, i.e. half a line per extra line. Continuity is the property;
  # asserting the two regimes separately cannot see a step between them.
  it "moves continuously as the band grows — no jump at the fit threshold" do
    original = CrymbleUI::Widget.font
    CrymbleUI::Widget.font = StubRefFont.new # ref_h = size/2, step = size: distinct, like production
    begin
      probe = VCenterProbe.new
      step = 0.5
      previous = nil
      h = 1.0
      while h <= 80.0
        y = probe.vcentered_block_y(h, 3, 0, 0.0)
        if prev = previous
          # The anchor may not move faster than the band it sits in. A regime change that
          # shifts it by half a line shows up here as a delta many times the step.
          (y - prev).abs.should be <= step
        end
        previous = y
        h += step
      end
    ensure
      CrymbleUI::Widget.font = original
    end
  end

  it "still equals vcentered_text_y for a single line, at every band height" do
    original = CrymbleUI::Widget.font
    CrymbleUI::Widget.font = StubRefFont.new
    begin
      probe = VCenterProbe.new
      [1.0, 5.0, 7.0, 17.0, 40.0, 120.0].each do |h|
        probe.vcentered_block_y(h, 1, 0, 0.0).should eq(probe.vcentered_text_y(h, 0, 0.0))
      end
    ensure
      CrymbleUI::Widget.font = original
    end
  end

  it "keeps line 1 fully visible once the band can hold one line" do
    # Between "one line fits" and "the whole block fits" the block is top-aligned: centring it
    # there would push line 1 off the top, which is what the user reads first.
    original = CrymbleUI::Widget.font
    CrymbleUI::Widget.font = StubRefFont.new
    begin
      probe = VCenterProbe.new
      # font_scale 0 is the 14px base, and StubRefFont reports ref_h = size * 0.5.
      ref_h = 7.0
      [8.0, 14.0, 20.0].each do |h| # one line fits, the 3-line block does not
        probe.vcentered_block_y(h, 3, 0, 0.0).should be >= 0.0
        (probe.vcentered_block_y(h, 3, 0, 0.0) + ref_h).should be <= h
      end
    ensure
      CrymbleUI::Widget.font = original
    end
  end
end
