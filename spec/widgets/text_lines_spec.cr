require "../spec_helper"
require "../../src/widgets/text_lines"

# The line decomposition of a value, and the geometry of the block it forms.
#
# One owner, because the alternative is what this replaces: centring, the caret, the
# selection, the scroll clamp and the cut marker each deriving "how tall is this block"
# for themselves and being free to disagree at the last line.
#
# The stub font below makes `font_size`, `ref_h` and `step` PAIRWISE DISTINCT on purpose.
# Under the real headless font all three collapse to the em size, so `block_extent` and
# `slot_height` become unfalsifiable — an implementation that returns `n * step` passes
# every example and is wrong only in SFML, where `reference_height` is the ink extent of
# "Ag" and the step is `get_line_spacing`. The production probe measures a 2-6px gap.
class PairwiseFont < CrymbleUI::Font
  def measure_text(text : String, size : Float64) : CrymbleUI::Size
    widest = text.split('\n').max_of(&.size)
    CrymbleUI::Size.new(widest * size * 0.6, size * 1.2 * (text.count('\n') + 1))
  end

  def get_kerning(first : Char, second : Char, size : UInt32) : Float64
    0.0
  end

  def get_text_offsets(text : String, size : Float64) : Tuple(Float64, Float64)
    {0.0, 0.0}
  end

  def reference_height(size : Float64) : Float64
    size * 0.5
  end
end

private def with_pairwise_font(&)
  original = CrymbleUI::Widget.font
  CrymbleUI::Widget.font = PairwiseFont.new
  begin
    yield
  ensure
    CrymbleUI::Widget.font = original
  end
end

describe CrymbleUI::TextLines do
  describe "decomposition" do
    it "splits on \\n, keeping a trailing empty line" do
      # `String#lines` chomps, which would drop the line a caret must be able to sit on.
      CrymbleUI::TextLines.of("a\nb").line_count.should eq(2)
      CrymbleUI::TextLines.of("a\n").line_count.should eq(2)
      CrymbleUI::TextLines.of("\n").line_count.should eq(2)
      CrymbleUI::TextLines.of("").line_count.should eq(1)
      CrymbleUI::TextLines.of("abc").line_count.should eq(1)
      CrymbleUI::TextLines.of("a\n\nb").line_count.should eq(3)
    end

    it "returns its stored value as the only line when single-line, allocating nothing" do
      # The steady state of a screenful of grid cells. Asserted against the STORED value
      # rather than the caller's string: `of` memoises on content, so a second caller with
      # an equal-but-distinct string legitimately gets the first one back. Object identity
      # with the caller would therefore pass or fail depending on which spec ran first —
      # which is exactly how it failed when the suite ran as one process.
      lines = CrymbleUI::TextLines.of("Solo#{1}line")
      lines.line_text(0).should be(lines.value)
    end

    it "maps a character index to its line and column" do
      lines = CrymbleUI::TextLines.of("ab\ncd\ne")
      lines.line_at(0).should eq(0)
      lines.line_at(2).should eq(0)  # the break itself belongs to the line it ends
      lines.line_at(3).should eq(1)
      lines.line_at(6).should eq(2)
      lines.column_at(0).should eq(0)
      lines.column_at(2).should eq(2)
      lines.column_at(3).should eq(0)
      lines.column_at(4).should eq(1)
    end

    it "puts the caret on the trailing empty line of a value ending in a break" do
      lines = CrymbleUI::TextLines.of("a\n")
      lines.line_at(2).should eq(1)
      lines.column_at(2).should eq(0)
    end

    it "keeps indices aligned with the ORIGINAL value across CRLF" do
      # `starts` is derived from the real `\n` positions. Stripping `\r` while building them
      # would shift every start after the first CRLF, so `line_at` would name the wrong line
      # and an edit would splice mid-terminator.
      lines = CrymbleUI::TextLines.of("ab\r\ncd")
      lines.line_count.should eq(2)
      lines.line_at(4).should eq(1) # 'c' — index 4 in the ORIGINAL string
      lines.column_at(4).should eq(0)
    end
  end

  describe "geometry" do
    it "derives the block extent from the ink of the first line plus a step per later line" do
      with_pairwise_font do
        size = 10.0
        step = 12.0  # measure_text height for one line
        ref_h = 5.0  # reference_height
        CrymbleUI::TextLines.of("a").block_extent(size).should eq(ref_h)
        CrymbleUI::TextLines.of("a\nb").block_extent(size).should eq(ref_h + step)
        CrymbleUI::TextLines.of("a\nb\nc").block_extent(size).should eq(ref_h + step * 2)
      end
    end

    it "places line k a step below the block origin" do
      with_pairwise_font do
        lines = CrymbleUI::TextLines.of("a\nb\nc")
        lines.y_of(0, 10.0).should eq(0.0) # relative to the block origin; the caller adds the anchor
        lines.y_of(1, 10.0).should eq(12.0)
        lines.y_of(2, 10.0).should eq(24.0)
      end
    end

    it "uses the historical font_size slot for a single line and the step for a block" do
      with_pairwise_font do
        # Single-line selection and marker rects are font_size tall today and pinned that way
        # by existing specs; a block tiles by the step so its rows have no gaps.
        CrymbleUI::TextLines.of("a").slot_height(10.0).should eq(10.0)
        CrymbleUI::TextLines.of("a\nb").slot_height(10.0).should eq(12.0)
      end
    end

    it "answers emptiness without slicing the value" do
      # The cut-content predicate asks this of every hidden line, so it must not allocate.
      lines = CrymbleUI::TextLines.of("a\n\nbb\n")
      lines.line_empty?(0).should be_false
      lines.line_empty?(1).should be_true
      lines.line_empty?(2).should be_false
      lines.line_empty?(3).should be_true # the trailing empty line
      CrymbleUI::TextLines.of("").line_empty?(0).should be_true
    end

    it "ends a CRLF line where its TEXT ends, not at the terminator" do
      # line_end feeds End / Ctrl+End and a vertical run's goal column, while line_text is
      # what the user sees. One char apart, the caret parks between CR and LF: typing there
      # splices into the terminator and Shift+End puts a CR on the clipboard.
      lines = CrymbleUI::TextLines.of("ab\r\ncd")
      lines.line_text(0).should eq("ab")
      lines.line_end(0).should eq(lines.line_start(0) + lines.line_text(0).size)
      lines.line_end(1).should eq(lines.line_start(1) + lines.line_text(1).size)
    end
  end

  describe "the memo" do
    it "serves the same decomposition for the same value" do
      a = CrymbleUI::TextLines.of("x\ny")
      b = CrymbleUI::TextLines.of("x\ny")
      a.line_count.should eq(b.line_count)
      a.line_text(1).should eq(b.line_text(1))
    end

    it "carries no font state, so a font swap cannot serve stale geometry" do
      # The reason `font_size` is not part of the key: `Widget.measure_text`'s cache is
      # cleared by `Widget.font=`, and a second memo would not see that. Holding only the
      # decomposition means there is nothing to invalidate.
      lines = CrymbleUI::TextLines.of("a\nb")
      first = with_pairwise_font { lines.block_extent(10.0) }
      second = lines.block_extent(10.0) # back on the suite's default font
      first.should_not eq(second)
    end
  end
end
