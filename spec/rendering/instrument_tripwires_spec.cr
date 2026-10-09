require "spec"
require "../spec_helper"

# INSTRUMENT TRIPWIRES — incident-named, allowlist-updatable-with-justification.
# These are NOT correctness claims about the render pipeline; each one pins the
# textual shape of a PAST INCIDENT's fix so a regression that re-introduces the bad
# shape trips loudly in a cheap, headless spec (no GPU, no display). A legitimate
# future change may need to update an allowlist here — do so WITH a justification
# comment, never by silently loosening a pattern.
#
# (d) font-cache incident: @@font_cache stale glyph atlas (fix 4a7b4a5). No class-var
#     FONT map may reappear in the two files where a glyph-cache regression would land.
# (e) blit_region containment (fix 7e79842): production must never regain a
#     blit_region caller. Exactly ONE `.blit_region(` call site exists across src/**,
#     and it must stay inside the cv/immediate macro-gated region of layer_renderer.cr.
# (f) clip ownership: CrSFMLBackend must express a clip as the target VIEW's scissor and
#     never issue raw GL scissor state itself. Raw glEnable/glScissor does not survive
#     SFML's own state application inside RenderTarget#draw, so the FIRST draw after any
#     render-target re-activation escaped its clip — cell text ran across its neighbours
#     into empty panel space. Two textual rules: no raw GL scissor anywhere in src/ (the
#     last raw-GL path, a dead paint context, is deleted), and `.view =` in crsfml_backend.cr
#     ONLY inside install_scissor (the view IS the clip's carrier, so setting it elsewhere
#     silently replaces the clip — install_scissor is the single door). Headless CANNOT catch this: TestRenderBackend clips in software
#     with no GL context, and CI has no display, so tools/clip-containment-probe.cr never
#     runs there. This textual guard is the only CI-visible protection the fix has.
# (g) one clip conversion: both backends must derive the clip's device box from the
#     SHARED ClipMath.device_box and neither may re-derive a clip edge with a bare
#     PixelSnap call. They used to convert separately and drifted — the instrument
#     truncated both edges where production floors the origin and ceils the extent, so it
#     clipped one column narrower and a real right-edge defect could pass headless. The
#     PixelSnap lint cannot guard production's side (its locals carry no clip carrier
#     word), which is why this is textual and lives here.
# (h) bulk writes go through the shared clamp: TestRenderBackend's `clear`, `fill_rect`
#     and blit_to's fast path once wrote the pixel buffer raw and consulted NO clip, while
#     everything routed through set_pixel did -- so the same blit clipped or not depending
#     on its blend mode, and a widget overhanging its layer clip left content in the
#     headless buffer that production scissors away. The recurrence mode is a NEW bulk
#     primitive bypassing the clamp; CI has no display so the SFML witness cannot see it.
# (i) one mouse path: SFMLRenderer and TestRenderer both hand mouse presses, releases and moves
#     to MouseDispatch. The focus a press gives lived in SFMLRenderer alone, so TestRenderer's
#     presses never focused, and TestRenderer's moves hovered during a drag; focus now lives in
#     App#handle_mouse_down (every path gets it), the move rule in MouseDispatch - a renderer
#     calling App's mouse handlers itself would drift from the other again, unseen headless.
# (j) one frame end: both renderers end render_frame with `@render_trigger.record(app)` then
#     `app.finish_frame`, and record nowhere else. finish_frame applies the structural work of
#     grids that did not paint (occlusion culling skipped them) before the next input; stamped
#     after it, the trigger would absorb its marks, and a renderer that skipped it would let the
#     next keystroke reach a grid whose cells were being replaced. SFMLRenderer's loop must not
#     idle on the flag it returns - the one path no headless spec runs.

# Replicated from pixel_snap_lint_spec.cr: strip string literals then trailing
# comments, so a pattern can't be tripped (or hidden) by text inside a comment/string.
private def tripwire_strip(line : String) : String
  s = line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"")
  idx = s.index("#")
  idx ? s[0...idx] : s
end

# --- (e) helpers: locate the single blit_region call site --------------------

private record BlitRegionSite, path : String, lineno : Int32, text : String

