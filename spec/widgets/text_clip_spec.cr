require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# The X-only text clip.
#
# The RED guard is the RIGHT edge. Today `draw_text` is emitted AFTER the four border
# rects (text_input.cr: borders, then draw_text), and the only clip in force is the
# widget's own bounds — so an overflowing value inks glyphs across the padding and
# straight over its own right border. That is what makes a "content is cut" marker a
# lie: the cut has to happen where the text box ends, not 5px later.
#
# This guard is also the ONLY thing that pins WHICH box the clip uses. The marker work
# deliberately makes the predicate and the geometry share one Rect, so a clip computed
# against `bounds.width` stays self-consistent and passes every marker example.
#
# Probe discipline: this is a GLYPH-INK example, so it uses an INKING value and probes no
# marker columns (no marker exists at this step). The character class is load-bearing and is
# asserted, not assumed: TestRenderBackend#draw_text inks a LEFT stripe iff `code & 0x01` and
# a RIGHT stripe iff `code & 0x02`. A value of 'm' (0x6D) inks only left stripes, which at
# pitch 8 from x=5 land on 53-54 and miss the probe region [55,60) entirely — the guard would
# pass on a completely unclipped widget. 'o' (0x6F) inks both, so every glyph cell reaches
# x+6..x+7 and no 5-wide region can slip between runs.
CLIP_GUARD_VALUE = "oooooooooooooooo"

class ClipGuardApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("ClipGuard", 400, 300) do
      vstack(padding: 20.0, spacing: 8.0) do
        text_input(id: "narrow", width: 60.0, value: CLIP_GUARD_VALUE)
        text_input(id: "roomy", width: 200.0, value: "oo")
      end
    end
  end
end

# The columns the instrument WOULD ink if nothing clipped the text — its own rasterisation
# model (test_render_backend.cr: char pitch, two stripes per cell), so an example can prove
# it is probing a region the instrument can actually reach.
private def unclipped_ink_columns(origin : Float64, font_size : Float64, chars : Int32) : Array(Int32)
  pitch = (font_size * 0.6).to_i.clamp(4, 20)
  stripe = (pitch // 3).clamp(1, 4)
  cols = [] of Int32
  chars.times do |k|
    x = origin.to_i + pitch * k
    stripe.times { |s| cols << x + s; cols << x + pitch - stripe + s }
  end
  cols
end

# Columns of `widget`'s own backend that carry `color`, within row range `rows`.
private def columns_with(widget, color, rows) : Array(Int32)
  cols = [] of Int32
  wb = widget.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  return cols unless wb
  (0...wb.width).each do |x|
    cols << x if rows.any? { |y| y < wb.height && wb.get_pixel(x, y) == color }
  end
  cols
end

describe "TextInput clips its text to the text box on the X axis" do
  it "inks no glyph at or past the text box's right edge, however long the value" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ClipGuardApp.new
    app.build_tree
    renderer.settle_rendering(app)

    input = app.find("narrow").not_nil!.as(CrymbleUI::TextInput)
    bounds = input.absolute_bounds

    # Derived from the widget, never hardcoded: this IS the box the text may occupy.
    text_origin_x = CrymbleUI::TextInput::BORDER_WIDTH + input.padding
    available_width = bounds.width - (CrymbleUI::TextInput::BORDER_WIDTH + input.padding) * 2
    right_edge = (text_origin_x + available_width).to_i

    # Preconditions — without both of these the guard is vacuous rather than green.
    # (1) the value really does overflow its box:
    text_width = CrymbleUI::Widget.measure_text(CLIP_GUARD_VALUE, input.font_size).width
    text_width.should be > available_width
    # (2) the instrument would ink inside the probe region if nothing clipped it. This is the
    # check that catches a value whose stripe pattern simply misses the region.
    wb = input.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)
    reachable = unclipped_ink_columns(text_origin_x, input.font_size, CLIP_GUARD_VALUE.size)
      .select { |x| x >= right_edge && x < wb.width }
    reachable.should_not be_empty

    rows = (0...bounds.height.to_i)
    inked = columns_with(input, input.text_color, rows)
    inked.should_not be_empty # the instrument really is drawing this value

    past_edge = inked.select { |x| x >= right_edge }
    past_edge.should be_empty
  end

  it "leaves the right border column intact under an overflowing value" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ClipGuardApp.new
    app.build_tree
    renderer.settle_rendering(app)

    input = app.find("narrow").not_nil!.as(CrymbleUI::TextInput)
    bounds = input.absolute_bounds
    border_x = (bounds.width - CrymbleUI::TextInput::BORDER_WIDTH).to_i

    input.focus_highlighted?.should be_false # else the border is focused_border_color
    wb = input.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)
    mid_y = (bounds.height / 2.0).to_i
    wb.get_pixel(border_x, mid_y).should eq(input.border_color)
  end

  it "leaves a value that fits untouched (the clip must not cut what already fits)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ClipGuardApp.new
    app.build_tree
    renderer.settle_rendering(app)

    input = app.find("roomy").not_nil!.as(CrymbleUI::TextInput)
    rows = (0...input.absolute_bounds.height.to_i)
    columns_with(input, input.text_color, rows).should_not be_empty
  end
end
