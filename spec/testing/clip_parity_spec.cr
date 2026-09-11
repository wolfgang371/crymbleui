require "spec"
require "../../src/testing/test_render_backend"

# SCOPE. Every primitive that production scissors is now clipped in the instrument too,
# against the SAME device box CrSFMLBackend hands the GPU: the per-pixel path via
# `point_in_clip?`, and the BULK writers — `clear`, `fill_rect` and `blit_to`'s fast path
# — by clamping their destination once against `writable_box`.
#
# ONE example still asserts a DIVERGENCE as it behaves today rather than a contract: the
# swallowed clip-stack underflow. It says so, in place.
#
# `point_in_clip?` is private, so every case drives it through `set_pixel`/`get_pixel`.
# Two traps that would make an example vacuous: `set_pixel` bounds-checks BEFORE it clips,
# so the backend must be big enough that a rejection can only have come from the clip; and
# the default background is opaque white, so the marker must be a different colour.
describe "TestRenderBackend clip parity with CrSFMLBackend" do
  bg = CrymbleUI::Color.new(255, 255, 255, 255)
  ink = CrymbleUI::Color.new(10, 20, 30, 255)

  # Big enough on BOTH axes that 299 is in bounds — otherwise the fractional cases are
  # bounds rejections that the fix could never turn green.
  backend = -> { CrymbleUI::Testing::TestRenderBackend.new(400, 400) }
  wrote = ->(be : CrymbleUI::Testing::TestRenderBackend, x : Int32, y : Int32) do
    be.set_pixel(x, y, ink)
    be.get_pixel(x, y) == ink
  end
  # Exact-area counter. "Nothing outside" alone cannot fail on OVER-clipping, so the
  # bulk-writer cases assert the inked area exactly.
  inked = ->(be : CrymbleUI::Testing::TestRenderBackend) do
    n = 0
    400.times { |y| 400.times { |x| n += 1 if be.get_pixel(x, y) == ink } }
    n
  end

  describe "a fractional extent COVERS its last column (the Historical seam)" do
    it "writes the seam column x=298 under a clip of width 298.666" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 298.666, 300.0))
      wrote.call(be, 298, 5).should be_true
    end

    it "writes the seam ROW y=298 under a clip of height 298.666" do
      # The same case on Y. A fix that touched only the x arithmetic must fail here.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 300.0, 298.666))
      wrote.call(be, 5, 298).should be_true
    end

    it "CONTROL: the same pixel is written with no clip at all" do
      # Proves the cases above fail (before the fix) because of the CLIP, not the bounds
      # check — without this, a too-small backend would look like the same red.
      wrote.call(backend.call, 298, 5).should be_true
    end

    it "still REJECTS the pixel one past the cover edge" do
      # cover(298.666) = 299, so column 299 is outside. This is what stops an
      # over-correction from `<` to `<=`.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 298.666, 300.0))
      wrote.call(be, 299, 5).should be_false
    end

    it "does not shift a clip that is already whole-valued" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(10.0, 10.0, 20.0, 20.0))
      wrote.call(be, 29, 29).should be_true
      wrote.call(be, 30, 10).should be_false
    end
  end

  describe "nesting, popping and the empty intersection" do
    it "intersects a nested clip instead of letting the inner one replace the outer" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0))
      be.push_clip(CrymbleUI::Rect.new(50.0, 50.0, 100.0, 100.0))
      wrote.call(be, 60, 60).should be_true
      # Inside the OUTER only. If the inner had replaced the outer this would be inside
      # nothing and still rejected, so the discriminating half is the case below.
      wrote.call(be, 20, 20).should be_false
    end

    it "lets an inner clip only SHRINK the outer, never widen it" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(10.0, 10.0, 20.0, 20.0))
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 200.0, 200.0))
      # Inner-replaces-outer would accept this; intersection rejects it.
      wrote.call(be, 5, 5).should be_false
      wrote.call(be, 15, 15).should be_true
    end

    it "writes nothing at all when the stack is disjoint" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 40.0, 40.0))
      be.push_clip(CrymbleUI::Rect.new(100.0, 100.0, 40.0, 40.0))
      wrote.call(be, 20, 20).should be_false
      wrote.call(be, 110, 110).should be_false
    end

    it "restores the OUTER clip on pop — the cache cannot go stale" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0))
      be.push_clip(CrymbleUI::Rect.new(50.0, 50.0, 20.0, 20.0))
      be.pop_clip
      wrote.call(be, 90, 90).should be_true # inside the outer, outside the popped inner
      wrote.call(be, 120, 120).should be_false
    end

    it "is unclipped again once the stack empties" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.pop_clip
      wrote.call(be, 300, 300).should be_true
    end
  end

  describe "suspension" do
    it "bypasses the clip while suspended and restores the SAME box on resume" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.suspend_clip
      wrote.call(be, 50, 50).should be_true
      be.resume_clip
      wrote.call(be, 51, 51).should be_false
      wrote.call(be, 5, 5).should be_true
    end
  end

  describe "draw_rect draws all four edges, INSIDE bounds" do
    # Production draws a border as four FILLED rects positioned inside the rect, so an edge
    # sitting on the clip boundary is inside the scissor and IS drawn. The instrument used
    # to skip the leftmost column / topmost row there, modelling SFML's CENTRED
    # outline_thickness — which production replaced in 2025-12 to fix sub-pixel artifacts.
    # These two go green from ONE deletion; they are not independent regressions.
    it "keeps the left column and top row when the border sits on the clip edge" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 50.0, 50.0))
      be.draw_rect(CrymbleUI::Rect.new(0.0, 0.0, 20.0, 20.0), ink, 1.0)
      be.get_pixel(0, 10).should eq(ink)
      be.get_pixel(10, 0).should eq(ink)
      be.get_pixel(19, 10).should eq(ink)
    end

    it "keeps them with NO clip pushed at all" do
      # The sharpest form of the old defect: with no clip, `clip_left` defaulted to 0.0, so
      # `bounds.x <= 0.0` held and ANY border at x==0 silently lost its left edge.
      be = backend.call
      be.draw_rect(CrymbleUI::Rect.new(0.0, 0.0, 20.0, 20.0), ink, 1.0)
      be.get_pixel(0, 10).should eq(ink)
      be.get_pixel(10, 0).should eq(ink)
    end

    it "still drops an edge that genuinely falls outside the clip" do
      # Not the skip — set_pixel's own clip check, which is what production's scissor does.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(10.0, 10.0, 50.0, 50.0))
      be.draw_rect(CrymbleUI::Rect.new(0.0, 0.0, 40.0, 40.0), ink, 1.0)
      be.get_pixel(0, 20).should eq(bg)
      be.get_pixel(39, 20).should eq(ink)
    end
  end

  describe "RECORDED DIVERGENCES — asserted as they behave today, NOT as contracts" do
    it "swallows a clip-stack underflow that CrSFMLBackend raises on" do
      # Production's bare `@clip_stack.pop` raises IndexError; the instrument's
      # `pop if any?` absorbs it. Pinned so the difference is visible, not endorsed.
      # It has its own backlog entry.
      be = backend.call
      be.pop_clip
      wrote.call(be, 5, 5).should be_true
    end

  end

  describe "the BULK writers honour the clip too, not just set_pixel" do
    # These three wrote the pixel buffer directly and consulted no clip at all, while
    # everything routed through set_pixel did — so the SAME blit clipped or not depending
    # on its blend mode. Production scissors all of them.
    it "fill_rect paints only inside the clip" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0), ink)
      be.get_pixel(50, 50).should eq(bg)
      be.get_pixel(5, 5).should eq(ink)
    end

    it "fill_rect inks the clip EXACTLY — the headless twin of the SFML witness's case O" do
      # 61.5/41.5 -> 62x42, the literals tools/clip-containment-probe.cr case O and
      # spec/rendering/clip_math_spec.cr both use. "Nothing outside" alone is structurally
      # incapable of failing on OVER-clipping, which would shave the clip's own last column.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 61.5, 41.5))
      be.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 400.0, 400.0), ink)
      inked.call(be).should eq(62 * 42)
    end

    it "clear fills only the clip, exactly" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 61.5, 41.5))
      be.clear(ink)
      inked.call(be).should eq(62 * 42)
    end

    it "GUARD (green before and after): clear while suspended still fills everything" do
      # Not RED-first — clear ignored the clip entirely before this change. It pins the
      # suspend contract the layer-background clear depends on.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.suspend_clip
      be.clear(ink)
      be.get_pixel(300, 300).should eq(ink)
    end

    it "an empty/off-buffer clip box writes nothing and does not raise" do
      # ClipMath legitimately returns boxes outside the buffer. A naive intersection
      # inverts, and Array#fill then RAISES on a negative count — or, worse, silently
      # fills the buffer's tail on a negative start.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 40.0, 40.0))
      be.push_clip(CrymbleUI::Rect.new(1000.0, 1000.0, 40.0, 40.0))
      be.clear(ink)
      be.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 400.0, 400.0), ink)
      be.get_pixel(20, 20).should eq(bg)
      be.get_pixel(399, 399).should eq(bg)
    end
  end

  describe "blit honours the TARGET's clip" do
    src = -> do
      b = CrymbleUI::Testing::TestRenderBackend.new(400, 400)
      b.fill_rect(CrymbleUI::Rect.new(0.0, 0.0, 400.0, 400.0), ink)
      b
    end

    it "COPY mode does not paint past the target's clip" do
      # The layer_renderer shape: a widget texture blitted into the layer INSIDE the layer
      # clip. use_alpha_blend: false takes the fast path.
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 20.0, 20.0))
      src.call.blit_to(tgt, 0, 0, use_alpha_blend: false)
      tgt.get_pixel(5, 5).should eq(ink)
      tgt.get_pixel(50, 50).should eq(bg)
    end

    it "BLEND mode with an opaque source takes the same fast path and clips too" do
      # opacity 1.0 + Normal is required, or this takes the SLOW path, which already
      # clipped — and the case would be green before the fix.
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 20.0, 20.0))
      src.call.blit_to(tgt, 0, 0, use_alpha_blend: true, opacity: 1.0)
      tgt.get_pixel(5, 5).should eq(ink)
      tgt.get_pixel(50, 50).should eq(bg)
    end

    it "writes nothing when the destination is inside the buffer but outside the clip" do
      # Inside the target BUFFER, or the fast path's own bounds clamp would reject it and
      # the case would prove nothing.
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 20.0, 20.0))
      src.call.blit_to(tgt, 100, 100, use_alpha_blend: false)
      tgt.get_pixel(150, 150).should eq(bg)
    end

    it "straddling the clip edge writes the inside part EXACTLY" do
      # Pins that source offsets are re-derived from the CLIPPED destination rather than
      # merely truncated.
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 30.0, 30.0))
      src.call.blit_to(tgt, 20, 20, use_alpha_blend: false)
      tgt.get_pixel(25, 25).should eq(ink)
      tgt.get_pixel(29, 29).should eq(ink)
      tgt.get_pixel(30, 25).should eq(bg)
      tgt.get_pixel(25, 30).should eq(bg)
    end

    it "handles NEGATIVE offsets — the background-memorization shape" do
      # layer_renderer blits the layer buffer back at a negative offset for background
      # capture; it is the only live negative-offset caller, and it is invariant (h).
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 30.0, 30.0))
      src.call.blit_to(tgt, -10, -10, use_alpha_blend: false)
      tgt.get_pixel(0, 0).should eq(ink)
      tgt.get_pixel(29, 29).should eq(ink)
      tgt.get_pixel(30, 30).should eq(bg)
    end

    it "GUARD: governed by the TARGET's clip, not the SOURCE's" do
      # An implementation reading self.writable_box instead of the target's would pass
      # every case above and then silently change background memorization.
      b = src.call
      b.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 5.0, 5.0))
      tgt = backend.call
      b.blit_to(tgt, 0, 0, use_alpha_blend: false)
      tgt.get_pixel(50, 50).should eq(ink)
    end

    it "GUARD: governed by the TARGET's suspension, not the source's" do
      tgt = backend.call
      tgt.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      tgt.suspend_clip
      src.call.blit_to(tgt, 0, 0, use_alpha_blend: false)
      tgt.get_pixel(50, 50).should eq(ink)
    end
  end

  describe "a push or a pop CANCELS a suspension, as production's apply_clip does" do
    it "re-installs the stack's box on push" do
      # Production's push_clip calls apply_clip unconditionally, overwriting the
      # full-target scissor suspend_clip installed. A sticky flag let the instrument stay
      # unclipped for a backend's whole life after an unbalanced suspend —
      # render_single_widget suspends and resumes with no `ensure`.
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.suspend_clip
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 300.0, 300.0))
      wrote.call(be, 50, 50).should be_false
    end

    it "re-installs the stack's box on pop" do
      be = backend.call
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0))
      be.push_clip(CrymbleUI::Rect.new(0.0, 0.0, 8.0, 8.0))
      be.suspend_clip
      be.pop_clip
      wrote.call(be, 50, 50).should be_false
    end
  end
end
