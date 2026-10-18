require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# A panel lies inside its window unless the user chose otherwise, per quantity: a width the user never
# changed is the app's ask (or the content's floor), never more than the window; an x the user never moved
# is the app's ask, shifted inside; a y the user never moved is the app's ask, shifted up inside (the top
# winning for a panel taller than the window - the height itself is not capped). What the user dragged or
# resized keeps the old rule (MIN_VISIBLE_MARGIN across, the title bar down). The ask is the build's
# x:/y:/width: at first placement, or the last write from code; all are carried across rebuilds.
class WindowFitApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property px = 300.0
  property pw = 500.0
  property image_w : Float64? = nil # content wider than the window when set
  property flow_items = 0           # wrapping content: fixed 100x60 images in a flow
  property py = 100.0
  property ph = 150.0
  property bars = false             # a menubar and a statusbar: the panel area starts below the one, ends above the other
  property tree = false             # content: a collapsed tree node holding five 100x60 images

  def build : CrymbleUI::Widget
    window("Host", 420, 600) do
      if bars
        menubar { menu("File") { menu_item("Quit") { } } }
      end
      window_panel("P", px, py, pw, ph, id: "p") do
        if w = image_w
          image("nonexistent.png", width: w, height: 20.0, id: "c")
        elsif flow_items > 0
          flow(id: "c", hspacing: 0.0, vspacing: 0.0) do
            flow_items.times { image("nonexistent.png", width: 100.0, height: 60.0) }
          end
        elsif tree
          tree_node("More", id: "t") do
            vstack { 5.times { image("nonexistent.png", width: 100.0, height: 60.0) } }
          end
        else
          text("hello", id: "c")
        end
      end
      statusbar("Ready") if bars
    end
  end
end

private def panel(app) : CrymbleUI::WindowPanel
  app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
end

# Settles, and fails if any frame raised (TestRenderer swallows frame exceptions).
private def settle(app, r)
  before = CrymbleUI::Testing::TestRenderer.frame_exceptions_swallowed
  r.settle_rendering(app)
  CrymbleUI::Testing::TestRenderer.frame_exceptions_swallowed.should eq(before)
end

private def fit_app(px, pw, window_w = 420, image_w : Float64? = nil, flow_items = 0,
                     py = 100.0, ph = 150.0, window_h = 600, bars = false, tree = false)
  app = WindowFitApp.new
  app.px = px; app.pw = pw; app.image_w = image_w; app.flow_items = flow_items
  app.py = py; app.ph = ph; app.bars = bars; app.tree = tree
  r = CrymbleUI::Testing::TestRenderer.new(window_w, window_h)
  app.build_tree
  settle(app, r)
  {app, r}
end

private def rebuild(app, r)
  app.request_rebuild
  settle(app, r)
end

private def resize(app, r, w, h = 600)
  r.resize(w, h)
  settle(app, r)
end

# The window's panel area: below the menubar, above the statusbar.
private def area(app) : CrymbleUI::Rect
  app.root.not_nil!.as(CrymbleUI::Window).panel_area_bounds
end

# A press on the title bar, clear of the buttons and the resize handles.
private def title_point(p) : {Float64, Float64}
  {p.x + 40.0, p.y + 12.0}
end

private def drag_title(app, r, dx : Float64, dy : Float64 = 0.0)
  tx, ty = title_point(panel(app))
  r.mouse_down(tx, ty)
  r.mouse_move(tx + dx, ty + dy)
  r.mouse_up(tx + dx, ty + dy)
  settle(app, r)
end

# A press inside the right-edge handle, at mid-height.
private def right_edge_point(p) : {Float64, Float64}
  {p.x + p.width - 3.0, p.y + 70.0}
end

# Presses inside the top / bottom handles, and the top corners.
private def top_edge_point(p) : {Float64, Float64}
  {p.x + 70.0, p.y + 3.0}
end

private def bottom_edge_point(p) : {Float64, Float64}
  {p.x + 70.0, p.y + p.height - 3.0}
end

private def top_left_point(p) : {Float64, Float64}
  {p.x + 3.0, p.y + 3.0}
end

private def top_right_point(p) : {Float64, Float64}
  {p.x + p.width - 3.0, p.y + 3.0}
end

# A press at `from`, a move by dx/dy, the release there.
private def drag_from(app, r, from : {Float64, Float64}, dx : Float64, dy : Float64)
  x, y = from
  r.mouse_down(x, y)
  r.mouse_move(x + dx, y + dy)
  r.mouse_up(x + dx, y + dy)
  settle(app, r)
