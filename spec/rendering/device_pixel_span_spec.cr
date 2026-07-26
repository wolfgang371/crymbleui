require "../spec_helper"
require "../../src/testing/test_renderer"

# The vanishing-widget bug, pinned behaviorally on the PUBLIC device_pixel_span seam:
# a widget spanning layer-local [-0.5, 0.5) genuinely covers device pixel 0, but
# truncate-both-edges computed span 0 — and render_single_widget drops any widget
# with width <= 0, so a 1px hairline scrolled half past the top/left edge VANISHED
# at fractional zoom. Floor-both-edges (PixelSnap.span) yields the correct 1.

describe "device_pixel_span" do
  it "gives a 1px widget at a negative fractional start its pixel (was 0 → dropped)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(10, 10)
    renderer.device_pixel_span(-0.5, 1.0).should eq(1)
  end

  it "keeps exact tiling for adjacent siblings across a negative start" do
    renderer = CrymbleUI::Testing::TestRenderer.new(10, 10)
    a = renderer.device_pixel_span(-0.5, 1.0)
    b = renderer.device_pixel_span(0.5, 2.0)
    (a + b).should eq(renderer.device_pixel_span(-0.5, 3.0))
  end
end
