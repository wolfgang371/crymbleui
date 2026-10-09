require "../spec_helper"
require "../../src/testing/test_render_backend"

# blit_region_to composites every viewport-cache layer. Its common case (Normal blend at full opacity,
# or COPY) runs on the row kernel blit_to uses instead of a per-pixel loop - it has to write exactly what
# that loop wrote. The loop is restated here as the reference, through public get_pixel/set_pixel, and
# compared on seeded random cases: source rects running out of the buffer, destinations off the target,
# a live clip, mixed alpha, COPY and blend.
private def reference_blit(src, target, sx, sy, w, h, dx, dy, alpha : Bool)
  h.times do |oy|
    w.times do |ox|
      c = src.get_pixel(sx + ox, sy + oy)
      next unless c
      tx, ty = dx + ox, dy + oy
      if alpha
        a = c.a / 255.0
        next if a == 0.0
        if a >= 1.0
          target.set_pixel(tx, ty, c)
        elsif bg = target.get_pixel(tx, ty)
          target.set_pixel(tx, ty, CrymbleUI::Color.new(
            ((c.r * a + bg.r * (1 - a)).to_i).clamp(0, 255).to_u8,
            ((c.g * a + bg.g * (1 - a)).to_i).clamp(0, 255).to_u8,
            ((c.b * a + bg.b * (1 - a)).to_i).clamp(0, 255).to_u8, 255_u8))
        end
      else
        target.set_pixel(tx, ty, c)
      end
    end
  end
end

private def painted(rng, w, h) : CrymbleUI::Testing::TestRenderBackend
  b = CrymbleUI::Testing::TestRenderBackend.new(w, h)
  h.times do |y|
    w.times do |x|
      a = [0, 255, 255, rng.rand(1..254)].sample(rng).to_u8
      b.set_pixel(x, y, CrymbleUI::Color.new(rng.rand(256).to_u8, rng.rand(256).to_u8, rng.rand(256).to_u8, a))
    end
  end
  b
end

describe "blit_region_to's fast path" do
  it "writes exactly what the per-pixel loop wrote" do
    rng = Random.new(20260927)
    200.times do |i|
      src = painted(rng, rng.rand(3..24), rng.rand(3..24))
      fast = painted(rng, rng.rand(3..24), rng.rand(3..24))
      ref = CrymbleUI::Testing::TestRenderBackend.new(fast.width, fast.height)
      fast.height.times { |y| fast.width.times { |x| ref.set_pixel(x, y, fast.get_pixel(x, y).not_nil!) } }
      if rng.rand(2) == 0
        clip = CrymbleUI::Rect.new(rng.rand(-3..10).to_f, rng.rand(-3..10).to_f, rng.rand(0..20).to_f, rng.rand(0..20).to_f)
        fast.push_clip(clip)
        ref.push_clip(clip)
      end
      sx, sy = rng.rand(-6..src.width), rng.rand(-6..src.height)
      w, h = rng.rand(0..30), rng.rand(0..30)
      dx, dy = rng.rand(-10..fast.width), rng.rand(-10..fast.height)
      alpha = rng.rand(2) == 0
      src.blit_region_to(fast, sx, sy, w, h, dx, dy, use_alpha_blend: alpha)
      reference_blit(src, ref, sx, sy, w, h, dx, dy, alpha)
      fast.get_pixels(0, 0, fast.width, fast.height).should eq(ref.get_pixels(0, 0, ref.width, ref.height)),
        "case #{i}: src #{src.width}x#{src.height} rect #{sx},#{sy} #{w}x#{h} -> #{dx},#{dy} alpha=#{alpha}"
    end
  end
end
