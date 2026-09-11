require "../src/crymble-ui"

# Clip-containment witness (SFML, needs a real DISPLAY).
#
#   crystal build tools/clip-containment-probe.cr -o bin/clip-containment-probe
#   DISPLAY=:0 ./bin/clip-containment-probe          # exits 0 GREEN, 1 RED, 2 no verdict
#
# WHAT IT PROVES: that a clip pushed on a CrSFMLBackend governs every subsequent draw on
# that backend until it is popped — including the FIRST draw after the render target has
# been re-activated, which is where this stopped being true.
#
# Why it exists. Raw glEnable(GL_SCISSOR_TEST)+glScissor issued at push time do not
# survive: SFML applies its own state inside RenderTarget::draw (setupDraw ->
# resetGLStates / applyCurrentView) and disables the scissor test while leaving the box.
# Two fixes were tried and refuted against THIS probe before the third was adopted:
#   - re-applying the clip immediately before each draw cured warm draws only (the cold
#     draw is the bug);
#   - warming SFML's state cache at push time cured the single-target case only, because
#     every render-target switch inside a clip window re-invalidates it (cases B/C/E).
# The fix that holds expresses the clip as the target VIEW's scissor, so SFML re-applies
# it itself on every re-activation.
#
# Every interlude below is a real sequence from layer_renderer.cr, not a synthetic one —
# an instrument that cannot contain the phenomenon reports its absence, and this arc
# produced three confident wrong answers that way before this probe existed.
#
# BLIND SPOTS (name them before trusting a green run): bare RenderTexture only — says
# nothing about the RenderWindow target or the compositor. (The widget-texture
# blit-to-layer step USED to be one; case M covers it now.) One driver, one GL context,
# one SFML version (behaviour here is
# SFML-version dependent); it compares colours exactly, so a sub-pixel/anti-aliased
# escape of a fraction of a pixel is invisible; and it is NOT run by CI, which has no
# display — run it alongside tools/sfml-parity.sh.

include CrymbleUI

W    = 240
H    = 140
FONT = "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"

# Asymmetric and off-centre on BOTH axes, so an x/y swap or a vertical flip cannot pass.
CX = 37
CY = 23
CW = 61
CH = 41

RED   = Color.new(255, 0, 0)
GREEN = Color.new(0, 255, 0)

class Witness
  getter failures = 0
  getter checks = 0

  def initialize(@font : SF::Font)
  end

  # Held for the whole run: a dropped CrSFMLBackend is destroyed by SF::RenderTexture's
  # finalizer at GC time, and destroying an FBO mid-render is exactly the hazard
  # CrSFMLBackend's deferred reaper exists to avoid. A witness whose exit code IS the
  # verdict must not be exposed to a nondeterministic finalizer.
  @alive = [] of CrSFMLBackend

  def backend : CrSFMLBackend
    be = CrSFMLBackend.new(W, H, @font)
    be.clear(Color.new(0, 0, 0))
    @alive << be
    be
  end

  def clip_rect : Rect
    Rect.new(CX.to_f64, CY.to_f64, CW.to_f64, CH.to_f64)
  end

  # Pixels of `want`, split by whether they landed inside the expected rect.
  def split(be : CrSFMLBackend, want : Color, rect : Tuple(Int32, Int32, Int32, Int32)) : Tuple(Int32, Int32)
    be.display
    px = be.capture_region_pixels(0, 0, W, H)
    x0, y0, x1, y1 = rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]
    inside = 0
    outside = 0
    H.times do |y|
      W.times do |x|
        v = px[y * W + x]
        next unless ((v >> 24) & 0xFF) == want.r && ((v >> 16) & 0xFF) == want.g && ((v >> 8) & 0xFF) == want.b
        (x >= x0 && x < x1 && y >= y0 && y < y1) ? (inside += 1) : (outside += 1)
      end
    end
    {inside, outside}
  end

  def report(label : String, ok : Bool, detail : String)
    @checks += 1
    @failures += 1 unless ok
    puts "  #{(ok ? "ok  " : "FAIL")} #{label.ljust(50)} #{detail}"
  end

  # The core shape: push a clip, run an interlude, draw an oversized rect. The rect must
  # be confined to the clip, and must actually ink (a vacuous case is a failure).
  def contained(label : String, expect : Tuple(Int32, Int32, Int32, Int32) = {CX, CY, CW, CH}, &interlude : CrSFMLBackend -> Nil)
    be = backend
    be.push_clip(clip_rect)
    interlude.call(be)
    be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
    be.pop_clip
    inside, outside = split(be, RED, expect)
    ok = outside == 0 && inside > 0
    report(label, ok, "inside=#{inside} outside=#{outside}#{inside == 0 ? "  (VACUOUS)" : ""}")
  end
