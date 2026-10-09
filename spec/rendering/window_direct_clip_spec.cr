require "../spec_helper"
require "../../src/testing/test_renderer"

# A window-direct draw (App#overlay_primitives, Renderer#render_primitives) has no clip stack. SFML used
# to ignore a clip there and draw its ink outside it; both renderers now refuse the list - before drawing
# any of it - with an error that frame recovery lets through, like a post-release use.
describe "window-direct draws refuse clip primitives" do
  it "raises WindowDirectClipError and draws nothing of the list" do
    renderer = CrymbleUI::Testing::TestRenderer.new(40, 30)
    fill = CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0), CrymbleUI::Color.new(1, 2, 3, 255))
    clip = CrymbleUI::PushClip.new(CrymbleUI::Rect.new(0.0, 0.0, 5.0, 5.0))
    untouched = renderer.backend.get_pixel(2, 2)
    expect_raises(CrymbleUI::WindowDirectClipError, /PushClip is not supported on a window-direct draw/) do
      renderer.render_primitives([fill, clip] of CrymbleUI::DrawPrimitive)
    end
    renderer.backend.get_pixel(2, 2).should eq untouched # the fill before the clip was not drawn either
  end

  it "draws a list without clips as before" do
    renderer = CrymbleUI::Testing::TestRenderer.new(40, 30)
    fill = CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, 10.0, 10.0), CrymbleUI::Color.new(1, 2, 3, 255))
    renderer.render_primitives([fill] of CrymbleUI::DrawPrimitive)
    renderer.backend.get_pixel(2, 2).should eq CrymbleUI::Color.new(1, 2, 3, 255)
  end
end
