require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# THE INVARIANT: a widget sees mouse points in ITS OWN space — the same space its `bounds` live
# in — so the thing every handler already writes, `point - absolute_bounds`, is right without
# anyone having to think about scrolling.
#
# `hit_test` has always worked that way (ScrollView#hit_test converts the point for its children).
# Delivery did not: App found the widget with a converted point and then handed it the raw window
# point, so inside a view scrolled by 60 a widget localising a click read -40 where it should read
# 20. Everything that went wrong in the scrolled panel is that mismatch surfacing through a
# different consumer.
class SpacySpy < CrymbleUI::Widget
  getter seen : CrymbleUI::Vec2? = nil
  getter right_click_seen : CrymbleUI::Vec2? = nil

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
    @seen = point
    super(point, button)
  end

  def on_mouse_move(point : CrymbleUI::Vec2)
    @seen = point
  end

  def on_mouse_up(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @seen = point
  end
end

private def scrolled_spy(scroll : Float64)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", 400, 300)
  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
  vstack = CrymbleUI::VStack.new(spacing: 0.0)
  spy = SpacySpy.new("spy")
  12.times { |i| vstack.add_child(i == 4 ? spy.as(CrymbleUI::Widget) : SpacySpy.new) }
  sv.set_content(vstack)
  window.add_child(sv)
  app.root_widget = window
  renderer.render_frame(app)
  sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll))
  renderer.render_frame(app)
  {app, window, sv, spy}
end

describe "mouse points delivered to a widget inside a scrolled ScrollView" do
  it "arrive in the widget's own space, so localising against its bounds is correct" do
    app, _w, _sv, spy = scrolled_spy(60.0)
    painted = spy.viewport_bounds
    painted.y.should_not eq(spy.absolute_bounds.y) # instrument: really scrolled

    app.handle_mouse_down(CrymbleUI::Vec2.new(painted.x + 20.0, painted.y + 25.0))

    seen = spy.seen.should_not be_nil
    # The one line every handler writes.
    (seen.y - spy.absolute_bounds.y).should be_close(25.0, 0.5)
    (seen.x - spy.absolute_bounds.x).should be_close(20.0, 0.5)
  end

  it "does the same for move and up" do
    app, _w, _sv, spy = scrolled_spy(60.0)
    painted = spy.viewport_bounds

    # on_mouse_move only reaches a widget while the button is down (the drag path).
    app.handle_mouse_down(CrymbleUI::Vec2.new(painted.x + 10.0, painted.y + 2.0))
    app.handle_mouse_move(CrymbleUI::Vec2.new(painted.x + 10.0, painted.y + 30.0))
    (spy.seen.not_nil!.y - spy.absolute_bounds.y).should be_close(30.0, 0.5)

    app.handle_mouse_down(CrymbleUI::Vec2.new(painted.x + 10.0, painted.y + 5.0))
    app.handle_mouse_up(CrymbleUI::Vec2.new(painted.x + 10.0, painted.y + 5.0))
    (spy.seen.not_nil!.y - spy.absolute_bounds.y).should be_close(5.0, 0.5)
  end

  # THE OUTWARD CONTROL. A right-click handler exists to put something ON THE SCREEN — embrace
  # hangs its table/field context menus off it — so it is handed WINDOW coordinates, whatever
  # space the widget itself lives in. If this ever flips, menus open a scroll-offset away.
  it "hands right-click handlers a window point, not the widget's own" do
    app, _w, _sv, spy = scrolled_spy(60.0)
    painted = spy.viewport_bounds
    got = nil.as(CrymbleUI::Vec2?)
    spy.on_right_click_handler = ->(p : CrymbleUI::Vec2) { got = p; nil }

    click = CrymbleUI::Vec2.new(painted.x + 12.0, painted.y + 18.0)
    app.handle_mouse_down(click, CrymbleUI::MouseButton::Right)

    got.should_not be_nil
    got.not_nil!.y.should be_close(click.y, 0.5)
    got.not_nil!.x.should be_close(click.x, 0.5)
  end

  # Unscrolled, the spaces coincide and nothing may move.
  it "is exact when nothing is scrolled" do
    app, _w, _sv, spy = scrolled_spy(0.0)
    app.handle_mouse_down(CrymbleUI::Vec2.new(spy.absolute_bounds.x + 7.0, spy.absolute_bounds.y + 9.0))
    (spy.seen.not_nil!.y - spy.absolute_bounds.y).should be_close(9.0, 0.5)
  end
end
