require "spec"

# The size-writer tripwire: nothing may change a VirtualMatrix's `@col_widths` / `@row_heights`
# without refreshing what is derived from them.
#
# A size change is not a Source. The arrays are mutated in place, so nothing marks the dependents
# and every consumer must be told by hand — and which consumers exist was knowledge that lived only
# inside `flush_resize_update`. Three arcs paid for that in a row: the sticky chrome kept a box
# sized for the old columns, the rulers kept drawing the old pitch, and the scroll
# extents left the scrollbar unpainted until a full layout. Each time, the fix was correct
# and the NEXT path forgot again.
#
# So this spec is the enforcement, not a style check: every writer is listed here with what it does
# about the derived surfaces. A new writer bumps a count and fails, and the failure message says
# what to call. `docs/VIRTUAL_MATRIX_ARCHITECTURE.md` documents the policy.
#
# It reads SOURCE TEXT because there is no type-level way to make the arrays write-private: the
# class is reopened across `virtual_matrix/*.cr`, and the carry accessors hand the arrays out.
LINT_SIZE_WRITER_HELP = <<-HELP
  A new write to @col_widths / @row_heights must say what it does about the surfaces derived from
  them (dimension caches, sticky chrome, ScrollView extents, scroll offset clamp):
    writer with NO layout      -> call `refresh_after_size_change`
    writer that marks layout   -> `invalidate_dimension_caches` only; the layout publishes the rest
    per-keystroke content fit  -> `refresh_after_size_change(sticky: false)` (flush_fit_cells does
                                  the sticky work once, at the end of the same frame)
    the interactive drag       -> `invalidate_dimension_caches` ONLY; the rest is deferred to
                                  mouse-up on purpose (live extents mid-gesture would make a
                                  scrollbar appear under the blit-shift fast path)
    construction / reconcile   -> nothing: there is no ScrollView or layer yet, and a reconciled
                                  instance starts NeedsLayout, so a layout follows anyway
  Then add the site to EXPECTED_SIZE_WRITERS below, in the same commit as its refresh.
  HELP

# file => number of size-array write sites. Reviewed baseline, 2026-09-02. The count is SITES, not
# methods: several methods write both arrays. The reviewed set is
#   :403,:420   ctors                    — nothing (no ScrollView, no layer yet)
#   :606,:622   flush_auto_size          — refresh_after_size_change. One assignment per axis:
#                                          a pinned line takes min(content, current) so it can
#                                          compact but never grow past a viewport it cannot scroll
#   :722,:729   fit_cell_to_content      — refresh_after_size_change(sticky: false) (flush_fit_cells
#                                          does the sticky work once, at the end of the same frame)
#   :836,:848   row_height / col_width   — invalidate_dimension_caches only; they schedule a
#                                          LAYOUT, which is what publishes the extents there
#   :859,:868   the two drag setters     — invalidate_dimension_caches only, deferred by design
#   :1753       the toggle-off handover  — refresh_after_size_change
#   :1799       flush_invalidate_all     — refresh_after_size_change
#   :2805,:2806 copy_state_from carry    — nothing (a reconciled instance starts NeedsLayout), and
#                                          `.dup` because assigning the array itself left two live
#                                          matrices sharing one buffer (measured)
EXPECTED_SIZE_WRITERS = {
  "src/widgets/virtual_matrix.cr" => 14,
}

private def size_writer_strip(line : String) : String
  l = line.gsub(/"(\\.|[^"\\])*"/, %("")) # string literals
  idx = l.index('#')
  idx ? l[0...idx] : l
end

# A write is: `@col_widths[...] =`, `@row_heights[...] =`, or an assignment TO the whole array
# (including the `@row_heights, @col_widths = adapter.get_sizes` tuple form). Reads are not writes.
private def size_writer_line?(text : String) : Bool
  return false unless text.includes?("@col_widths") || text.includes?("@row_heights")
  return true if text.matches?(/@(col_widths|row_heights)\[[^\]]*\]\s*=[^=]/)
  return true if text.matches?(/@(col_widths|row_heights)\s*=[^=]/)
  return true if text.matches?(/@(row_heights|col_widths)\s*,\s*@(col_widths|row_heights)\s*=[^=]/)
  # mutating array methods reach the same buffer without a subscript
  return true if text.matches?(/@(col_widths|row_heights)\s*\.\s*(fill|map!|concat|clear|push|<<|delete_at|insert)\b/)
  false
end

describe "size-writer tripwire" do
  EXPECTED_SIZE_WRITERS.each do |path, expected|
    it "#{path} has exactly #{expected} reviewed size-array writers" do
      found = [] of String
      File.read_lines(path).each_with_index do |line, i|
        text = size_writer_strip(line)
        found << "#{path}:#{i + 1}: #{line.strip}" if size_writer_line?(text)
      end
      found.size.should eq(expected),
        "#{found.size} size-array write sites, expected #{expected}.\n\n" \
        "#{LINT_SIZE_WRITER_HELP}\n\nSites:\n#{found.join("\n")}"
    end
  end

  it "finds no size-array writer OUTSIDE the file that owns the refresh" do
    # The class is reopened across virtual_matrix/*.cr; a write from one of those files would be
    # invisible to the baseline above and could not be paired with a refresh by review.
    offenders = [] of String
    Dir.glob("src/widgets/virtual_matrix/*.cr").each do |path|
      File.read_lines(path).each_with_index do |line, i|
        offenders << "#{path}:#{i + 1}: #{line.strip}" if size_writer_line?(size_writer_strip(line))
      end
    end
    offenders.should be_empty,
      "size-array writes outside virtual_matrix.cr:\n#{offenders.join("\n")}\n\n#{LINT_SIZE_WRITER_HELP}"
  end
end
