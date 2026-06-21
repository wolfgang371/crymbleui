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