end

describe "a panel in a window narrower than it asks for" do
  it "is narrowed to the window and moved inside, content included" do
    app, _r = fit_app(300.0, 500.0)
    p = panel(app)
    p.x.should eq(0.0)
    p.width.should eq(420.0)
    c = app.find("p_content").not_nil!.absolute_bounds # the panel's content area
    (c.x + c.width).should be <= 420.0
  end

  it "fits but reaches past the right edge: moved, not narrowed" do
    app, _r = fit_app(300.0, 200.0)
    panel(app).x.should eq(220.0)
    panel(app).width.should eq(200.0)
  end

  it "reaches past the left edge: moved to the left edge" do
    app, _r = fit_app(-50.0, 200.0)
    panel(app).x.should eq(0.0)
  end

  it "exactly as wide as the window: unchanged" do
    app, _r = fit_app(0.0, 420.0)
    panel(app).x.should eq(0.0)
    panel(app).width.should eq(420.0)
  end

  it "content wider than the window: the window wins, and lets go when the window grows" do
    app, r = fit_app(300.0, 500.0, image_w: 700.0)
    panel(app).width.should eq(420.0)
    resize(app, r, 1000)
    panel(app).width.should eq(716.0) # the content's floor: 700 + 2 x CONTENT_PADDING
  end

  it "gets its asked x back when the window grows" do
    app, r = fit_app(300.0, 200.0)
    panel(app).x.should eq(220.0)
    resize(app, r, 1000)
    panel(app).x.should eq(300.0)
    panel(app).width.should eq(200.0)
  end

  it "gets its asked width back when the window grows" do
    app, r = fit_app(300.0, 500.0)
    resize(app, r, 1200)
    panel(app).width.should eq(500.0)
  end

  it "a rebuild of a narrowed panel lays it out once" do
    app, r = fit_app(300.0, 500.0, image_w: 700.0)
    before = CrymbleUI::WindowPanel.min_floor_recompute_count
    rebuild(app, r)
    panel(app).width.should eq(420.0)
    (CrymbleUI::WindowPanel.min_floor_recompute_count - before).should eq(1)
  end

  it "an ask changed by the app between builds does not move a placed panel" do
    app, r = fit_app(300.0, 200.0, window_w: 1000)
    app.px = 10.0; app.pw = 300.0
    rebuild(app, r)
    panel(app).x.should eq(300.0)
    panel(app).width.should eq(200.0)
  end

  it "returns to its asked width when its content floor drops" do
    app, r = fit_app(100.0, 500.0, window_w: 1200, image_w: 700.0)
    panel(app).width.should eq(716.0)
    app.image_w = nil
    rebuild(app, r)
    panel(app).width.should eq(500.0)
  end
end

