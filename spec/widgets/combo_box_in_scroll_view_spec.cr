require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"
require "../../src/widgets/window"

# A filler row, so the content is taller than the viewport and the view can be scrolled.
class ComboScrollFiller < CrymbleUI::Widget
  def initialize
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, 50.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(constraints.max_width, 50.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# The popup is mounted into Window.overlays — WINDOW space. The combo inside a ScrollView
# keeps its laid-out (content) position, so anchoring the popup to `absolute_bounds` opens it
# `scroll_offset` pixels away from the control the user clicked. Same defect class as the drag ghost.
describe "ComboBox inside a scrolled ScrollView" do
  it "opens its popup at the cell the user sees" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 0.0)
    combo = CrymbleUI::ComboBox.new(items: ["A", "B", "C"], selected: 0, width: 150.0, id: "c")
    12.times { |i| vstack.add_child(i == 3 ? combo.as(CrymbleUI::Widget) : ComboScrollFiller.new) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window
    renderer.render_frame(app)

    scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 100.0))
    renderer.render_frame(app)

    painted = combo.viewport_bounds
    painted.y.should be_close(combo.absolute_bounds.y - 100.0, 0.5) # the view really is scrolled

    combo.expand
    popup = combo.current_popup.not_nil!

    popup.bounds.x.should be_close(painted.x, 0.5)
    popup.bounds.y.should be_close(painted.y + painted.height, 0.5)
  end
end
