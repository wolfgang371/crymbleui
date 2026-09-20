require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# THE SWEEP. One invariant, every scroll configuration: a widget whose ancestors scroll keeps its
# laid-out bounds, so everything that MEETS THE CURSOR or LEAVES THE WIDGET TREE must use the
# painted position, and everything a widget is HANDED must already be in its own space.
#
# Written because fixing the reported symptoms one at a time is not coverage: the same missing
# term produced a drag ghost far below the cursor, a dropdown opening in the wrong place, the
# Configurator's arrows left behind, and a cell editor popping up in a scrolled grid's unscrolled
# position. This asserts the rule for each consumer across the axis configurations, with an
# unscrolled control that must stay exact.
class SweepRow < CrymbleUI::Widget
  include CrymbleUI::Draggable
  include CrymbleUI::DropTarget

  getter seen : CrymbleUI::Vec2? = nil
  getter dropped = false

  def initialize(@label : String, id : String? = nil)
    super(id: id)
  end

  def get_drag_data : CrymbleUI::DragData?
    CrymbleUI::TextDragData.new(@label)
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    data.data_type == "text"
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @dropped = true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(300.0, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(300.0, 40.0))
  end

  def to_primitives(b : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @seen = point
    super(point, button)
  end
end

class SweepFgBox < CrymbleUI::DecoratedContainer
  MARK = CrymbleUI::Color.new(255, 0, 255, 255)

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(300.0, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(300.0, 40.0))
  end

  def draw_foreground(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, 6.0), MARK)
    end
  end
end

class SweepFiller < CrymbleUI::Widget
  def initialize(id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(300.0, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(300.0, 40.0))
  end

  def to_primitives(b : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private def build_sweep(direction : CrymbleUI::ScrollDirection, scroll : CrymbleUI::Vec2)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  window = CrymbleUI::Window.new("Sweep", 400, 300)
  root = CrymbleUI::VStack.new(spacing: 0.0)

  sv = CrymbleUI::ScrollView.new(direction: direction, max_height: 260.0, max_width: 200.0, id: "sv")
  content = CrymbleUI::VStack.new(spacing: 0.0)
  drag_row = SweepRow.new("drag", id: "drag_row")
  drop_row = SweepRow.new("drop", id: "drop_row")
  fg_box = SweepFgBox.new
  fg_box.add_child(SweepFiller.new)
  combo = CrymbleUI::ComboBox.new(items: ["A", "B", "C"], selected: 0, width: 120.0, id: "combo")
  inner = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 60.0, id: "inner")
  inner_content = CrymbleUI::VStack.new(spacing: 0.0)
  3.times { inner_content.add_child(SweepFiller.new) }
  inner.set_content(inner_content)

  14.times do |i|
    content.add_child(case i
    when 1 then drag_row.as(CrymbleUI::Widget)
    when 2 then drop_row.as(CrymbleUI::Widget)
    when 3 then fg_box.as(CrymbleUI::Widget)
    when 4 then combo.as(CrymbleUI::Widget)
    when 5 then inner.as(CrymbleUI::Widget)
    else SweepFiller.new
    end)
  end
  sv.set_content(content)
  root.add_child(sv)

  outside = CrymbleUI::Button.new("outside", id: "outside") { }
  root.add_child(outside)

  window.add_child(root)
  app.root_widget = window
  renderer.render_frame(app)
  sv.set_scroll_offset_for_test(scroll)
  renderer.render_frame(app)

  {renderer: renderer, app: app, window: window, sv: sv, drag_row: drag_row, drop_row: drop_row,
   fg_box: fg_box, combo: combo, inner: inner, outside: outside}
end


# A probe that aims at a CLIPPED position proves nothing — the first run of this sweep failed
# four examples that way, not because the code was wrong but because the subject was outside the
# viewport. These two keep every probe on a pixel the user could actually hit.

# Scroll the subject into view on whatever axes this direction can scroll, keeping the case's
# scroll on the other. Returns the applied offset.
private def sweep_focus(f, subject : CrymbleUI::Widget, direction : CrymbleUI::ScrollDirection,
                        base : CrymbleUI::Vec2) : CrymbleUI::Vec2
  sv = f[:sv]
  # The control case stays at zero — scrolling it to a subject would quietly delete the control.
  return sv.scroll_offset if base.x == 0.0 && base.y == 0.0
  vertical = direction.vertical? || direction.both?
  y = vertical ? {subject.absolute_bounds.y - sv.absolute_bounds.y - 20.0, 0.0}.max : 0.0
  x = (direction.horizontal? || direction.both?) ? base.x : 0.0
  sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(x, y))
  f[:renderer].render_frame(f[:app])
  sv.scroll_offset
end

# The centre of what is actually VISIBLE of the subject: its painted rect clipped to the view.
private def sweep_visible_point(subject : CrymbleUI::Widget, sv : CrymbleUI::Widget) : CrymbleUI::Vec2
  p = subject.viewport_bounds
  v = sv.viewport_bounds
  left = {p.x, v.x}.max
  right = {p.x + p.width, v.x + v.width}.min
  top = {p.y, v.y}.max
  bottom = {p.y + p.height, v.y + v.height}.min
  (right - left).should be > 2.0
  (bottom - top).should be > 2.0
  CrymbleUI::Vec2.new((left + right) / 2.0, (top + bottom) / 2.0)
