require "spec"
require "../../src/rendering/clip_math"

# ClipMath.device_box is the ONE conversion from a clip stack to a device-pixel box.
# Both backends call it, so these examples are the contract for both: CrSFMLBackend
# turns the box into the view scissor's factors, TestRenderBackend compares written
# pixels against it. They used to derive it separately and drifted — three stack-collapse
# semantics across two files, and a rounding rule that clipped one column narrower
# headless than in production.
#
# The literals are deliberate cross-references: 298.666 -> 299 is the "Historical seam
# note" width, and 61.5/41.5 -> 62x42 is case O of tools/clip-containment-probe.cr, the
# SFML-side witness. Same numbers on both sides of the harness.
describe CrymbleUI::ClipMath do
  r = ->(x : Float64, y : Float64, w : Float64, h : Float64) { CrymbleUI::Rect.new(x, y, w, h) }

  describe "empty stack" do
    it "is nil — no clip, not a zero-sized one" do
      CrymbleUI::ClipMath.device_box([] of CrymbleUI::Rect).should be_nil
    end
  end

  describe "the extent is a conservative BOUND (cover), never round-to-nearest" do
    it "covers a fractional width rather than truncating it (the Historical seam)" do
      # 298.666 must yield 299. Truncating gives 298 — the column the compositor samples
      # (it uses cover too) but nothing ever wrote, i.e. the seam-note defect verbatim.
      box = CrymbleUI::ClipMath.device_box([r.call(0.0, 0.0, 298.666, 10.0)]).not_nil!
      box.should eq({0, 0, 299, 10})
    end

    it "matches the SFML witness's case-O literals" do
      box = CrymbleUI::ClipMath.device_box([r.call(0.0, 0.0, 61.5, 41.5)]).not_nil!
      box.should eq({0, 0, 62, 42})
    end

    it "leaves a whole-valued rect exactly where it is" do
      box = CrymbleUI::ClipMath.device_box([r.call(37.0, 23.0, 61.0, 41.0)]).not_nil!
      box.should eq({37, 23, 98, 64})
    end
  end

  describe "the origin FLOORS (not truncates), so it is translation-invariant across zero" do
    it "floors a negative fractional origin" do
      # origin(-0.5) = -1, cover(10.2) = 11 -> far edge 10. Truncation would give 0..9.
      box = CrymbleUI::ClipMath.device_box([r.call(-0.5, -0.5, 10.2, 10.2)]).not_nil!
      box.should eq({-1, -1, 10, 10})
    end
  end

  describe "KNOWN LIMITATION — under-covers by a pixel at a FRACTIONAL origin" do
    it "is cover(far - near), not ceil(far) - floor(near)" do
      # near 0.9, far 1.1: the true covering box is [0,2), this yields [0,1). Inherited
      # deliberately from the pre-existing trunc+ceil so the change moves no pixel, and
      # harmless for the clip that matters (the layer clip's origin is 0). Pinned so it
      # stays a recorded decision rather than a surprise — and so that anyone who fixes
      # it has to come here and say so.
      box = CrymbleUI::ClipMath.device_box([r.call(0.9, 0.9, 0.2, 0.2)]).not_nil!
      box.should eq({0, 0, 1, 1})
    end
  end

  describe "the stack collapses to its INTERSECTION" do
    it "takes max-of-origins and min-of-far-edges" do
      box = CrymbleUI::ClipMath.device_box([
        r.call(0.0, 0.0, 100.0, 100.0),
        r.call(50.0, 40.0, 100.0, 100.0),
      ]).not_nil!
      box.should eq({50, 40, 100, 100})
    end

    it "lets an inner clip only SHRINK what an outer one allows, never widen it" do
      inner_wider = CrymbleUI::ClipMath.device_box([
        r.call(10.0, 10.0, 20.0, 20.0),
        r.call(0.0, 0.0, 100.0, 100.0),
      ]).not_nil!
      inner_wider.should eq({10, 10, 30, 30})
    end

    it "intersects in FLOAT and converts ONCE — not round-then-intersect" do
      # Rounding each rect first would give far edge trunc(0.4+99.4)=99 then intersect;
      # intersecting first gives right = 99.8 -> origin(0.4)=0 + cover(99.4)=100.
      box = CrymbleUI::ClipMath.device_box([
        r.call(0.4, 0.0, 99.4, 10.0),
        r.call(0.0, 0.0, 99.8, 10.0),
      ]).not_nil!
      box.should eq({0, 0, 100, 10})
    end
  end

  describe "an empty intersection clamps to ZERO extent" do
    it "never yields a negative extent" do
      # A negative extent reaching glScissor is GL_INVALID_VALUE: the call is DROPPED and
      # the previous scissor stays live — a silent wrong-clip, not a no-op.
      box = CrymbleUI::ClipMath.device_box([
        r.call(0.0, 0.0, 40.0, 40.0),
        r.call(100.0, 100.0, 40.0, 40.0),
      ]).not_nil!
      box.should eq({100, 100, 100, 100})
      (box[2] - box[0]).should eq(0)
      (box[3] - box[1]).should eq(0)
    end
  end

  describe "a NaN coordinate DETONATES" do
    it "raises rather than silently picking the non-NaN operand" do
      # A NaN rect is a layout bug. Both backends fail at push time, alike and loudly —
      # the same stance as TestRenderBackend's negative-dimension raise.
      expect_raises(Exception) do
        CrymbleUI::ClipMath.device_box([r.call(Float64::NAN, 0.0, 10.0, 10.0)])
      end
    end
  end
end
