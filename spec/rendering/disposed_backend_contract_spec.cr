require "../spec_helper"
require "../../src/testing/test_render_backend"

# THE POST-RELEASE CONTRACT.
#
# Releasing a backend is now real, so using one afterwards is a real defect: under SFML the payload
# is a destroyed driver texture, and reading it is a use-after-free rather than a no-op. This pins
# what is legal after release and what must fail loudly.
#
# The split is not arbitrary. Anything answerable from Crystal-side state alone stays legal —
# width, height, disposed?, the counters — because the test harness aggregates those over
# registries that deliberately outlive the backends in them (TestRenderer's @layer_backends is
# append-only by design). Anything that touches the PAYLOAD raises.
#
# `dispose` itself is idempotent by contract: teardown paths legitimately reach the same backend
# twice — the orphan sweep and the discarded-generation walk both reach layer-hosted widgets — and
# a double-release raise would convert correct redundancy into a crash.

private def fresh : CrymbleUI::Testing::TestRenderBackend
  CrymbleUI::Testing::TestRenderBackend.new(20, 10)
end

describe "disposed backend contract" do
  it "keeps answerable-from-Crystal-state operations legal after release" do
    b = fresh
    b.dispose

    # These must NOT raise: the harness reads them over registries that outlive their backends.
    b.disposed?.should be_true
    b.width.should eq 20
    b.height.should eq 10
    b.primitive_count.should eq 0
    b.inspect.should_not be_empty
  end

  it "is idempotent — teardown paths legitimately reach the same backend twice" do
    b = fresh
    b.dispose
    b.dispose # must not raise
    b.disposed?.should be_true
  end

  it "raises a distinguished error on every operation that touches the payload" do
    # One representative per family; the guard is the same shared helper in all of them.
    {
      "clear"                  => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.clear(CrymbleUI::Color.new(0, 0, 0, 255)); nil },
      "fill_rect"              => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 2.0, 2.0), CrymbleUI::Color.new(1, 2, 3, 255)); nil },
      "get_pixel"              => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.get_pixel(0, 0); nil },
      "set_pixel"              => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.set_pixel(0, 0, CrymbleUI::Color.new(1, 2, 3, 255)); nil },
      "capture_region_pixels"  => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.capture_region_pixels(0, 0, 2, 2); nil },
      "push_clip"              => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 2.0, 2.0)); nil },
      "display"                => ->(x : CrymbleUI::Testing::TestRenderBackend) { x.display; nil },
    }.each do |name, op|
      b = fresh
      b.dispose
      expect_raises(CrymbleUI::DisposedBackendError, /#{name}/) { op.call(b) }
    end
  end

  # The shape the guard exists for. The receiver is perfectly healthy and its own flag says so —
  # only the OTHER side is dead. Every real instance of this in the renderer is a live layer
  # blitting from a cell's released surface.
  it "raises when a LIVE receiver blits from a RELEASED source" do
    dest = fresh
    source = fresh
    source.dispose

    dest.disposed?.should be_false, "the receiver must be live, or this proves nothing"
    expect_raises(CrymbleUI::DisposedBackendError, /source/) { dest.blit(source, 0, 0) }
    expect_raises(CrymbleUI::DisposedBackendError, /source/) { dest.blit_region(source, 0, 0, 2, 2, 0, 0) }
  end

  it "raises when a LIVE source writes into a RELEASED target" do
    source = fresh
    target = fresh
    target.dispose

    source.disposed?.should be_false, "the source must be live, or this proves nothing"
    expect_raises(CrymbleUI::DisposedBackendError, /target/) { source.blit_to(target, 0, 0) }
    expect_raises(CrymbleUI::DisposedBackendError, /target/) { source.blit_region_to(target, 0, 0, 2, 2, 0, 0) }
  end

  it "leaves a live backend entirely unaffected" do
    # Non-vacuity for the whole file: if the guard fired on live backends, every assertion above
    # would pass for the wrong reason and the renderer would be dead in the water.
    b = fresh
    b.clear(CrymbleUI::Color.new(10, 20, 30, 255))
    b.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 4.0, 4.0), CrymbleUI::Color.new(9, 9, 9, 255))
    b.get_pixel(0, 0).should_not be_nil
    b.disposed?.should be_false
  end
end
