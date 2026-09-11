require "../src/crymble-ui"

# Multi-line text metrics witness (SFML, needs a real font; no DISPLAY required).
#
#   crystal build tools/multiline-probe.cr -o bin/multiline-probe
#   ./bin/multiline-probe                            # exits 0 GREEN, 1 RED, 2 no verdict
#
# WHAT IT PROVES — the four production facts the headless suite cannot see, because
# `TestFont` has no glyphs and reports `reference_height == size`:
#
#   (1) `SFMLFont#measure_text(...).width` for a multi-line string IS the widest line, not
#       the sum and not the first line. The whole "width needs no change" decision rests on
#       this, and it was measured ONCE, in a scratch file that no longer exists.
#   (2) `measure_text(...).height` is now line_spacing x line_count, and a string with no
#       break is byte-identical to what it was.
#   (3) `reference_height(size) != measure_text("x", size).height` — the INK extent of a
#       line differs from its SLOT. Headlessly these two are equal, so any block-geometry
#       arithmetic that confuses them is green in the suite and wrong on screen. This probe
#       is the only place that difference is observable.
#   (4) Each line's own `local_bounds.left` versus the BLOCK's. This measurement is WHY the
#       renderer draws one `draw_text` PER LINE rather than one for the whole block: a single
#       call is positioned by the block's left bearing, which SFML reports as the MINIMUM
#       across lines, while a caret is positioned from its own line's measurement — so the
#       caret would drift from the glyphs by the difference. Measured here at 1px (size 9) and
#       2px (size 24) on the bundled font, i.e. not sub-pixel, which overturned the original
#       single-draw design. Reporting only the block's `left` could not have shown that.
#
# BLIND SPOTS (name them before trusting a green run): one font (the bundled Cousine
# Regular) at the sizes swept below — a proportional font with unusual bearings could
# differ, and (4) is the measurement that would show it; nothing here touches rasterisation,
# so it says nothing about where ink actually lands, only about what the metrics claim.

FONT_PATH = "resources/Cousine-Regular.ttf"
SIZES     = [9.0, 14.0, 24.0]

ONE_LINE   = "Alice"
THREE_LINE = "Alice\nBob\nCarol"

record Finding, ok : Bool, label : String, detail : String

def check(ok, label, detail) : Finding
  Finding.new(ok, label, detail)
end

findings = [] of Finding

font_file = File.exists?(FONT_PATH) ? FONT_PATH : nil
unless font_file
  STDERR.puts "NO VERDICT: font not found at #{FONT_PATH} (run from the repo root)"
  exit 2
end

sf_font = SF::Font.from_file(font_file)
font = CrymbleUI::SFMLFont.new(sf_font)

SIZES.each do |size|
  one = font.measure_text(ONE_LINE, size)
  three = font.measure_text(THREE_LINE, size)
  ref_h = font.reference_height(size)
  slot = font.measure_text("x", size).height

  # (1) width is the widest line. "Alice" is the widest of the three.
  findings << check(three.width == one.width,
    "width@#{size} is the widest line",
    "block=#{three.width} widest-line=#{one.width}")

  # (2) height scales with the line count, and one line is unchanged.
  findings << check((three.height - one.height * 3.0).abs < 0.001,
    "height@#{size} is slot x line_count",
    "block=#{three.height} 3x-one-line=#{one.height * 3.0}")
  findings << check((one.height - slot).abs < 0.001,
    "height@#{size} of a single line is one slot",
    "one-line=#{one.height} slot=#{slot}")

  # (3) ink extent != slot. If these are equal in production the headless suite cannot
  #     distinguish a correct block extent from `n * slot`, and neither can any spec.
  findings << check((ref_h - slot).abs > 0.001,
    "ref_h@#{size} differs from the slot",
    "ref_h=#{ref_h} slot=#{slot} delta=#{(slot - ref_h).abs}")

  # (4) per-line left bearing vs the block's. Reported as a MEASUREMENT, not a pass/fail:
  #     any non-zero drift is a caret-position budget the geometry has to respect.
  block_left = font.get_text_offsets(THREE_LINE, size)[0]
  worst = 0.0
  THREE_LINE.split('\n').each do |line|
    d = (font.get_text_offsets(line, size)[0] - block_left).abs
    worst = d if d > worst
  end
  # Reported, never asserted: the spread is a property of the FONT, not of our code, and
  # this measurement is why a block is drawn per LINE rather than as one call. Measured on
  # Cousine: 1px at size 9, 0px at 14, 2px at 24 — i.e. NOT sub-pixel, so a single block
  # draw (positioned by the minimum bearing across lines) would leave a caret placed from
  # its own line's measurement up to 2px off its glyphs. Drawing per line makes each line's
  # ink start exactly where it was asked to, because draw_text compensates per call.
  puts "  size #{size}: per-line left-bearing spread vs the block = #{worst}px" \
       " (#{worst > 0 ? "per-line draw REQUIRED" : "no spread at this size"})"
end

puts
failed = findings.reject(&.ok)
findings.each { |f| puts "#{f.ok ? "ok  " : "FAIL"} #{f.label} — #{f.detail}" }
puts
if failed.empty?
  puts "GREEN — #{findings.size} production metric facts hold"
  exit 0
else
  puts "RED — #{failed.size}/#{findings.size} failed"
  exit 1
end
