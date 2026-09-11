require "../spec_helper"
require "../../src/core/types"

# WCAG relative luminance / contrast, and the derived neutral a cut-content marker uses.
#
# The luminance pins below are EXTERNAL values — from the WCAG definition, not from this
# implementation. That matters more than usual here: production and the marker's own specs
# share one luminance function, so a wrong implementation would agree with itself and every
# contrast assertion in the suite would pass over an under-contrasted marker. These pins are
# the only thing standing between "we computed a number" and "the number is right".
private def approx(actual : Float64, expected : Float64, eps = 0.0005)
  (actual - expected).abs.should be < eps
end

describe "Color WCAG luminance and contrast" do
  it "matches the WCAG relative luminance of the primaries and the extremes" do
    approx(CrymbleUI::Color.from_hex("#000000").relative_luminance, 0.0)
    approx(CrymbleUI::Color.from_hex("#FFFFFF").relative_luminance, 1.0)
    approx(CrymbleUI::Color.from_hex("#FF0000").relative_luminance, 0.2126)
    approx(CrymbleUI::Color.from_hex("#00FF00").relative_luminance, 0.7152)
    approx(CrymbleUI::Color.from_hex("#0000FF").relative_luminance, 0.0722)
  end

  it "matches WCAG's own worked contrast examples" do
    white = CrymbleUI::Color.from_hex("#FFFFFF")
    black = CrymbleUI::Color.from_hex("#000000")
    # The maximum possible ratio, and the canonical 4.5:1 boundary grey.
    approx(white.contrast_ratio(black), 21.0, 0.001)
    approx(black.contrast_ratio(white), 21.0, 0.001) # order-independent
    approx(CrymbleUI::Color.from_hex("#767676").contrast_ratio(white), 4.54, 0.01)
  end

  it "refuses a translucent colour instead of returning a quietly wrong number" do
    translucent = CrymbleUI::Color.new(128, 128, 128, 128)
    expect_raises(ArgumentError) { translucent.relative_luminance }
  end
end

describe "Color#contrasting_neutral" do
  it "clears its floor against EVERY neutral backdrop, after 8-bit quantisation" do
    # The quantisation is the point. Solving for the exact target luminance and rounding to
    # nearest lands at 2.977:1 in the worst case — under the floor, on a colour the maths
    # says is fine. Rounding directionally (away from the backdrop) is what makes this hold.
    worst = 21.0
    (0..255).each do |v|
      bg = CrymbleUI::Color.new(v, v, v, 255u8)
      band = bg.contrasting_neutral(4.5)
      ratio = band.contrast_ratio(bg)
      worst = ratio if ratio < worst
      ratio.should be >= 4.5
    end
    # Sanity that the sweep is tight rather than accidentally generous.
    worst.should be < 6.0
  end

  it "returns a NEUTRAL colour" do
    band = CrymbleUI::Color.from_hex("#605000").contrasting_neutral(4.5)
    band.r.should eq(band.g)
    band.g.should eq(band.b)
    band.a.should eq(255u8)
  end

  it "goes lighter on a dark backdrop and darker on a light one" do
    dark = CrymbleUI::Color.from_hex("#2D2D2D")
    light = CrymbleUI::Color.from_hex("#FFFFFF")
    dark.contrasting_neutral(4.5).relative_luminance.should be > dark.relative_luminance
    light.contrasting_neutral(4.5).relative_luminance.should be < light.relative_luminance
  end

  it "handles the diff-cell backdrop embrace actually paints" do
    # #605000 is embrace's DIFF_HIGHLIGHT_COLOR. Only the lighter branch is valid here
    # (the darker target is negative), and the directional ceil is what keeps it above the
    # floor: channel 195 gives 4.5048:1, while rounding to 194 would give 4.4576:1 — under.
    diff = CrymbleUI::Color.from_hex("#605000")
    band = diff.contrasting_neutral(4.5)
    band.contrast_ratio(diff).should be >= 4.5
    band.r.should eq(195u8)
  end

  it "raises rather than return a colour that misses an unsatisfiable floor" do
    # The two branches stop meeting once min^2 > 21, i.e. above ~4.5826: for a mid-luminance
    # backdrop neither a lighter nor a darker neutral can reach the ratio. Returning a
    # best-effort colour there would silently break the caller's floor.
    expect_raises(ArgumentError) do
      CrymbleUI::Color.from_hex("#808080").contrasting_neutral(7.0)
    end
  end
end
