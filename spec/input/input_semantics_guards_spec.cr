require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/popup"
require "../../src/core/drag_manager"

# WHAT REAL INPUT DOES AROUND A HANDLER - pinned before the test Driver moves any of it.
#
# The Driver (src/testing/driver.cr) acts on widgets by id, and to do what real input does it
# shares three steps with the mouse path: closing popups and menus around a click
# (App#handle_mouse_down), the right-click bubble (Widget#on_mouse_down) and the drop
# (DragManager#end_drag). Each guard below holds the behaviour those steps must keep, through the
# REAL mouse path, and names the mutation that turns it red.

# Records whether (and how) a drag ended.
private class RecordingDraggable < CrymbleUI::Widget
  include CrymbleUI::Draggable

  getter ends = [] of Bool

  def initialize
    super(id: nil)
  end

  def get_drag_data : CrymbleUI::DragData?
    CrymbleUI::TextDragData.new("x")
  end

  def on_drag_end(data : CrymbleUI::DragData, dropped : Bool)
    @ends << dropped
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(100, 50))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class AcceptingTarget < CrymbleUI::Widget
  include CrymbleUI::DropTarget

  getter drops = 0

  def initialize
    super(id: nil)
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    true
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @drops += 1
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200, 100)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(200, 100))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class DragRoot < CrymbleUI::Widget
  def initialize
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(800, 600)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(800, 600))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Stands in for an open menu: anything Dismissable, closed by a click that is not a gesture on an
# overlay surface.
private class OpenThing < CrymbleUI::Widget
  include CrymbleUI::Dismissable

  getter? open = true

  def initialize
    super(id: "open_thing")
  end

  def dismiss_overlay : Bool
    was = @open
    @open = false
    was
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(10, 10)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(10, 10))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private def click(app, point : CrymbleUI::Vec2, button = CrymbleUI::MouseButton::Left)
  app.handle_mouse_down(point, button)
  app.handle_mouse_up(point)
end

private def centre(w : CrymbleUI::Widget) : CrymbleUI::Vec2
  b = w.viewport_bounds
  CrymbleUI::Vec2.new(b.x + b.width / 2, b.y + b.height / 2)
end

