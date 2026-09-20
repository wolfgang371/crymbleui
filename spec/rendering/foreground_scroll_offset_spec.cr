require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A DecoratedContainer's foreground is drawn AFTER its children, by a separate pass in
# layer_renderer. embrace's Configurator draws the reference arrows between table boxes that way,
# and Wolfgang photographed them (2026-09-20) sitting far from the boxes they connect once the
# Config tab is scrolled — the line keeps the position the content had at scroll 0.
class FgMarkedBox < CrymbleUI::DecoratedContainer
  MARK = CrymbleUI::Color.new(255, 0, 255, 255)
  BAND = 8.0

  def draw_foreground(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, BAND), MARK)
    end
  end
end

class FgFiller < CrymbleUI::Widget
  def initialize
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(constraints.max_width, 40.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

describe "foreground primitives inside a scrolled ScrollView" do
  it "moves with the content it decorates" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 0.0)
    box = FgMarkedBox.new
    box.add_child(FgFiller.new)
    12.times { |i| vstack.add_child(i == 4 ? box.as(CrymbleUI::Widget) : FgFiller.new) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    # Where the mark is painted in the window, top row of the band.
    mark_top = ->{
      top = nil.as(Int32?)
      y = 0
      while y < renderer.backend.height && top.nil?
        x = 0
        while x < renderer.backend.width
          if renderer.backend.get_pixel(x, y) == FgMarkedBox::MARK
            top = y
            break
          end
          x += 1
        end
        y += 1
      end
      top
    }

    before = mark_top.call
    before.should_not be_nil # instrument: the foreground is painted at all
    before.not_nil!.should be_close(box.absolute_bounds.y.to_i, 2)

    scroll = 60.0
    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll))
    renderer.render_frame(app)

    # The box scrolled up by `scroll`; its foreground must have gone with it.
    after = mark_top.call
    after.should_not be_nil
    after.not_nil!.should be_close(box.viewport_bounds.y.to_i, 2)
    (before.not_nil! - after.not_nil!).should be_close(scroll.to_i, 2)
  end
end
