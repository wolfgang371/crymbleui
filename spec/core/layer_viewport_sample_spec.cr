require "../spec_helper"

# Viewport-cache sampling math — THE single source of truth for "where
# inside an oversized layer buffer does the visible viewport start".
# Extracted from composite_viewport_cache_layer so the live compositor
# and capture_composited_frame can never diverge again: the 2026-06-05
# "VirtualMatrix content offset" hunt ended with correct buffers, a
# correct live compositor — and a capture function that plain-blitted
# viewport-cache layers from (0,0), shifting every captured PNG by the
# cache margin. The instrument was the bug.
describe "Layer#viewport_sample_origin" do
    it "compensates the buffer origin (cache margin) at rest" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(8.0, 8.0, 684.0, 344.0))
        layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(-100.0, -100.0))
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({100, 100})
    end

    it "adds the scroll offset" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(-100.0, -100.0))
        layer.scroll_offset = CrymbleUI::Vec2.new(30.0, 50.0)
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({130, 150})
    end

    it "clamps to the valid buffer region" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(-100.0, -100.0))
        layer.scroll_offset = CrymbleUI::Vec2.new(10_000.0, 10_000.0)
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({884 - 684, 544 - 344})
    end

    it "degenerates safely when the buffer is smaller than the viewport" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(-100.0, -100.0))
        layer.viewport_sample_origin(400, 200, 684, 344).should eq({0, 0})
    end

    it "is the identity for origin-anchored, unscrolled layers" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0))
        layer.viewport_sample_origin(300, 300, 100, 100).should eq({0, 0})
    end
end

# compute_buffer_origin is the sole writer — always whole, always fitting so the reader never clamps.
describe "Layer#compute_buffer_origin" do
    it "keeps a whole, FITTING origin at zero margin (M=0) at fractional scroll" do
        # Backend exactly ceil(viewport) on both axes → zero margin, the empty integer-range case where the
        # old writer skipped its clamp and left a cache_extent multiple → the composite clamped → a shift.
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 468.0, 438.0))
        layer.viewport_cache = true
        layer.cache_extent = 100.0
        layer.scroll_offset = CrymbleUI::Vec2.new(250.5, 90.5)

        origin = layer.compute_buffer_origin(468, 438)
        origin.x.should eq(250.0) # floor(scroll.x); buggy skip kept quantized 200 → 50px shift
        origin.y.should eq(90.0)  # floor(scroll.y); buggy kept 0

        layer.set_buffer_origin_for_test(origin)
        layer.viewport_fits_buffer?(468, 438).should be_true # the one reader must not clamp → no shift
    end

    it "returns a whole floor(scroll) origin when cache_extent is 0" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0))
        layer.viewport_cache = true
        layer.cache_extent = 0.0
        layer.scroll_offset = CrymbleUI::Vec2.new(30.5, 40.7)

        origin = layer.compute_buffer_origin(100, 100)
        origin.x.should eq(30.0)
        origin.y.should eq(40.0)
        layer.set_buffer_origin_for_test(origin)
        layer.viewport_fits_buffer?(100, 100).should be_true
    end
end

# viewport_fits_buffer? is the recenter gate, DERIVED from the one composite reader — so it agrees
# with the ceil-based composite clamp, unlike the old float+0.5-eps gate that left a near-capacity band
# unrecentered. This witness is where the two verdicts DIVERGE (not an A == A tautology).
describe "Layer#viewport_fits_buffer? (recenter gate, Finding 2)" do
    it "reports NO-fit in the near-capacity band the old float+eps gate wrongly accepted" do
        # viewport 683.3 wide in a 700 buffer, (scroll - origin) = 17.1. The composite reads at
        # (700 - ceil(683.3)) = 16 and clamps 17 → 16 (a 1px shift). The OLD gate accepted this
        # (17.1 ≤ 700 - 683.3 + 0.5 = 17.2) and skipped the recenter, so the composite shifted.
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 683.3, 100.0))
        layer.viewport_cache = true
        layer.set_buffer_origin_for_test(CrymbleUI::Vec2.new(0.0, 0.0))
        layer.scroll_offset = CrymbleUI::Vec2.new(17.1, 0.0)

        layer.viewport_fits_buffer?(700, 700).should be_false # matches the composite's ceil clamp → recenter fires

        # The OLD float+0.5-eps gate DISAGREED — it called this "fits" and skipped the recenter:
        viewport_in_buffer = layer.scroll_offset.x - layer.buffer_origin.x # 17.1
        max_valid = 700.0 - layer.bounds.width                             # 16.7
        old_gate_fits = viewport_in_buffer >= -0.5 && viewport_in_buffer <= max_valid + 0.5
        old_gate_fits.should be_true # documents the divergence — this assertion is what makes the test non-tautological
    end
end

# across the M=1 → M=0 crossing (the buffer margin collapsing to zero) the content coordinate at
# the viewport's LEFT edge (buffer_origin + viewport_sample_origin) must NOT jump — even though
# buffer_origin itself legitimately moves ±1px. This is the frame-to-frame continuity that keeps the
# leading edge from tearing when a resize shrinks the margin.
describe "Layer leading-edge continuity across M=1 → M=0" do
    it "keeps content-at-left-edge = floor(scroll) for both a 299 (M=1) and 300 (M=0) viewport" do
        {299, 300}.each do |vw|
            layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, vw.to_f64, 100.0))
            layer.viewport_cache = true
            layer.cache_extent = 100.0
            layer.scroll_offset = CrymbleUI::Vec2.new(250.0, 0.0)

            origin = layer.compute_buffer_origin(300, 300)
            origin.x.should eq(origin.x.round) # whole-valued (else render/composite truncate-disagree → seam)
            layer.set_buffer_origin_for_test(origin)

            sample = layer.viewport_sample_origin(300, 300, vw, 100)
            (origin.x + sample[0]).should eq(250.0) # content at the viewport's left edge — stable across the crossing
            layer.viewport_fits_buffer?(300, 300).should be_true
        end
    end
end
