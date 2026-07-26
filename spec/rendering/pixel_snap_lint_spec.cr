require "spec"

# The PixelSnap tripwire: no ad-hoc float→pixel conversion may appear in render-path
# files without an explicit, reviewed exemption. This spec IS the enforcement of the
# policy documented in docs/LAYER_RENDERING_ARCHITECTURE.md ("Float-to-Integer
# Coordinate Rounding") — the defect class behind repeated 1px/blur/ghost/seam bugs.
#
# Mechanism: per file, per line — strip string literals and comments, then flag
#   (a) `.round(:` — mode-rounding is coordinate work by definition;
#   (b) text-position assignments (`sf_text.position`/`text.position = `) without
#       PixelSnap on the line — glyph-atlas text must snap;
#   (c) a conversion (to_i/to_i32/round/floor/ceil) on a coordinate-carrier line —
#       carriers include underscore compounds (scroll_offset, buffer_origin,
#       layer_offset, …) — in any of three shapes: directly after `.x`/`.y`,
#       after a closing paren (the `(a - b).to_i` difference idiom), or after
#       `.width`/`.height` (extent ceils). Excluded: `.round(<digit>` (string
#       formatting), `size.x/.y` casts (type conversion), and `to_i.to_f64` /
#       `to_i32.to_f64` round-trips — those RETURN to Float64, i.e. content-space
#       quantization (scroll grids), never a float→device-pixel conversion.
# A line may carry `# snap-exempt: <reason>` to be excluded (the annotation is the
# review surface; it survives in the diff).
#
# The EXPECTED table below records the reviewed baseline per file; any NEW raw
# conversion bumps a count and fails this spec. Kept-raw-by-design sites carry
# `# snap-exempt:` annotations naming their reason (each annotation is load-bearing:
# a mis-annotation hides a real conversion).
#
# Vector shapes (fills, lines, borders, circles) position sub-pixel BY DESIGN and are
# OUTSIDE pattern scope: only glyph-atlas text and texture-blit sprite destinations
# snap. See the docs chapter for the role decision table.

LINT_ROLE_TABLE = <<-TABLE
  Which PixelSnap function does this conversion need?
    a DRAW position (text, sprite blit dest)      -> PixelSnap.snap   (half-up, translation-invariant)
    a value WHOLE BY CONSTRUCTION (buffer_origin) -> PixelSnap.whole  (asserting cast)
    a widget/layer-local ORIGIN                   -> PixelSnap.origin (floor of the DIFFERENCE)
    a backend/texture EXTENT (size)               -> PixelSnap.span   (via device_pixel_span)
    a culling/visibility BOUND                    -> PixelSnap.cover  (ceil, conservative)
    a viewport slot key (stamp/blit-shift)        -> slot_axis        (one owner, both sides)
  Or annotate `# snap-exempt: <reason>` if this is genuinely not a device-pixel coordinate.
  Policy: docs/LAYER_RENDERING_ARCHITECTURE.md "Float-to-Integer Coordinate Rounding".
  TABLE

private def lint_strip(line : String) : String
  # order matters: strip comments first would eat # inside strings; strings first.
  s = line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"")
  idx = s.index("#")
  # keep `#` that is part of a char literal or method ref out of scope — a plain
  # heuristic suffices for these files (verified against the baseline table).
  idx ? s[0...idx] : s
end

# One conversion alternation for all three shapes of pattern (c). The lookaheads keep
# content-space quantization round-trips (`.to_i.to_f64`) out of scope BY DEFINITION:
# the value stays Float64, so it cannot be a device-pixel conversion.
LINT_CONV = /(?:to_i\b(?!\.to_f64)|to_i32\b(?!\.to_f64)|round\b|floor\b|ceil\b)/