end

# ---------------------------------------------------------------- validity conditions

display = ENV["DISPLAY"]?
if display.nil? || display.empty?
  puts "INVALID: no DISPLAY. This witness needs a real GL context; a headless run proves nothing."
  exit 2
end
unless File.exists?(FONT)
  puts "INVALID: font not found at #{FONT}"
  exit 2
end
font = SF::Font.new(FONT)
w = Witness.new(font)

puts "clip-containment witness   clip=(#{CX},#{CY},#{CW},#{CH})  target=#{W}x#{H}  DISPLAY=#{display}"
puts

# Positive control FIRST: if an unclipped oversized draw does NOT ink outside the rect,
# the geometry or the capture is wrong and every "contained" below would be vacuous.
be = w.backend
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
pin, pout = w.split(be, RED, {CX, CY, CW, CH})
w.report("positive control: no clip => inks outside", pout > 0, "inside=#{pin} outside=#{pout}")

puts
puts "containment (each interlude is a real layer_renderer.cr sequence):"

# A — the plain cold draw. RED before the fix.
w.contained("A cold draw, no interlude") { }

# B — create_widget_backend (:1441/:1453) constructs a backend whose ctor clears.
w.contained("B construct another backend (its ctor clears)") { w.backend }

# C — a push/pop on another backend (:1059-1063, :1648-1654); the pop disables scissor.
w.contained("C push+pop a clip on another backend") do
  b = w.backend
  b.push_clip(Rect.new(0.0, 0.0, 10.0, 10.0))
  b.pop_clip
end

# D — suspend_clip (:1483) -> work on other backends -> resume_clip (:1624).
w.contained("D suspend -> draw on another backend -> resume") do |a|
  a.suspend_clip
  b = w.backend
  b.fill_rect(Rect.new(0.0, 0.0, 10.0, 10.0), GREEN)
  b.display
  a.resume_clip
end

# E — display() mid-clip (:1608), which does active = false.
w.contained("E display() on the same backend mid-clip") { |a| a.display }

# F — nested depth 2, production's real shape (cell clip inside layer clip). A view holds
# ONE scissor, so apply_clip must intersect the stack; asserting the intersection is what
# stops "inner replaces outer" from painting outside the outer clip.
be = w.backend
be.push_clip(Rect.new(0.0, 0.0, 100.0, 100.0))
be.push_clip(Rect.new(50.0, 50.0, 100.0, 100.0))
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
be.pop_clip
be.pop_clip
i, o = w.split(be, RED, {50, 50, 50, 50})
w.report("F nested depth 2 => INTERSECTION, not inner-replaces", o == 0 && i > 0, "inside=#{i} outside=#{o}")

# G — pop back to depth 1: the outer clip must govern again.
be = w.backend
be.push_clip(Rect.new(0.0, 0.0, 100.0, 100.0))
be.push_clip(Rect.new(50.0, 50.0, 20.0, 20.0))
be.pop_clip
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
be.pop_clip
i, o = w.split(be, RED, {0, 0, 100, 100})
# EXACT area: `i > 0` would also pass with the inner (50,50,20,20) clip still installed.
w.report("G pop back to depth 1 restores the outer clip", o == 0 && i == 100 * 100,
  "inside=#{i}/#{100 * 100} outside=#{o}")

# H — pop to depth 0: no clip, the whole target is writable again.
be = w.backend
be.push_clip(w.clip_rect)
be.pop_clip
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
i, o = w.split(be, RED, {0, 0, W, H})
w.report("H pop to depth 0 => whole target writable", o == 0 && i == W * H, "inked=#{i}/#{W * H}")

# I — an empty intersection must draw NOTHING. A negative extent reaching glScissor is
# GL_INVALID_VALUE, which drops the call and leaves the PREVIOUS box live and enabled —
# a silent wrong-clip, which is the failure class this whole task exists to remove.
be = w.backend
be.push_clip(Rect.new(0.0, 0.0, 40.0, 40.0))
be.push_clip(Rect.new(100.0, 100.0, 40.0, 40.0))
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
be.pop_clip
be.pop_clip
i, o = w.split(be, RED, {0, 0, W, H})
w.report("I disjoint clips => draws nothing", i == 0 && o == 0, "inked=#{i}")

