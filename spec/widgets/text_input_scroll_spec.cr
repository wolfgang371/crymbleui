require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# Scroll-to-caret: entering a marked cell must actually SHOW you the hidden text.
#
# A hint you cannot act on is only half a feature. Enter opens an ordinary text cell and walks
# the view to the caret, so the tail of a cut value becomes readable.
#
# Probe discipline: examples that read BAND pixels use ink-free characters ('d', code & 0x03
# == 0). The Enter-reveal example needs to see glyphs move, so it uses a SENTINEL shape
# instead — one right-stripe-only head character, an ink-free body, one inking tail — because
# a homogeneous inking value re-occupies the head columns with whatever scrolled into them and
# cannot distinguish "scrolled" from "not scrolled".
SCROLL_LONG = "dddddddddddddddddddd"
# 'b' (0x62) inks ONLY a right stripe, at head_x+6..+7 — clear of a left band at
# [head_x, head_x+3), and drift-immune because it is character 0.
SCROLL_SENTINEL = "b" + "dddddddddddddddd" + "c"

class ScrollApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Scroll", 120, 160) do
      vstack(padding: 0.0, spacing: 0.0) do
        # QuickEntry: embrace's cell mode. Parked (focused, not yet typed) it draws NO caret,
        # so nothing scrolls until Enter opens the cell — which is the behaviour under test.
        text_input(id: "cell", width: 60.0, value: SCROLL_SENTINEL,
          mode: CrymbleUI::TextInputMode::QuickEntry)
        text_input(id: "quiet", width: 60.0, value: SCROLL_LONG,
          mode: CrymbleUI::TextInputMode::QuickEntry)
      end
    end
  end
end

private def scroll_app
  renderer = CrymbleUI::Testing::TestRenderer.new(120, 160)
  app = ScrollApp.new
  app.build_tree
  renderer.settle_rendering(app)
  {app, renderer}
end

# A tall cell whose value overflows it, opened for editing the way a matrix opens one.
# TALL is what the vertical examples need: it is the regime where the block is top-anchored a
# padding below the border, which is exactly the padding the scroll offset used to eat.
private TALL_VALUE  = (1..12).map { |i| "line#{i}" }.join("\n")
private TALL_HEIGHT = 120.0
private TALL_WIDTH  =  200.0

private def tall_editor
  input = CrymbleUI::TextInput.new(value: TALL_VALUE, multiline: true, width: TALL_WIDTH)
  app = TestApp.new
  app.root_widget = input
  app.build_tree
  input.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(TALL_WIDTH, TALL_HEIGHT)),
    CrymbleUI::Vec2.zero)
  input.activate_proxy_focus
  input.enter_edit_mode
  input
end

private def line_y(input, text : String) : Float64?
  input.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, TALL_WIDTH, TALL_HEIGHT))
    .select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText))
    .find { |t| t.text == text }.try(&.position.y)
end

private def inked_at?(widget, x : Int32, color) : Bool
  wb = widget.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)
  return false if x < 0 || x >= wb.width
  (0...wb.height).any? { |y| wb.get_pixel(x, y) == color }
end

