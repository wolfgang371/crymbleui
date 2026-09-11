require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/widgets/combo_box"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# A widget can report the width its content actually needs.
#
# Neither TextInput nor ComboBox reports one today: both return
# `@explicit_width || constraints.max_width` with a 200.0 fallback, under a comment in ComboBox
# that claims "then natural". embrace's auto-size needs the real number to size a column
# to its cells.
#
# It is deliberately NOT `min_intrinsic_width`. That protocol answers "smallest acceptable
# width", and WindowPanel feeds it into `panel_min_width` — so a TextInput answering it with its
# content would make a typed-in value a panel's drag floor. It is also semantically wrong: a
# TextInput legitimately shrinks below its content, scrolling and painting the cut band, which
# is the affordance auto-size relies on. Hence a separate query, and the regression examples
# below that pin the two existing protocols in place.

private def loose : CrymbleUI::BoxConstraints
    CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(Float64::INFINITY, Float64::INFINITY))
end

private def tightish : CrymbleUI::BoxConstraints
    CrymbleUI::BoxConstraints.new(min_width: 0.0, max_width: 120.0, min_height: 0.0, max_height: 20.0)
end

describe "content width" do
    before_each { CrymbleUI::Widget.font = CrymbleUI::Testing::TestFont.new }

    describe "the regression that must NOT move" do
        it "TextInput#measure is unchanged under loose and bounded constraints" do
            ti = CrymbleUI::TextInput.new(value: "a rather long value indeed")
            # Loose: no finite max — the documented 200.0 fallback, NOT the content width.
            ti.measure(loose).width.should eq(200.0)
            # Bounded: fills its constraint, which is what every dialog field relies on.
            ti.measure(tightish).width.should eq(120.0)
        end

        it "ComboBox#measure is unchanged under loose and bounded constraints" do
            cb = CrymbleUI::ComboBox.new(items: ["a rather long value indeed"], selected: 0)
            cb.measure(loose).width.should eq(200.0)
            cb.measure(tightish).width.should eq(120.0)
        end

        it "min_intrinsic_width stays the SMALLEST acceptable width, not the content width" do
            # If this ever starts reporting the content width, a Shape panel can no longer be
            # dragged narrower than whatever someone typed into its filter box.
            short = CrymbleUI::TextInput.new(value: "x")
            long = CrymbleUI::TextInput.new(value: "an extremely long value that would be wide")
            short.min_intrinsic_width(20.0).should eq(long.min_intrinsic_width(20.0))
        end

        it "the floor a panel reads does not follow the text typed into it" do
            # WindowPanel#recompute_content_min does `@content_min_width =
            # @content.min_intrinsic_width(...)` and feeds it to panel_min_width, so the content
            # stack's answer IS the panel's drag floor. Asserting it here keeps the example on
            # the mechanism rather than on WindowPanel's construction API.
            field = CrymbleUI::TextInput.new(value: "x")
            stack = CrymbleUI::VStack.new
            stack.add_child(field)
            floor_before = stack.min_intrinsic_width(100.0)
            field.value = "an extremely long value that would be wide"
            stack.min_intrinsic_width(100.0).should eq(floor_before)
        end
    end

    describe "the new query" do
        it "TextInput reports the width its own text needs" do
            ti = CrymbleUI::TextInput.new(value: "hello")
            measured = CrymbleUI::Widget.measure_text("hello", ti.font_size).width
            ti.content_width.should be_close(measured + (ti.padding + CrymbleUI::TextInput::BORDER_WIDTH) * 2, 0.01)
        end

        it "at the reported width the text is NOT cut, one pixel narrower it is" do
            # The independent oracle: the cut-marker band, found by geometry. Asserting the
            # arithmetic against itself would prove nothing.
            value = "dddddddddddddddddddd"
            ti = CrymbleUI::TextInput.new(value: value)
            w = ti.content_width
            band_at = ->(box_w : Float64) {
                probe = CrymbleUI::TextInput.new(value: value, width: box_w)
                prims = probe.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, box_w, 20.0))
                band_w = CrymbleUI::PrimitiveBuilder::CLIPPED_MARKER_WIDTH * CrymbleUI::FontSizing.zoom_factor
                edge = box_w - CrymbleUI::TextInput::BORDER_WIDTH
                !prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))
                    .find { |f| (f.bounds.x + f.bounds.width - edge).abs < 0.5 && f.bounds.width <= band_w + 0.5 }.nil?
            }
            band_at.call(w).should be_false
            band_at.call(w - 2.0).should be_true
        end

        it "ComboBox includes the prefix it actually paints" do
            # The collapsed ComboBox renders "»value"; a consumer must not have to know that.
            cb = CrymbleUI::ComboBox.new(items: ["hello"], selected: 0)
            # ComboBox does not mix in FontScalable — it sizes from its own FONT_SCALE.
            font_size = CrymbleUI::FontSizing.calculate_size(CrymbleUI::ComboBox::FONT_SCALE)
            bare = CrymbleUI::Widget.measure_text("hello", font_size).width
            with_prefix = CrymbleUI::Widget.measure_text("»hello", font_size).width
            cb.content_width.should be > bare
            cb.content_width.should be_close(with_prefix + (CrymbleUI::ComboBox::PADDING + CrymbleUI::ComboBox::BORDER_WIDTH) * 2, 0.01)
        end
    end
end
