require "../spec_helper"
require "../../src/widgets/scroll_view"

# ScrollView's horizontal/vertical scrollbar decisions must be JOINT -- each axis's need must
# account for the 16px the OTHER scrollbar steals from it. VirtualMatrix#effective_content_size
# already resolves jointly; ScrollView#needs_* did not, so at the boundary band (content fits the
# full viewport but NOT the viewport minus the vscrollbar) the two layers disagreed about the bottom
# 16px strip and the last partial row landed in limbo. This pins the joint invariant.
describe "ScrollView scrollbar resolution at the boundary" do
  it "needs the horizontal scrollbar when the vertical scrollbar's 16px pushes content past the usable width" do
    sb = CrymbleUI::ScrollView::SCROLLBAR_WIDTH
    sv = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, id: "sv")
    sv.viewport_size = CrymbleUI::Size.new(200.0, 100.0)
    # content TALLER than the viewport -> vscroller needed; content WIDTH in the band (200-sb, 200]:
    # it fits the full 200 viewport, but NOT the 200-16=184 left after the vscrollbar takes its space.
    sv.content_size = CrymbleUI::Size.new(200.0 - sb / 2.0, 100.0 + 50.0) # width 192, height 150

    sv.needs_vertical_scrollbar?.should be_true # 150 > 100
    # JOINT: the vscroller ate 16px -> usable width 184; content 192 > 184 -> the hscroller IS needed.
    # (Non-joint bug: 192 > 200 is false -> wrongly decides "no hscroller".)
    sv.needs_horizontal_scrollbar?.should be_true
  end
end
