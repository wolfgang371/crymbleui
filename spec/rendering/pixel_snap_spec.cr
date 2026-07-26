require "spec"
require "../../src/rendering/pixel_snap"

# PixelSnap.snap is the single position-snapping used by every SFML text draw
# (CrSFMLBackend#draw_text, SFMLPaintContext#draw_text). Its load-bearing property is
# TRANSLATION INVARIANCE: snap(v + n) == snap(v) + n for integer n — a widget's text
# must land on the same device pixel whether rasterized widget-local into its own
# texture (blitted at an integer offset) or layer-local (offset added first).
# Ties-to-even rounding violates this for exact .5 fractions (parity-dependent),
# which showed up as the cursor cell's text jumping 1px when a click flipped the
# cell between the direct and texture render paths.

describe CrymbleUI::PixelSnap do
  it "keeps integers fixed" do
    [-5.0, 0.0, 3.0, 426.0].each do |v|
      CrymbleUI::PixelSnap.snap(v).should eq(v)
    end
  end

  it "is translation-invariant for integer offsets (incl. the .5-fraction regression)" do
    values = [0.25, 3.5, 4.5, 10.67, -2.5, -0.75]
    offsets = [-427, -3, -2, -1, 1, 2, 3, 425, 426]
    values.each do |v|
      offsets.each do |n|
        CrymbleUI::PixelSnap.snap(v + n).should eq(CrymbleUI::PixelSnap.snap(v) + n),
          "snap(#{v} + #{n}) must equal snap(#{v}) + #{n}"
      end
    end
  end

  it "whole() casts whole values and raises on any fractional part (exact tolerance)" do
    CrymbleUI::PixelSnap.whole(3.0).should eq(3)
    CrymbleUI::PixelSnap.whole(-2.0).should eq(-2)
    CrymbleUI::PixelSnap.whole(0.0).should eq(0)
    expect_raises(Exception, /whole-valued/) { CrymbleUI::PixelSnap.whole(3.5) }
    expect_raises(Exception, /ctx/) { CrymbleUI::PixelSnap.whole(0.1, "ctx") }
  end

  it "origin() is translation-invariant over the whole domain (floor, not truncate)" do
    values = [0.25, 3.5, 4.5, 10.67, -0.75, -2.5, -3.5]
    offsets = [-427, -3, -1, 1, 3, 425]
    values.each do |v|
      offsets.each do |n|
        CrymbleUI::PixelSnap.origin(v + n).should eq(CrymbleUI::PixelSnap.origin(v) + n)
      end
    end
    CrymbleUI::PixelSnap.origin(-0.5).should eq(-1) # floor; truncate would give 0
  end

  it "span() anchors, stays non-negative, is tight, and fixes the negative-start case" do
    [0.0, 0.5, 1.0, 2.7, 20.0].each do |l|
      CrymbleUI::PixelSnap.span(0.0, l).should eq(l.floor.to_i32) # anchor
    end
    starts = [-2.5, -0.5, 0.0, 0.3, 0.5, 7.6, 425.5]
    lens = [0.0, 0.5, 1.0, 1.5, 2.7, 20.0]
    starts.each do |s|
      lens.each do |l|
        sp = CrymbleUI::PixelSnap.span(s, l)
        (sp >= 0).should be_true
        (sp == l.floor.to_i32 || sp == l.floor.to_i32 + 1).should be_true # tightness
      end
    end
    CrymbleUI::PixelSnap.span(-0.5, 1.0).should eq(1) # the vanishing-widget fix
  end

  it "cover() is conservative: cover(len) >= span(start, len) for every placement" do
    starts = [-2.5, -0.5, 0.0, 0.3, 0.5, 7.6]
    lens = [0.0, 0.5, 1.0, 1.5, 2.7, 20.0]
    starts.each do |s|
      lens.each do |l|
        (CrymbleUI::PixelSnap.cover(l) >= CrymbleUI::PixelSnap.span(s, l)).should be_true
      end
    end
  end

  it "is monotonic" do
    xs = [-3.6, -3.5, -3.4, -0.5, 0.0, 0.49, 0.5, 0.51, 3.49, 3.5, 3.51]
    xs.each_cons_pair do |a, b|
      (CrymbleUI::PixelSnap.snap(a) <= CrymbleUI::PixelSnap.snap(b)).should be_true
    end
  end
end
