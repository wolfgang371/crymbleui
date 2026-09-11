require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# "Where content is cut, say so" — the VERTICAL half.
#
# The horizontal marker ships already. Vertical was deferred to here because the predicate
# cannot be the same one: a single line's glyphs legitimately overhang a tight cell (a 17px
# row leaves a 7px content box for a 14px font), so an INK-overflow predicate would light a
# band on every cell in every table. The predicate is therefore on LINES — and only on lines
# that are not the only line, so a break the user typed is marked like any other line.
#
# Assertions are at the PRIMITIVE level, located by position plus EMISSION ORDER: the
# full-width fill emitted after the four border fills. Not by colour elimination, which the
# marker arc already rejected once (the derived neutral can collide with the text colour),
# and not by "is inset from the border", which is unsatisfiable at the default geometry —
# a 17px row leaves well under one free pixel between the last line's ink and the border.

private BLOCK_VALUE  = "one\ntwo\nthree"
private SINGLE_VALUE = "one"

private def render_input(value : String, height : Float64, width : Float64 = 90.0)
  input = CrymbleUI::TextInput.new(value: value, multiline: true, width: width)
  app = TestApp.new
  app.root_widget = input
  app.build_tree
  input.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(width, height)), CrymbleUI::Vec2.zero)
  input.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, width, height))
end

# The bars live on the widget's INNER rect, just inside its border — so their width is the
# widget's width less two borders, which is a signature nothing else in the primitive list
# shares: the background fill and the top/bottom borders all span the FULL width. Derived
# from the widget's own constant rather than written out, so the locator cannot drift from
# the geometry it is looking for.
private BORDER = CrymbleUI::TextInput::BORDER_WIDTH

private def horizontal_bars(primitives, width : Float64)
  target = width - BORDER * 2
  primitives.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))
    .select { |f| (f.bounds.width - target).abs < 0.001 }
end

private def vertical_band(primitives, width : Float64) : CrymbleUI::FillRect?
  horizontal_bars(primitives, width).first?
end

describe "TextInput vertical cut hint" do
  it "marks a block whose later lines do not fit" do
    prims = render_input(BLOCK_VALUE, 17.0)
    band = vertical_band(prims, 90.0)
    band.should_not be_nil
    band.not_nil!.bounds.height.should be >= 1.0
  end

  it "leaves a SINGLE-line value unmarked at every row height a user can drag to" do
    # The disaster this predicate exists to avoid. MIN_ROW_HEIGHT is 0.5 frame units against
    # a 20px base, and the zoom floor is 50%, so a row can be ~5px — far below one line's ink.
    # An ink-overflow predicate would light a band on every cell in such a row.
    [5.0, 8.0, 12.0, 17.0, 24.0, 40.0].each do |h|
      vertical_band(render_input(SINGLE_VALUE, h), 90.0).should be_nil
    end
  end

  it "leaves a block unmarked once the row is tall enough to show every line" do
    vertical_band(render_input(BLOCK_VALUE, 200.0), 90.0).should be_nil
  end

  it "keeps the bar until the last line is COMPLETELY visible, not merely started" do
    # Reported from the running app. A bar that goes out the moment the last line STARTS to
    # appear says "you have the whole value" while half of it is still missing — the one
    # thing a cut marker must never say.
    #
    # The threshold is derived, not guessed: three lines with a 14px slot and 14px ink,
    # top-aligned at content_y = 5, so the last line's ink runs 33..47. Pinned below.
    texts = render_input(BLOCK_VALUE, 47.0).select(&.is_a?(CrymbleUI::DrawText))
      .map(&.as(CrymbleUI::DrawText))
    texts.size.should eq(3)
    texts.map(&.position.y).max.should eq(33.0)

    vertical_band(render_input(BLOCK_VALUE, 46.0), 90.0).should_not be_nil # one pixel short
    vertical_band(render_input(BLOCK_VALUE, 47.0), 90.0).should be_nil     # exactly enough
  end

  it "marks a value whose hidden lines are EMPTY — a break is content too" do
    # REVERSED 2026-08-29 (field report). A break the user typed is part of the value: content
    # sizing grows the row for it, and a row that cannot grow far enough must say so. Under the
    # old rule those two disagreed — a value cut to its first lines went unmarked and looked
    # complete. A SINGLE line still never marks, which is what keeps this off ordinary cells.
    vertical_band(render_input("a\n", 17.0), 90.0).should_not be_nil
    vertical_band(render_input("\n", 17.0), 90.0).should_not be_nil
    vertical_band(render_input("a", 17.0), 90.0).should be_nil
  end

  it "sits at the cut edge, below the last drawn line's top" do
    # It is drawn BEHIND the glyphs, exactly as the horizontal band is — that is what makes
    # the marker legible without hiding what it reports on. What it must not do is drift up
    # into the block: it marks the EDGE the content is cut at.
    # 30px: line 2 is WHOLLY undrawn, which is what the predicate marks. At 40 all three are
    # at least partly drawn, and a partly-drawn line is deliberately NOT marked — marking it
    # would be the same claim as "content is hidden above" over a line you can plainly see.
    # A band means "there is more here"; its absence was never a promise of completeness.
    prims = render_input(BLOCK_VALUE, 30.0)
    band = vertical_band(prims, 90.0)
    band.should_not be_nil

    texts = prims.select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText))
    texts.size.should be > 1 # reachability: the block really did draw several lines
    last_ink_top = texts.map(&.position.y).max
    band.not_nil!.bounds.y.should be >= last_ink_top
  end

  it "is emitted after the border fills, so it is never overpainted" do
    prims = render_input(BLOCK_VALUE, 17.0)
    fills = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))
    bar = vertical_band(prims, 90.0)
    bar.should_not be_nil
    # The bottom border spans the full width at the widget's bottom edge; the bar must come
    # after it in the stream, or the border paints over the thing reporting the cut.
    bottom_border = fills.index { |f| (f.bounds.width - 90.0).abs < 0.001 && f.bounds.y > 1.0 }
    bottom_border.should_not be_nil
    fills.index(bar.not_nil!).not_nil!.should be > bottom_border.not_nil!
  end

  it "uses ONE full-height bar on the side, whatever line is cut" do
    # Per-line segments were tried and rejected in use: a stub beside one line of a block
    # reads as a rendering artifact rather than as the same marker the bottom edge uses.
    # The side bar spans the cell exactly as the bottom bar spans its width — one cue, one
    # shape, both axes.
    prims = render_input("ab\nthis one is far too long to fit\ncd", 200.0, 90.0)
    fills = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

    texts = prims.select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText))
    texts.size.should eq(3) # reachability: all three lines drew

    # Narrow, not at a widget edge (those are the border fills), and spanning the cell.
    side = fills.select { |f| f.bounds.width < 10.0 && f.bounds.x > 1.0 && f.bounds.x < 88.0 }
    side.size.should eq(1)
    side.first.bounds.height.should eq(200.0 - BORDER * 2) # spans the cell, borders excluded
  end
