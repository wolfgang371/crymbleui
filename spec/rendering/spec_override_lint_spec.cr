require "../spec_helper"

# LINT: unwanted overrides inside the spec suite.
#
# `crystal spec` compiles the WHOLE suite into ONE binary, and Crystal redefines silently - two
# `def foo` at top level leave the second one in force for every file, with no warning (verified:
# a two-line program prints 2). So a helper copied into one spec quietly replaces the real one
# everywhere, and per-file runs cannot see it.
#
# Cost, measured 2026-09-20: `combo_box_interaction_spec` carried its own `click_on` aiming at
# `absolute_bounds` - the UNSCROLLED position. It replaced the library helper binary-wide, so the
# spec written to prove `click_on` works in WINDOW space passed alone and failed in CI. Four
# subset runs came back green; only the full single-binary run reproduced it. Same family as
# embrace's `set_statusbar_info` monkey-patch, which silenced a statusbar surface for a whole
# spec group.
#
# `private def` is file-scoped and shadows nothing - that is the fix, not an exception.
private def spec_files : Array(String)
  # src_glob, never Dir.glob: on Windows the latter returns backslash paths, so the
  # `spec/autotest/` exclusion below silently matches nothing and the autotests - which
  # legitimately share top-level names across separate binaries - get reported as clashes.
  # That is exactly how this lint failed CI on windows-latest while passing on linux.
  #
  # spec/autotest/* are standalone programs, each its own binary: names there cannot collide.
  src_glob("spec/**/*.cr").reject(&.starts_with?("spec/autotest/"))
end

private def top_level_defs(path : String) : Array({String, Int32})
  File.read_lines(path).each_with_index.compact_map do |line, i|
    if m = line.match(/^def ([a-z_][a-z_0-9?!]*)/)
      {m[1], i + 1}
    end
  end.to_a
end

describe "spec-suite override lint" do
  it "does not shadow a testing helper with a top-level def" do
    helpers = File.read_lines("src/testing/gui_test_helpers.cr")
      .compact_map { |l| l.match(/^\s*def ([a-z_][a-z_0-9?!]*)/).try(&.[](1)) }.to_set
    helpers.empty?.should be_false # instrument: the helper list really parsed

    offenders = spec_files.flat_map do |path|
      top_level_defs(path).select { |name, _| helpers.includes?(name) }
        .map { |name, line| "#{path}:#{line} redefines the helper `#{name}`" }
    end
    offenders.should eq([] of String),
      "a top-level def replaces the library helper for the whole binary - use `private def`: " \
      "#{offenders.join("; ")}"
  end

  it "excludes the standalone autotests from the cross-file rules" do
    # An instrument, not a rule: if the exclusion ever matches nothing (it did on Windows,
    # where Dir.glob returns backslashes), the cross-file checks start reporting the
    # autotests - separate binaries that may legitimately share a name - and the failure
    # reads as a code problem rather than a path problem. Assert the COVERAGE.
    all = src_glob("spec/**/*.cr")
    all.count(&.starts_with?("spec/autotest/")).should be > 0
    spec_files.none?(&.starts_with?("spec/autotest/")).should be_true
    spec_files.none?(&.includes?('\\')).should be_true
  end

  it "does not define the same top-level name in two spec files" do
    seen = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
    spec_files.each do |path|
      top_level_defs(path).each { |name, line| seen[name] << "#{path}:#{line}" }
    end
    clashes = seen.select { |_, where| where.size > 1 }
      .map { |name, where| "#{name} defined at #{where.join(" and ")}" }
    clashes.should eq([] of String),
      "one of these wins for the entire binary, silently: #{clashes.join("; ")}"
  end

  it "scans paths through src_glob, never a bare Dir.glob" do
    # `Dir.glob` returns BACKSLASH paths on Windows, so any `starts_with?("spec/...")` or
    # path comparison built on it silently matches nothing there. spec_helper owns the
    # normalisation (`src_glob`) precisely so each new path-scanning spec does not re-learn
    # this from a red CI run - which is how this very file failed on windows-latest.
    offenders = src_glob("spec/**/*.cr").reject(&.ends_with?("spec_helper.cr")).flat_map do |path|
      File.read_lines(path).each_with_index.compact_map do |line, i|
        code = line.gsub(/"(?:[^"\\]|\\.)*"/, %q("")).split('#').first
        "#{path}:#{i + 1}" if code.includes?("Dir.glob")
      end.to_a
    end
    offenders.should eq([] of String),
      "use src_glob (spec_helper) so Windows paths are normalised: #{offenders.join("; ")}"
  end

  it "does not REPLACE a production method by reopening its type" do
    # Adding a test-only accessor to a reopened class is fine and common (`..._for_spec`).
    # Replacing a method the production type already defines is what silences a real surface.
    production = Hash(String, Set(String)).new { |h, k| h[k] = Set(String).new }
    src_glob("src/**/*.cr").each do |path|
      current = nil.as(String?)
      File.read_lines(path).each do |line|
        if m = line.match(/^\s*(?:abstract\s+)?class\s+([A-Za-z_][A-Za-z_0-9:]*)/)
          current = m[1].split("::").last
        elsif (m = line.match(/^\s*(?:private\s+|protected\s+)?def\s+([a-z_][a-z_0-9?!]*)/)) && current
          production[current] << m[1]
        end
      end
    end

    offenders = [] of String
    spec_files.each do |path|
      current = nil.as(String?)
      File.read_lines(path).each_with_index do |line, i|
        if m = line.match(/^class\s+([A-Za-z_][A-Za-z_0-9:]*)/)
          name = m[1].split("::").last
          current = production.has_key?(name) ? name : nil
        elsif (m = line.match(/^\s*(?:private\s+|protected\s+)?def\s+([a-z_][a-z_0-9?!]*)/)) && (cls = current)
          offenders << "#{path}:#{i + 1} replaces #{cls}##{m[1]}" if production[cls].includes?(m[1])
        end
      end
    end
    offenders.should eq([] of String),
      "these replace production behaviour for every example in the binary: #{offenders.join("; ")}"
  end
end
