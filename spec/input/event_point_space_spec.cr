require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# THE INVARIANT: a widget sees mouse and drop points in ITS OWN space — the same space its `bounds` live
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

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(constraints.max_width, 40.0))
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

# A drop target records the points its hooks are handed.
class DropSpy < SpacySpy
  include CrymbleUI::DropTarget
  getter dropped_at : CrymbleUI::Vec2? = nil
  getter over_at = [] of CrymbleUI::Vec2

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    true
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @dropped_at = position
  end

  def on_drag_over(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @over_at << position
  end
end

# A scrolled column: a draggable row, a drop target, a drop zone - each 40 high, scrolled by `scroll`.
private def scrolled_drop(scroll : Float64, zone_got : Array(CrymbleUI::Vec2))
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", 400, 300)
  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
  vstack = CrymbleUI::VStack.new(spacing: 0.0)
  source = CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "source")
  source.add_child(SpacySpy.new)
  target = DropSpy.new("target")
  zone = CrymbleUI::DropZoneBox.new(accept_types: ["text"],
    on_drop_handler: ->(_d : CrymbleUI::DragData, p : CrymbleUI::Vec2) { zone_got << p; nil }, id: "zone")
  zone.add_child(SpacySpy.new)
  12.times do |i|
    vstack.add_child(case i
                     when 2 then source.as(CrymbleUI::Widget)
                     when 4 then target.as(CrymbleUI::Widget)
                     when 5 then zone.as(CrymbleUI::Widget)
                     else        SpacySpy.new.as(CrymbleUI::Widget)
                     end)
  end
  sv.set_content(vstack)
  window.add_child(sv)
  app.root_widget = window
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  renderer.render_frame(app)
  sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll))
  renderer.render_frame(app)
  {app, source, target, zone}
end

# Press on the source, cross the threshold, move over `onto` twice (on_drag_over fires on the second -
# the first enters), release there - real App input, so the target is found by hit_test.
private def drag_onto(app, source : CrymbleUI::Widget, onto : CrymbleUI::Vec2) : Nil
  from = source.viewport_bounds
  app.handle_mouse_down(CrymbleUI::Vec2.new(from.x + 10.0, from.y + 10.0))
  app.handle_mouse_move(CrymbleUI::Vec2.new(from.x + 10.0, from.y + 30.0))
  app.handle_mouse_move(onto)
  app.handle_mouse_move(onto)
  app.handle_mouse_up(onto)
end

# The drop hooks are handlers too: DragManager hands a target its own space, as App does a mouse handler;
# a drop zone's app handler - there to place a menu - gets the window point, as a right-click's does.
# Mutations: drop the conversion at on_drop, at on_drag_over; drop the zone's conversion back.
describe "drop points delivered to a drop target inside a scrolled ScrollView" do
  it "arrive in the target's own space, over and on drop" do
    app, source, target, _zone = scrolled_drop(60.0, [] of CrymbleUI::Vec2)
    painted = target.viewport_bounds
    painted.y.should_not eq(target.absolute_bounds.y) # instrument: really scrolled
    drag_onto(app, source, CrymbleUI::Vec2.new(painted.x + 20.0, painted.y + 25.0))

    over = target.over_at.last? || fail "no on_drag_over reached the target"
    (over.y - target.absolute_bounds.y).should eq(25.0)
    dropped = target.dropped_at || fail "the drop did not reach the target"
    (dropped.y - target.absolute_bounds.y).should eq(25.0)
    (dropped.x - target.absolute_bounds.x).should eq(20.0)
  end

  it "hands a drop zone's handler the window point" do
    got = [] of CrymbleUI::Vec2
    app, source, _target, zone = scrolled_drop(60.0, got)
    painted = zone.viewport_bounds
    at = CrymbleUI::Vec2.new(painted.x + 12.0, painted.y + 18.0)
    drag_onto(app, source, at)
    got.should eq([at])
  end
end
