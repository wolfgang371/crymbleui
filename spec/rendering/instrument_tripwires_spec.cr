require "spec"

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
end
