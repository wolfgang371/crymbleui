require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# A selection must not bury the cut marker.
#
# The marker is emitted BEFORE the clipped block so it sits behind the glyphs; the selection
# highlight is emitted INSIDE that block, i.e. after it. Left alone, Ctrl+A on a long value
# therefore paints input_selection straight over the band — the hint disappears in exactly
# the state a user reaches for when they want to read or copy a value they cannot fully see.
#
# The fix is a reservation rather than a re-ordering: the highlight stops short of the band's
# columns. Re-ordering instead (band last) would put the band on top of the glyphs, and would
# also make its backdrop input_selection rather than the widget's own background — the colour
# it was derived against.
#
# Probe discipline: band assertions use an ink-free value ('d', code & 0x03 == 0) so no glyph
# stripe can be mistaken for a band or a highlight pixel.
SEL_LONG  = "dddddddddddddddddddd"
SEL_SHORT = "dd"

class MarkerSelectionApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("MarkerSel", 120, 120) do
      vstack(padding: 0.0, spacing: 0.0) do
        text_input(id: "cut", width: 60.0, value: SEL_LONG)
        text_input(id: "fits", width: 60.0, value: SEL_SHORT)
      end
    end
  end
end

private def select_all_in(id : String)
  renderer = CrymbleUI::Testing::TestRenderer.new(120, 120)
  app = MarkerSelectionApp.new
  app.build_tree
  renderer.settle_rendering(app)

  input = app.find(id).not_nil!.as(CrymbleUI::TextInput)
  click_on(app, input)
  press_key(SF::Keyboard::Key::A, control: true)
  renderer.settle_rendering(app)
  {app, input}
end

private def column_colors(widget, x : Int32) : Array(CrymbleUI::Color?)
  wb = widget.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)
  (0...wb.height).map { |y| wb.get_pixel(x, y) }
end

describe "a cut marker under an active selection" do
  it "survives select-all: the band keeps its own colour, the highlight stops short" do
    _, input = select_all_in("cut")
    input.has_selection?.should be_true # precondition: Ctrl+A really selected

    band_color = input.background_color.contrasting_neutral(
      CrymbleUI::PrimitiveBuilder::CLIPPED_MARKER_MIN_RATIO)
    bounds = input.absolute_bounds
    text_origin_x = CrymbleUI::TextInput::BORDER_WIDTH + input.padding
    available = bounds.width - (CrymbleUI::TextInput::BORDER_WIDTH + input.padding) * 2

    # Probe the LEFT band, not the right one. Ctrl+A puts the caret at the END, which scrolls
    # the view to the tail — and there the right band is DARK by construction
    # (text_width - offset == box_width - CURSOR_WIDTH, so nothing remains past the box) while
    # the left band carries the hint. The rightmost column belongs to the caret in that state,
    # which is correct: the caret is drawn inside the clip, i.e. on top of the band.
    input.effective_scroll_offset.x.should be > 0.0 # precondition: it really did scroll
    # The bar sits on the CELL's inner edge (just inside the border), not on the text box —
    # the text box is additionally inset by the padding, and a bar placed there floats short
    # of the edge its vertical twin sits on.
    probe_x = CrymbleUI::TextInput::BORDER_WIDTH.to_i
    colors = column_colors(input, probe_x)
    colors.should contain(band_color)
    colors.should_not contain(CrymbleUI::Theme.current.input_selection)
    available.should be > 0.0
  end

  it "does not shorten the highlight when there is no band to reserve for" do
    # The failure mode of an unconditional reserve: a fitting value has no band, so the
    # highlight must still run to the end of the text and leave no gap before the box edge.
    _, input = select_all_in("fits")
    input.has_selection?.should be_true

    text_width = CrymbleUI::Widget.measure_text(SEL_SHORT, input.font_size).width
    text_origin_x = CrymbleUI::TextInput::BORDER_WIDTH + input.padding
    last_x = (text_origin_x + text_width - 1.0).to_i

    column_colors(input, last_x).should contain(CrymbleUI::Theme.current.input_selection)
  end
end
