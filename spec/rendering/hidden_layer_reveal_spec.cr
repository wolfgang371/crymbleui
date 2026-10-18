require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/layout/vstack"
require "../../src/rendering/layer_renderer"

# A panel covered by another renders nothing while covered - and must show, when revealed, everything that changed
# meanwhile. The reveal itself marks the panel (its title bar turns active), so a repaint request that a later mark
# can narrow is not enough.

RV_RED   = CrymbleUI::Color.new(200, 30, 30, 255)
RV_GREEN = CrymbleUI::Color.new(30, 200, 30, 255)
RV_BG1   = CrymbleUI::Color.new(60, 60, 60, 255)
RV_BG2   = CrymbleUI::Color.new(130, 130, 130, 255)

# An opaque cell; its colour is a plain property a spec sets live.
class RvCell < CrymbleUI::Widget
  property color : CrymbleUI::Color

  def initialize(@color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color)] of CrymbleUI::DrawPrimitive
  end
end

# "back" (a container with a fill around one cell) and "front", which covers it whole once raised.
class RevealApp < CrymbleUI::App
  property cell_color : CrymbleUI::Color = RV_RED

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Reveal", 300, 260)
    back = CrymbleUI::WindowPanel.new("Back", x: 20.0, y: 20.0, width: 200.0, height: 150.0, id: "back")
    stack = CrymbleUI::VStack.new(id: "stack", spacing: 4.0, padding: 16.0, background_color: RV_BG1)
    stack.add_child(RvCell.new(@cell_color, id: "cell"))
    stack.add_child(RvCell.new(RV_RED, id: "other"))
    back.add_child(stack)
    window.add_child(back)
    window.add_child(CrymbleUI::WindowPanel.new("Front", x: 10.0, y: 10.0, width: 260.0, height: 200.0, id: "front"))
    window
  end
end

private def rv_lr
  CrymbleUI::LayerRenderer
end

private def rv_panel(app, id) : CrymbleUI::WindowPanel
  app.find(id).as(CrymbleUI::WindowPanel)
end

private def rv_center(renderer, widget)
  b = widget.absolute_bounds
  renderer.backend.get_pixel((b.x + b.width / 2).to_i, (b.y + b.height / 2).to_i)
end

# The app with "back" rendered while on top, then covered by "front"; nobody holds the keyboard.
private def rv_covered : {RevealApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(300, 260)
  app = RevealApp.new
  app.build_tree
  renderer.settle_rendering(app)
  CrymbleUI::Widget.focus_manager.clear_focus
  rv_panel(app, "back").bring_to_front
  renderer.settle_rendering(app)
  rv_center(renderer, app.find("cell").not_nil!).should eq(RV_RED) # back shows, on top
  rv_panel(app, "front").bring_to_front
  renderer.settle_rendering(app)
  {app, renderer}
end

describe "a covered panel, revealed" do
  it "shows a widget that changed while it was covered" do
    app, renderer = rv_covered
    cell = app.find("cell").as(RvCell)
    cell.color = RV_GREEN
    cell.mark_needs_render
    renderer.settle_rendering(app) # covered: nothing of back renders

    rv_panel(app, "back").bring_to_front
    renderer.settle_rendering(app)
    rv_center(renderer, cell).should eq(cell.color) # before: red - the reveal repainted only the title bars
    renderer.exceptions_caught.should eq 0
  end

  it "shows a container whose fill changed while it was covered, and the child on it" do
    app, renderer = rv_covered
    stack = app.find("stack").as(CrymbleUI::VStack)
    stack.background_color = RV_BG2
    renderer.settle_rendering(app)

    rv_panel(app, "back").bring_to_front
    renderer.settle_rendering(app)
    sb = stack.absolute_bounds
    renderer.backend.get_pixel((sb.x + 4).to_i, (sb.y + 4).to_i).should eq(RV_BG2) # before: the old fill
    cell = app.find("cell").as(RvCell)
    rv_center(renderer, cell).should eq(cell.color)
    renderer.exceptions_caught.should eq 0
  end

  it "shows what a rebuild changed while it was covered, and a no-op rebuild after costs nothing" do
    # Control: with back VISIBLE the same rebuild re-renders exactly the changed cell - the rebuild's selective
    # branch, which is the one the covered case takes.
    renderer = CrymbleUI::Testing::TestRenderer.new(300, 260)
    visible = RevealApp.new
    visible.build_tree
    renderer.settle_rendering(visible)
    CrymbleUI::Widget.focus_manager.clear_focus
    rv_panel(visible, "back").bring_to_front
    renderer.settle_rendering(visible)
    visible.cell_color = RV_GREEN
    rv_lr.reset_frame_counters
    visible.request_rebuild
    renderer.render_frame(visible)
    rv_lr.frame_widget_count.should eq 1

    app, renderer = rv_covered
    app.cell_color = RV_GREEN
    app.request_rebuild
    renderer.settle_rendering(app)

    rv_panel(app, "back").bring_to_front
    renderer.settle_rendering(app)
    cell = app.find("cell").as(RvCell)
    rv_center(renderer, cell).should eq(cell.color) # before: red - the selective mark was dropped while covered

    rv_lr.reset_frame_counters
    app.request_rebuild
    renderer.render_frame(app)
    rv_lr.frame_widget_count.should eq 0 # the reveal recorded what it painted
    renderer.exceptions_caught.should eq 0
  end

  # Guard: green today; RED if every layer needing a render were cleared and repainted whole.
  it "a visible panel with one widget changed renders that widget only" do
    renderer = CrymbleUI::Testing::TestRenderer.new(300, 260)
    app = RevealApp.new
    app.build_tree
    renderer.settle_rendering(app)
    CrymbleUI::Widget.focus_manager.clear_focus
    rv_panel(app, "back").bring_to_front
    renderer.settle_rendering(app)
    cell = app.find("cell").as(RvCell)
    cell.color = RV_GREEN
    cell.mark_needs_render
    rv_lr.reset_frame_counters
    renderer.render_frame(app)
    rv_lr.frame_widget_count.should eq 1
    rv_center(renderer, cell).should eq(cell.color)
  end
end
