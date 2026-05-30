require "../spec_helper"
require "../../src/testing/test_renderer"

# Specs for ScrollView#max_height / #max_width size-to-content behaviour.
#
# When max_height is set, the ScrollView shrinks vertically to the content's
# natural height up to the cap — short content takes no more space than it
# needs, long content caps at max_height and shows a scrollbar. Legacy (no
# max_height) behaviour remains: fill parent constraint, fall back to 200 px.

describe "ScrollView max_height / max_width size-to-content" do
  it "legacy: no max_height → fills parent or falls back to 200 px" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 2.0)
    2.times { vstack.add_child(CrymbleUI::Text.new("row")) }
    sv.set_content(vstack)

    # Unbounded measure: legacy fallback is 200 px.
    sized = sv.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(Float64::INFINITY, Float64::INFINITY)))
    sized.height.should eq 200.0
    sized.width.should eq 200.0
  end

  it "max_height shorter than content → caps at max_height" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 50.0)
    vstack = CrymbleUI::VStack.new(spacing: 2.0)
    20.times { vstack.add_child(CrymbleUI::Text.new("row")) }  # tall content
    sv.set_content(vstack)

    sized = sv.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(400.0, 1000.0)))
    sized.height.should eq 50.0  # capped
  end

  it "max_height longer than content → shrinks to content" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 500.0)
    short = CrymbleUI::Text.new("one line")
    sv.set_content(short)

    sized = sv.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(400.0, 1000.0)))
    # ScrollView shrinks to content — small text widget is way under 500 px.
    sized.height.should be < 500.0
    # And at least the content's intrinsic height.
    sized.height.should be > 0.0
  end

  it "max_height with no content attached → returns 0 (nothing to size to)" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 200.0)
    sized = sv.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(400.0, 1000.0)))
    sized.height.should eq 0.0
  end

  it "max_height with horizontal direction → does not cap (only affects scroll axis)" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal, max_height: 50.0)
    sv.set_content(CrymbleUI::Text.new("a"))
    sized = sv.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(400.0, 1000.0)))
    # Horizontal direction: max_height irrelevant, height uses legacy fallback (1000 from constraint).
    sized.height.should eq 1000.0
  end
end