describe "what the user chose" do
  it "a click on the title bar without moving is not a move" do
    app, r = fit_app(200.0, 200.0, window_w: 1000)
    tx, ty = title_point(panel(app))
    r.mouse_down(tx, ty)
    r.mouse_up(tx, ty)
    settle(app, r)
    panel(app).user_moved_x.should be_false
    resize(app, r, 300)
    panel(app).x.should eq(100.0) # fitted, not the margin rule's 200
  end

  it "a rebuild between the press and a motionless move keeps the press start" do
    app, r = fit_app(200.0, 200.0, window_w: 1000)
    tx, ty = title_point(panel(app))
    r.mouse_down(tx, ty)
    rebuild(app, r)
    panel(app).dragging?.should be_true # the press reached the rebuilt panel
    r.mouse_move(tx, ty)
    r.mouse_up(tx, ty)
    settle(app, r)
    resize(app, r, 300)
    panel(app).x.should eq(100.0)
  end

  it "a panel dragged past the edge keeps the margin rule, across a rebuild and a resize" do
    app, r = fit_app(100.0, 200.0, window_w: 1000)
    drag_title(app, r, 1000.0) # the drag clamp stops it at area.right - MIN_VISIBLE_MARGIN
    panel(app).x.should eq(1000.0 - CrymbleUI::WindowPanel::MIN_VISIBLE_MARGIN)
    rebuild(app, r)
    panel(app).user_moved_x.should be_true
    resize(app, r, 600)
    panel(app).x.should eq(600.0 - CrymbleUI::WindowPanel::MIN_VISIBLE_MARGIN)
  end

  it "moving a narrowed panel does not hand over its width" do
    app, r = fit_app(300.0, 500.0, image_w: 700.0)
    drag_title(app, r, 10.0)
    panel(app).user_moved_x.should be_true
    panel(app).width.should eq(420.0)
  end

  it "a vertical drag is not a move" do
    app, r = fit_app(200.0, 200.0, window_w: 1000)
    drag_title(app, r, 0.0, 50.0)
    panel(app).user_moved_x.should be_false
    resize(app, r, 300)
    panel(app).x.should eq(100.0)
  end

  it "a panel widened past the edge keeps its width, and its x is fitted" do
    app, r = fit_app(300.0, 100.0)
    ex, ey = right_edge_point(panel(app))
    r.mouse_down(ex, ey)
    r.mouse_move(ex + 200.0, ey)
    r.mouse_up(ex + 200.0, ey)
    settle(app, r)
    rebuild(app, r)
    panel(app).user_sized.should be_true
    panel(app).width.should eq(300.0)
    panel(app).x.should eq(120.0)
  end

  it "a resize of the height only is not a choice of width" do
    app, r = fit_app(100.0, 300.0, window_w: 1000)
    p = panel(app)
    bx, by = p.x + 150.0, p.y + p.height - 3.0
    r.mouse_down(bx, by)
    r.mouse_move(bx, by + 40.0)
    r.mouse_up(bx, by + 40.0)
    settle(app, r)
    panel(app).user_sized.should be_false
    resize(app, r, 250)
    panel(app).width.should eq(250.0)
  end

  it "a window shrinking under a pressed title bar does not move the panel until the release" do
    app, r = fit_app(300.0, 100.0)
    tx, ty = title_point(panel(app))
    r.mouse_down(tx, ty)
    resize(app, r, 350)
    panel(app).x.should eq(300.0) # pressed, not moved: the fit (250) waits for the release
    r.mouse_up(tx, ty)
    settle(app, r)
    panel(app).x.should eq(250.0)
  end

  it "a rebuild mid-resize does not move the panel; the release fits it" do
    app, r = fit_app(300.0, 100.0)
    ex, ey = right_edge_point(panel(app))
    r.mouse_down(ex, ey)
    r.mouse_move(ex + 200.0, ey)
    rebuild(app, r)
    panel(app).x.should eq(300.0)
    r.mouse_up(ex + 200.0, ey)
    settle(app, r)
    panel(app).x.should eq(120.0)
  end

  it "a window narrower than the smallest panel: the smallest panel, at the left edge" do
    app, _r = fit_app(300.0, 500.0, window_w: 60)
    panel(app).width.should eq(CrymbleUI::WindowPanel::MIN_PANEL_SIZE)
    panel(app).x.should eq(0.0)
  end

  it "maximize and restore are not the user placing the panel" do
    app, r = fit_app(300.0, 500.0, window_w: 1000)
    tx, ty = title_point(panel(app))
    r.mouse_down(tx, ty); r.mouse_up(tx, ty)
    r.mouse_down(tx, ty); r.mouse_up(tx, ty) # a double-click: maximize
    settle(app, r)
    panel(app).maximized.should be_true
    r.mouse_down(500.0, 12.0); r.mouse_up(500.0, 12.0)
    r.mouse_down(500.0, 12.0); r.mouse_up(500.0, 12.0) # restore, away from the first point
    settle(app, r)
    panel(app).maximized.should be_false
    panel(app).x.should eq(300.0)
    panel(app).width.should eq(500.0)
    resize(app, r, 420)
    panel(app).x.should eq(0.0)
    panel(app).width.should eq(420.0)
  end

  it "a window resized while maximized: restore fits the asks, not the window's bounds" do
    app, r = fit_app(300.0, 500.0, window_w: 1000)
    panel(app).maximize(CrymbleUI::Rect.new(0.0, 0.0, 1000.0, 600.0))
    settle(app, r)
    resize(app, r, 600)
    panel(app).restore
    settle(app, r)
    panel(app).x.should eq(100.0)
    panel(app).width.should eq(500.0)
  end

  it "restore does not turn the fitted geometry into the ask" do
    app, r = fit_app(300.0, 500.0) # carried 0/420, asked 300/500
    panel(app).maximize(CrymbleUI::Rect.new(0.0, 0.0, 420.0, 600.0))
    settle(app, r)
    resize(app, r, 1000)
    panel(app).restore
    settle(app, r)
    panel(app).x.should eq(300.0)
    panel(app).width.should eq(500.0)
  end

  it "a width from code wider than the window is fitted at once, with no rebuild" do
    app, r = fit_app(0.0, 200.0)
    panel(app).width = 2000.0
    settle(app, r)
    panel(app).width.should eq(420.0)
  end

  it "writing back the fitted x from code does not make it the ask" do
    app, r = fit_app(300.0, 200.0) # fitted to 220
    panel(app).move_by(0.0, 10.0)
    settle(app, r)
    resize(app, r, 1000)
    panel(app).x.should eq(300.0)
  end

  it "a write from code is a new ask, kept across a rebuild" do
    app, r = fit_app(300.0, 500.0, window_w: 1000)
    panel(app).width = 300.0
    panel(app).move_to(50.0, 100.0)
    settle(app, r)
    panel(app).width.should eq(300.0)
    panel(app).x.should eq(50.0)
    rebuild(app, r)
    panel(app).width.should eq(300.0)
    panel(app).x.should eq(50.0)
  end
