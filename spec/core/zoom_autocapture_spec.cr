require "spec"
require "../../src/core/font_sizing"
require "../../src/core/cached"

# Reseat foundation: the zoom axis. FontSizing's zoom level is a tracked Source, so a
# Cached node that READS zoom (via zoom_factor / calculate_size / measure_text, which all bottom out in
# the zoom level) AUTO-CAPTURES the zoom edge. Zoom was the Coder gate's #1 silent-stale risk because it
# enters indirectly through font measurement — this proves the read is captured at the source.
describe "FontSizing zoom auto-capture" do
  it "a Cached node reading zoom_factor recomputes on a zoom change" do
    CrymbleUI::FontSizing.reset_zoom
    runs = 0
    node = CrymbleUI::Cached(Float64).new { runs += 1; CrymbleUI::FontSizing.zoom_factor }

    first = node.get
    runs.should eq 1
    node.get # memoized
    runs.should eq 1

    CrymbleUI::FontSizing.zoom_in.should be_true # zoom actually changed
    second = node.get
    runs.should eq 2 # auto-captured: reading zoom_factor registered the zoom edge
    second.should_not eq first
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end
end