describe "TextInput scroll-to-caret" do
  it "is a pure function of the stored offset, the caret and the box" do
    # Unit-level, because the property it must hold is arithmetic, not pixels. box 90, text
    # 200, so the value overflows and the reserve applies.
    fits = CrymbleUI::TextInput.derive_scroll_offset(0.0, 50.0, 80.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH)
    fits.should eq(0.0) # a value that fits never scrolls, whatever the caret does

    # Caret at the tail: the view ends one pixel past it, so the caret itself stays visible.
    tail = CrymbleUI::TextInput.derive_scroll_offset(0.0, 200.0, 200.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH)
    tail.should eq(200.0 - 90.0 + CrymbleUI::TextInput::CURSOR_WIDTH)

    # Never negative, and never past the end.
    CrymbleUI::TextInput.derive_scroll_offset(0.0, 0.0, 200.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH).should eq(0.0)
    CrymbleUI::TextInput.derive_scroll_offset(999.0, 200.0, 200.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH)
      .should eq(200.0 - 90.0 + CrymbleUI::TextInput::CURSOR_WIDTH)
  end

  it "holds the view still while the caret walks back inside it (hysteresis)" do
    # Without this the text shifts a character on every Left press, which is what the stored
    # offset buys. Caret moves from 200 to 150 while the window [111, 200] still contains it.
    stored = CrymbleUI::TextInput.derive_scroll_offset(0.0, 200.0, 200.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH)
    CrymbleUI::TextInput.derive_scroll_offset(stored, 150.0, 200.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH).should eq(stored)
  end

  it "re-derives to 0 when the value shrinks to fit under a stale offset" do
    # The union the marker relies on holds only while the offset stays within its bounds. A
    # value can shrink with NO cursor move (delete, an external write, Escape-restore), so a
    # stale offset must not survive into a state where nothing is hidden — a left band lit
    # over a value with nothing to its left is a lie.
    CrymbleUI::TextInput.derive_scroll_offset(120.0, 20.0, 40.0, 90.0, CrymbleUI::TextInput::CURSOR_WIDTH).should eq(0.0)
  end

  it "leaves an unfocused cell head-anchored" do
    # cursor_pos starts at value.size for EVERY TextInput, so an ungated choke point would
    # scroll every overflowing cell in a fresh sheet to its tail — the whole table showing
    # ends of values instead of beginnings. No band-vs-band assertion can catch this; a band
    # is lit either way.
    app, _ = scroll_app
    quiet = app.find("quiet").not_nil!.as(CrymbleUI::TextInput)
    quiet.effective_scroll_offset.x.should eq(0.0)
  end

  it "reveals the tail on Enter, and not before" do
    # Parked QuickEntry draws no caret, so the cell is head-anchored: the head sentinel's
    # stripe is on screen. Enter opens the cell, the caret is already at the end, and the view
    # walks to it — the head goes off-screen left and the tail's inking character appears.
    #
    # Both halves matter. Without the BEFORE assertion this example passes with the Enter
    # deleted: a default-FullEdit input scrolls on focus, so "tail visible" would be true
    # either way and the example would certify scroll-on-focus wearing Enter's name.
    app, renderer = scroll_app
    cell = app.find("cell").not_nil!.as(CrymbleUI::TextInput)
    head_x = (CrymbleUI::TextInput::BORDER_WIDTH + cell.padding + 6).to_i

    click_on(app, cell)
    renderer.settle_rendering(app)
    cell.pending_replace.should be_true # parked: no caret, nothing scrolled
    cell.effective_scroll_offset.x.should eq(0.0)
    inked_at?(cell, head_x, cell.text_color).should be_true

    press_key(SF::Keyboard::Key::Enter)
    renderer.settle_rendering(app)
    cell.pending_replace.should be_false # Enter really opened the cell
    cell.effective_scroll_offset.x.should be > 0.0
    inked_at?(cell, head_x, cell.text_color).should be_false
  end

  it "walking back to the first line restores its padding, not just its visibility" do
    # Field report: in a tall cell whose value overflows, scrolling down and back up left the
    # FIRST line clipped by the border — the value sat a padding higher than it does when the
    # cell is opened fresh. The two axes disagreed about their frame: X derives against the
    # INNER box, Y derived against the whole widget while measuring the caret from the block
    # anchor, so the offset could grow to the anchor and slide the block under the border.
    input = tall_editor
    inner_top = CrymbleUI::TextInput::BORDER_WIDTH + input.padding

    input.cursor_pos = 0 # opened at the start (a fresh caret rests at the TAIL)
    line_y(input, "line1").should eq(inner_top) # control: unscrolled, the padding is there

    input.cursor_pos = TALL_VALUE.size                  # scroll down to the tail...
    input.scroll_offset = input.effective_scroll_offset # ...persisted, as the handlers persist it
    line_y(input, "line1").should be_nil                # really scrolled: line 1 is gone

    input.cursor_pos = 0 # ...and walk back up
    input.scroll_offset = input.effective_scroll_offset
    input.effective_scroll_offset.y.should eq(0.0)
    line_y(input, "line1").should eq(inner_top)
  end

  it "the tail sits inside the box, not under the bottom border" do
    # The same frame error at the other end: with the caret on the last line, the block was
    # allowed to scroll until the last line's ink ended at the widget's outer edge.
    input = tall_editor
    input.cursor_pos = TALL_VALUE.size
    input.scroll_offset = input.effective_scroll_offset

    top = line_y(input, "line12")
    top.should_not be_nil
    ink_bottom = top.not_nil! + CrymbleUI::TextLines.ref_h(input.font_size)
    ink_bottom.should be <= TALL_HEIGHT - (CrymbleUI::TextInput::BORDER_WIDTH + input.padding)
  end

  it "keeps a band lit at every scroll position while anything is hidden" do
    # The property the hint rests on, swept rather than spot-checked. A marker that switches
    # off while content is still hidden is worse than no marker.
    box = 90.0
    text = 200.0
    row = CrymbleUI::Rect.new(5.0, 4.0, box, 14.0)
    probe = ScrollBandProbe.new
    (0..(text - box).to_i).each do |i|
      offset = CrymbleUI::TextInput.derive_scroll_offset(0.0, i.to_f, text, box, CrymbleUI::TextInput::CURSOR_WIDTH)
      left, right = probe.clipped_text_bands(row, offset, text)
      (left || right).should_not be_nil, "no band lit at caret #{i} (offset #{offset})"
    end
  end
end

class ScrollBandProbe
  include CrymbleUI::PrimitiveBuilder
end