end

SWEEP_CASES = [
  {"vertical", CrymbleUI::ScrollDirection::Vertical, CrymbleUI::Vec2.new(0.0, 120.0)},
  {"horizontal", CrymbleUI::ScrollDirection::Horizontal, CrymbleUI::Vec2.new(80.0, 0.0)},
  {"both axes", CrymbleUI::ScrollDirection::Both, CrymbleUI::Vec2.new(60.0, 100.0)},
  {"unscrolled control", CrymbleUI::ScrollDirection::Vertical, CrymbleUI::Vec2.zero},
]

describe "scroll-space sweep" do
  SWEEP_CASES.each do |name, direction, scroll|
    describe name do
      it "paints every subject at absolute minus the scroll" do
        f = build_sweep(direction, scroll)
        applied = f[:sv].scroll_offset
        [f[:drag_row], f[:drop_row], f[:combo], f[:inner]].each do |w|
          w.viewport_bounds.x.should be_close(w.absolute_bounds.x - applied.x, 0.5)
          w.viewport_bounds.y.should be_close(w.absolute_bounds.y - applied.y, 0.5)
        end
      end

      it "finds the widget under the painted position, and hands it its own space" do
        f = build_sweep(direction, scroll)
        row = f[:drag_row]
        sweep_focus(f, row, direction, scroll)
        click = sweep_visible_point(row, f[:sv])
        offset_x = click.x - row.viewport_bounds.x
        offset_y = click.y - row.viewport_bounds.y

        f[:window].hit_test(click).should eq(row)
        f[:app].handle_mouse_down(click)
        seen = row.seen.should_not be_nil
        # The widget localises against its OWN bounds and gets the offset the cursor really had.
        (seen.x - row.absolute_bounds.x).should be_close(offset_x, 0.5)
        (seen.y - row.absolute_bounds.y).should be_close(offset_y, 0.5)
      end

      it "keeps the drag ghost under the cursor and highlights the row the cursor is over" do
        f = build_sweep(direction, scroll)
        row = f[:drag_row]
        target = f[:drop_row]
        sweep_focus(f, row, direction, scroll)
        grab = sweep_visible_point(row, f[:sv])
        grab_dx = grab.x - row.viewport_bounds.x
        grab_dy = grab.y - row.viewport_bounds.y

        manager = CrymbleUI::DragManager.new
        manager.begin_drag_tracking(row, grab)
        manager.update_drag(CrymbleUI::Vec2.new(grab.x, grab.y + 8.0), f[:window])
        ghost = manager.ghost_layer.should_not be_nil
        ghost.bounds.y.should be_close(grab.y + 8.0 - grab_dy, 0.5)
        ghost.bounds.x.should be_close(grab.x - grab_dx, 0.5)

        tp = target.viewport_bounds
        over = sweep_visible_point(target, f[:sv])
        manager.update_drag(over, f[:window])
        manager.state.current_target.should eq(target)
        highlight = manager.highlight_layer.should_not be_nil
        highlight.bounds.y.should be_close(tp.y, 0.5)
        highlight.bounds.x.should be_close(tp.x, 0.5)
      end

      it "anchors a popup to the painted control" do
        f = build_sweep(direction, scroll)
        combo = f[:combo]
        sweep_focus(f, combo, direction, scroll)
        painted = combo.viewport_bounds
        combo.expand
        popup = combo.current_popup.not_nil!
        popup.bounds.x.should be_close(painted.x, 0.5)
        # Below the cell, or flipped above it — but anchored to the PAINTED cell either way.
        below = (popup.bounds.y - (painted.y + painted.height)).abs <= 0.5
        above = (popup.bounds.y - (painted.y - popup.bounds.height)).abs <= 0.5
        (below || above).should be_true
      end

      it "paints a foreground decoration on the content it decorates" do
        f = build_sweep(direction, scroll)
        sweep_focus(f, f[:fg_box], direction, scroll)
        backend = f[:renderer].backend
        painted = f[:fg_box].viewport_bounds
        found = false
        y = 0
        while y < backend.height && !found
          x = 0
          while x < backend.width
            if backend.get_pixel(x, y) == SweepFgBox::MARK
              found = true
              y.should be_close(painted.y.to_i, 2)
              break
            end
            x += 1
          end
          y += 1
        end
        found.should be_true
      end

      it "composites a nested scroller's layer at its painted position" do
        f = build_sweep(direction, scroll)
        sweep_focus(f, f[:inner], direction, scroll)
        inner = f[:inner]
        layer = inner.layer.should_not be_nil
        painted = inner.viewport_bounds
        layer.bounds.x.should be_close(painted.x, 1.0)
        layer.bounds.y.should be_close(painted.y, 1.0)
      end

      it "orders focus by what the user sees" do
        f = build_sweep(direction, scroll)
        order = CrymbleUI::FocusCycler.new.collect_focusable_widgets(f[:window])
        painted = order.map { |w| w.viewport_bounds.y }
        painted.each_cons(2) { |pair| pair[1].should be >= pair[0] }
      end
    end
  end
end
