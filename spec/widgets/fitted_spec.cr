require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# fitted { } shows its one child uniformly scaled to the box it is given (Flutter's FittedBox, BoxFit.contain):
# text rasterised at its final size, input landing where it is drawn, and no widget inside knowing about it.
#
# Every expected value below is DERIVED, never read from the implementation: the box is the fitted's painted
# rect (or the slot a loose parent offers), N the child's natural size (its laid-out size - it is laid out with
# no limit on either axis), and
#   f = min over the bounded axes with N > 0 of box / N   (none -> 1)
#   C = the image's top-left = the box's top-left plus half the slack on each axis
# A point p of the child's content space is painted at C + (p - child origin) * f. The window's content box is
# the window minus Window::CONTENT_PADDING on every side.

FIT_RED   = CrymbleUI::Color.new(210, 30, 30, 255)
FIT_BLUE  = CrymbleUI::Color.new(30, 30, 210, 255)
FIT_GREEN = CrymbleUI::Color.new(30, 170, 30, 255)
FIT_INK   = CrymbleUI::Color.new(250, 230, 0, 255)
FIT_PAD   = CrymbleUI::Window::CONTENT_PADDING

# A block of one colour (a covering fill) that records what the mouse hands it, in its own space.
class FitSwatch < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  class_property layouts : Int32 = 0
  getter hover_points = [] of CrymbleUI::Vec2
  getter down_points = [] of CrymbleUI::Vec2
  getter move_points = [] of CrymbleUI::Vec2

  def initialize(@w : Float64, @h : Float64, @color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@w, @h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    FitSwatch.layouts += 1
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(@w, @h))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_background(bounds, @color) }
  end

  def on_hover_move(point : CrymbleUI::Vec2) : Nil
    @hover_points << point
  end

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @down_points << point
  end

  def on_mouse_move(point : CrymbleUI::Vec2)
    @move_points << point
  end
end

# What lies behind a fitted: fills what it is given, gives its one child all of it (tight), counts the presses
# that reach it.
class FitBackdrop < CrymbleUI::Widget
  getter downs = 0

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, constraints.max_height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    @children.each { |child| child.layout(CrymbleUI::BoxConstraints.tight(@bounds.size), CrymbleUI::Vec2.zero) }
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @downs += 1
  end
end

# The refusal switched off - what reaches the backstop when a layer owner slips past it.
class FitNoRefusal < CrymbleUI::Fitted
  private def refuse_layer_owners : Nil
  end
end

abstract class FitApp < CrymbleUI::App
  property clicks = 0
  property flag = false
  property label = "12:00"
  property wide = "a wide line of text"
end

# A DSL app (new instances on every build, as real apps are) whose window holds the block.
macro fit_app(name, &block)
  class {{name.id}} < FitApp
    def build : CrymbleUI::Widget
      window("Fit", 400, 300) do
        {{block.body}}
      end
    end
  end
end

private def fit_run(app : CrymbleUI::App, w : Int32 = 400, h : Int32 = 300) : CrymbleUI::Testing::TestRenderer
  renderer = CrymbleUI::Testing::TestRenderer.new(w, h)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  renderer
end

private def fit_resize(app : CrymbleUI::App, renderer : CrymbleUI::Testing::TestRenderer, w : Int32, h : Int32) : Nil
  renderer.resize(w, h)
  app.root.not_nil!.mark_needs_layout
  renderer.settle_rendering(app)
end

private def fit_px(r : CrymbleUI::Testing::TestRenderer, x : Float64, y : Float64) : CrymbleUI::Color
  r.backend.get_pixel(x.floor.to_i, y.floor.to_i).not_nil!
end

private def fit_find(app : CrymbleUI::App, id : String) : CrymbleUI::Widget
  app.find(id).not_nil!
end

private record FitGeo, box : CrymbleUI::Rect, n : CrymbleUI::Size, f : Float64, c : CrymbleUI::Vec2,
  origin : CrymbleUI::Vec2 do
  # Where the child is painted, in window space.
  def image : CrymbleUI::Rect
    CrymbleUI::Rect.new(c.x, c.y, n.width * f, n.height * f)
  end

  # Where a content-space point of the child's subtree is painted.
  def paint(p : CrymbleUI::Vec2) : CrymbleUI::Vec2
    CrymbleUI::Vec2.new(c.x + (p.x - origin.x) * f, c.y + (p.y - origin.y) * f)
  end

  def paint_rect(r : CrymbleUI::Rect) : CrymbleUI::Rect
    p = paint(r.position)
    CrymbleUI::Rect.new(p.x, p.y, r.width * f, r.height * f)
  end

  # A window point, brought into the child's natural (content) space.
  def natural(q : CrymbleUI::Vec2) : CrymbleUI::Vec2
    CrymbleUI::Vec2.new(origin.x + (q.x - c.x) / f, origin.y + (q.y - c.y) / f)
  end
end

private def fit_factor(n : CrymbleUI::Size, max_w : Float64, max_h : Float64) : Float64
  f = Float64::INFINITY
  f = {f, {max_w, 0.0}.max / n.width}.min if max_w.finite? && n.width > 0
  f = {f, {max_h, 0.0}.max / n.height}.min if max_h.finite? && n.height > 0
  f == Float64::INFINITY ? 1.0 : f
end

# The geometry of a fitted given the whole of `box` (a tight slot): the image centred in it.
private def fit_geo(fitted : CrymbleUI::Widget, box : CrymbleUI::Rect = fitted.viewport_bounds) : FitGeo
  child = fitted.children.first
  n = child.bounds.size
  f = fit_factor(n, box.width, box.height)
  c = CrymbleUI::Vec2.new(box.x + (box.width - n.width * f) / 2.0, box.y + (box.height - n.height * f) / 2.0)
  FitGeo.new(box, n, f, c, child.absolute_bounds.position)
end

# The geometry of a fitted in a LOOSE slot starting at `at`: it takes only N * f, flush at the slot's start.
private def fit_geo_loose(fitted : CrymbleUI::Widget, at : CrymbleUI::Vec2, max_w : Float64, max_h : Float64) : FitGeo
  child = fitted.children.first
  n = child.bounds.size
  f = fit_factor(n, max_w, max_h)
  FitGeo.new(CrymbleUI::Rect.new(at.x, at.y, n.width * f, n.height * f), n, f, at, child.absolute_bounds.position)
end

# A fitted inside a window panel: the panel's content area hands each child a LOOSE box of its whole size.
private def fit_geo_slot(fitted : CrymbleUI::Widget) : FitGeo
  area = fitted.parent.not_nil!.viewport_bounds
  fit_geo_loose(fitted, area.position, area.width, area.height)
end

