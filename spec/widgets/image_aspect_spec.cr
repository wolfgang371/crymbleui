require "../spec_helper"
require "../../src/widgets/image"

# AN IMAGE GIVEN BOTH DIMENSIONS DECLARES AN ASPECT RATIO, AND A SMALLER BOX MUST NOT BREAK IT.
#
# Wolfgang, 2026-09-17, narrowing the About dialog: the H3O logo "gets distorted (rather than either
# cropped or panel staying at minimum width)". measure() clamped each axis on its own —
# `w = explicit_width || max_width`, `h = explicit_height || max_height`, then constrain — so a box
# narrower than the request kept the requested HEIGHT and the picture was stretched to fill it.
#
# It needs no knowledge of the file to get this right: a caller passing width AND height has stated
# the ratio it wants, whatever the pixels behind it are. The About box asks for 655x655 of an 800x800
# logo, so the distortion was visible at EVERY window size, not only narrow ones — measured 15% even
# at a comfortably wide panel, because the available HEIGHT was the binding constraint there.
describe "Image, asked for both dimensions" do
  it "keeps its declared aspect ratio when the box is smaller than requested" do
    img = CrymbleUI::Image.new(CrymbleUI::ImageSource.new("logo", nil), width: 655.0, height: 655.0)

    { {900.0, 570.0}, {645.0, 285.0}, {370.0, 285.0}, {370.0, 570.0} }.each do |(mw, mh)|
      size = img.measure(CrymbleUI::BoxConstraints.new(0.0, mw, 0.0, mh))
      (size.width / size.height).should be_close(1.0, 0.01),
        "a square image in a #{mw.round.to_i}x#{mh.round.to_i} box came out #{size.width.round(1)}x#{size.height.round(1)}"
      # ...and it must FIT, not merely keep its shape.
      size.width.should be <= mw + 0.01
      size.height.should be <= mh + 0.01
    end
  end

  it "does not enlarge past what was asked for when the box is bigger" do
    img = CrymbleUI::Image.new(CrymbleUI::ImageSource.new("logo", nil), width: 100.0, height: 50.0)
    size = img.measure(CrymbleUI::BoxConstraints.new(0.0, 4000.0, 0.0, 4000.0))
    size.width.should eq(100.0)
    size.height.should eq(50.0)
  end

  it "leaves a one-sided request alone, having no declared ratio to keep" do
    # width only: the height still takes what is available, which is the documented behaviour of
    # the single-dimension form and is what fills a row.
    img = CrymbleUI::Image.new(CrymbleUI::ImageSource.new("logo", nil), width: 100.0)
    size = img.measure(CrymbleUI::BoxConstraints.new(0.0, 900.0, 0.0, 300.0))
    size.width.should eq(100.0)
    size.height.should eq(300.0)
  end

  it "does not volunteer to be narrower than the size it asked for" do
    # WindowPanel decides how far it may be dragged from its content's min_intrinsic_width. Widget's
    # default answers by measuring with an unbounded width, which — once measure scales both axes
    # together — is limited by the available HEIGHT. That collapsed the panel's floor and let the
    # content reflow on every drag, which is what surfaced the ghosting: a viewport_cache layer has
    # repair for scroll and none for reflow.
    img = CrymbleUI::Image.new(CrymbleUI::ImageSource.new("logo", nil), width: 655.0, height: 655.0)
    [574.0, 400.0, 284.0].each do |content_h|
      img.min_intrinsic_width(content_h).should eq(655.0),
        "a short container (#{content_h.round.to_i}px) made the image offer to be narrower than it asked for"
    end
  end
end