# J — a COLD draw_text. This is what an EMPTY cell paints: CrymbleUI::Text has no
# background fill, so the text IS the first draw and there is no fill to absorb the
# escape. draw_text also activates the texture, which fill_rect does not.
be = w.backend
be.push_clip(w.clip_rect)
be.draw_text("MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM", Vec2.new(2.0, 2.0), Color.new(255, 255, 255), 22.0)
be.pop_clip
be.display
px = be.capture_region_pixels(0, 0, W, H)
tin = 0
tout = 0
H.times do |y|
  W.times do |x|
    v = px[y * W + x]
    lum = (((v >> 24) & 0xFF) * 299 + ((v >> 16) & 0xFF) * 587 + ((v >> 8) & 0xFF) * 114) // 1000
    next unless lum > 150
    (x >= CX && x < CX + CW && y >= CY && y < CY + CH) ? (tin += 1) : (tout += 1)
  end
end
w.report("J cold draw_text (the empty-cell case)", tout == 0 && tin > 0, "inside=#{tin} outside=#{tout}")

# K — glyph-atlas growth inside a clip window: a text size never used before in this
# process creates an SF::Texture under a transient context lock. Whether the clip
# survives that was an open question; this pins it.
be = w.backend
be.push_clip(w.clip_rect)
be.draw_text("WWWWWWWWWWWWWWWWWWWWWWWW", Vec2.new(2.0, 2.0), Color.new(255, 255, 255), 37.0)
be.pop_clip
be.display
px = be.capture_region_pixels(0, 0, W, H)
gout = 0
gin = 0
H.times do |y|
  W.times do |x|
    v = px[y * W + x]
    lum = (((v >> 24) & 0xFF) * 299 + ((v >> 16) & 0xFF) * 587 + ((v >> 8) & 0xFF) * 114) // 1000
    next unless lum > 150
    (x >= CX && x < CX + CW && y >= CY && y < CY + CH) ? (gin += 1) : (gout += 1)
  end
end
w.report("K glyph-atlas growth inside a clip window", gout == 0 && gin > 0, "inside=#{gin} outside=#{gout}")

# L — clear() under a live clip. SFML documents the view scissor as governing "draw or
# clear operations", and RenderTarget::clear applies the view. No production site clears
# a target that holds its own live clip (audited), but this pins the contract for the
# next caller, and it is what decides whether suspend_clip/resume_clip can ever go.
be = w.backend
be.push_clip(w.clip_rect)
be.clear(Color.new(0, 255, 0))
be.pop_clip
gi, go = w.split(be, GREEN, {CX, CY, CW, CH})
w.report("L clear() under a live clip is scissored", go == 0 && gi > 0, "inside=#{gi} outside=#{go}")

# M: a SPRITE BLIT under a live clip. This is the one primitive the probe had no case
# for, and it is the architecture's main path — layer_renderer blits each widget texture
# into the layer INSIDE the layer clip, in COPY mode. docs/BUGFIXING.md names exactly this
# as the probe's blind spot ("says nothing about ... the widget-texture blit-to-layer
# step"), so the headless twin of this case had no production evidence behind it.
src = w.backend
src.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
src.display
a = w.backend
a.push_clip(w.clip_rect)
a.blit(src, 0, 0)
a.pop_clip
q_in, q_out = w.split(a, RED, {CX, CY, CW, CH})
w.report("M blit under a clip is scissored", q_out == 0 && q_in == CW * CH,
  "inside=#{q_in}/#{CW * CH} outside=#{q_out}")

puts
puts "over-clipping (the mirror failure: content wrongly cut AWAY — tolerance 0, alpha included):"

# A primitive that FITS must ink byte-identically with and without a clip pushed.
# "Zero pixels outside the clip" is structurally incapable of failing on over-clipping,
# so without this the witness only watches one direction.
inner = Rect.new((CX + 8).to_f64, (CY + 6).to_f64, 20.0, 15.0)
a = w.backend
a.push_clip(w.clip_rect)
a.fill_rect(inner, RED)
a.pop_clip
a.display
b = w.backend
b.fill_rect(inner, RED)
b.display
pa = a.capture_region_pixels(0, 0, W, H)
pb = b.capture_region_pixels(0, 0, W, H)
diff = 0
(W * H).times { |i| diff += 1 if pa[i] != pb[i] }
w.report("N a fitting draw is byte-identical to unclipped", diff == 0, "differing px=#{diff}")

