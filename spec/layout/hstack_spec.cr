require "../spec_helper"

# HStack used to TOP-align children (y = padding), so a row mixing a short bare text()
# label with a taller combo_box / button left the label riding high. A horizontal row
# should cross-axis CENTER its children. (Expanded children stay at the top — they
# typically fill or carry their own content.)
private class FixedBox < CrymbleUI::Widget
  def initialize(@w : Float64, @h : Float64)
    super(id: nil)
  end

  def measure(c : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@w, @h)
  end

  def perform_layout(c : CrymbleUI::BoxConstraints, pos : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(pos, measure(c))
  end

  def to_primitives(b : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

describe "HStack cross-axis (vertical) alignment" do
  it "vertically centers children of differing heights" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0)
    short = FixedBox.new(20.0, 10.0)
    tall = FixedBox.new(20.0, 30.0)
    hstack.add_child(short)
    hstack.add_child(tall)
    hstack.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(1000.0, 1000.0)), CrymbleUI::Vec2.zero)

    hstack.bounds.height.should eq(30.0) # tallest child sets the row height
    short.bounds.y.should eq(10.0)        # centered: (30 - 10) / 2, NOT 0 (top)
    tall.bounds.y.should eq(0.0)          # fills the height
  end

  it "keeps centering correct with padding" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 4.0)
    short = FixedBox.new(20.0, 10.0)
    tall = FixedBox.new(20.0, 30.0)
    hstack.add_child(short)
    hstack.add_child(tall)
    hstack.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(1000.0, 1000.0)), CrymbleUI::Vec2.zero)

    # inner band is [padding, padding + 30]; short centered within it
    short.bounds.y.should eq(4.0 + (30.0 - 10.0) / 2.0) # 14.0
    tall.bounds.y.should eq(4.0)
  end
end
