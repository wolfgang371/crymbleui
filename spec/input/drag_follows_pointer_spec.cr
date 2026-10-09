require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/testing/driver"

# THE TREE MOVES UNDER A STILL POINTER during a drag - a wheel scroll, a re-layout: the drop target, its
# highlight and a grid's target cell are what is under the pointer after it, and the release drops there.
# Each case names the mutation that turns it red.

# A block of a fixed height, full width.
private class Tall < CrymbleUI::Widget
  def initialize(@height : Float64)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 300.0, @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A draggable chip above a scrolled column of two drop zones, each 100 high.
class ZonesApp < CrymbleUI::App
  getter dropped = [] of String

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 400, 400, id: "window")
    outer = CrymbleUI::VStack.new(spacing: 0.0)
    outer.add_child(CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip")
      .tap(&.add_child(CrymbleUI::Text.new("chip"))))
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv", max_height: 150.0)
    column = CrymbleUI::VStack.new(spacing: 0.0)
    {"A", "B"}.each do |name|
      zone = CrymbleUI::DropZoneBox.new(accept_types: ["text"], id: "zone_#{name}",
        on_drop_handler: ->(_d : CrymbleUI::DragData, _p : CrymbleUI::Vec2) { @dropped << name; nil })
      zone.add_child(Tall.new(100.0))
      column.add_child(zone)
    end
    column.add_child(Tall.new(300.0)) # room to scroll
    sv.set_content(column)
    outer.add_child(sv)
    window.add_child(outer)
    window
  end
end

private def zones : {ZonesApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
  app = ZonesApp.new
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {app, renderer}
end

# Drag the chip onto zone A's centre, the drag active and A highlighted.
private def drag_onto_a(app) : CrymbleUI::Vec2
  from = app.find("chip").not_nil!.viewport_bounds.center
  at = app.find("zone_A").not_nil!.viewport_bounds.center
  app.handle_mouse_down(from)
  app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
  app.handle_mouse_move(at)
  app.drag_manager.dragging?.should be_true # instrument
  at
end

private def highlight(app) : CrymbleUI::Rect
  app.drag_manager.highlight_layer.not_nil!.bounds
end

describe "a drag whose target moves under a still pointer" do
  # Mutation: no per-frame re-resolve - the highlight and the drop stay on A.
  it "retargets to the zone the wheel brought under the pointer, and drops there" do
    app, renderer = zones
    at = drag_onto_a(app)
    4.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) } # 80px down: B under the pointer
    renderer.render_frame(app)
    b = app.find("zone_B").not_nil!.viewport_bounds
    b.contains_point(at).should be_true # instrument
    highlight(app).y.should be_close(b.y, 1.0)
    app.handle_mouse_up(at)
    app.dropped.should eq(["B"])
  end

  # Mutation: no re-place for an unchanged target - the highlight stays where A was.
  it "moves the highlight with the zone a small scroll keeps under the pointer" do
    app, renderer = zones
    at = drag_onto_a(app)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) # 20px: A still under the pointer
    renderer.render_frame(app)
    a = app.find("zone_A").not_nil!.viewport_bounds
    a.contains_point(at).should be_true # instrument
    # A's top has scrolled out: the highlight is its visible part, from the view's top to A's bottom
    highlight(app).y.should be_close(app.find("sv").not_nil!.viewport_bounds.y, 1.0)
    highlight(app).bottom.should be_close(a.bottom, 1.0)
    app.handle_mouse_up(at)
    app.dropped.should eq(["A"])
  end

  # A wheel and the release in one batch run no frame between them. Mutation: the release not re-resolving.
  it "drops on the zone under the pointer when the release follows the wheel without a frame" do
    app, renderer = zones
    at = drag_onto_a(app)
    4.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) }
    app.handle_mouse_up(at)
    app.dropped.should eq(["B"])
  end
end

describe "a cell drag whose grid scrolls under a still pointer" do
  # The grid's decal is drawn with the grid's scroll; its target cell must follow too. Mutation: no
  # per-frame on_drag_over - the decal names one cell, the drop lands on another.
  it "drops on the cell its decal shows" do
    adapter = MergeableTestAdapter.new(60, 4)
    ui = CrymbleUI::Testing::Driver.new(GridOnlyApp.new(adapter), 800, 600)
    app = ui.app
    ui.focus_cell "grid", 1, 1
    vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
    from = vm.active_cells[{1, 1}].viewport_bounds.center
    at = vm.active_cells[{5, 1}].viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
    app.handle_mouse_move(at)
    app.handle_mouse_move(at) # the first move enters the grid; this one names the cell
    before = vm.@drag_target_cell
    before.should_not be_nil # instrument
    3.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) }
    ui.settle
    grid = ui.find("grid").as(CrymbleUI::VirtualMatrix)
    grid.scroll_offset.y.should be > 0.0 # instrument: the grid scrolled under the pointer
    shown = grid.@drag_target_cell
    shown.should_not eq(before) # the decal names the cell now under the pointer
    app.handle_mouse_up(at)
    adapter.moves.last[1].should eq(shown)
  end
end

# One grid in a panel.
class GridOnlyApp < CrymbleUI::App
  def initialize(@adapter : MergeableTestAdapter)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 380.0, 300.0, id: "panel")
    panel.add_child(CrymbleUI::VirtualMatrix.new(adapter: @adapter, id: "grid"))
    window.add_child(panel)
    window
  end
end