# The clip's own edges must not shave a draw that ends exactly on them.
edge = Rect.new(CX.to_f64, CY.to_f64, CW.to_f64, CH.to_f64)
a = w.backend
a.push_clip(w.clip_rect)
a.fill_rect(edge, GREEN)
a.pop_clip
gi, go = w.split(a, GREEN, {CX, CY, CW, CH})
w.report("O a draw exactly filling the clip is not shaved", go == 0 && gi == CW * CH, "inked=#{gi}/#{CW * CH}")

# FRACTIONAL clip — the input class where the conversion could differ from the old
# trunc(x)+ceil(w). The layer clip (layer_renderer.cr:781) is Rect(0,0,bounds.w,bounds.h)
# and bounds are fractional at fractional zoom. Extents use PixelSnap.cover (ceil)
# deliberately: rounding to nearest would give 298 where the compositor samples 299 and
# shave the rightmost column of every layer (the "Historical seam note").
fw = 61.5
be = w.backend
be.push_clip(Rect.new(0.0, 0.0, fw, 41.5))
be.fill_rect(Rect.new(0.0, 0.0, W.to_f64, H.to_f64), RED)
be.pop_clip
cw = PixelSnap.cover(fw)
ch = PixelSnap.cover(41.5)
i, o = w.split(be, RED, {0, 0, cw, ch})
# EXACT area: `i > 0` would also pass with a truncated 61x41 extent — i.e. with the very
# shave this check is named for. cover(61.5)=62 must actually be inked.
w.report("P fractional clip covers (ceil), does not shave", o == 0 && i == cw * ch,
  "inside=#{i}/#{cw * ch} outside=#{o} => cover=#{cw}x#{ch}")

puts
puts "scissor factor round trip (integer pixels -> 0..1 factors -> lround, must be exact):"

bad = 0
checked = 0
sample = [] of String
held_targets = [] of SF::RenderTexture
[{1254, 586}, {1320, 900}, {1440, 1080}, {1264, 463}, {1100, 750}, {193, 439}].each do |(tw, th)|
  rt = SF::RenderTexture.new(tw.to_u32, th.to_u32)
  held_targets << rt # same finalizer hazard as the backends above
  view = rt.default_view.dup
  x = 0
  while x < tw
    [1, 7, 23, 100, 143, 297].each do |cw|
      next if x + cw > tw
      # Sweep y and h too — an earlier sweep varied x/w only and left the Y axis, where
      # SFML additionally flips, sampled at a single point.
      [{3, 5}, {17, 20}, {th // 2, 31}, {th - 9, 8}].each do |(y, ch)|
        next if y + ch > th
        view.scissor = SF.float_rect(x.to_f32 / tw, y.to_f32 / th, cw.to_f32 / tw, ch.to_f32 / th)
        got = rt.scissor(view)
        checked += 1
        if {got.left, got.top, got.width, got.height} != {x, y, cw, ch}
          bad += 1
          sample << "tex=#{tw}x#{th} want=(#{x},#{y},#{cw},#{ch}) got=(#{got.left},#{got.top},#{got.width},#{got.height})" if sample.size < 5
        end
      end
    end
    x += 37
  end
  # The magic full-target value, which SFML treats as "scissor disabled".
  view.scissor = SF.float_rect(0.0, 0.0, 1.0, 1.0)
  got = rt.scissor(view)
  checked += 1
  if {got.left, got.top, got.width, got.height} != {0, 0, tw, th}
    bad += 1
    sample << "tex=#{tw}x#{th} full-target got=(#{got.left},#{got.top},#{got.width},#{got.height})"
  end
end
sample.each { |s| puts "    #{s}" }
w.report("Q factor round trip exact over real buffer sizes", bad == 0, "#{checked} rects, #{bad} mismatches")

puts
if w.failures == 0
  puts "GREEN — #{w.checks} checks, 0 failures."
  exit 0
else
  puts "RED — #{w.checks} checks, #{w.failures} failures."
  exit 1
end
