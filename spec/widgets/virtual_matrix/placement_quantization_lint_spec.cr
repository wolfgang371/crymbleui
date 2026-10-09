require "../../spec_helper"

# The placement tripwire: a grid places a line - and anything on it - by ONE rule, with ONE quantization of the
# scroll. The content layer composites at the floor of the scroll and the sticky pass moves the headers by the
# same whole value (VirtualMatrix#painted_scroll); a line is placed by painted_col / painted_row (laid out by
# placed_col_start / placed_row_start); and a cell region is asked of the placed cells (painted_rect). Each copy
# of that arithmetic elsewhere was, once, a pixel of disagreement: a merged header blitted a pixel off its bounds,
# a decal a scroll away, a ruler line straddling a column edge at a fractional scroll.
#
# It reads SOURCE TEXT (string literals stripped, so debug output does not count): a scroll quantized by hand
# (.to_i / .to_i32 / .floor / .round / .trunc / .ceil on the scroll or a name bound to it), and a ruler offset
# added to a cumulative line position, are flagged outside the methods that own them - unless the line says why
# with `# snap-exempt` (a content-space range, not a painted position) or `# size, not a position`.
PLACEMENT_FILES = ["src/widgets/virtual_matrix.cr"] + src_glob("src/widgets/virtual_matrix/**/*.cr").sort

# The methods that ARE the rule.
PLACEMENT_OWNERS = %w(painted_scroll painted_col painted_row placed_col_start placed_row_start)

private def placement_strip(line : String) : String
  l = line.gsub(/"(\\.|[^"\\])*"/, %("")) # string literals (and their interpolations)
  idx = l.index('#')
  idx ? l[0...idx] : l
end

private QUANTIZE = /\.(to_i|to_i32|floor|round|trunc|ceil)\b/
private RULER_ON_A_LINE = /ruler_(col_width|row_height)_pixels\s*\+.*cum|cum.*\+\s*ruler_(col_width|row_height)_pixels/

describe "placement tripwire" do
  it "finds no hand-quantized scroll and no hand-placed line outside the rule's owners" do
    offenders = [] of String
    exempt = 0
    owners_seen = Set(String).new
    PLACEMENT_FILES.each do |path|
      aliases = Set{"scroll_offset"}
      current = ""
      File.read_lines(path).each_with_index do |raw, i|
        if m = raw.match(/^\s*(?:private |protected )?def ([a-z_?!]+)/)
          current = m[1]
          owners_seen << current if PLACEMENT_OWNERS.includes?(current)
        end
        code = placement_strip(raw)
        # a name bound to the scroll is the scroll (`scroll = @matrix.scroll_offset`, then `scroll.x.to_i`)
        if m = code.match(/\b([a-z_]+)\s*=\s*(?:@matrix\.|@)?scroll_offset\s*$/)
          aliases << m[1]
        end
        next if PLACEMENT_OWNERS.includes?(current)
        quantized = aliases.any? { |a| code.matches?(/\b#{a}(\.[xy])?#{QUANTIZE.source}/) }
        placed = code.matches?(RULER_ON_A_LINE)
        next unless quantized || placed
        if raw.includes?("# snap-exempt") || raw.includes?("# size, not a position")
          exempt += 1
          next
        end
        offenders << "#{path}:#{i + 1}: #{raw.strip}"
      end
    end
    (PLACEMENT_FILES.size >= 8).should be_true # instrument: the glob found the matrix's files
    owners_seen.should eq(PLACEMENT_OWNERS.to_set) # instrument: the owners exist where the rule lives
    (exempt >= 1).should be_true                   # instrument: an exempt line is seen (and let through)
    offenders.should be_empty,
      "place lines through painted_col / painted_row, quantize the scroll only in painted_scroll:\n#{offenders.join("\n")}"
  end
end