private def lint_violations(path : String) : Array(String)
  out = [] of String
  File.read_lines(path).each_with_index do |raw, i|
    next if raw.includes?("# snap-exempt:")
    line = lint_strip(raw)
    hit =
      line.matches?(/\.round\(:/) ||
        (line.matches?(/\b(sf_text|text)\.position\s*=/) && !line.includes?("PixelSnap")) ||
        (line.matches?(/\b(\w+_)?(position|bounds|origin|offset|dest\w*)\b/) &&
          (line.matches?(/\.(x|y)\.#{LINT_CONV}/) ||
            line.matches?(/\)\.#{LINT_CONV}/) ||
            line.matches?(/\.(width|height)\.#{LINT_CONV}/)) &&
          !line.matches?(/\.round\(\d/) &&
          !line.matches?(/\bsize\.(x|y)\./) &&
          !line.includes?("PixelSnap"))
    out << "#{path}:#{i + 1}: #{raw.strip}" if hit
  end
  out
end

# file => {expected count, reason}. 0 = fully migrated/clean.
LINT_EXPECTED = {
  "src/rendering/cache_validation.cr"   => {0, "clean"},
  "src/rendering/crsfml_backend.cr"     => {0, "text snapped; shapes/blits outside pattern scope"},
  "src/rendering/draw_primitive.cr"     => {0, "data definitions"},
  "src/rendering/fbo_math.cr"           => {0, "pure Int32 flip algebra"},
  "src/rendering/frame_work_log.cr"     => {0, "diagnostics"},
  "src/rendering/layer_renderer.cr"     => {0, "consolidated: origin/span/cover + slot_axis; kept-raw sites are annotated"},
  "src/rendering/opengl_bindings.cr"    => {0, "bindings"},
  "src/rendering/pixel_snap.cr"         => {0, "the policy module itself"},
  "src/rendering/render_backend.cr"     => {0, "interface"},
  "src/rendering/render_debug.cr"       => {0, "diagnostics"},
  "src/rendering/render_trigger.cr"     => {0, "no coordinates"},
  "src/rendering/renderer.cr"           => {0, "no conversions"},
  "src/rendering/sfml_clipboard.cr"     => {0, "no coordinates"},
  "src/rendering/sfml_font.cr"          => {0, "measures only, draws nothing"},
  "src/rendering/sfml_paint_context.cr" => {0, "text snapped"},
  "src/rendering/sfml_renderer.cr"      => {0, "text + compositor snapped"},
  "src/testing/test_render_backend.cr"  => {8, "fill_rect center-coverage + draw_rect outline model the SFML rasterizer (permanent)"},
  "src/testing/test_renderer.cr"        => {0, "compositor snapped; clip extents via cover (parity with SFML)"},
  # Matrix blit/park internals + the layer sampling seam:
  "src/widgets/virtual_matrix/adapter.cr"           => {0, "no coordinate conversions"},
  "src/widgets/virtual_matrix/blit_plan.cr"         => {0, "dests via PixelSnap.origin; scroll quantization is content-space round-trips"},
  "src/widgets/virtual_matrix/cursor.cr"            => {0, "scroll-into-view arithmetic is content-space (annotated)"},
  "src/widgets/virtual_matrix/cursor_overlay.cr"    => {0, "clean"},
  "src/widgets/virtual_matrix/event_handlers.cr"    => {0, "clean"},
  "src/widgets/virtual_matrix/ruler_widget.cr"      => {0, "clean"},
  "src/widgets/virtual_matrix/sticky_math.cr"       => {0, "clean"},
  "src/widgets/virtual_matrix/sticky_reposition.cr" => {0, "content-space scroll round-trips; park predicates quantized == blit_plan"},
  "src/widgets/virtual_matrix.cr"                   => {0, "visible-range bounds are content-space (annotated)"},
  "src/core/layer.cr"                               => {0, "sample origin via PixelSnap.origin; extents via cover"},
}

describe "PixelSnap lint tripwire" do
  it "covers exactly the globbed render-path files (a rename cannot disarm the guard)" do
    globbed = src_glob("src/rendering/*.cr").to_set
    globbed.concat(src_glob("src/widgets/virtual_matrix/*.cr"))
    globbed << "src/testing/test_render_backend.cr"
    globbed << "src/testing/test_renderer.cr"
    globbed << "src/widgets/virtual_matrix.cr"
    globbed << "src/core/layer.cr"
    LINT_EXPECTED.keys.to_set.should eq(globbed)
    LINT_EXPECTED.each_key { |f| File.exists?(f).should be_true, "lint target vanished: #{f}" }
  end

  it "finds no unreviewed raw float→pixel conversions" do
    failures = [] of String
    LINT_EXPECTED.each do |path, (expected, reason)|
      v = lint_violations(path)
      next if v.size == expected
      failures << "#{path}: #{v.size} raw conversion(s), expected #{expected} (#{reason}):\n  " + v.join("\n  ")
    end
    unless failures.empty?
      fail "#{failures.join("\n")}\n\n#{LINT_ROLE_TABLE}"
    end
  end
end