describe "real input around a handler" do
  # A popup lives in the window's OVERLAYS, which the production lookup does not walk - on purpose:
  # App#close_all_menus and Menu#on_click walk `find_all`, and seeing into popups would make them
  # close menus that live there. The test Driver walks overlays itself. If this ever flips, those
  # two callers change behaviour: look there first.
  it "mounts a context popup as an overlay, which the production lookup does not see" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    panel = CrymbleUI::WindowPanel.new("P", 100.0, 100.0, 300.0, 200.0)
    row = CrymbleUI::Button.new("row", id: "row") { }
    panel.add_child(row)
    window.add_child(panel)
    panel.on_right_click_handler = ->(_p : CrymbleUI::Vec2) {
      popup = CrymbleUI::Popup.new(width: 120.0, height: 40.0, id: "ctx")
      popup.add_child(CrymbleUI::Button.new("Rename", id: "ctx_rename") { })
      window.add_overlay(popup)
      nil
    }
    app.root_widget = window
    renderer.render_frame(app)

    click(app, centre(row), CrymbleUI::MouseButton::Right)
    renderer.render_frame(app)

    window.overlays.size.should eq(1)          # the menu opened
    app.find("ctx_rename").should be_nil       # ...and the production lookup cannot see into it
  end

  # Mutation: stop the walk after the clicked widget itself.
  it "bubbles a right-click to an ANCESTOR's handler, handing it a window point" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    panel = CrymbleUI::WindowPanel.new("P", 100.0, 100.0, 300.0, 200.0)
    row = CrymbleUI::Button.new("row", id: "row") { }
    panel.add_child(row)
    window.add_child(panel)
    got = nil.as(CrymbleUI::Vec2?)
    panel.on_right_click_handler = ->(p : CrymbleUI::Vec2) { got = p; nil }
    app.root_widget = window
    renderer.render_frame(app)

    at = centre(row)
    click(app, at, CrymbleUI::MouseButton::Right)
    got.should_not be_nil
    got.not_nil!.x.should be_close(at.x, 0.5)
    got.not_nil!.y.should be_close(at.y, 0.5)
  end

  # Mutation: move the raise into the right-click branch only.
  it "brings a panel to front on a LEFT mouse-down on its content" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    back = CrymbleUI::WindowPanel.new("Back", 100.0, 100.0, 300.0, 200.0, id: "back")
    back_row = CrymbleUI::Button.new("b", id: "back_row") { }
    back.add_child(back_row)
    front = CrymbleUI::WindowPanel.new("Front", 450.0, 100.0, 300.0, 200.0, id: "front")
    window.add_child(back)
    window.add_child(front)
    app.root_widget = window
    renderer.render_frame(app)
    front.bring_to_front
    renderer.render_frame(app)
    (front.z_index > back.z_index).should be_true # precondition

    click(app, centre(back_row))
    (back.z_index > front.z_index).should be_true
  end

  # Mutations: delete the on_drag_end call; hard-code dropped = false.
  it "tells the drag source whether its drop landed" do
    [true, false].each do |over_target|
      manager = CrymbleUI::DragManager.new
      source = RecordingDraggable.new
      target = AcceptingTarget.new
      root = DragRoot.new
      root.add_child(source)
      root.add_child(target)
      root.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)), CrymbleUI::Vec2.zero)
      source.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)), CrymbleUI::Vec2.new(10, 10))
      target.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)), CrymbleUI::Vec2.new(200, 200))

      release = over_target ? CrymbleUI::Vec2.new(250, 250) : CrymbleUI::Vec2.new(600, 500)
      manager.begin_drag_tracking(source, CrymbleUI::Vec2.new(20, 20))
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)
      manager.update_drag(release, root)
      manager.end_drag(release)

      source.ends.should eq([over_target])
      target.drops.should eq(over_target ? 1 : 0)
    end
  end

  # Mutation: skip closing popups on a mouse-down.
  it "closes a popup on a click outside it, and the click still reaches the widget there" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    clicks = 0
    under = CrymbleUI::Button.new("under", id: "under") { clicks += 1 }
    window.add_child(under)
    app.root_widget = window
    renderer.render_frame(app)
    popup = CrymbleUI::Popup.new(width: 100.0, height: 40.0, id: "pop")
    popup.target_x = 500.0
    popup.target_y = 400.0
    popup.on_click_outside_callback = ->{ window.remove_overlay(popup); nil }
    window.add_overlay(popup)
    renderer.render_frame(app)

    click(app, centre(under))
    window.overlays.should be_empty
    clicks.should eq(1)
  end

  # Closing a popup REMOVES it from the list being walked; walking that list itself skipped the
  # next popup. Mutation: iterate @overlays directly.
  it "closes every open popup on one click outside them" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    under = CrymbleUI::Button.new("under", id: "under") { }
    window.add_child(under)
    app.root_widget = window
    renderer.render_frame(app)
    [{400.0, "p1"}, {600.0, "p2"}].each do |x, id|
      popup = CrymbleUI::Popup.new(width: 100.0, height: 40.0, id: id)
      popup.target_x = x
      popup.target_y = 400.0
      popup.on_click_outside_callback = ->{ window.remove_overlay(popup); nil }
      window.add_overlay(popup)
    end
    renderer.render_frame(app)

    click(app, centre(under))
    window.overlays.should be_empty
  end

  # Mutations: drop the overlay-surface exemption (the first half goes red); skip closing
  # dismissables on a mouse-down (the second half goes red).
  it "keeps an open menu open on a click inside a popup, and closes it on a click elsewhere" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 800, 600)
    thing = OpenThing.new
    elsewhere = CrymbleUI::Button.new("elsewhere", id: "elsewhere") { }
    window.add_child(thing)
    window.add_child(elsewhere)
    app.root_widget = window
    popup = CrymbleUI::Popup.new(width: 100.0, height: 40.0, id: "pop")
    popup.target_x = 500.0
    popup.target_y = 400.0
    inside = CrymbleUI::Button.new("inside", id: "inside") { }
    popup.add_child(inside)
    window.add_overlay(popup)
    renderer.render_frame(app)

    click(app, centre(inside))
    thing.open?.should be_true
    click(app, centre(elsewhere))
    thing.open?.should be_false
  end
end
