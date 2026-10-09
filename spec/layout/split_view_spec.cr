require "../spec_helper"
require "../../src/testing/driver"
require "../../src/layout/split_view"

# SplitView: panes side by side (or stacked) with a draggable bar in each gap - the classic splitter.
# And the hover hook it uses: a hovered widget is told where the mouse is (on_hover_move).

# A widget that records the hover points it is told about.
private class HoverProbe < CrymbleUI::Widget
  getter points = [] of CrymbleUI::Vec2

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200.0, 100.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end

  def on_hover_move(point : CrymbleUI::Vec2)
    @points << point
  end
end

private class HoverApp < CrymbleUI::App
  getter probe = HoverProbe.new(id: "probe")

  def build : CrymbleUI::Widget
    window("W", 800, 600) do
      vstack(padding: 50.0) { widget(@probe) }
    end
  end
end

# Three columns, the first split again into two rows; built anew on every rebuild, as DSL apps are.
private class SplitApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("W", 1000, 600) do
      split(id: "cols", ratios: [0.2, 0.3, 0.5], min_size: 50.0) do
        split(:vertical, id: "rows", ratios: [0.5, 0.5]) do
          text("top", id: "top")
          text("bottom", id: "bottom")
        end
        text("middle", id: "middle")
        text("right", id: "right")
      end
    end
  end
end

private def split_view(ui, id = "cols") : CrymbleUI::SplitView
  ui.find(id).as(CrymbleUI::SplitView)
end

private def widths(ui, id = "cols") : Array(Float64)
  split_view(ui, id).panes.map(&.bounds.width)
end

# Ink (pixels other than the first one) inside a widget, in the composited window.
private def ink(ui, id : String) : Int32
  r = ui.find(id).viewport_bounds
  px = ui.renderer.backend.get_pixels(r.x.to_i, r.y.to_i, r.width.to_i, r.height.to_i)
  px.count(&.!= px.first)
end

private def drag_bar(ui, id : String, bar : Int32, by : Float64, rebuild_midway = false)
  r = split_view(ui, id).bar_window_rect(bar)
  from = r.center
  vertical = split_view(ui, id).direction.vertical?
  to = vertical ? CrymbleUI::Vec2.new(from.x, from.y + by) : CrymbleUI::Vec2.new(from.x + by, from.y)
  ui.app.handle_mouse_down(from)
  if rebuild_midway
    ui.app.request_rebuild
    ui.settle
  end
  ui.app.handle_mouse_move(to)
  ui.app.handle_mouse_up(to)
  ui.settle
end

describe "on_hover_move" do
  it "tells the hovered widget where the mouse is, in its own space" do
    app = HoverApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    at = ui.find("probe").viewport_bounds
    ui.app.update_hover(CrymbleUI::Vec2.new(at.x + 10, at.y + 20))
    ui.app.update_hover(CrymbleUI::Vec2.new(at.x + 30, at.y + 20))
    app.probe.points.size.should eq 2
    a = ui.find("probe").absolute_bounds
    (app.probe.points.last.x - a.x).should eq 30.0
    (app.probe.points.last.y - a.y).should eq 20.0
  end
end

describe CrymbleUI::SplitView do
  it "shares the length by its ratios, leaving room for the bars" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    bar = CrymbleUI::SplitView::BAR
    w = widths(ui)
    total = split_view(ui).bounds.width - 2 * bar # the window's content area, not the window
    w[0].should be_close(total * 0.2, 1.0)
    w[1].should be_close(total * 0.3, 1.0)
    w[2].should be_close(total * 0.5, 1.0)
    split_view(ui).panes[1].bounds.x.should be_close(w[0] + bar, 1.0)
    # nested and vertical: two rows sharing the first column's height
    rows = split_view(ui, "rows").panes.map(&.bounds.height)
    rows[0].should be_close((split_view(ui, "rows").bounds.height - bar) / 2, 1.0)
  end

  it "drags a bar: only its two neighbours change, down to the minimum size" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    before = widths(ui)
    drag_bar(ui, "cols", 0, 100.0)
    after = widths(ui)
    (after[0] - before[0]).should be_close(100.0, 1.0)
    (after[1] - before[1]).should be_close(-100.0, 1.0)
    after[2].should be_close(before[2], 0.5)

    drag_bar(ui, "cols", 1, -1000.0) # far past the middle pane's minimum
    widths(ui)[1].should be_close(50.0, 1.0)
  end

  it "keeps its ratios through a rebuild, and a drag the rebuild interrupts" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    before = widths(ui)
    drag_bar(ui, "cols", 0, 80.0, rebuild_midway: true)
    (widths(ui)[0] - before[0]).should be_close(80.0, 1.0)
    ui.app.request_rebuild
    ui.settle
    (widths(ui)[0] - before[0]).should be_close(80.0, 1.0)
  end

  it "scales its panes with the space it is given" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    sv = split_view(ui)
    sv.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(2000.0, 600.0)), CrymbleUI::Vec2.zero)
    total = 2000.0 - 2 * CrymbleUI::SplitView::BAR
    sv.panes[2].bounds.width.should be_close(total * 0.5, 1.0)
  end

  it "shows the resize cursor over a bar and lights the bar up on hover" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    col_bar = split_view(ui).bar_window_rect(0).center
    row_bar = split_view(ui, "rows").bar_window_rect(0).center
    ui.app.get_cursor_for_point(col_bar).should eq CrymbleUI::CursorType::SizeHorizontal
    ui.app.get_cursor_for_point(row_bar).should eq CrymbleUI::CursorType::SizeVertical

    before = ui.renderer.backend.get_pixel(col_bar.x.to_i, col_bar.y.to_i)
    ui.app.update_hover(col_bar)
    ui.settle
    ui.renderer.backend.get_pixel(col_bar.x.to_i, col_bar.y.to_i).should_not eq before
    ui.app.update_hover(split_view(ui).panes[1].viewport_bounds.center) # off the bar again
    ui.settle
    ui.renderer.backend.get_pixel(col_bar.x.to_i, col_bar.y.to_i).should eq before
  end

  # The chrome/content law (LAYER_RENDERING_ARCHITECTURE.md): a bar lighting up must not repaint over
  # the panes. It once did - the split drew its bars itself, and a repaint of its whole area wiped
  # every pane until something made each one repaint (imagetagger: panes blank after a mouse pass).
  it "leaves the panes painted when a bar lights up and goes dark" do
    ui = CrymbleUI::Testing::Driver.new(SplitApp.new, 1000, 600)
    before = {ink(ui, "top"), ink(ui, "middle"), ink(ui, "right")}
    before.each(&.should(be > 0))
    bar = split_view(ui).bar_window_rect(0).center
    ui.app.update_hover(bar)
    ui.settle
    {ink(ui, "top"), ink(ui, "middle"), ink(ui, "right")}.should eq before
    ui.app.update_hover(CrymbleUI::Vec2.new(bar.x + 300, bar.y))
    ui.settle
    {ink(ui, "top"), ink(ui, "middle"), ink(ui, "right")}.should eq before
  end
end
