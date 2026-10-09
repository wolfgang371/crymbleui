require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A REBUILD DURING A PRESS OR A DRAG hands the gesture to the widgets that replace the ones it began on -
# the ones RECONCILE paired them with (by id, else by index and class), never merely the first widget whose
# path matches. And a drag whose source a rebuild removes ends cleanly; one whose target it removes or
# replaces keeps an honest highlight. Each case names the mutation that turns it red.

# A block that records releases as "<its parent's id>:<its index among its siblings>", and asks for a
# rebuild when pressed.
class ReleaseRecorder < CrymbleUI::Widget
  class_getter released = [] of String

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(100.0, 40.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left) : Bool
    CrymbleUI::Widget.app?.not_nil!.request_rebuild
    true
  end

  def on_mouse_up(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    holder = parent.not_nil!
    @@released << "#{holder.id}:#{holder.children.index { |c| c.same?(self) }}"
  end
end

# A drop target that paints from drag_hover? (the documented pattern) and counts the entries it hears.
class HoverTarget < CrymbleUI::Widget
  include CrymbleUI::DropTarget
  class_getter entered = 0

  def self.reset : Nil
    @@entered = 0
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    true
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
  end

  def on_drag_enter(data : CrymbleUI::DragData)
    @@entered += 1
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200.0, 60.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(200.0, 60.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Takes a drop zone's place and size, but takes no drop.
class ZoneGap < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200.0, 60.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(200.0, 60.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A column built afresh each build from a list of widget makers; `parts` may change between builds.
class ColumnApp < CrymbleUI::App
  property parts : Array(-> CrymbleUI::Widget)

  def initialize(@parts)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 600, 500, id: "window")
    column = CrymbleUI::VStack.new(spacing: 10.0, id: "column")
    @parts.each { |make| column.add_child(make.call) }
    window.add_child(column)
    window
  end
end

private def run(parts : Array(-> CrymbleUI::Widget)) : {ColumnApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 500)
  app = ColumnApp.new(parts)
  CrymbleUI::Widget.app = app # as the renderer's run does: a widget asks its app for a rebuild
  app.build_tree
  renderer.render_frame(app)
  {app, renderer}
end

private def column(app) : Array(CrymbleUI::Widget)
  app.find("column").not_nil!.children
end

# An id-less, label-less draggable block: two of them share one path_id.
private def chip(text : String) : -> CrymbleUI::Widget
  -> { CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new(text)).tap(&.add_child(ReleaseRecorder.new)).as(CrymbleUI::Widget) }
end

private def zone(id : String) : -> CrymbleUI::Widget
  -> { CrymbleUI::DropZoneBox.new(accept_types: ["text"], id: id).tap(&.add_child(HoverTarget.new)).as(CrymbleUI::Widget) }
end

private BELOW = CrymbleUI::Vec2.new(0.0, 12.0)

describe "a rebuild during a press re-finds what reconcile paired" do
  # Mutation: re-find the pressed widget by path - the first of two id-less siblings answers.
  it "hands the release to the rebuilt widget that was pressed, not its first same-path sibling" do
    ReleaseRecorder.released.clear
    make = -> { ReleaseRecorder.new.as(CrymbleUI::Widget) }
    app, renderer = run([make, make])
    second = column(app)[1]
    at = second.viewport_bounds.center
    app.handle_mouse_down(at) # the press asks for a rebuild, applied inside the press
    column(app)[1].same?(second).should be_false # instrument: the pressed widget was replaced
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should eq(["column:1"])
  end

  # Reconcile can pair one old widget twice: by id with a new sibling, then by index with the id-less one
  # that took its place - or by index first, then by id. The id match is the widget either way. Mutations:
  # the later pairing wins (this case); the first pairing wins (the next).
  it "hands the release to the id-matched widget when reconcile paired the pressed one twice" do
    ReleaseRecorder.released.clear
    app, renderer = run([-> { CrymbleUI::Text.new("first").as(CrymbleUI::Widget) },
                         -> { ReleaseRecorder.new(id: "x").as(CrymbleUI::Widget) }])
    pressed = column(app)[1]
    at = pressed.viewport_bounds.center
    app.parts = [-> { ReleaseRecorder.new(id: "x").as(CrymbleUI::Widget) }, # the pressed one, by id, first
                 -> { ReleaseRecorder.new.as(CrymbleUI::Widget) }]           # an id-less one at its old index
    app.handle_mouse_down(at) # the press's rebuild builds the new parts
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should eq(["column:0"])
  end

  it "hands the release to the id-matched widget when the index pairing came first" do
    ReleaseRecorder.released.clear
    app, renderer = run([-> { ReleaseRecorder.new(id: "x").as(CrymbleUI::Widget) }])
    at = column(app)[0].viewport_bounds.center
    app.parts = [-> { ReleaseRecorder.new.as(CrymbleUI::Widget) },          # an id-less one at its old index
                 -> { ReleaseRecorder.new(id: "x").as(CrymbleUI::Widget) }] # the pressed one, by id, later
    app.handle_mouse_down(at)
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should eq(["column:1"])
  end

  # The id decision holds for what is INSIDE the double-paired widget too: its children are paired under
  # both copies (by index), and the one under the id-matched copy is the pressed widget. Mutation: a child's
  # pairing not following its parent's.
  it "hands the release to the widget inside the id-matched copy of its container" do
    ReleaseRecorder.released.clear
    holder = ->(id : String?) { -> { CrymbleUI::VStack.new(id: id).tap(&.add_child(ReleaseRecorder.new)).as(CrymbleUI::Widget) } }
    app, renderer = run([holder.call("x")])
    at = column(app)[0].children[0].viewport_bounds.center
    app.parts = [holder.call(nil), holder.call("x")] # an id-less copy at the old index, the id'd one after
    app.handle_mouse_down(at)
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should eq(["x:0"])
  end

  # The id-matched copy of the container holds no counterpart of the pressed widget (the index copy does):
  # the widget is gone - whichever order reconcile paired the container in. Mutation: counterpart answering a
  # pairing made under a copy its container has since left.
  it "loses the press when the id-matched copy of its container has no counterpart for it" do
    ReleaseRecorder.released.clear
    holder = ->(id : String?, inside : Bool) {
      -> { CrymbleUI::VStack.new(id: id).tap { |v| v.add_child(ReleaseRecorder.new) if inside }.as(CrymbleUI::Widget) }
    }
    app, renderer = run([holder.call("x", true)])
    at = column(app)[0].children[0].viewport_bounds.center
    app.parts = [holder.call(nil, true), holder.call("x", false)] # index copy first, holding a recorder
    app.handle_mouse_down(at)
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should be_empty
  end

  # The same one level deeper: the pressed widget's container is gone, so the widget is too - not left in
  # the copy its container's container left. Mutation: counterpart checking only the immediate container.
  it "loses the press when a container above it has no counterpart in the id-matched copy" do
    ReleaseRecorder.released.clear
    outer = ->(id : String?, inside : Bool) {
      -> {
        CrymbleUI::VStack.new(id: id).tap do |v|
          v.add_child(CrymbleUI::VStack.new(id: "inner").tap(&.add_child(ReleaseRecorder.new))) if inside
        end.as(CrymbleUI::Widget)
      }
    }
    app, renderer = run([outer.call("x", true)])
    at = column(app)[0].children[0].children[0].viewport_bounds.center
    app.parts = [outer.call(nil, true), outer.call("x", false)]
    app.handle_mouse_down(at)
    app.handle_mouse_up(at)
    ReleaseRecorder.released.should be_empty
  end

  # The payload was already right (taken from the pressed instance); what the path re-find got wrong is
  # the SOURCE - the ghost sized and placed from the first sibling. Mutation: re-find the source by path.
  it "keeps the pressed draggable as the drag's source across a rebuild before the threshold" do
    app, renderer = run([chip("a"), chip("b")])
    pressed = column(app)[1]
    from = pressed.viewport_bounds.center
    app.handle_mouse_down(from)
    app.rebuild
    renderer.render_frame(app)
    app.handle_mouse_move(from + BELOW)
    source = app.drag_manager.state.source_widget.not_nil!
    source.same?(column(app)[1]).should be_true
    ghost = app.drag_manager.ghost_layer.not_nil!.bounds
    ghost.y.should be_close(column(app)[1].viewport_bounds.y + BELOW.y, 0.5)
    app.handle_mouse_up(from + BELOW)
  end
end

describe "a rebuild during a drag that removes or replaces its widgets" do
  # Mutation: reset the state instead of ending the drag - the ghost and the highlight stay drawn.
  it "ends the drag cleanly when its source is removed" do
    src = chip("a")
    app, renderer = run([src, zone("z")])
    from = column(app)[0].viewport_bounds.center
    over = column(app)[1].viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + BELOW)
    app.handle_mouse_move(over)
    app.handle_mouse_move(over)
    app.drag_manager.highlight_layer.not_nil!.composite_anchor.should_not be_nil # instrument: highlighted
    app.parts = [zone("z")]
    app.rebuild
    renderer.render_frame(app)
    app.drag_manager.ghost_layer.should be_nil
    app.drag_manager.highlight_layer.should be_nil
    app.drag_manager.state.phase.idle?.should be_true
  end

  # Mutation: keep the highlight of a target the rebuild removed.
  it "hides the highlight of a target the rebuild removed, and highlights the next one" do
    app, renderer = run([chip("a"), zone("z1"), zone("z2")])
    from = column(app)[0].viewport_bounds.center
    over = column(app)[1].viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + BELOW)
    app.handle_mouse_move(over)
    app.parts = [chip("a"), -> { ZoneGap.new.as(CrymbleUI::Widget) }, zone("z2")] # z1 goes; nothing takes a drop there
    app.rebuild
    renderer.render_frame(app)
    app.drag_manager.dragging?.should be_true
    app.drag_manager.highlight_layer.not_nil!.composite_anchor.should be_nil # hidden
    z2 = column(app)[2].viewport_bounds
    app.handle_mouse_move(z2.center)
    app.drag_manager.highlight_layer.not_nil!.bounds.y.should be_close(z2.y, 1.0)
    app.handle_mouse_up(z2.center)
  end

  # Mutation: no re-announce to a replaced target - the new instance is not hovered and heard no entry.
  it "tells a target the rebuild replaced that the drag is over it" do
    HoverTarget.reset
    target = -> { HoverTarget.new.as(CrymbleUI::Widget) }
    app, renderer = run([chip("a"), target])
    from = column(app)[0].viewport_bounds.center
    over = column(app)[1].viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + BELOW)
    app.handle_mouse_move(over)
    HoverTarget.entered.should eq(1)
    app.rebuild
    renderer.render_frame(app)
    fresh = column(app)[1].as(HoverTarget)
    fresh.drag_hover?.should be_true
    HoverTarget.entered.should eq(2)
    app.handle_mouse_up(over)
  end
end
