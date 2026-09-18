require "../spec_helper"

# CLAIMING REPAIR REQUIRES IMPLEMENTING IT.
#
# `note_position_change` clears the layer holding a moved widget's vacated pixels, because selective
# rendering repaints a widget where it now IS and never where it was. A layer that translates its own
# buffer instead opts out via Layer#owns_geometry_repair, since the clear would discard the shift it
# was about to perform.
#
# That exemption used to be spelled `viewport_cache`, and the bug was precisely the gap between the
# claim and the implementation: the repair it assumed is `mark_needs_resize_shift`, whose only callers
# are VirtualMatrix's two, while EVERY viewport_cache layer took the exemption. A plain ScrollView's
# content layer therefore declined the clear with nothing of its own to repair with, and content that
# reflowed inside one left its old pixels behind — embrace's About dialog, narrowed, showing the logo
# footer stamped at every size it had passed through.
#
# Making the claim opt-in fixed that instance. This spec is what stops it recurring: an opt-in is a
# PROMISE, and nothing else checks that the promiser can keep it. Source text, in the manner of the
# PixelSnap and size-writer tripwires, because the relationship is "this file claims X and must also
# contain Y" — there is no runtime moment at which to assert it.
LINT_REPAIR_HELP = <<-HELP
  A layer may set `owns_geometry_repair = true` only if the same file implements the repair it is
  thereby promising — today that means calling `mark_needs_resize_shift`, which TRANSLATES the buffer
  region instead of clearing it. If you are adding a claimant:
    · implement the repair, then add the file to EXPECTED_REPAIR_CLAIMANTS below in the same commit;
    · if your repair is a NEW mechanism rather than a resize-shift, add it to REPAIR_MECHANISMS and
      say in the claimant's comment which layer state it maintains.
  If you cannot name the mechanism, do not set the flag: without it the layer simply gets the clear,
  which is correct and merely less efficient. The flag trades correctness for speed, so it has to be
  earned.
  HELP

# file => number of `owns_geometry_repair = true` sites. Reviewed 2026-09-17.
#   virtual_matrix.cr:1841  the matrix content layer — repairs via the two mark_needs_resize_shift
#                           calls (column resize, row resize), which keep viewport culling and the
#                           per-slot skip on so only the resized line re-renders.
EXPECTED_REPAIR_CLAIMANTS = {
  "src/widgets/virtual_matrix.cr" => 1,
}

# What counts as implementing repair. Layer.cr is excluded as a claimant source below because it
# DEFINES the mechanism rather than using it.
REPAIR_MECHANISMS = ["mark_needs_resize_shift("]

# src_glob, not a bare Dir.glob: spec_helper's version normalises the separator
# (`Dir.glob(...).map(&.gsub('\\', '/'))`), and without it this spec passes everywhere except
# Windows, where the glob yields `src\widgets\virtual_matrix.cr` and the comparison against the
# reviewed list fails on the slashes alone. That is exactly how it broke the public CI.
private def repair_lint_sources : Array(String)
  src_glob("src/**/*.cr")
end

private def strip_comment(line : String) : String
  l = line.gsub(/"(\\.|[^"\\])*"/, %(""))
  idx = l.index('#')
  idx ? l[0...idx] : l
end

describe "geometry-repair claim tripwire" do
  it "is claimed only by files that implement the repair" do
    claimants = {} of String => Int32
    repair_lint_sources.each do |path|
      n = File.read_lines(path).count { |l| strip_comment(l).includes?("owns_geometry_repair = true") }
      claimants[path] = n if n > 0
    end

    claimants.should eq(EXPECTED_REPAIR_CLAIMANTS),
      "the set of geometry-repair claimants changed\n  found:    #{claimants}\n  reviewed: #{EXPECTED_REPAIR_CLAIMANTS}\n\n#{LINT_REPAIR_HELP}"

    claimants.each_key do |path|
      body = File.read(path)
      REPAIR_MECHANISMS.any? { |m| body.includes?(m) }.should be_true,
        "#{path} claims owns_geometry_repair but implements none of #{REPAIR_MECHANISMS}\n\n#{LINT_REPAIR_HELP}"
    end
  end

  it "keeps the exemption keyed on the claim rather than on the layer type" do
    # The original defect in one assertion: `viewport_cache` must not be what grants the exemption,
    # because being a viewport cache is not what provides the repair. A rename or a well-meaning
    # revert here reintroduces that defect exactly.
    body = File.read_lines("src/core/widget.cr")
    idx = body.index { |l| l.includes?("def note_position_change") }
    idx.should_not be_nil, "note_position_change moved — this tripwire is pointing at nothing"
    window = body[idx.not_nil!, 20].join("\n")
    condition = window.lines.find { |l| strip_comment(l).includes?("mark_needs_clear_and_render") }
    condition.should_not be_nil, "note_position_change no longer clears the containing layer at all"
    stripped = strip_comment(condition.not_nil!)
    stripped.should contain("owns_geometry_repair"),
      "the exemption is no longer keyed on the claim: #{condition}\n\n#{LINT_REPAIR_HELP}"
    stripped.should_not contain("viewport_cache"),
      "the exemption is keyed on the layer TYPE again, which is the original defect: #{condition}"
  end
end
