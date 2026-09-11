require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

# Field report 2026-09-05: a group label scrolled away with its first row and only became sticky
# after several clicks — the opposite order from correct behaviour, which pins first and releases
# at the end of the span.
#
# The span's first row was TALLER THAN THE VIEWPORT (a multi-line cell under auto-size). Only that
# one constituent is then visible, and `visible_count > 1` reads "one left, let it scroll off" —
# the branch meant for the LAST row of a group. It cannot tell one huge constituent at the START
# of a span from one small constituent at its END, and those need opposite treatment.
private ROW0 = 123 # a six-line cell
private REST = 23

private def tall_view(scroll : Float64, viewport : Float64 = 60.0)
  sizes = [ROW0, REST, REST, REST]
  cum = [0, ROW0, ROW0 + REST, ROW0 + 2 * REST, ROW0 + 3 * REST]
  CrymbleUI::Widgets::VirtualMatrix::StickyMath::AxisView.new(
    sizes: sizes, cum: cum, ruler_offset: 20.0, sticky_extent: 20.0,
    viewport_extent: viewport, scroll_q: scroll, shifted: nil,
    park: CrymbleUI::VirtualMatrix::OFFSCREEN_PARK)
end

describe "a compound whose constituent is taller than the viewport" do
  it "pins while the span still continues below, even with ONE constituent visible" do
    # scroll 30: only row 0 (123px) intersects a 60px viewport. Measured before the fix:
    # pos=-10.0 extent=123.0 — the full box, unclamped, scrolling away at content speed.
    pos, extent = CrymbleUI::Widgets::VirtualMatrix::StickyMath.compound_axis(
      tall_view(30.0), 0, 3, 20.0)
    pos.should eq(20.0), "expected the box pinned at the sticky boundary, got #{pos}"
    extent.should be <= 40.0, "expected the VISIBLE slice, got the full span #{extent}"
  end

  it "still lets the span go once its LAST constituent is the only one left" do
    # The branch that must survive: at the end of the group the label leaves with the last row
    # instead of sticking forever. scroll 180 puts row 3 alone in view.
    pos, extent = CrymbleUI::Widgets::VirtualMatrix::StickyMath.compound_axis(
      tall_view(180.0), 0, 3, 20.0)
    extent.should eq(REST.to_f64), "the last row must scroll off at its own size, got #{extent}"
    pos.should be < 20.0, "the last row must scroll PAST the boundary, got #{pos}"
  end

  it "pins normally when several constituents are visible (control)" do
    pos, extent = CrymbleUI::Widgets::VirtualMatrix::StickyMath.compound_axis(
      tall_view(120.0), 0, 3, 20.0)
    pos.should eq(20.0)
    extent.should be <= 40.0
  end
end
