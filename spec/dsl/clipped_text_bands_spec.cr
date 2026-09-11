require "../spec_helper"
require "../../src/dsl/primitive_builder"
require "../../src/core/font_sizing"

# The cut-content marker's geometry and per-edge predicate, as a pure function.
#
# Asserting the returned rects rather than pixels is deliberate. The marker is drawn BEHIND
# the text, so its columns are exactly where cut glyphs ink — a pixel probe there is
# ambiguous unless the value is chosen to ink nothing, and several of these cases (a 1px
# floor at a 2px box, a band's y/height) cannot be distinguished by ink at all.
class BandGeometryProbe
  include CrymbleUI::PrimitiveBuilder
end

private def bands(row_x, row_w, offset, text_width, row_y = 4.0, row_h = 14.0)
  BandGeometryProbe.new.clipped_text_bands(
    CrymbleUI::Rect.new(row_x, row_y, row_w, row_h), offset, text_width)
end

describe "PrimitiveBuilder#clipped_text_bands" do
  it "lights nothing when the text fits" do
    left, right = bands(5.0, 90.0, 0.0, 90.0)
    left.should be_nil
    right.should be_nil
  end

  it "lights the RIGHT edge when the text runs past the box" do
    left, right = bands(5.0, 90.0, 0.0, 200.0)
    left.should be_nil
    right.should_not be_nil
    right.not_nil!.x.should be > 5.0
  end

  it "lights the LEFT edge as soon as the view is scrolled, and only then" do
    bands(5.0, 90.0, 0.0, 200.0)[0].should be_nil
    bands(5.0, 90.0, 1.0, 200.0)[0].should_not be_nil
  end

  it "lights BOTH edges when content is hidden on both sides" do
    left, right = bands(5.0, 90.0, 40.0, 200.0)
    left.should_not be_nil
    right.should_not be_nil
  end

  it "keeps at least one edge lit at every scroll position while anything is hidden" do
    # The property the whole hint rests on: a marker that switches off while content is
    # still hidden is worse than no marker. Sweep the whole scroll range, including the
    # tail, where the right edge legitimately goes dark and the left must carry it.
    row_w = 90.0
    text_w = 200.0
    (0..(text_w - row_w).to_i).each do |off|
      left, right = bands(5.0, row_w, off.to_f, text_w)
      (left || right).should_not be_nil, "no band lit at offset #{off}"
    end
  end

  it "lights nothing for an empty string, however narrow the box" do
    bands(5.0, 2.0, 0.0, 0.0).should eq({nil, nil})
  end

  it "spans the text row exactly — never the whole widget" do
    _, right = bands(5.0, 90.0, 0.0, 200.0)
    band = right.not_nil!
    band.y.should eq(4.0)
    band.height.should eq(14.0)
  end

  it "keeps a visible band in a box too narrow to hold a full-width one" do
    # A column dragged to its minimum must still say its content is cut. The band is capped
    # at a third of the box so it cannot swallow the cell, but the cap must never win over
    # the 1px floor — which is what a naive `clamp(1.0, w/3.0)` would do, since Crystal's
    # clamp tests max first and would return the sub-pixel cap.
    _, right = bands(5.0, 2.0, 0.0, 200.0)
    right.not_nil!.width.should eq(1.0)
  end

  it "still marks a box whose width has gone NEGATIVE" do
    # embrace's narrowest column leaves a cell smaller than the widget's own chrome, so the
    # text box width is negative. That is the state where EVERYTHING is hidden, so it is the
    # last state that may lose the hint.
    left, right = bands(5.0, -3.0, 0.0, 200.0)
    (left || right).should_not be_nil
    band = (right || left).not_nil!
    band.width.should be >= 1.0
    band.x.should be >= 0.0
  end
end
