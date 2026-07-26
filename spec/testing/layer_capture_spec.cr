require "spec"
require "../../src/testing/layer_capture"

# Minimal direct spec for the BACKEND-GENERIC signatures of LayerCapture — the ones
# that touch no SFML and need no display: the black-pixel predicate/count and the
# tolerance compare (plus rgba_string formatting). The SFML capture paths
# (capture_layer_region / capture_layer_visible_region / capture_window_composite /
# save_layer_image) sample a real FBO and are exercised on hardware by the SFML
# parity sweep — a headless spec cannot fake a GPU texture, so they are intentionally
# NOT unit-tested here.
#
# RGBA packing: R in the high byte, (r<<24)|(g<<16)|(b<<8)|a.

private def rgba(r : Int32, g : Int32, b : Int32, a : Int32) : UInt32
  (r.to_u32 << 24) | (g.to_u32 << 16) | (b.to_u32 << 8) | a.to_u32
end

describe CrymbleUI::Testing::LayerCapture do
  describe ".is_black_pixel?" do
    it "flags an opaque window-background pixel (~40,40,40) as black" do
      CrymbleUI::Testing::LayerCapture.is_black_pixel?(rgba(40, 40, 40, 255)).should be_true
    end

    it "does NOT flag an opaque cell-background pixel (~45,50,55) as black" do
      # avg = (45+50+55)/3 = 50 >= 43 -> not black (this is the discriminator: cell
      # content vs the window gap it would leak).
      CrymbleUI::Testing::LayerCapture.is_black_pixel?(rgba(45, 50, 55, 255)).should be_false
    end

    it "does NOT flag a transparent dark pixel as black (alpha gate)" do
      CrymbleUI::Testing::LayerCapture.is_black_pixel?(rgba(40, 40, 40, 100)).should be_false
    end

    it "treats the avg<43 boundary as exclusive" do
      # avg exactly 43 must NOT count (predicate is avg < 43).
      CrymbleUI::Testing::LayerCapture.is_black_pixel?(rgba(43, 43, 43, 255)).should be_false
      CrymbleUI::Testing::LayerCapture.is_black_pixel?(rgba(42, 42, 42, 255)).should be_true
    end
  end

  describe ".count_black_pixels" do
    it "counts only the black tuples in a mixed set" do
      pixels = [
        {0, 0, rgba(40, 40, 40, 255)},  # black
        {2, 0, rgba(45, 50, 55, 255)},  # cell (not black)
        {4, 0, rgba(10, 10, 10, 255)},  # black
        {6, 0, rgba(40, 40, 40, 100)},  # transparent (not black)
      ]
      CrymbleUI::Testing::LayerCapture.count_black_pixels(pixels).should eq(2)
    end

    it "is zero for an empty set" do
      CrymbleUI::Testing::LayerCapture.count_black_pixels([] of Tuple(Int32, Int32, UInt32)).should eq(0)
    end
  end

  describe ".pixels_different?" do
    it "is false for identical colors" do
      c = rgba(45, 50, 55, 255)
      CrymbleUI::Testing::LayerCapture.pixels_different?(c, c).should be_false
    end

    it "is false within the default tolerance (per channel)" do
      CrymbleUI::Testing::LayerCapture.pixels_different?(rgba(45, 50, 55, 255), rgba(49, 54, 59, 255)).should be_false
    end

    it "is true past the tolerance on any channel" do
      CrymbleUI::Testing::LayerCapture.pixels_different?(rgba(45, 50, 55, 255), rgba(45, 50, 90, 255)).should be_true
    end

    it "ignores alpha (only RGB channels compared)" do
      CrymbleUI::Testing::LayerCapture.pixels_different?(rgba(45, 50, 55, 255), rgba(45, 50, 55, 0)).should be_false
    end
  end

  describe ".rgba_string" do
    it "formats R in the high byte" do
      CrymbleUI::Testing::LayerCapture.rgba_string(rgba(45, 50, 55, 255)).should eq("RGBA(45,50,55,255)")
    end
  end
end
