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
        layer.buffer_origin = CrymbleUI::Vec2.new(-100.0, -100.0)
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({100, 100})
    end

    it "adds the scroll offset" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.buffer_origin = CrymbleUI::Vec2.new(-100.0, -100.0)
        layer.scroll_offset = CrymbleUI::Vec2.new(30.0, 50.0)
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({130, 150})
    end

    it "clamps to the valid buffer region" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.buffer_origin = CrymbleUI::Vec2.new(-100.0, -100.0)
        layer.scroll_offset = CrymbleUI::Vec2.new(10_000.0, 10_000.0)
        layer.viewport_sample_origin(884, 544, 684, 344).should eq({884 - 684, 544 - 344})
    end

    it "degenerates safely when the buffer is smaller than the viewport" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 684.0, 344.0))
        layer.buffer_origin = CrymbleUI::Vec2.new(-100.0, -100.0)
        layer.viewport_sample_origin(400, 200, 684, 344).should eq({0, 0})
    end

    it "is the identity for origin-anchored, unscrolled layers" do
        layer = CrymbleUI::Layer.new("t", CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0))
        layer.viewport_sample_origin(300, 300, 100, 100).should eq({0, 0})
    end
end