# The window's content box: where a single child is laid out (tight).
private def fit_content_box(w : Int32, h : Int32) : CrymbleUI::Rect
  CrymbleUI::Rect.new(FIT_PAD, FIT_PAD, w - FIT_PAD * 2, h - FIT_PAD * 2)
end

# The longest run of `color` in column x between rows y0 and y1.
private def fit_ink_rows(r : CrymbleUI::Testing::TestRenderer, x : Int32, y0 : Int32, y1 : Int32, color : CrymbleUI::Color) : Int32
  best = 0
  run = 0
  (y0...y1).each do |y|
    if r.backend.get_pixel(x, y) == color
      run += 1
      best = run if run > best
    else
      run = 0
    end
  end
  best
end

private def fit_count_color(r : CrymbleUI::Testing::TestRenderer, rect : CrymbleUI::Rect, color : CrymbleUI::Color) : Int32
  n = 0
  (rect.y.floor.to_i...rect.bottom.ceil.to_i).each do |y|
    (rect.x.floor.to_i...rect.right.ceil.to_i).each do |x|
      n += 1 if r.backend.get_pixel(x, y) == color
    end
  end
  n
end

private def fit_subtree(w : CrymbleUI::Widget) : Array(CrymbleUI::Widget)
  all = [w]
  w.children.each { |c| all.concat(fit_subtree(c)) }
  all
end

# How many of `made` (a census) are surfaces of the fitted's subtree or its layer - the window's own root layer is
# created afresh on every rebuild, and is no business of the fitted's.
private def fit_subtree_surfaces(fitted : CrymbleUI::Widget, made : Array(CrymbleUI::Testing::TestRenderBackend)) : Int32
  mine = [] of CrymbleUI::RenderBackend
  fit_subtree(fitted).each do |w|
    w.widget_backend.try { |b| mine << b }
    w.background_backend.try { |b| mine << b }
    w.layer.try(&.backend).try { |b| mine << b }
  end
  made.count { |b| mine.any?(&.same?(b)) }
end

private def fit_finite?(p : CrymbleUI::Vec2) : Bool
  p.x.finite? && p.y.finite?
end

# ---- apps -------------------------------------------------------------------------------------------------

fit_app FitHalvesApp do
  fitted(id: "f") do
    hstack(spacing: 0.0) do
      widget(FitSwatch.new(50.0, 40.0, FIT_RED, id: "red"))
      widget(FitSwatch.new(50.0, 40.0, FIT_BLUE, id: "blue"))
    end
  end
end

fit_app FitThirdsApp do
  fitted(id: "f") do
    hstack(spacing: 0.0) do
      widget(FitSwatch.new(33.0, 40.0, FIT_RED, id: "a"))
      widget(FitSwatch.new(33.0, 40.0, FIT_BLUE, id: "b"))
      widget(FitSwatch.new(33.0, 40.0, FIT_GREEN, id: "c"))
    end
  end
end

fit_app FitHoleApp do
  fitted(id: "f") do
    vstack(id: "card", padding: 4.0, background_color: FIT_RED) do
      text("AAAA", id: "label", color: FIT_INK)
    end
  end
end

fit_app FitNestedApp do
  fitted(id: "f") do
    vstack(spacing: 0.0) do
      hstack(spacing: 0.0) do
        widget(FitSwatch.new(50.0, 40.0, FIT_RED, id: "grand"))
        widget(FitSwatch.new(50.0, 40.0, FIT_BLUE))
      end
    end
  end
end

fit_app FitTextApp do
  fitted(id: "f") do
    text("AA", id: "label", color: FIT_INK)
  end
end

fit_app FitButtonApp do
  fitted(id: "f") do
    button("Go", id: "go") { @clicks += 1 }
  end
end

fit_app FitProbeApp do
  fitted(id: "f") do
    widget(FitSwatch.new(40.0, 30.0, FIT_RED, id: "probe"))
  end
end

fit_app FitInputApp do
  fitted(id: "f") do
    text_input("", id: "in", width: 60.0) { }
  end
end

fit_app FitBesideApp do
  hstack(spacing: 0.0) do
    expanded do
      fitted(id: "f") do
        widget(FitSwatch.new(600.0, 40.0, FIT_RED, id: "wide"))
      end
    end
    button("Next", id: "next") { @clicks += 1 }
  end
end

fit_app FitBesideDirectApp do
  hstack(spacing: 0.0) do
    fitted(id: "f") do
      widget(FitSwatch.new(600.0, 40.0, FIT_RED, id: "wide"))
    end
    button("Next", id: "next") { @clicks += 1 }
  end
end

fit_app FitEmptyApp do
  fitted(id: "f") do
    vstack(id: "empty") { }
  end
end

fit_app FitDropTextApp do
  fitted(id: "f") do
    vstack(spacing: 0.0) do
      widget(FitSwatch.new(10000.0, 40.0, FIT_RED))
      text("H" * 100, id: "label", color: FIT_INK)
    end
  end
end

fit_app FitPlainHalvesApp do
  hstack(spacing: 0.0) do
    widget(FitSwatch.new(50.0, 40.0, FIT_RED, id: "red"))
    widget(FitSwatch.new(50.0, 40.0, FIT_BLUE, id: "blue"))
  end
end

fit_app FitTitleApp do
  vstack(id: "col", spacing: 0.0) do
    text("Title")
    fitted(id: "f") do
      widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s"))
    end
  end
end

fit_app FitExpandedTallApp do
  vstack(id: "col", spacing: 0.0) do
    expanded do
      fitted(id: "f") { widget(FitSwatch.new(40.0, 100.0, FIT_RED, id: "s")) }
    end
  end
end

fit_app FitFillAreaTallApp do
  vstack(id: "col", spacing: 0.0) do
    expanded(fill_area: true) do
      fitted(id: "f") { widget(FitSwatch.new(40.0, 100.0, FIT_RED, id: "s")) }
    end
  end
end