end

describe "TextInput vertical hint under scroll" do
  # The visible-line range must be derived from the SAME anchored position the glyphs are
  # drawn at. Deriving it from the raw scroll offset ignores the block anchor, and the two
  # answers then differ by nearly a line at ordinary cell geometry — so a line with most of
  # its ink on screen is reported as hidden, the top band claims content is cut above when
  # it is not, and that line silently loses its own horizontal marker.
  it "asks the bar the same question the glyphs answer" do
    # The bar's predicate must read the SAME anchored positions the text is drawn at. It once
    # derived the visible range from the raw scroll offset while the glyphs used an anchored
    # one; the two differed by nearly a line, so a bar claimed content was hidden above a line
    # that was plainly on screen. Rather than pin one geometry, this asserts the INVARIANT:
    # a top bar exists exactly when some line really is cut at the top.
    input = CrymbleUI::TextInput.new(value: "one\ntwo\nthree", multiline: true, width: 90.0)
    app = TestApp.new
    app.root_widget = input
    app.build_tree
    input.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(90.0, 40.0)), CrymbleUI::Vec2.zero)
    input.request_focus
    input.on_key_down(SF::Keyboard::Key::End, true, false) # caret to the last line -> scrolls
    prims = input.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, 90.0, 40.0))

    texts = prims.select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText))
    texts.size.should be > 1 # reachability: something was actually drawn

    top_bar = horizontal_bars(prims, 90.0).find { |f| f.bounds.y < BORDER * 2 }

    cut_at_top = texts.any? { |t| t.position.y < 0.0 }
    (!top_bar.nil?).should eq(cut_at_top)
  end

  it "is the same cue on both axes — same thickness, same colour" do
    # Reported from the running app: the vertical band came out a 1px near-white hairline
    # beside a 3px grey horizontal one, and read as a rendering artifact rather than as the
    # same marker. It had been given its own adaptive thickness and its own backdrop; both
    # are gone. This pins them together so they cannot drift apart again.
    prims = render_input("aaaaaaaaaaaaaaaaaaaaaaaaa\nb\nc", 17.0)
    fills = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

    # Not at the widget edge: the left/right BORDER fills are equally narrow and taller, so
    # a width-only filter picks one of those and compares chrome with chrome.
    x_band = fills.find { |f| f.bounds.width < 10.0 && f.bounds.x > 1.0 && f.bounds.x < 88.0 }
    y_band = horizontal_bars(prims, 90.0).first?
    x_band.should_not be_nil
    y_band.should_not be_nil

    y_band.not_nil!.color.should eq(x_band.not_nil!.color)
    y_band.not_nil!.bounds.height.should eq(x_band.not_nil!.bounds.width)
  end
end
