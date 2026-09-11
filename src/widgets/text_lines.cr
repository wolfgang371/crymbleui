require "../core/widget"

module CrymbleUI
  # The line decomposition of a string, and the geometry of the block it forms.
  #
  # ONE owner, deliberately. Centring, the caret, the selection, the vertical scroll clamp
  # and the cut marker all read their geometry from here, so they cannot disagree about
  # where line k sits or how tall the block is. Two derivations of a block extent that
  # differ by `step - ref_h` are enough to make the bottom marker and the scroll clamp
  # contradict each other at the last line, which is exactly the drift a second derivation
  # invites.
  #
  # Holds NO font-derived state. Every geometric answer takes the font size and reads
  # through `Widget.measure_text` / `Widget.font.reference_height`, both of which
  # `Widget.font=` already invalidates. A memo carrying `step` or `ref_h` would need an
  # invalidation of its own and would otherwise serve another font's numbers after a swap —
  # which specs do routinely (and production does on every zoom), order-dependently and
  # silently.
  struct TextLines
    getter value : String

    # nil when the value holds no break. The single-line path then allocates nothing and
    # `line_text(0)` hands back the value itself — the steady state of a screenful of grid
    # cells. This is a representation choice behind a total API, not a second mode: no
    # consumer ever asks which one it got.
    @starts : Array(Int32)?

    @@memo = {} of String => TextLines

    def self.of(value : String) : TextLines
      if hit = @@memo[value]?
        return hit
      end
      # Bounded exactly the way `Widget.measure_text`'s cache is, by the SAME constant rather
      # than a second copy of the number: same key space (a string of dynamic text), same
      # reason, so they cannot drift apart. A wholesale clear, not an LRU. Unbounded, this
      # would retain every distinct string ever painted, on the widget that re-derives per
      # keystroke.
      @@memo.clear if @@memo.size > Widget::TEXT_MEMO_LIMIT
      built = TextLines.new(value)
      @@memo[value] = built
      built
    end

    protected def initialize(@value : String)
      starts = nil
      @value.each_char_with_index do |ch, i|
        (starts ||= [0]) << i + 1 if ch == '\n'
      end
      @starts = starts
    end

    # How many lines a string holds, without building a decomposition. For callers that need
    # only the count (a label, a button) — so "line count" has one definition even where the
    # full line model would be overkill.
    def self.count(text : String) : Int32
      text.count('\n') + 1
    end

    def line_count : Int32
      @starts.try(&.size) || 1
    end

    # Which line a CHARACTER index falls on. Indices are always into the ORIGINAL value:
    # `starts` is built from the real `\n` positions, so a `\r` inside a CRLF shifts
    # nothing. Building them from stripped lines instead would put every start after the
    # first CRLF one short — naming the wrong line and splicing edits mid-terminator.
    def line_at(index : Int32) : Int32
      starts = @starts
      return 0 unless starts
      lo = 0
      hi = starts.size - 1
      while lo < hi
        mid = (lo + hi + 1) // 2
        starts[mid] <= index ? (lo = mid) : (hi = mid - 1)
      end
      lo
    end

    def column_at(index : Int32) : Int32
      starts = @starts
      return index unless starts
      index - starts[line_at(index)]
    end

    # Character index where line k begins, and where it ends (exclusive of its terminator).
    # Derived from `starts`, never from `line_text`, whose `\r` chomp would make the end one
    # short on a CRLF value and silently misplace Home/End there.
    def line_start(k : Int32) : Int32
      (starts = @starts) ? starts[k] : 0
    end

    def line_end(k : Int32) : Int32
      starts = @starts
      stop = starts.nil? ? @value.size : (k + 1 < starts.size ? starts[k + 1] - 1 : @value.size)
      # Exclude a terminating CR, so this agrees with `line_text`, which chomps it. They must:
      # End / Ctrl+End and a vertical run's goal column are computed from THIS, and the text
      # the user sees is that. One char apart, the caret parks between CR and LF — typing
      # there splices into the terminator and Shift+End puts a CR on the clipboard.
      stop > 0 && @value[stop - 1] == '\r' ? stop - 1 : stop
    end

    # Is line k blank? Answered from the index arithmetic, never by slicing: the cut-content
    # predicate asks this of every hidden line, and `line_text` allocates.
    def line_empty?(k : Int32) : Bool
      line_end(k) <= line_start(k)
    end

    # Line k's text, for MEASUREMENT. A trailing `\r` is dropped here and only here: it is
    # a terminator artifact rather than anything the user typed, and `starts` — which the
    # index arithmetic above depends on — is left untouched.
    def line_text(k : Int32) : String
      starts = @starts
      return @value unless starts
      from = starts[k]
      to = k + 1 < starts.size ? starts[k + 1] - 1 : @value.size
      slice = @value[from...to]
      slice.ends_with?('\r') ? slice[0...-1] : slice
    end

    # === GEOMETRY (font-size in, nothing cached) ===

    # One line's vertical slot: what the next line is offset by. Class-level because it is a
    # property of the FONT, not of any particular string — which lets the DSL's block-centring
    # helper ask for it instead of spelling the same formula out a second time.
    def self.step(font_size : Float64) : Float64
      Widget.measure_text("x", font_size).height
    end

    # One line's INK extent. Smaller than its slot in production, equal to it headlessly —
    # confusing the two is invisible to the suite and wrong on screen.
    def self.ref_h(font_size : Float64) : Float64
      (f = Widget.font) ? f.reference_height(font_size) : font_size
    end

    # The ink extent of a block of `count` lines: the first line's ink plus a slot for each
    # line after it. NOT `count * step`, which over-reserves by the slot's leading.
    def self.block_extent(count : Int32, font_size : Float64) : Float64
      ref_h(font_size) + (count - 1) * step(font_size)
    end

    def step(font_size : Float64) : Float64
      TextLines.step(font_size)
    end

    def ref_h(font_size : Float64) : Float64
      TextLines.ref_h(font_size)
    end

    def block_extent(font_size : Float64) : Float64
      TextLines.block_extent(line_count, font_size)
    end

    # Line k's y RELATIVE to the block origin. The caller adds the block's anchor, which is
    # a property of the widget and its box — never of the string, so it cannot live in a
    # value shared by every widget holding the same text.
    def y_of(line : Int32, font_size : Float64) : Float64
      line * step(font_size)
    end

    # The height of a per-line rect (selection row, cut band). A single line keeps the
    # historical `font_size`, which existing specs pin; a block tiles by the step so its
    # rows leave no gaps.
    def slot_height(font_size : Float64) : Float64
      line_count == 1 ? font_size : step(font_size)
    end

  end
end
