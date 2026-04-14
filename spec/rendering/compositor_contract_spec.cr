require "../spec_helper"
require "../../src/testing/test_render_backend"

# Compositor contract tests: verify TestRenderBackend blending math
# matches the equations defined in csfml3/wrapper.cr BlendMode definitions.
#
# These tests ensure headless compositing produces identical results to SFML,
# preventing SFML-only bugs from escaping headless detection.
#
# Blend equations (from wrapper.cr):
#   Normal:      result = src * src_alpha + dst * (1 - src_alpha)
#   Additive:    result = src * src_alpha + dst
#   Subtractive: result_color = dst - src * src_alpha; result_alpha = dst_alpha (preserved)
#   Multiply:    result = src * dst
#   None:        result = src (overwrite)

private def solid_backend(w : Int32, h : Int32, color : CrymbleUI::Color) : CrymbleUI::Testing::TestRenderBackend
  b = CrymbleUI::Testing::TestRenderBackend.new(w, h)
  b.clear(color)
  b
end

describe "Compositor blend mode contract" do

  describe "Normal blend (alpha compositing)" do
    it "fully opaque source overwrites destination" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 100, 50, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(10, 20, 30, 255))

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Normal)

      # Inside overlay: source color
      p = dst.get_pixel(50, 50).not_nil!
      p.r.should eq 10
      p.g.should eq 20
      p.b.should eq 30

      # Outside overlay: destination unchanged
      p2 = dst.get_pixel(5, 5).not_nil!
      p2.r.should eq 200
    end

    it "semi-transparent source blends with destination" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(0, 0, 0, 128)) # 50% alpha black

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Normal)

      # result = src * 0.5 + dst * 0.5 = 0 + 100 = 100
      p = dst.get_pixel(50, 50).not_nil!
      (p.r.to_i - 100).abs.should be <= 2
      (p.g.to_i - 100).abs.should be <= 2
    end

    it "fully transparent source has no effect" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(255, 0, 0, 0)) # fully transparent red

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Normal)

      p = dst.get_pixel(50, 50).not_nil!
      p.r.should eq 200 # unchanged
    end
  end

  describe "Additive blend" do
    it "adds source color scaled by alpha to destination" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(100, 100, 100, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(50, 50, 50, 255)) # full alpha

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Additive)

      # result = dst + src * 1.0 = 100 + 50 = 150
      p = dst.get_pixel(50, 50).not_nil!
      (p.r.to_i - 150).abs.should be <= 2
    end

    it "clamps to 255" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(200, 200, 200, 255))

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Additive)

      p = dst.get_pixel(50, 50).not_nil!
      p.r.should eq 255 # clamped
    end
  end

  describe "Subtractive blend" do
    it "subtracts source color scaled by alpha from destination" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(50, 50, 50, 255)) # full alpha

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Subtractive)

      # result = dst - src * 1.0 = 200 - 50 = 150
      p = dst.get_pixel(50, 50).not_nil!
      (p.r.to_i - 150).abs.should be <= 2
    end

    it "clamps to 0" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(30, 30, 30, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(200, 200, 200, 255))

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Subtractive)

      p = dst.get_pixel(50, 50).not_nil!
      p.r.should eq 0 # clamped
    end

    it "preserves destination alpha" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(50, 50, 50, 128))

      src.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Subtractive)

      p = dst.get_pixel(50, 50).not_nil!
      p.a.should eq 255 # alpha preserved, not subtracted
    end

    it "does not accumulate on repeated application (idempotent clear+render)" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      overlay = solid_backend(50, 50, CrymbleUI::Color.new(30, 30, 30, 255))

      # First application
      overlay.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Subtractive)
      p1 = dst.get_pixel(50, 50).not_nil!

      # Reset destination, apply again (simulates clear + re-composite)
      dst.clear(CrymbleUI::Color.new(200, 200, 200, 255))
      overlay.blit_to(dst, 25, 25, blend_mode: CrymbleUI::BlendMode::Subtractive)
      p2 = dst.get_pixel(50, 50).not_nil!

      # Should be identical — no accumulation
      p1.r.should eq p2.r
      p1.g.should eq p2.g
    end
  end

  describe "COPY mode (use_alpha_blend: false)" do
    it "overwrites destination regardless of source alpha" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(0, 0, 0, 0)) # fully transparent

      src.blit_to(dst, 25, 25, use_alpha_blend: false)

      # Transparent source MUST overwrite (for widget background restoration)
      p = dst.get_pixel(50, 50).not_nil!
      p.r.should eq 0
      p.a.should eq 0
    end
  end

  describe "Opacity multiplier" do
    it "reduces effective alpha" do
      dst = solid_backend(100, 100, CrymbleUI::Color.new(200, 200, 200, 255))
      src = solid_backend(50, 50, CrymbleUI::Color.new(0, 0, 0, 255)) # full alpha black

      src.blit_to(dst, 25, 25, opacity: 0.5, blend_mode: CrymbleUI::BlendMode::Normal)

      # result = src * 0.5 + dst * 0.5 = 0 + 100 = 100
      p = dst.get_pixel(50, 50).not_nil!
      (p.r.to_i - 100).abs.should be <= 2
    end
  end
end