fit_app FitRowExpandedApp do
  hstack(id: "row", spacing: 0.0) do
    expanded do
      fitted(id: "f") { widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s")) }
    end
  end
end

fit_app FitRowFillAreaApp do
  hstack(id: "row", spacing: 0.0) do
    expanded(fill_area: true) do
      fitted(id: "f") { widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s")) }
    end
  end
end

fit_app FitUnboundedApp do
  scroll_view(id: "sv", direction: CrymbleUI::ScrollDirection::Both, max_height: 200.0, max_width: 300.0) do
    fitted(id: "f") do
      hstack(spacing: 0.0) do
        widget(FitSwatch.new(50.0, 40.0, FIT_RED, id: "red"))
        widget(FitSwatch.new(50.0, 40.0, FIT_BLUE, id: "blue"))
      end
    end
  end
end

fit_app FitUnboundedPlainApp do
  scroll_view(id: "sv", direction: CrymbleUI::ScrollDirection::Both, max_height: 200.0, max_width: 300.0) do
    hstack(spacing: 0.0) do
      widget(FitSwatch.new(50.0, 40.0, FIT_RED, id: "red"))
      widget(FitSwatch.new(50.0, 40.0, FIT_BLUE, id: "blue"))
    end
  end
end

fit_app FitLooseTallApp do
  text("T", id: "t")
  fitted(id: "f") { widget(FitSwatch.new(40.0, 100.0, FIT_RED, id: "s")) }
end

fit_app FitLooseWideApp do
  text("T", id: "t")
  fitted(id: "f") { widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s")) }
end

# The row is laid out LOOSE (a multi-child window): its width is its content's, below the max - the ancestor
# that may take the relaxation skip - while the fitted fills its height.
fit_app FitSubMaxApp do
  text("T", id: "t")
  hstack(id: "row", padding: 6.0, spacing: 0.0) do
    fitted(id: "f") { widget(FitSwatch.new(40.0, 100.0, FIT_RED, id: "s")) }
    text("x")
  end
end

fit_app FitPanelApp do
  window_panel("P", 20.0, 20.0, 300.0, 200.0, id: "p") do
    fitted(id: "f") { widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s")) }
  end
end

fit_app FitClockApp do
  fitted(id: "f") do
    text(@label, id: "label", color: FIT_INK)
  end
end

fit_app FitScrollApp do
  scroll_view(id: "sv", max_height: 200.0) do
    vstack(spacing: 0.0) do
      widget(FitSwatch.new(300.0, 150.0, FIT_GREEN))
      fitted(id: "f") { widget(FitSwatch.new(60.0, 20.0, FIT_RED, id: "probe")) }
      widget(FitSwatch.new(300.0, 400.0, FIT_GREEN))
    end
  end
end

fit_app FitPanelDropApp do
  draggable(CrymbleUI::TextDragData.new("x"), id: "src") { text("source") }
  window_panel("P", 150.0, 40.0, 230.0, 200.0, id: "p") do
    fitted(id: "f") do
      hstack(spacing: 0.0) do
        widget(FitSwatch.new(30.0, 30.0, FIT_RED, id: "s"))
        drop_zone(accept_types: ["text"], id: "dz") do
          widget(FitSwatch.new(30.0, 30.0, FIT_BLUE, id: "t"))
        end
      end
    end
  end
end

fit_app FitRescaleApp do
  fitted(id: "f") do
    vstack(spacing: 0.0) do
      widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s"))
      text(@label, id: "label", color: FIT_INK)
    end
  end
end

# A fitted bound by its width in a column: a width change rescales it about the column's start - the image's
# origin stays where it is.
fit_app FitRescaleLooseApp do
  vstack(id: "col", spacing: 0.0) do
    fitted(id: "f") do
      vstack(spacing: 0.0) do
        widget(FitSwatch.new(100.0, 40.0, FIT_RED, id: "s"))
        text(@label, id: "label", color: FIT_INK)
      end
    end
  end
end

fit_app FitComboApp do
  fitted(id: "f") do
    combo_box(["Apple", "Banana"], id: "cb", width: 120.0)
  end
end

fit_app FitRefuseScrollApp do
  fitted(id: "f") do
    scroll_view(id: "log") { text("x") }
  end
end

fit_app FitTwoChildrenApp do
  fitted(id: "f") do
    text("a")
    text("b")
  end
end

fit_app FitDeepScrollApp do
  fitted(id: "f") do
    vstack do
      text("x")
      if @flag
        scroll_view(id: "log") { text("y") }
      end
    end
  end
end

fit_app FitZoomApp do
  vstack(id: "col", spacing: 0.0) do
    text("control", id: "ctl")
    expanded(fill_area: true) do
      fitted(id: "f") do
        hstack(spacing: 0.0) do
          widget(FitSwatch.new(10.0, 10.0, FIT_RED))
          text(@wide)
          widget(FitSwatch.new(10.0, 10.0, FIT_BLUE))
        end
      end
    end
  end
end

fit_app FitBudgetApp do
  vstack(id: "col", spacing: 0.0) do
    fitted(id: "f") do
      hstack(spacing: 0.0) do
        widget(FitSwatch.new(50.0, 40.0, FIT_RED))
        widget(FitSwatch.new(50.0, 40.0, FIT_BLUE))
      end
    end
  end
end

# The letterbox pass-through: built by hand, a backdrop behind the fitted (new instances per build).
class FitBackdropApp < FitApp
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Fit", 400, 300)
    backdrop = FitBackdrop.new(id: "back")
    fitted = CrymbleUI::Fitted.new(id: "f")
    fitted.add_child(FitSwatch.new(40.0, 20.0, FIT_RED, id: "probe"))
    backdrop.add_child(fitted)
    window.add_child(backdrop)
    window
  end
end

class FitBackstopApp < FitApp
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Fit", 400, 300)
    fitted = FitNoRefusal.new(id: "f")
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 30.0, id: "log")
    sv.set_content(CrymbleUI::Text.new("x"))
    fitted.add_child(sv)
    window.add_child(fitted)
    window
  end
end

# ---- the cases ----------------------------------------------------------------------------------------------

describe "fitted { }" do
  it "1: paints the child scaled into the box, centred, the rest letterboxed" do
    app = FitHalvesApp.new
    r = fit_run(app, 400, 200)
    g = fit_geo(fit_find(app, "f"), fit_content_box(400, 200))
    g.f.should be > 2.0 # coverage: a real scale, with slack on the other axis
    (g.box.height - g.image.height).should be > 20.0

    mid_y = g.c.y + 20.0 * g.f
    edge = g.c.x + 50.0 * g.f
    fit_px(r, g.c.x + 2.0, mid_y).should eq(FIT_RED)
    fit_px(r, edge - 2.0, mid_y).should eq(FIT_RED)
    fit_px(r, edge + 2.0, mid_y).should eq(FIT_BLUE)
    fit_px(r, g.c.x + 100.0 * g.f - 2.0, mid_y).should eq(FIT_BLUE)
    # the bands above and below the image show what lies behind the fitted (it paints nothing)
    fit_px(r, edge, g.c.y - 2.0).should eq(r.background_color)
    fit_px(r, edge, g.image.bottom + 2.0).should eq(r.background_color)
    r.exceptions_caught.should eq(0)
  end

  it "2: siblings meet without a seam at a fractional factor" do
    app = FitThirdsApp.new
    r = fit_run(app, 273, 400)
    g = fit_geo(fit_find(app, "f"), fit_content_box(273, 400))
    # coverage: the swatch edges fall BETWEEN pixels (at 274 the box is 258 = 3 * 86, and every edge is whole)
    [33.0 * g.f, 66.0 * g.f].each { |edge| (edge - edge.floor).should be_close(0.5, 0.4) }
    y = g.c.y + 20.0 * g.f
    row = (g.c.x.ceil.to_i...(g.c.x + 99.0 * g.f).floor.to_i).map { |x| r.backend.get_pixel(x, y.to_i).not_nil! }
    row.size.should be > 200
    row.each { |px| [FIT_RED, FIT_BLUE, FIT_GREEN].includes?(px).should be_true } # no background column
    runs = row.chunk_while { |a, b| a == b }.map { |run| {run.first, run.size} }.to_a
    runs.map(&.[0]).should eq([FIT_RED, FIT_BLUE, FIT_GREEN]) # no overlap: each once, in order
    runs.each { |(_, size)| (size - 33.0 * g.f).abs.should be <= 1.5 }
  end

  it "3: a resize that changes the factor leaves no hole where a transparent child stands" do
    app = FitHoleApp.new
    r = fit_run(app, 216, 300)
    [{216, 300}, {260, 300}, {240, 300}].each do |(w, h)|
      fit_resize(app, r, w, h)
      g = fit_geo(fit_find(app, "f"), fit_content_box(w, h))
      label = fit_find(app, "label")
      # inside the label, right of the first glyph's stripe, off every glyph: the card's red shows through
      size = 14.0 # natural font size of the label (font_scale 0, zoom 100%)
      off_glyph = CrymbleUI::Vec2.new(label.absolute_bounds.x + 0.8 * size * 0.6, label.absolute_bounds.y + size / 2.0)
      p = g.paint(off_glyph)
      fit_px(r, p.x, p.y).should eq(FIT_RED)
    end
  end

  it "4: a shrink within the layer's slack re-renders a grandchild at its new scaled rect" do
    app = FitNestedApp.new
    r = fit_run(app, 400, 200)
    renderer_w = 388
    r.resize(renderer_w, 200)
    app.root.not_nil!.mark_needs_layout
    r.render_frame(app)
    grand = fit_find(app, "grand")
    r.widget_disposition(grand).should eq(:rendered)
    g = fit_geo(fit_find(app, "f"), fit_content_box(renderer_w, 200))
    rect = g.paint_rect(grand.absolute_bounds)
    fit_px(r, rect.right - 2.0, rect.y + 2.0).should eq(FIT_RED)
    fit_px(r, rect.right + 2.0, rect.y + 2.0).should eq(FIT_BLUE)
  end

  it "5: rasterises text at its final size" do
    CrymbleUI::Testing::TestRenderBackend.text_log = [] of {String, Float64}
    begin
      app = FitTextApp.new
      r = fit_run(app, 216, 44)
      label = fit_find(app, "label")
      s = label.get_primitives(label.bounds).compact_map(&.as?(CrymbleUI::DrawText)).first.size
      g = fit_geo(fit_find(app, "f"), fit_content_box(216, 44))
      (s * g.f).should be <= 30.0 # the headless glyph model is linear below these caps
      (s * g.f * 0.6).should be <= 20.0
      g.f.should be > 1.5
      expected = {CrymbleUI::Testing::TestFont.line_step(s * g.f).to_i, (s * g.f).to_i.clamp(6, 30)}.min
      column = g.c.x.floor.to_i + 1 # inside the first 'A''s left stripe
      fit_ink_rows(r, column, 0, 44, FIT_INK).should eq(expected)
      log = CrymbleUI::Testing::TestRenderBackend.text_log.not_nil!
      log.any? { |(text, size)| text == "AA" && (size - s * g.f).abs < 0.01 }.should be_true
    ensure
      CrymbleUI::Testing::TestRenderBackend.text_log = nil
    end
  end

  describe "6: input lands where it is drawn" do
    it "fires a scaled button clicked outside its natural rect" do
      app = FitButtonApp.new
      r = fit_run(app)
      button = fit_find(app, "go")
      g = fit_geo(fit_find(app, "f"))
      g.f.should be > 2.0
      at = CrymbleUI::Vec2.new(g.image.right - 4.0, g.image.bottom - 4.0)
      button.absolute_bounds.contains_point(at).should be_false # outside the natural rect
      r.mouse_down(at.x, at.y)
      r.mouse_up(at.x, at.y)
      app.clicks.should eq(1)
    end

    it "passes a click in the letterbox through to what lies behind" do
      app = FitBackdropApp.new
      r = fit_run(app)
      g = fit_geo(fit_find(app, "f"))
      (g.box.height - g.image.height).should be > 20.0 # a letterbox band above and below
      at = CrymbleUI::Vec2.new(g.image.center.x, g.c.y - 5.0)
      g.box.contains_point(at).should be_true
      r.mouse_down(at.x, at.y)
      r.mouse_up(at.x, at.y)
      fit_find(app, "back").as(FitBackdrop).downs.should eq(1)
    end

    it "hands a hover the point in the widget's own natural space" do
      app = FitProbeApp.new
      r = fit_run(app)
      probe = fit_find(app, "probe").as(FitSwatch)
      g = fit_geo(fit_find(app, "f"))
      at = CrymbleUI::Vec2.new(g.image.right - 6.0, g.image.bottom - 6.0)
      probe.absolute_bounds.contains_point(at).should be_false
      r.mouse_move(at.x, at.y)
      seen = probe.hover_points.last?.should_not be_nil
      expected = g.natural(at)
      seen.x.should be_close(expected.x, 0.01)
      seen.y.should be_close(expected.y, 0.01)
    end

    it "lets typing reach a scaled text input clicked outside its natural rect" do
      app = FitInputApp.new
      r = fit_run(app)
      input = fit_find(app, "in").as(CrymbleUI::TextInput)
      g = fit_geo(fit_find(app, "f"))
      at = CrymbleUI::Vec2.new(g.image.right - 6.0, g.image.center.y)
      input.absolute_bounds.contains_point(at).should be_false
      events = CrymbleUI::Testing::Keys.click_at(at.x.to_i, at.y.to_i) + CrymbleUI::Testing::Keys.typed("hi")
      r.deliver(app, events)
      r.settle_rendering(app)
      input.value.should eq("hi")
    end
  end

  # The sibling's clicks are 7b's: here an Expanded between the stack and the fitted answers the hit test first.
  it "7: a shrunk image beside a sibling paints nothing over it" do
    app = FitBesideApp.new
    r = fit_run(app, 400, 200)
    fitted = fit_find(app, "f")
    nxt = fit_find(app, "next")
    g = fit_geo(fitted)
    g.f.should be < 1.0 # precondition: the child's natural rect reaches over the sibling
    wide = fit_find(app, "wide")
    nb = nxt.viewport_bounds
    wide.absolute_bounds.contains_point(nb.center).should be_true
    fit_px(r, nb.x + 2.0, nb.y + 2.0).should_not eq(FIT_RED)
  end

  # The same with nothing between the stack and the fitted (an Expanded's own bounds check would stop the hit
  # test before the fitted is asked): a fitted bound by its height, beside the sibling its natural rect reaches.
  it "7b: a shrunk image directly in a stack does not take its sibling's clicks (GUARD)" do
    app = FitBesideDirectApp.new
    r = fit_run(app, 440, 40)
    fitted = fit_find(app, "f")
    g = fit_geo_loose(fitted, fitted.viewport_bounds.position, Float64::INFINITY, 40.0 - FIT_PAD * 2)
    g.f.should be < 1.0
    nb = fit_find(app, "next").viewport_bounds
    nb.center.x.should be < 440.0 - FIT_PAD # on screen, inside the stack
    fit_find(app, "wide").absolute_bounds.contains_point(nb.center).should be_true # the natural rect reaches over it
    fit_px(r, nb.x + 2.0, nb.center.y).should_not eq(FIT_RED)
    r.mouse_down(nb.center.x, nb.center.y)
    r.mouse_up(nb.center.x, nb.center.y)
    app.clicks.should eq(1)
  end

  describe "8: degenerate boxes" do
    it "draws nothing for an empty child, at factor 1, without raising" do
      app = FitEmptyApp.new
      r = fit_run(app)
      fit_count_color(r, fit_content_box(400, 300), r.background_color).should eq(384 * 284)
      r.exceptions_caught.should eq(0)
    end

    it "draws nothing in a 0x0 box, and the mouse over it delivers no NaN" do
      app = FitProbeApp.new
      r = fit_run(app, 16, 16)
      probe = fit_find(app, "probe").as(FitSwatch)
      r.mouse_move(8.0, 8.0)
      r.mouse_down(8.0, 8.0)
      r.mouse_up(8.0, 8.0)
      probe.hover_points.empty?.should be_true # nothing in a 0x0 box is hit, so nothing is handed a point
      probe.down_points.empty?.should be_true
      fit_count_color(r, CrymbleUI::Rect.new(0.0, 0.0, 16.0, 16.0), FIT_RED).should eq(0)
      r.exceptions_caught.should eq(0)
    end

    it "hands a captured drag finite points while the window collapses" do
      app = FitProbeApp.new
      r = fit_run(app)
      probe = fit_find(app, "probe").as(FitSwatch)
      g = fit_geo(fit_find(app, "f"))
      at = g.image.center
      r.mouse_down(at.x, at.y)
      probe.down_points.size.should eq(1)
      fit_resize(app, r, 16, 16) # the content box is 0x0: factor 0
      r.mouse_move(10.0, 10.0)
      probe.move_points.empty?.should be_false
      probe.move_points.each { |p| fit_finite?(p).should be_true }
      r.mouse_up(10.0, 10.0)
      r.exceptions_caught.should eq(0)
    end

    # A text whose glyphs fall below a pixel while its box still covers device pixels: the drop is what keeps it
    # from being rasterised (in a 1px-high box the text's box spans no pixel, and it is never drawn at all).
    it "rasterises no text below one pixel even where its box spans pixels" do
      CrymbleUI::Testing::TestRenderBackend.text_log = [] of {String, Float64}
      begin
        app = FitDropTextApp.new
        r = fit_run(app)
        g = fit_geo(fit_find(app, "f"))
        label = fit_find(app, "label")
        s = label.get_primitives(label.bounds).compact_map(&.as?(CrymbleUI::DrawText)).first.size
        (s * g.f).should be < 1.0 # coverage: the glyphs are below a pixel...
        painted = g.paint_rect(label.absolute_bounds)
        (painted.right.floor - painted.x.floor).should be >= 1.0 # ...while the text's box spans device pixels
        (painted.bottom.floor - painted.y.floor).should be >= 1.0
        CrymbleUI::Testing::TestRenderBackend.text_log.not_nil!.each { |(_, size)| size.should be >= 1.0 }
        r.exceptions_caught.should eq(0)
      ensure
        CrymbleUI::Testing::TestRenderBackend.text_log = nil
      end
    end

    it "at factor 1 on a bounded box is pixel-identical to the child without fitted, and maps 1:1" do
      plain = FitPlainHalvesApp.new
      pr = fit_run(plain, 116, 300)
      app = FitHalvesApp.new
      r = fit_run(app, 116, 300)
      g = fit_geo(fit_find(app, "f"), fit_content_box(116, 300))
      g.f.should eq(1.0)
      red = fit_find(app, "red")
      plain_red = fit_find(plain, "red")
      dx = g.c.x - plain_red.viewport_bounds.x
      dy = g.c.y - plain_red.viewport_bounds.y
      (0...100).each do |x|
        (0...40).each do |y|
          px = plain_red.viewport_bounds.x + x
          py = plain_red.viewport_bounds.y + y
          fit_px(r, px + dx, py + dy).should eq(fit_px(pr, px, py))
        end
      end
      red.viewport_bounds.should eq(CrymbleUI::Rect.new(g.c.x, g.c.y, 50.0, 40.0))
      red.to_window(red.absolute_bounds.position).should eq(g.c)
    end
  end

  describe "9: unbounded and loose slots" do
    it "fits the width only under a vstack (its height is N * f)" do
      app = FitTitleApp.new
      r = fit_run(app)
      fitted = fit_find(app, "f")
      col = fit_find(app, "col")
      g = fit_geo_loose(fitted, fitted.viewport_bounds.position, col.viewport_bounds.width, Float64::INFINITY)
      g.f.should be > 2.0
      fitted.viewport_bounds.height.should be_close(40.0 * g.f, 0.01)
      fit_px(r, g.image.right - 2.0, g.image.center.y).should eq(FIT_RED)
    end

    it "is not centred inside a plain expanded (GUARD: the trap)" do
      app = FitExpandedTallApp.new
      r = fit_run(app)
      col = fit_find(app, "col")
      g = fit_geo_loose(fit_find(app, "f"), col.viewport_bounds.position, col.viewport_bounds.width, col.viewport_bounds.height)
      g.image.width.should be < col.viewport_bounds.width - 20.0
      fit_px(r, g.image.x + 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right - 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right + 2.0, g.image.center.y).should eq(r.background_color)
    end

    it "is centred in the full width inside expanded(fill_area: true)" do
      app = FitFillAreaTallApp.new
      r = fit_run(app)
      col = fit_find(app, "col")
      g = fit_geo(fit_find(app, "f"), col.viewport_bounds)
      (g.c.x - col.viewport_bounds.x).should be > 20.0
      fit_px(r, g.image.x - 2.0, g.image.center.y).should eq(r.background_color)
      fit_px(r, g.image.x + 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right - 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right + 2.0, g.image.center.y).should eq(r.background_color)
    end

    it "is not centred inside a plain expanded in an hstack (GUARD: the trap)" do
      app = FitRowExpandedApp.new
      r = fit_run(app)
      row = fit_find(app, "row")
      g = fit_geo_loose(fit_find(app, "f"), row.viewport_bounds.position, row.viewport_bounds.width, row.viewport_bounds.height)
      g.image.height.should be < row.viewport_bounds.height - 20.0
      fit_px(r, g.image.center.x, g.image.y + 2.0).should eq(FIT_RED)
      fit_px(r, g.image.center.x, g.image.bottom - 2.0).should eq(FIT_RED)
      fit_px(r, g.image.center.x, g.image.bottom + 2.0).should eq(r.background_color)
    end

    it "is centred in the full height inside expanded(fill_area: true) in an hstack" do
      app = FitRowFillAreaApp.new
      r = fit_run(app)
      row = fit_find(app, "row")
      g = fit_geo(fit_find(app, "f"), row.viewport_bounds)
      (g.c.y - row.viewport_bounds.y).should be > 20.0
      fit_px(r, g.image.center.x, g.image.y - 2.0).should eq(r.background_color)
      fit_px(r, g.image.center.x, g.image.y + 2.0).should eq(FIT_RED)
      fit_px(r, g.image.center.x, g.image.bottom - 2.0).should eq(FIT_RED)
      fit_px(r, g.image.center.x, g.image.bottom + 2.0).should eq(r.background_color)
    end

    it "keeps factor 1 when both axes are unbounded: pixel-identical, mapped 1:1" do
      plain = FitUnboundedPlainApp.new
      pr = fit_run(plain)
      app = FitUnboundedApp.new
      r = fit_run(app)
      red = fit_find(app, "red")
      plain_red = fit_find(plain, "red")
      red.viewport_bounds.should eq(plain_red.viewport_bounds)
      (0...100).each do |x|
        (0...40).each do |y|
          px = plain_red.viewport_bounds.x + x
          py = plain_red.viewport_bounds.y + y
          fit_px(r, px, py).should eq(fit_px(pr, px, py))
        end
      end
    end

    it "takes only N * f in a loose slot (multi-child window), flush at the slot's start (GUARD)" do
      app = FitLooseTallApp.new
      r = fit_run(app)
      t = fit_find(app, "t")
      start = CrymbleUI::Vec2.new(FIT_PAD, t.viewport_bounds.bottom)
      g = fit_geo_loose(fit_find(app, "f"), start, 400 - FIT_PAD * 2, 300 - FIT_PAD - start.y)
      g.image.width.should be < 300.0
      fit_px(r, g.image.x + 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right - 2.0, g.image.center.y).should eq(FIT_RED)
      fit_px(r, g.image.right + 2.0, g.image.center.y).should eq(r.background_color)
    end

    it "re-fits when each axis grows and shrinks (loose slot)" do
      {FitLooseTallApp.new, FitLooseWideApp.new}.each do |app|
        r = fit_run(app)
        [{400, 340}, {400, 260}, {460, 300}, {340, 300}].each do |(w, h)|
          fit_resize(app, r, w, h)
          t = fit_find(app, "t")
          start = CrymbleUI::Vec2.new(FIT_PAD, t.viewport_bounds.bottom)
          g = fit_geo_loose(fit_find(app, "f"), start, w - FIT_PAD * 2, h - FIT_PAD - start.y)
          fit_px(r, g.image.right - 2.0, g.image.bottom - 2.0).should eq(FIT_RED)
          fit_px(r, g.image.right + 2.0, g.image.center.y).should_not eq(FIT_RED)
          fit_px(r, g.image.center.x, g.image.bottom + 2.0).should_not eq(FIT_RED)
        end
      end
    end

    it "re-fits when each axis grows and shrinks under a content-sized ancestor" do
      app = FitSubMaxApp.new
      r = fit_run(app)
      [{400, 340}, {400, 260}, {460, 300}, {340, 300}, {400, 380}].each do |(w, h)|
        fit_resize(app, r, w, h)
        t = fit_find(app, "t")
        row = fit_find(app, "row")
        fit_find(app, "row").viewport_bounds.width.should be < w - FIT_PAD * 2 - 20.0 # content-sized on x
        inner_h = h - FIT_PAD - t.viewport_bounds.bottom - 12.0 # the row's slot height, less its padding
        at = CrymbleUI::Vec2.new(row.viewport_bounds.x + 6.0, row.viewport_bounds.y + 6.0)
        g = fit_geo_loose(fit_find(app, "f"), at, Float64::INFINITY, inner_h)
        fit_px(r, g.image.right - 2.0, g.image.bottom - 2.0).should eq(FIT_RED)
        fit_px(r, g.image.center.x, g.image.bottom + 2.0).should_not eq(FIT_RED)
      end
    end

    it "re-fits when a window panel holding it is resized" do
      app = FitPanelApp.new
      r = fit_run(app)
      [{360.0, 200.0}, {260.0, 200.0}, {300.0, 260.0}, {300.0, 150.0}].each do |(w, h)|
        panel = fit_find(app, "p").as(CrymbleUI::WindowPanel)
        panel.width = w
        panel.height = h
        panel.mark_needs_layout
        r.settle_rendering(app)
        fit_find(app, "p").as(CrymbleUI::WindowPanel).width.should eq(w) # instrument: the panel did resize
        g = fit_geo_slot(fit_find(app, "f"))
        g.f.should be > 1.5
        fit_px(r, g.image.right - 2.0, g.image.bottom - 2.0).should eq(FIT_RED)
        fit_px(r, g.image.x + 2.0, g.image.y + 2.0).should eq(FIT_RED)
        fit_px(r, g.image.right + 2.0, g.image.y + 2.0).should_not eq(FIT_RED)
        fit_px(r, g.image.x + 2.0, g.image.bottom + 2.0).should_not eq(FIT_RED)
      end
    end
  end

  it "10: re-fits a rebuilt app whose text grows, leaving no ink of the old text outside the new image" do
    app = FitClockApp.new
    r = fit_run(app, 100, 200) # the width binds, at a factor whose glyphs the headless font draws linearly
    before = fit_geo(fit_find(app, "f"), fit_content_box(100, 200))
    (14.0 * before.f).should be <= 30.0
    app.label = "12:00:00"
    app.request_rebuild
    r.settle_rendering(app)
    g = fit_geo(fit_find(app, "f"), fit_content_box(100, 200))
    g.f.should be < before.f
    g.image.height.should be < before.image.height - 4.0
    # the new text's ink spans the new image's height (its first glyph '1' draws a left stripe)
    column = g.c.x.floor.to_i + 1
    fit_ink_rows(r, column, 0, 200, FIT_INK).should be >= (g.image.height - 2.0).to_i
    # nothing of the old, taller text survives above or below the new image
    fit_count_color(r, CrymbleUI::Rect.new(0.0, 0.0, 100.0, g.image.y - 1.0), FIT_INK).should eq(0)
    fit_count_color(r, CrymbleUI::Rect.new(0.0, g.image.bottom + 1.0, 100.0, 200.0 - g.image.bottom - 1.0), FIT_INK).should eq(0)
  end

  describe "11: inside other spaces" do
    it "maps through a scrolled scroll view: a click lands, pixels are scrolled and scaled" do
      app = FitScrollApp.new
      r = fit_run(app)
      sv = fit_find(app, "sv").as(CrymbleUI::ScrollView)
      sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 100.0))
      r.settle_rendering(app)
      fitted = fit_find(app, "f")
      probe = fit_find(app, "probe").as(FitSwatch)
      g = fit_geo_loose(fitted, fitted.viewport_bounds.position, fitted.parent.not_nil!.viewport_bounds.width, Float64::INFINITY)
      g.f.should be > 2.0
      at = CrymbleUI::Vec2.new(g.image.x + 0.8 * g.image.width, g.image.center.y) # clear of the scrollbar
      probe.absolute_bounds.contains_point(at).should be_false
      sv.viewport_bounds.contains_point(at).should be_true # coverage: the point is on screen
      fit_px(r, at.x, at.y).should eq(FIT_RED)
      r.mouse_down(at.x, at.y)
      r.mouse_up(at.x, at.y)
      seen = probe.down_points.last?.should_not be_nil
      expected = g.natural(at)
      seen.x.should be_close(expected.x, 0.01)
      seen.y.should be_close(expected.y, 0.01)
    end

    it "composites inside a window panel, clipped to it, and a drop highlight covers the scaled target" do
      app = FitPanelDropApp.new
      r = fit_run(app)
      fitted = fit_find(app, "f")
      g = fit_geo_slot(fitted)
      g.f.should be > 2.0
      red = g.paint_rect(fit_find(app, "s").absolute_bounds)
      fit_px(r, red.center.x, red.center.y).should eq(FIT_RED)
      panel = fit_find(app, "p")
      fitted.viewport_bounds.right.should be <= panel.viewport_bounds.right
      # drag from the source (outside the panel) onto the scaled drop zone
      src = fit_find(app, "src")
      start = CrymbleUI::Vec2.new(src.viewport_bounds.x + 20.0, src.viewport_bounds.bottom - 20.0)
      panel.viewport_bounds.contains_point(start).should be_false
      dz = fit_find(app, "dz")
      target = g.paint_rect(dz.absolute_bounds)
      r.mouse_down(start.x, start.y)
      r.mouse_move(start.x + 20.0, start.y)
      r.mouse_move(target.center.x, target.center.y)
      r.render_frame(app)
      app.drag_manager.state.current_target.should eq(dz)
      highlight = app.drag_manager.highlight_layer.should_not be_nil
      highlight.bounds.x.should be_close(target.x, 0.5)
      highlight.bounds.y.should be_close(target.y, 0.5)
      highlight.bounds.right.should be_close(target.right, 0.5)
      highlight.bounds.bottom.should be_close(target.bottom, 0.5)
      r.mouse_up(target.center.x, target.center.y)
    end
  end

  describe "12: rebuilds" do
    it "rescales in a frame that also rebuilds" do
      app = FitRescaleApp.new
      r = fit_run(app, 300, 300)
      app.label = "12:01"
      app.request_rebuild
      r.resize(400, 300)
      app.root.not_nil!.mark_needs_layout
      r.render_frame(app)
      g = fit_geo(fit_find(app, "f"), fit_content_box(400, 300))
      red = g.paint_rect(fit_find(app, "s").absolute_bounds)
      fit_px(r, red.right - 2.0, red.bottom - 2.0).should eq(FIT_RED)
      fit_px(r, red.x + 2.0, red.y + 2.0).should eq(FIT_RED)
    end

    # The image's origin held still, so the rebuild assessment sees the same content-space signature and keeps the
    # carried buffer - only the scale's own invalidation repaints it at the new factor. A grow within the layer
    # buffer's slack: outgrowing it would reallocate, and that clears the layer by itself.
    it "rescales in a frame that also rebuilds, the image's origin unchanged" do
      app = FitRescaleLooseApp.new
      r = fit_run(app, 300, 300)
      fitted = fit_find(app, "f")
      before = fit_geo_loose(fitted, fitted.viewport_bounds.position, fit_find(app, "col").viewport_bounds.width, Float64::INFINITY)
      backend_w = fitted.layer.not_nil!.backend.not_nil!.width
      app.label = "12:01"
      app.request_rebuild
      r.resize(320, 300)
      app.root.not_nil!.mark_needs_layout
      r.render_frame(app)
      fitted = fit_find(app, "f")
      g = fit_geo_loose(fitted, fitted.viewport_bounds.position, fit_find(app, "col").viewport_bounds.width, Float64::INFINITY)
      g.c.should eq(before.c) # coverage: the origin did not move
      g.f.should be > before.f + 0.1
      red = g.paint_rect(fit_find(app, "s").absolute_bounds)
      fit_px(r, red.right - 2.0, red.bottom - 2.0).should eq(FIT_RED)
      fit_px(r, red.x + 2.0, red.y + 2.0).should eq(FIT_RED)
      g.image.width.should be < backend_w # coverage: the layer still fit the buffer it had
    end

    it "keeps the factor across a rebuild that does not change it: no re-scale, and pays per re-rendered widget" do
      app = FitClockApp.new
      r = fit_run(app, 400, 200)
      CrymbleUI::Fitted.apply_scale_calls = 0
      app.request_rebuild
      CrymbleUI::Testing::TestRenderBackend.census_start
      r.settle_rendering(app)
      fit_subtree_surfaces(fit_find(app, "f"), CrymbleUI::Testing::TestRenderBackend.census_take).should eq(0) # an unchanged rebuild allocates nothing there
      CrymbleUI::Fitted.apply_scale_calls.should eq(0)

      # a clock tick of the same width: one widget re-renders, at most one surface per re-rendered widget
      app.label = "12:01"
      app.request_rebuild
      CrymbleUI::LayerRenderer.reset_frame_counters
      CrymbleUI::Testing::TestRenderBackend.census_start
      r.settle_rendering(app)
      made = fit_subtree_surfaces(fit_find(app, "f"), CrymbleUI::Testing::TestRenderBackend.census_take)
      rendered = CrymbleUI::LayerRenderer.rendered_widgets.count(&.includes?("/f/"))
      rendered.should be >= 1
      made.should be <= rendered
      CrymbleUI::Fitted.apply_scale_calls.should eq(0)
    end
  end

  it "13: a combo box inside opens its popup at natural size, anchored under the scaled combo (GUARD: the limit)" do
    CrymbleUI::Testing::TestRenderBackend.text_log = [] of {String, Float64}
    begin
      app = FitComboApp.new
      r = fit_run(app)
      combo = fit_find(app, "cb").as(CrymbleUI::ComboBox)
      g = fit_geo(fit_find(app, "f"))
      g.f.should be > 2.0
      painted = g.paint_rect(combo.absolute_bounds)
      at = CrymbleUI::Vec2.new(painted.right - 6.0, painted.center.y)
      combo.absolute_bounds.contains_point(at).should be_false
      r.mouse_down(at.x, at.y)
      r.mouse_up(at.x, at.y)
      r.settle_rendering(app)
      combo.popup_open?.should be_true
      popup = combo.current_popup.not_nil!
      popup.bounds.x.should be_close(painted.x, 0.5)
      below = (popup.bounds.y - painted.bottom).abs <= 0.5
      above = (popup.bounds.y - (painted.y - popup.bounds.height)).abs <= 0.5
      (below || above).should be_true
      natural = CrymbleUI::FontSizing.calculate_size(0)
      log = CrymbleUI::Testing::TestRenderBackend.text_log.not_nil!
      log.any? { |(text, size)| text.includes?("Banana") && size < natural * 1.5 }.should be_true
    ensure
      CrymbleUI::Testing::TestRenderBackend.text_log = nil
    end
  end

  describe "14: a layer owner inside is refused" do
    it "refuses a scroll view as the child, naming it, where it is and what to do" do
      app = FitRefuseScrollApp.new
      r = fit_run(app)
      r.exceptions_caught.should be > 0
      message = r.last_exception_message.not_nil!
      message.should contain("fitted cannot scale a ScrollView")
      message.should contain("#log")
      message.should contain(fit_find(app, "log").path_id)
      message.should contain("put fitted around the content inside the scroll view")
      message.should_not contain("INVARIANT")
    end

    it "refuses two children" do
      app = FitTwoChildrenApp.new
      r = fit_run(app)
      r.exceptions_caught.should be > 0
      r.last_exception_message.not_nil!.should contain("fitted takes one child - wrap several in a vstack or hstack")
    end

    it "refuses a scroll view appearing deep inside on a later build, in that frame" do
      app = FitDeepScrollApp.new
      r = fit_run(app)
      r.exceptions_caught.should eq(0)
      app.flag = true
      app.request_rebuild
      r.render_frame(app)
      r.exceptions_caught.should eq(1)
      r.last_exception_message.not_nil!.should contain("fitted cannot scale a ScrollView")
    end

    it "fails loud on the backstop when a layer owner slips past the refusal" do
      app = FitBackstopApp.new
      r = fit_run(app)
      r.exceptions_caught.should be > 0
      r.last_exception_message.not_nil!.should contain("enclosing_scroll")
    end
  end

  it "15: Ctrl+zoom inside a filling fitted keeps the image's extent; outside, text grows" do
    app = FitZoomApp.new
    r = fit_run(app)
    extent = ->(renderer : CrymbleUI::Testing::TestRenderer, y : Int32) do
      left = (0...renderer.backend.width).find { |x| renderer.backend.get_pixel(x, y) == FIT_RED }.not_nil!
      right = (0...renderer.backend.width).to_a.reverse.find { |x| renderer.backend.get_pixel(x, y) == FIT_BLUE }.not_nil!
      right - left
    end
    ctl = fit_find(app, "ctl")
    ctl_h = ctl.bounds.height
    g = fit_geo(fit_find(app, "f"))
    before = extent.call(r, g.image.center.y.to_i)
    (g.box.width - g.image.width).abs.should be <= 1.0 # the width binds: the image fills it
    CrymbleUI::FontSizing.zoom_in.should be_true
    r.settle_rendering(app)
    g2 = fit_geo(fit_find(app, "f"))
    after = extent.call(r, g2.image.center.y.to_i)
    (after - before).abs.should be <= 1
    fit_find(app, "ctl").bounds.height.should be > ctl_h
  end

  describe "16: budgets" do
    it "a resize the fitted does not see re-renders nothing in its layer" do
      app = FitBudgetApp.new
      r = fit_run(app)
      fitted = fit_find(app, "f")
      layer_id = fitted.layer.not_nil!.id
      CrymbleUI::LayerRenderer.reset_frame_counters
      CrymbleUI::Fitted.apply_scale_calls = 0
      fit_resize(app, r, 400, 360) # the column is laid out loose in height: the fitted's width is unchanged
      CrymbleUI::LayerRenderer.rendered_layer_ids.includes?(layer_id).should be_false
      CrymbleUI::Fitted.apply_scale_calls.should eq(0)
    end

    it "a factor change costs at most its subtree" do
      app = FitBudgetApp.new
      r = fit_run(app)
      fitted = fit_find(app, "f")
      subtree = fit_subtree(fitted.children.first)
      CrymbleUI::LayerRenderer.reset_frame_counters
      CrymbleUI::Fitted.apply_scale_calls = 0
      CrymbleUI::Fitted.refusal_walk_visits = 0
      FitSwatch.layouts = 0
      CrymbleUI::Widget.reset_layout_count
      CrymbleUI::Testing::TestRenderBackend.census_start
      r.resize(440, 300)
      app.root.not_nil!.mark_needs_layout
      2.times { r.render_frame(app) }
      made = CrymbleUI::Testing::TestRenderBackend.census_take.size
      rendered = CrymbleUI::LayerRenderer.rendered_widgets.count { |name| subtree.any? { |w| name.ends_with?("##{w.path_id}") } }
      rendered.should be <= subtree.size
      made.should be <= 2 * subtree.size + 1 # a widget surface and its background each, plus the layer's
      FitSwatch.layouts.should eq(0) # the child keeps its natural size: not laid out again
      CrymbleUI::Fitted.apply_scale_calls.should be <= 1
      CrymbleUI::Fitted.refusal_walk_visits.should be <= subtree.size * 2
      CrymbleUI::Widget.layout_count.should be <= 8 # the ancestors' relayouts, measured
      g = fit_geo_loose(fitted, fitted.viewport_bounds.position, fit_find(app, "col").viewport_bounds.width, Float64::INFINITY)
      fit_px(r, g.image.right - 2.0, g.image.center.y).should eq(FIT_BLUE)
    end
  end
end
