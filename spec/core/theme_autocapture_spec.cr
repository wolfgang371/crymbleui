require "spec"
require "../../src/core/theme"
require "../../src/core/cached"

# Reseat foundation. Theme.current is a tracked Source, so a Cached node that READS
# it during recompute AUTO-CAPTURES the theme edge (no hand-declared dependency). This is the first
# integration of the auto-capture core with the real global Theme — and the mechanism the reseat
# uses to make theme-recolor correct-by-construction (reading the colour IS declaring the theme edge).
describe "Theme.current auto-capture" do
  it "a Cached node reading Theme.current recomputes on Theme.set" do
    CrymbleUI::Theme.set(:light)
    runs = 0
    node = CrymbleUI::Cached(CrymbleUI::Color).new { runs += 1; CrymbleUI::Theme.current.panel_background }

    first = node.get
    runs.should eq 1
    node.get # memoized — no recompute
    runs.should eq 1

    CrymbleUI::Theme.set(:dark)
    second = node.get
    runs.should eq 2 # auto-captured: reading Theme.current registered the theme edge
    second.should_not eq first
  ensure
    CrymbleUI::Theme.set(:light)
  end
end
