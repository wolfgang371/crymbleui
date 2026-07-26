require "../spec_helper"
require "../../src/testing/test_renderer"

# Composition CONTRACT-PIN for the slot-key arithmetic (not a behavioral RED — both
# sides share slot_axis by construction post-consolidation; this pins them against
# future divergence). The render path stamps a viewport slot as
#   round_to_layer_pixels(abs, layer_bound)  minus  whole(buffer_origin)
# and the blit-shift bookkeeping re-derives the SAME key via slot_axis. These are two
# distinct production functions; this spec holds them equal over a grid of fractional
# coords/bounds/origins — including the positive-coordinate cases where term-wise
# flooring diverges (floor(10.7)-floor(0.8)=10 vs floor(9.9)=9).
#
# The scroll-recenter SHIFT relation (old-origin keys + (dest−src) == new-origin keys)
# is exercised BEHAVIORALLY by the fractional-bounds blit-shift specs, which drive
# real recenters and assert cell-data integrity — a synthetic relation here would
# only re-derive (dest−src) from the same algebra and prove nothing.

describe "slot_axis composition contract" do
  it "equals the render-stamp key over a fractional grid (incl. positive-coord divergence cases)" do
    r = CrymbleUI::Testing::TestRenderer.new(4, 4)
    coords = [-3.5, -0.5, 0.0, 0.3, 0.8, 10.7, 100.3, 425.5]
    bounds = [-2.5, 0.0, 0.8, 10.6, 37.0]
    origins = [-100.0, 0.0, 200.0]
    coords.each do |c|
      bounds.each do |b|
        origins.each do |o|
          stamp = r.round_to_layer_pixels(c, c, b, b)[0] - o.to_i
          r.slot_axis(c, b, o).should eq(stamp),
            "slot_axis(#{c}, #{b}, #{o}) must equal the stamp key #{stamp}"
        end
      end
    end
  end
end
