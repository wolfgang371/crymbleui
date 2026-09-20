require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

class ClickSpy < CrymbleUI::Widget
  getter clicked = false

  def initialize(id : String? = nil)
    super(id: id)
  end

  def measure(c : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(c.max_width, 40.0)
  end

  def perform_layout(c : CrymbleUI::BoxConstraints, p : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(p, CrymbleUI::Size.new(c.max_width, 40.0))
  end

  def to_primitives(b : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @clicked = true
  end
end

# The harness must click where the widget IS PAINTED. `click_on` feeds App's window-space entry
# point, so building that point from `absolute_bounds` aims at the unscrolled position: inside a
# scrolled view it lands on a different row, and the test passes or fails for the wrong reason.
describe "GUITestHelpers#click_on inside a scrolled ScrollView" do

  it "reaches the widget the user would see under the cursor" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 0.0)
    target = ClickSpy.new("target")
    decoy = ClickSpy.new("decoy")
    12.times do |i|
      vstack.add_child(case i
      when 4 then decoy.as(CrymbleUI::Widget)  # sits where the target's content bounds point
      when 7 then target.as(CrymbleUI::Widget)
      else        ClickSpy.new
      end)
    end
    sv.set_content(vstack)
    window.add_child(sv)
    app.root_widget = window
    renderer.render_frame(app)

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 120.0))
    renderer.render_frame(app)
    target.viewport_bounds.y.should_not eq(target.absolute_bounds.y) # instrument: really scrolled

    view = sv.viewport_bounds
    painted = target.viewport_bounds
    point = CrymbleUI::Vec2.new(painted.x + painted.width / 2, painted.y + painted.height / 2)
    geo = "scroll=#{sv.scroll_offset} view=#{view} painted=#{painted} " \
          "laid_out=#{target.absolute_bounds} point=#{point}"

    # Preconditions, each naming itself: a bare "clicked == false" says only that something went
    # wrong, and this spec exists to tell window space from content space. These are what
    # diagnosed the real cause - a spec elsewhere had redefined `click_on` for the whole binary.
    painted.y.should_not(eq(target.absolute_bounds.y), "nothing scrolled: #{geo}")
    inside = point.y > view.y && point.y < view.y + view.height
    inside.should(be_true, "the click point is outside the viewport: #{geo}")
    window.hit_test(point).should(eq(target), "hit_test found the wrong widget: #{geo}")

    click_on(app, target)

    target.clicked.should(be_true, "click_on did not reach the target: #{geo}")
    decoy.clicked.should(be_false, "click_on reached the DECOY, the unscrolled position: #{geo}")
  end
end
