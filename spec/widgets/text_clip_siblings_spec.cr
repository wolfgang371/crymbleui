require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_item"
require "../../src/widgets/text"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# The X-only text clip, for the three non-editing text widgets. Same guard as
# text_clip_spec.cr: an overflowing value must not ink glyphs at or past the box its text
# is measured against, and the chrome must survive the clip.
#
# The chrome half is not paranoia. ComboBox draws its border as a `draw_rect` RING over the
# full bounds, and a checkable ComboBoxItem draws a real checkbox glyph at x in [2, ~16]
# while its LABEL starts at GUTTER_WIDTH + PADDING = 28. A clip wrapped naively around the
# whole primitive block would delete that checkbox from every checkable dropdown row.
#
# Probe discipline: these are GLYPH-INK examples, so they use an inking value. 'o' (0x6F)
# sets both stripe bits, so every glyph cell reaches x+6..x+7 and no probe region can slip
# between runs — 'm' (0x6D) inks only the left stripe and would pass on an unclipped widget.
CLIP_SIBLING_VALUE = "oooooooooooooooooooo"

class ComboClipApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("ComboClip", 120, 100) do
      vstack(padding: 0.0, spacing: 0.0) do
        combo_box(items: [CLIP_SIBLING_VALUE], selected: 0, id: "combo")
      end
    end
  end
end

class TextClipApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("TextClip", 120, 100) do
      vstack(padding: 0.0, spacing: 0.0) do
        # Constructed directly: the DSL `text` helper takes no padding, and padding is what
        # gives Text a text box narrower than its bounds — at the default 0.0 the box IS the
        # bounds and the clip is a no-op, so the guard could not go red.
        widget(CrymbleUI::Text.new(CLIP_SIBLING_VALUE, id: "label", padding: 6.0))
      end
    end
  end
end

class ItemClipApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("ItemClip", 120, 100) do
      vstack(padding: 0.0, spacing: 0.0) do
        widget(CrymbleUI::ComboBoxItem.new(CLIP_SIBLING_VALUE, id: "item"))
      end
    end
  end
end

# Columns of `widget`'s own backend carrying `color`, anywhere in its rows.
private def ink_columns(widget, color) : Array(Int32)
  cols = [] of Int32
  wb = widget.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  return cols unless wb
  (0...wb.width).each do |x|
    (0...wb.height).each do |y|
      if wb.get_pixel(x, y) == color
        cols << x
        break
      end
    end
  end
  cols
end

# The columns the instrument WOULD ink unclipped — its own stripe model, so an example can
# prove it probes a region the instrument can actually reach before asserting emptiness.
private def reachable_past(origin : Float64, font_size : Float64, chars : Int32,
                           edge : Int32, limit : Int32) : Array(Int32)
  pitch = (font_size * 0.6).to_i.clamp(4, 20)
  stripe = (pitch // 3).clamp(1, 4)
  cols = [] of Int32
  chars.times do |k|
    x = origin.to_i + pitch * k
    stripe.times { |s| cols << x + s; cols << x + pitch - stripe + s }
  end
  cols.select { |x| x >= edge && x < limit }
end

private def settled(app_class, renderer_w = 120, renderer_h = 100)
  renderer = CrymbleUI::Testing::TestRenderer.new(renderer_w, renderer_h)
  app = app_class.new
  app.build_tree
  renderer.settle_rendering(app)
  app
end

describe "the X-only text clip, across the non-editing text widgets" do
  it "ComboBox inks no glyph at or past its text box's right edge" do
    app = settled(ComboClipApp)
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    bounds = combo.absolute_bounds
    wb = combo.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)

    # ComboBox does NOT include FontScalable — it has no `font_size`; its own text is sized
    # from its FONT_SCALE constant, which is the expression the widget itself uses.
    combo_font_size = CrymbleUI::FontSizing.calculate_size(CrymbleUI::ComboBox::FONT_SCALE)
    right_edge = (bounds.width - CrymbleUI::ComboBox::PADDING).to_i
    # +1 char: the drawn string is "»#{value}", one glyph wider than the value.
    reachable_past(CrymbleUI::ComboBox::PADDING, combo_font_size, CLIP_SIBLING_VALUE.size + 1,
      right_edge, wb.width).should_not be_empty

    ink_columns(combo, CrymbleUI::Theme.current.combo_text).select { |x| x >= right_edge }.should be_empty
  end

  it "ComboBox keeps its border ring under an overflowing value" do
    app = settled(ComboClipApp)
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    bounds = combo.absolute_bounds
    wb = combo.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)

    border_x = (bounds.width - 1.0).to_i
    mid_y = (bounds.height / 2.0).to_i
    wb.get_pixel(border_x, mid_y).should eq(CrymbleUI::Theme.current.combo_border)
  end

  it "Text inks no glyph at or past its padded text box's right edge" do
    app = settled(TextClipApp)
    label = app.find("label").not_nil!.as(CrymbleUI::Text)
    bounds = label.absolute_bounds
    wb = label.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)

    right_edge = (bounds.width - label.padding).to_i
    reachable_past(label.padding, label.font_size, CLIP_SIBLING_VALUE.size,
      right_edge, wb.width).should_not be_empty

    ink_columns(label, label.color).select { |x| x >= right_edge }.should be_empty
  end

  it "ComboBoxItem inks no glyph at or past its text box's right edge" do
    app = settled(ItemClipApp)
    item = app.find("item").not_nil!.as(CrymbleUI::ComboBoxItem)
    bounds = item.absolute_bounds
    wb = item.widget_backend.as(CrymbleUI::Testing::TestRenderBackend)

    right_edge = (bounds.width - CrymbleUI::ComboBoxItem::PADDING).to_i
    reachable_past(CrymbleUI::ComboBoxItem::PADDING, item.font_size, CLIP_SIBLING_VALUE.size,
      right_edge, wb.width).should_not be_empty

    ink_columns(item, item.text_color).select { |x| x >= right_edge }.should be_empty
  end
end