private def blit_region_call_sites : Array(BlitRegionSite)
  sites = [] of BlitRegionSite
  src_glob("src/**/*.cr").each do |path|
    File.read_lines(path).each_with_index do |raw, i|
      code = tripwire_strip(raw)
      # `\.blit_region\(` = dot + name + open-paren: excludes `def blit_region`,
      # `blit_region_to(`, `blit_region_count`, and the abstract def.
      sites << BlitRegionSite.new(path, i + 1, raw.strip) if code.matches?(/\.blit_region\(/)
    end
  end
  sites
end

# Range-parse the macro block that opens with the exact cv||immediate guard, by
# counting {% if/unless/for/begin %} openers vs {% end %} closers (nesting-aware —
# a bare line-range hardcode would miss same-file relocation of the block). Returns
# {opener_lineno, closer_lineno} (1-based, inclusive of the directive lines).
private def cv_immediate_macro_range(path : String) : {Int32, Int32}
  lines = File.read_lines(path)
  opener_idx = nil
  lines.each_with_index do |raw, i|
    if tripwire_strip(raw).matches?(/\{%\s*if\s+flag\?\(:cache_validation\)\s*\|\|\s*flag\?\(:immediate_mode_only\)\s*%\}/)
      raise "more than one cv||immediate macro opener in #{path}" if opener_idx
      opener_idx = i
    end
  end
  raise "cv||immediate macro opener not found in #{path}" unless opener_idx

  depth = 1 # the opener itself
  closer_idx = nil
  (opener_idx + 1...lines.size).each do |i|
    s = tripwire_strip(lines[i])
    depth += s.scan(/\{%\s*(?:if|unless|for|begin)\b/).size
    depth -= s.scan(/\{%\s*end\b/).size
    if depth <= 0
      closer_idx = i
      break
    end
  end
  raise "cv||immediate macro block never closed in #{path}" unless closer_idx

  {opener_idx + 1, closer_idx + 1}
end

# --- (d) helpers: class-var font map --------------------------------------------

private def font_cache_violations(path : String) : Array(String)
  out = [] of String
  File.read_lines(path).each_with_index do |raw, i|
    code = tripwire_strip(raw)
    # A `@@`-class-var whose name means "font" AND "cache/map/hash".
    code.scan(/@@(\w+)/) do |m|
      name = m[1]
      out << "#{path}:#{i + 1}: class-var font map `@@#{name}`: #{raw.strip}" if name =~ /font/i && name =~ /cache|map|hash/i
    end
    # A member (@ / @@) declared as a Hash valued/keyed by SF::Font (a font map by type).
    if code.matches?(/@@?\w+\s*[:=].*Hash\([^)]*SF::Font/)
      out << "#{path}:#{i + 1}: Hash(..., SF::Font) member (font map by type): #{raw.strip}"
    end
  end
  out
end

FONT_CACHE_GUARD_FILES = [
  "src/rendering/sfml_renderer.cr",
  "src/rendering/crsfml_backend.cr",
]

describe "instrument tripwires" do
  describe "(d) font-cache incident (fix 4a7b4a5)" do
    it "has no class-var font map in the glyph-cache-regression files" do
      violations = FONT_CACHE_GUARD_FILES.flat_map { |f| font_cache_violations(f) }
      violations.should be_empty,
        "@@font_cache stale-glyph-atlas incident tripwire fired (fix 4a7b4a5). If a NEW\n" \
        "font map is legitimate, update this allowlist WITH a justification, not silently:\n  " +
          violations.join("\n  ")
    end
  end

  describe "(e) blit_region containment (fix 7e79842)" do
    it "has exactly ONE `.blit_region(` call site across src/**" do
      sites = blit_region_call_sites
      sites.size.should eq(1),
        "production must never regain a blit_region caller (fix 7e79842). Sites found:\n  " +
          sites.map { |s| "#{s.path}:#{s.lineno}: #{s.text}" }.join("\n  ")
    end

    it "keeps EVERY blit_region call site inside the cv/immediate macro-gated region of layer_renderer.cr" do
      sites = blit_region_call_sites
      sites.should_not be_empty,
        "no blit_region call site found — the containment tripwire has nothing to guard (fix 7e79842)."

      sites.each do |site|
        site.path.should eq("src/rendering/layer_renderer.cr"),
          "a blit_region caller is outside layer_renderer.cr: #{site.path}:#{site.lineno}: #{site.text}"

        opener, closer = cv_immediate_macro_range(site.path)
        # Strictly inside the {% if flag?(:cache_validation) || flag?(:immediate_mode_only) %} block.
        (opener < site.lineno && site.lineno < closer).should be_true,
          "blit_region call at #{site.path}:#{site.lineno} is OUTSIDE the cv/immediate macro gate " \
          "[#{opener}, #{closer}] — production could regain a live blit_region caller (fix 7e79842)."
      end
    end
  end

  describe "(f) clip ownership: the view carries the clip, not raw GL scissor" do
    it "issues NO raw GL scissor state anywhere in src/" do
      offenders = [] of String
      src_glob("src/**/*.cr").each do |path|
        File.read_lines(path).each_with_index do |raw, i|
          code = tripwire_strip(raw)
          next unless code.matches?(/LibGL|GL_SCISSOR_TEST|glScissor|glEnable|0x0C11/)
          offenders << "#{path}:#{i + 1}: #{raw.strip}"
        end
      end
      offenders.should be_empty,
        "Nothing may issue raw GL scissor state — SFML resets it inside " \
        "RenderTarget#draw, so the first draw after any re-activation escapes the clip. " \
        "Express the clip as the view's scissor instead. Sites found:\n  " + offenders.join("\n  ")
    end

    it "sets the backend's view ONLY inside install_scissor" do
      path = "src/rendering/crsfml_backend.cr"
      lines = File.read_lines(path)
      from = lines.index { |l| l.matches?(/private def install_scissor/) }
      from.should_not be_nil,
        "install_scissor not found in #{path} — the (f) tripwire has nothing to anchor on."
      start = from.not_nil!
      stop = (start...lines.size).find { |i| lines[i] == "    end" }.not_nil!

      offenders = [] of String
      lines.each_with_index do |raw, i|
        next if i >= start && i <= stop
        code = tripwire_strip(raw)
        offenders << "#{path}:#{i + 1}: #{raw.strip}" if code.matches?(/\.view\s*=/)
      end
      offenders.should be_empty,
        "the view is the clip's carrier: setting it outside install_scissor silently replaces " \
        "the active clip. Sites found:\n  " + offenders.join("\n  ")
    end
  end


  describe "(g) one clip conversion, shared by both backends" do
    clip_backends = ["src/rendering/crsfml_backend.cr", "src/testing/test_render_backend.cr"]

    it "derives the clip box ONLY through ClipMath.device_box" do
      clip_backends.each do |path|
        File.read_lines(path).map { |l| tripwire_strip(l) }.join("\n")
          .should contain("ClipMath.device_box"),
          "#{path} must derive its clip box from the shared conversion — a re-inlined " \
          "origin/cover here is exactly the drift that let the instrument clip one " \
          "column narrower than production."
      end
    end

    it "computes no clip edge with a bare PixelSnap call in either backend" do
      # The PixelSnap lint cannot catch this side: apply_clip's locals are named
      # left/top/right/bottom, which carry no clip carrier word, so a re-inlined
      # `(right - left).ceil.to_i32` there would keep the lint green.
      offenders = [] of String
      clip_backends.each do |path|
        File.read_lines(path).each_with_index do |raw, i|
          code = tripwire_strip(raw)
          next unless code.matches?(/PixelSnap\.(origin|cover|span)\(/)
          offenders << "#{path}:#{i + 1}: #{raw.strip}"
        end
      end
      offenders.should be_empty,
        "clip geometry belongs in ClipMath.device_box, not re-derived in a backend. " \
        "Sites found:\n  " + offenders.join("\n  ")
    end
  end


  describe "(h) every bulk pixel write goes through the shared clamp" do
    it "confines raw @pixels writes to defs that consult writable_box / fill_span" do
      # How the defect arose: `clear`, `fill_rect` and blit_to's fast path wrote the pixel
      # buffer directly and consulted no clip, while everything routed through set_pixel
      # did -- so the SAME blit clipped or not depending on its blend mode. The recurrence
      # mode is someone adding a new bulk primitive that bypasses the clamp, and CI has no
      # display, so the SFML witness cannot guard it. This can.
      path = "src/testing/test_render_backend.cr"
      # Only defs that CAN legitimately write pixels. `initialize`/`release_payload` are
      # deliberately absent: they REBIND @pixels wholesale rather than index into it, so
      # they never match below — listing them would assert a coverage this has not got.
      # composite_rows is the kernel blit_to and blit_region_to share: it asserts its rect lies in writable_box.
      allowed = {"set_pixel", "fill_span", "blit_to", "composite_rows"}
      # Indexed assignment, and the bulk mutators a new primitive would plausibly reach
      # for. `[^=]` after `=` so a comparison (`@pixels[i] == x`) is not a false offender.
      bulk = /@pixels\s*(\[[^\]]*\]\s*=[^=]|\.(fill|map!|to_unsafe|copy_from|\[\]=))/
      current = "?"
      offenders = [] of String
      File.read_lines(path).each_with_index do |raw, i|
        code = tripwire_strip(raw)
        if m = code.match(/^\s*(?:private |protected )?def ([a-z_0-9]+[?!=]?)/)
          current = m[1]
        end
        next unless code.matches?(bulk)
        offenders << "#{path}:#{i + 1} (in `#{current}`): #{raw.strip}" unless allowed.includes?(current)
      end
      offenders.should be_empty,
        "a bulk pixel write outside the clamped writers -- it would paint through a live " \
        "clip, which production scissors. Route it through fill_span or writable_box, or " \
        "add it to this allowlist WITH a justification. Sites found:\n  " + offenders.join("\n  ")
    end
  end

  describe "(j) one frame end" do
    it "ends both renderers' render_frame with record, then finish_frame, and records nowhere else" do
      %w(src/rendering/sfml_renderer.cr src/testing/test_renderer.cr).each do |path|
        code = File.read_lines(path).map { |l| tripwire_strip(l) }
        records = code.each_index.select { |i| code[i].includes?("@render_trigger.record(") }.to_a
        records.size.should eq(1), "#{path}: the render trigger is stamped #{records.size} times; once, at the frame's end"
        code[records.first + 1].should contain("app.finish_frame"), "#{path}: finish_frame must follow the stamp"
        # Every way out of render_frame passes end_frame: a `return` in its body comes right after one.
        start = code.index! { |l| l.matches?(/^\s*def render_frame\b/) }
        stop = code.index!(start + 1) { |l| l.matches?(/^\s*(private )?def /) }
        body = code[start...stop]
        body.count { |l| l.includes?("end_frame(app)") }.should be >= 1, "#{path}: render_frame never ends the frame"
        body.each_with_index do |l, i|
          next unless l.matches?(/\breturn\b/) && !l.includes?("@window")
          body[i - 1].should contain("end_frame(app)"), "#{path}: a return in render_frame skips the frame's end"
        end
      end
      sfml = File.read_lines("src/rendering/sfml_renderer.cr").map { |l| tripwire_strip(l) }.join("\n")
      sfml.should match(/def end_frame.*?rescue ex.*?app\.report_event_exception\(ex\)/m),
        "SFMLRenderer#end_frame must report a flush that raised - the loop runs it outside the frame's rescue"
      sfml.should match(/unless app\.input_waits_for_frame\? \|\| @flushed_after_frame/),
        "SFMLRenderer must not block in wait_event after a frame whose end applied work"
    end
  end

  describe "(i) one mouse path" do
    it "keeps both renderers off App's mouse handlers - they go through MouseDispatch" do
      offenders = %w(src/rendering/sfml_renderer.cr src/testing/test_renderer.cr).flat_map do |path|
        File.read_lines(path).each_with_index.compact_map do |raw, i|
          code = tripwire_strip(raw)
          "#{path}:#{i + 1}: #{raw.strip}" if code.matches?(/\.handle_mouse_(down|up|move)\b/)
        end.to_a
      end
      offenders.should be_empty,
        "a renderer dispatches the mouse itself instead of through MouseDispatch - the two renderers " \
        "drift (focus on press, hover during a drag). Sites found:\n  " + offenders.join("\n  ")
    end
  end
end