end

describe "the chrome and the content follow a narrowing" do
  it "the title bar is as wide as the narrowed panel" do
    app, _r = fit_app(300.0, 500.0)
    app.find("p_chrome").not_nil!.bounds.width.should eq(420.0)
  end

  it "wrapping content gets the height it needs at the narrowed width" do
    # One row of 8 at 800 fits the built height 150; two rows (120 + chrome) at ~400 do not.
    app, r = fit_app(0.0, 820.0, window_w: 1000, flow_items: 8)
    panel(app).height.should eq(150.0)
    resize(app, r, 420)
    p = panel(app)
    flow = app.find("c").not_nil!
    flow.bounds.height.should eq(120.0)
    (p.y + p.height).should be >= (flow.absolute_bounds.y + flow.bounds.height)
  end
end

describe "down the height: a panel the user never moved keeps its bottom inside the window" do
  it "asked low in a short window, it opens with its bottom at the window's bottom" do
    app, _r = fit_app(100.0, 200.0, py: 300.0, window_h: 400)
    panel(app).y.should eq(250.0)
    panel(app).height.should eq(150.0)
  end

  it "the panel area counts: its bottom is the statusbar's top" do
    app, _r = fit_app(100.0, 200.0, py: 300.0, window_h: 400, bars: true)
    panel(app).y.should eq(area(app).bottom - 150.0)
    panel(app).height.should eq(150.0)
  end

  it "taller than the window, its top stays at the window's top and its height as asked" do
    app, _r = fit_app(100.0, 200.0, ph: 700.0)
    panel(app).y.should eq(0.0)
    panel(app).height.should eq(700.0)
  end

  it "taller than the panel area, its top is the area's top - below the menubar" do
    app, _r = fit_app(100.0, 200.0, ph: 700.0, bars: true)
    area(app).y.should be > 0.0 # precondition: a menubar
    panel(app).y.should eq(area(app).y)
  end

  it "the window losing height lifts it, and gaining it back returns it to the ask" do
    app, r = fit_app(100.0, 200.0, py: 300.0)
    panel(app).y.should eq(300.0)
    resize(app, r, 420, 400)
    panel(app).y.should eq(250.0)
    resize(app, r, 420, 600)
    panel(app).y.should eq(300.0)
  end

  it "a y from code is a new ask, fitted at once with no rebuild" do
    app, r = fit_app(100.0, 200.0)
    panel(app).move_to(100.0, 500.0)
    settle(app, r)
    panel(app).y.should eq(450.0)
  end

  it "writing back the fitted y from code does not make it the ask" do
    app, r = fit_app(100.0, 200.0, py: 300.0, window_h: 400)
    panel(app).y.should eq(250.0)
    panel(app).move_by(10.0, 0.0)
    settle(app, r)
    resize(app, r, 420, 600)
    panel(app).y.should eq(300.0)
  end

  it "content growing past the bottom lifts it, through a rebuild" do
    app, r = fit_app(0.0, 820.0, window_w: 1000, flow_items: 8, py: 400.0)
    panel(app).y.should eq(400.0)
    app.flow_items = 32
    rebuild(app, r)
    p = panel(app)
    p.height.should be > 200.0 # precondition: it grew past the bottom
    p.y.should eq(600.0 - p.height)
  end

  it "content growing past the bottom lifts it, with no rebuild: a tree node opened by a click" do
    app, r = fit_app(100.0, 300.0, py: 400.0, tree: true)
    panel(app).y.should eq(400.0)
    node = app.find("t").not_nil!.as(CrymbleUI::TreeNode)
    click_on(app, node.children.first)
    settle(app, r)
    p = panel(app)
    p.height.should be > 200.0 # precondition: it grew past the bottom
    p.y.should eq(600.0 - p.height)
  end

  it "a horizontal drag does not hand over the y" do
    app, r = fit_app(300.0, 200.0, window_w: 1000, py: 300.0)
    drag_title(app, r, 50.0, 0.0)
    resize(app, r, 1000, 400)
    panel(app).y.should eq(250.0)
  end

  it "a window shrinking under a pressed title bar lifts the panel only after the release" do
    app, r = fit_app(100.0, 200.0, py: 300.0)
    tx, ty = title_point(panel(app))
    r.mouse_down(tx, ty)
    resize(app, r, 420, 400) # the title bar stays inside
    panel(app).y.should eq(300.0)
    r.mouse_up(tx, ty)
    settle(app, r)
    panel(app).y.should eq(250.0)
  end

  it "the bottom edge resized past the window: still during the resize, slid up on the release" do
    app, r = fit_app(100.0, 200.0, py: 300.0)
    bx, by = bottom_edge_point(panel(app))
    r.mouse_down(bx, by)
    r.mouse_move(bx, by + 200.0)
    rebuild(app, r)
    panel(app).y.should eq(300.0)
    r.mouse_up(bx, by + 200.0)
    settle(app, r)
    panel(app).height.should eq(350.0)
    panel(app).y.should eq(250.0)
  end

  it "a window losing height while maximized: restore fits the asked y" do
    app, r = fit_app(100.0, 200.0, py: 300.0)
    panel(app).maximize(CrymbleUI::Rect.new(0.0, 0.0, 420.0, 600.0))
    settle(app, r)
    resize(app, r, 420, 400)
    panel(app).restore
    settle(app, r)
    panel(app).y.should eq(250.0)
  end

  it "restore does not turn the fitted y into the ask" do
    app, r = fit_app(100.0, 200.0, py: 300.0, window_h: 400)
    panel(app).y.should eq(250.0)
    panel(app).maximize(CrymbleUI::Rect.new(0.0, 0.0, 420.0, 400.0))
    settle(app, r)
    resize(app, r, 420, 600)
    panel(app).restore
    settle(app, r)
    panel(app).y.should eq(300.0)
  end

  # Guards (green before): what the user moved keeps the title-bar rule - each case with numbers where the fit
  # would give another y.

  it "a vertical drag hands over the y: kept across a rebuild and a window losing height" do
    app, r = fit_app(100.0, 200.0, window_w: 1000)
    drag_title(app, r, 0.0, 350.0)
    panel(app).y.should eq(450.0)
    rebuild(app, r)
    resize(app, r, 1000, 500) # the title bar stays inside, the bottom does not; the fit would give 100
    panel(app).y.should eq(450.0)
  end

  it "a top-edge resize hands over the y" do
    app, r = fit_app(100.0, 200.0, window_w: 1000, py: 300.0)
    drag_from(app, r, top_edge_point(panel(app)), 0.0, 40.0)
    panel(app).y.should eq(340.0)
    panel(app).height.should eq(110.0)
    rebuild(app, r) # the fit would bring it back to the ask, 300
    panel(app).y.should eq(340.0)
  end

  it "a top-left resize hands over both x and y" do
    app, r = fit_app(300.0, 200.0, window_w: 1000, py: 300.0)
    drag_from(app, r, top_left_point(panel(app)), -40.0, -40.0)
    {panel(app).x, panel(app).y}.should eq({260.0, 260.0})
    resize(app, r, 420, 600) # the fit would give x 180 (420 - 240), y 300
    {panel(app).x, panel(app).y}.should eq({260.0, 260.0})
  end

  it "a top-right resize hands over the y only" do
    app, r = fit_app(300.0, 200.0, window_w: 1000, py: 300.0)
    drag_from(app, r, top_right_point(panel(app)), 40.0, -40.0)
    {panel(app).y, panel(app).width}.should eq({260.0, 240.0})
    resize(app, r, 420, 600) # x fitted: 420 - 240; the fit would give y 300
    {panel(app).x, panel(app).y}.should eq({180.0, 260.0})
  end

  it "a diagonal drag hands over both" do
    app, r = fit_app(300.0, 200.0, window_w: 1000, py: 300.0)
    drag_title(app, r, -50.0, 100.0)
    resize(app, r, 420, 600) # the fit would give x 220, y 300
    {panel(app).x, panel(app).y}.should eq({250.0, 400.0})
  end

  it "a y: changed by the app between builds does not move a placed panel" do
    app, r = fit_app(100.0, 200.0, py: 300.0)
    app.py = 10.0
    rebuild(app, r)
    panel(app).y.should eq(300.0)
  end
end
