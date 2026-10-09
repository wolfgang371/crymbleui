require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# THE COMPOSITE ORDER: a layer composites directly above the layer it is painted into and below that layer's
# later siblings, at any depth - so what covers a widget covers the layers inside it too. Read from the
# composited window pixels; every covered sample is paired with an uncovered one of the same layer (the
# positive control: the layer did render).

private HEAD  = CrymbleUI::Color.new(0, 0, 90, 255)
private INNER = CrymbleUI::Color.new(0, 200, 0, 255)

class CoSwatch < CrymbleUI::Widget
  def initialize(@height : Float64, @color : CrymbleUI::Color, @width : Float64? = nil, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width || (constraints.max_width.finite? ? constraints.max_width : 100.0), @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# A small scroll view over tall content: a layer owner with a content layer and a scrollbar.
private def co_scroller(id : String) : CrymbleUI::ScrollView
  CrymbleUI::ScrollView.new(max_height: 10.0, id: id).tap(&.set_content(CoSwatch.new(40.0, INNER)))
end

# Row 0 a sticky header (the scroll order's descending tail); every other cell a box holding a scroll view.
class CoNestedGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], [0, 1]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return CoSwatch.new(10.0, HEAD) if row == 0
    CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(co_scroller("sv_#{row}_#{col}")))
  end
end

class CoApp < CrymbleUI::App
  def initialize(&@make : -> CrymbleUI::Widget)
    super()
  end

  def build : CrymbleUI::Widget
    @make.call
  end
end

private def co_run(&make : -> CrymbleUI::Widget) : {CoApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(700, 500)
  app = CoApp.new(&make)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {app, renderer}
end

private def co_pixel(renderer, at : CrymbleUI::Vec2) : CrymbleUI::Color
  renderer.backend.get_pixel(at.x.to_i, at.y.to_i).not_nil!
end

# A grid of `adapter` in a panel, scrolled 8px - row 1 slides partly under the sticky header row. Every cell the
# scenes sample is on screen from the first frame (cells a scroll REVEALS are another matter). Its cursor overlay
# paints nothing (cursor_highlight_delta 0 - its layers are there, in their place): the scenes read pixels of
# row 0 and column 0, where the cursor's bands would lie.
private def co_grid(adapter) : {CoApp, CrymbleUI::Testing::TestRenderer, CrymbleUI::VirtualMatrix}
  app, renderer = co_run do
    window = CrymbleUI::Window.new("W", 700, 500)
    panel = CrymbleUI::WindowPanel.new("P", 20.0, 60.0, 400.0, 300.0, id: "p")
    vm = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "grid", cursor_highlight_delta: 0)
    panel.add_child(vm)
    window.add_child(panel)
    window
  end
  vm = app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)
  vm.scroll_offset = CrymbleUI::Vec2.new(0.0, 8.0)
  renderer.settle_rendering(app)
  adapter.has_active_highlights?.should be_false # instrument: no change wash either - the one overlay fill not off
  {app, renderer, vm}
end

private INNER2 = CrymbleUI::Color.new(200, 0, 200, 255)
private NAVY   = CrymbleUI::Color.new(0, 0, 120, 255)
private GREY   = CrymbleUI::Color.new(200, 200, 200, 255)

# Depth 2: a cell holds scroll view A, A holds scroll view B. `cell_is_a`: the cell widget IS A.
class CoDepthTwoAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@cell_is_a : Bool)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], [0, 1]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return CoSwatch.new(10.0, HEAD) if row == 0
    b = CrymbleUI::ScrollView.new(max_height: 10.0, id: "b_#{row}_#{col}").tap(&.set_content(CoSwatch.new(40.0, INNER2)))
    a = CrymbleUI::ScrollView.new(max_height: 10.0, id: "a_#{row}_#{col}")
    a.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(b)))
    @cell_is_a ? a : CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(a))
  end
end

# A header row whose column-1 cell (a box) holds a scroll view; 10 columns, so the grid scrolls sideways.
class CoStickyCellAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], (0...10).to_a}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return CoSwatch.new(10.0, GREY) unless row == 0
    return CoSwatch.new(10.0, HEAD) unless col == 1
    CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(co_scroller("hdr_sv")))
  end
end

# Plain cells under a sticky header row.
class CoPlainGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], [0, 1, 2]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CoSwatch.new(10.0, row == 0 ? HEAD : GREY)
  end
end

# CoNestedGridAdapter whose sticky header can be switched off and on - announced the app's way (invalidate_all!).
class CoTogglingStickyAdapter < CoNestedGridAdapter
  property sticky = true

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {sticky ? (1...20).to_a + [0] : (0...20).to_a, [0, 1]}
  end
end

private def co_panel(title : String, x, y, w, h, id : String, z : Int32 = 0) : CrymbleUI::WindowPanel
  CrymbleUI::WindowPanel.new(title, x.to_f, y.to_f, w.to_f, h.to_f, z_index: z, id: id)
end

private def co_order(app) : Array(CrymbleUI::Layer)
  app.root.not_nil!.as(CrymbleUI::Window).collect_all_layers
end

# Does `hit` lie in `w`'s subtree (a click there reaches w or something inside it)?
private def within?(hit : CrymbleUI::Widget?, w : CrymbleUI::Widget) : Bool
  node = hit
  while node
    return true if node.same?(w)
    node = node.parent
  end
  false
end

describe "the composite order" do
  it "keeps a grid's sticky header over the layers inside its cells" do
    app, renderer, vm = co_grid(CoNestedGridAdapter.new)
    header = vm.active_cells[{0, 0}].viewport_bounds
    covered = app.find("sv_1_0").not_nil!.as(CrymbleUI::ScrollView)
    shown = app.find("sv_3_0").not_nil!.as(CrymbleUI::ScrollView)
    c, s = covered.viewport_bounds, shown.viewport_bounds
    (c.y < header.bottom).should be_true # instrument: row 1's scroll view reaches under the header
    under = (c.y + header.bottom) / 2.0  # inside both the header cell and the covered scroll view
    content_x, scrollbar_x = c.x + 10.0, c.right - 3.0
    # The positive controls: the same kind of layer, uncovered - its content and its scrollbar render.
    co_pixel(renderer, CrymbleUI::Vec2.new(content_x, s.y + 5.0)).should eq(INNER)
    bar = co_pixel(renderer, CrymbleUI::Vec2.new(scrollbar_x, s.y + 5.0))
    {INNER, HEAD}.includes?(bar).should be_false # instrument: a scrollbar pixel, neither content nor header
    # Covered: the header over the nested content and over its scrollbar.
    co_pixel(renderer, CrymbleUI::Vec2.new(content_x, under)).should eq(HEAD)
    co_pixel(renderer, CrymbleUI::Vec2.new(scrollbar_x, under)).should eq(HEAD)
    # A click where the header is drawn lands on the header cell.
    vm.point_to_cell(CrymbleUI::Vec2.new(scrollbar_x, under)).should eq({0, 0})
  end

  it "keeps plain window content under a panel, even the first panel (z 0)" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = co_panel("P", 40, 60, 300, 200, "p", 0)
      panel.add_child(CoSwatch.new(150.0, NAVY))
      window.add_child(panel) # first in tree order
      window.add_child(CrymbleUI::ScrollView.new(max_height: 400.0, id: "win_sv").tap(&.set_content(CoSwatch.new(800.0, INNER))))
      window
    end
    p = app.find("p").not_nil!.viewport_bounds
    at = CrymbleUI::Vec2.new(p.x + 60.0, p.y + 80.0)
    app.find("win_sv").not_nil!.viewport_bounds.contains_point(at).should be_true # instrument: the content lies under it
    co_pixel(renderer, CrymbleUI::Vec2.new(p.right + 30.0, p.y + 80.0)).should eq(INNER) # the content, uncovered
    co_pixel(renderer, at).should eq(NAVY)
    within?(app.root.not_nil!.hit_test(at), app.find("p").not_nil!).should be_true
  end

  {% for cell_is_a in [false, true] %}
    it "nests a scroll view two deep in a cell inside its container ({{ cell_is_a ? "the cell is the scroll view".id : "a box cell".id }})" do
      app, renderer, vm = co_grid(CoDepthTwoAdapter.new({{ cell_is_a }}))
      header = vm.active_cells[{0, 0}].viewport_bounds
      a = app.find("a_1_0").not_nil!.as(CrymbleUI::ScrollView)
      b = app.find("b_1_0").not_nil!.as(CrymbleUI::ScrollView)
      shown = app.find("b_3_0").not_nil!.viewport_bounds
      bb = b.viewport_bounds
      (bb.y < header.bottom).should be_true # instrument
      under = (bb.y + header.bottom) / 2.0
      co_pixel(renderer, CrymbleUI::Vec2.new(shown.x + 10.0, shown.y + 5.0)).should eq(INNER2) # B renders
      co_pixel(renderer, CrymbleUI::Vec2.new(bb.x + 10.0, under)).should eq(HEAD)             # the header over B
      # B composites inside A: after A's content, before A's scrollbar
      order = co_order(app)
      bi = order.index!(b.layer.not_nil!)
      (order.index!(a.layer.not_nil!) < bi && bi < order.index!(a.scrollbar_layer.not_nil!)).should be_true
    end
  {% end %}

  it "shows a scroll view in a sticky header cell over the band, where the band scrolled it" do
    app, renderer, vm = co_grid(CoStickyCellAdapter.new)
    vm.scroll_offset = CrymbleUI::Vec2.new(30.0, 0.0)
    renderer.settle_rendering(app)
    sv = app.find("hdr_sv").not_nil!
    v = sv.viewport_bounds
    band = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!.bounds
    band.contains_point(CrymbleUI::Vec2.new(v.x + 10.0, v.y + 5.0)).should be_true # instrument: inside the band
    co_pixel(renderer, CrymbleUI::Vec2.new(v.x + 10.0, v.y + 5.0)).should eq(INNER)
    co_pixel(renderer, CrymbleUI::Vec2.new(v.x - 20.0, v.y + 5.0)).should_not eq(INNER) # left of it: the band
  end

  # The cursor band and the drag decal extend over the sticky headers (VIRTUAL_MATRIX_ARCHITECTURE): the matrix's
  # own overlays composite after everything painted into its content, the chrome's bands included.
  it "keeps a grid's cursor band and drag decal over its sticky headers" do
    app, renderer, vm = co_grid(CoPlainGridAdapter.new)
    order = co_order(app)
    chrome = [] of CrymbleUI::Layer
    sv = vm.content_scroll_view.not_nil!
    chrome << sv.layer.not_nil!
    sv.each_owned_layer { |l| chrome << l }
    last_chrome = chrome.max_of { |l| order.index!(l) }
    vm.each_owned_layer { |overlay| order.index!(overlay).should be > last_chrome }
  end

  it "raises a panel by a click, no layout forced: its nested layers over the other panel" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      back = co_panel("B", 20, 60, 400, 300, "back", 1)
      outer = CrymbleUI::ScrollView.new(max_height: 200.0, id: "outer")
      inner = CrymbleUI::ScrollView.new(max_height: 60.0, id: "inner").tap(&.set_content(CoSwatch.new(200.0, INNER)))
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(inner); v.add_child(CoSwatch.new(400.0, GREY)) })
      back.add_child(outer)
      front = co_panel("F", 30, 100, 300, 200, "front", 2)
      front.add_child(CoSwatch.new(150.0, NAVY))
      window.add_child(back)
      window.add_child(front)
      window
    end
    i = app.find("inner").not_nil!.viewport_bounds
    at = CrymbleUI::Vec2.new(i.x + 20.0, i.bottom - 5.0)
    f = app.find("front").not_nil!.as(CrymbleUI::WindowPanel)
    (f.viewport_bounds.contains_point(at) && at.y > f.y + f.title_bar_height).should be_true # instrument: its content covers it
    co_pixel(renderer, at).should eq(NAVY)
    bar = app.find("inner").not_nil!.as(CrymbleUI::ScrollView).scrollbar_layer.not_nil!
    title = app.find("back").not_nil!.viewport_bounds
    click = CrymbleUI::Vec2.new(title.x + 40.0, title.y + 8.0)
    app.handle_mouse_down(click)
    app.handle_mouse_up(click)
    renderer.render_frame(app)
    co_pixel(renderer, at).should eq(INNER)
    order = co_order(app)
    order.index!(bar).should be > order.index!(app.find("front").not_nil!.layer.not_nil!)
  end

  it "composites popups above every panel: tree popups, then opened ones by z and opening order" do
    popups = [] of CrymbleUI::Popup
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      back = co_panel("B", 20, 60, 300, 300, "back", 1)
      tree = CrymbleUI::Popup.new(width: 120.0, height: 80.0, z_index: 1000, id: "tree_pop")
      tree.target_x, tree.target_y = 100.0, 150.0
      tree.add_child(CoSwatch.new(80.0, INNER))
      back.add_child(tree)
      front = co_panel("F", 60, 100, 400, 300, "front", 2)
      front.add_child(CoSwatch.new(250.0, NAVY))
      window.add_child(back)
      window.add_child(front)
      parent_menu = CrymbleUI::Popup.new(width: 100.0, height: 60.0, z_index: 1000, id: "menu")
      parent_menu.target_x, parent_menu.target_y = 150.0, 180.0
      parent_menu.add_child(CoSwatch.new(60.0, GREY))
      sub = CrymbleUI::Popup.new(width: 100.0, height: 60.0, z_index: 1000, id: "sub")
      sub.target_x, sub.target_y = 200.0, 200.0
      sub.add_child(CoSwatch.new(60.0, INNER2))
      window.add_overlay(parent_menu)
      window.add_overlay(sub)
      popups = [tree, parent_menu, sub]
      window
    end
    tree, parent_menu, sub = popups
    t = tree.viewport_bounds
    co_pixel(renderer, CrymbleUI::Vec2.new(t.x + 10.0, t.y + 10.0)).should eq(INNER) # over the front panel
    overlap_tm = CrymbleUI::Vec2.new(160.0, 190.0)                                      # tree popup under the menu
    co_pixel(renderer, overlap_tm).should eq(GREY)
    overlap_ms = CrymbleUI::Vec2.new(210.0, 210.0)                                      # menu under the submenu
    co_pixel(renderer, overlap_ms).should eq(INNER2)
    within?(app.root.not_nil!.hit_test(overlap_ms), sub).should be_true
    within?(app.root.not_nil!.hit_test(overlap_tm), parent_menu).should be_true
    # A z change re-orders without a layout
    parent_menu.z_index = 2000
    renderer.render_frame(app)
    co_pixel(renderer, overlap_ms).should eq(GREY)
    within?(app.root.not_nil!.hit_test(overlap_ms), parent_menu).should be_true
  end

  # A LayerBox is a local boundary: within the layer it sits in, after the plain content, by its z. (Nested in a
  # container it places its layer at its parent-relative position - a separate defect - so the nested case is
  # read from the order; the window-level one from the pixels.)
  it "composites a LayerBox by its z within its container" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      badge = CrymbleUI::LayerBox.new(50.0, 90.0, 60.0, 40.0, z_index: 1_000_000, id: "badge") # created before the panel
      badge.add_child(CoSwatch.new(40.0, INNER2))
      window.add_child(badge)
      tag = CrymbleUI::LayerBox.new(80.0, 100.0, 60.0, 40.0, z_index: 10, id: "tag") # overlaps the badge
      tag.add_child(CoSwatch.new(40.0, GREY))
      window.add_child(tag)
      panel = co_panel("P", 20, 60, 400, 300, "p", 5)
      box = CrymbleUI::LayerBox.new(100.0, 150.0, 80.0, 50.0, z_index: 1, id: "box") # before the scroll view
      box.add_child(CoSwatch.new(50.0, INNER))
      col = CrymbleUI::VStack.new(spacing: 0.0)
      col.add_child(box)
      col.add_child(CrymbleUI::ScrollView.new(max_height: 250.0, id: "sv").tap(&.set_content(CoSwatch.new(600.0, GREY))))
      panel.add_child(col)
      window.add_child(panel)
      front = co_panel("F", 150, 170, 200, 150, "front", 9)
      front.add_child(CoSwatch.new(120.0, NAVY))
      window.add_child(front)
      window
    end
    badge = app.find("badge").not_nil!.layer.not_nil!.bounds
    app.find("p").not_nil!.viewport_bounds.contains_point(badge.center).should be_true # instrument: over the panel
    co_pixel(renderer, badge.center).should eq(INNER2)
    order = co_order(app)
    box = app.find("box").not_nil!.layer.not_nil!
    sv = app.find("sv").not_nil!.as(CrymbleUI::ScrollView)
    (order.index!(sv.scrollbar_layer.not_nil!) < order.index!(box)).should be_true
    (order.index!(box) < order.index!(app.find("front").not_nil!.layer.not_nil!)).should be_true
    # A z change re-orders without a layout: the tag over the badge where they overlap
    overlap = CrymbleUI::Vec2.new(95.0, 115.0)
    co_pixel(renderer, overlap).should eq(INNER2)
    within?(app.root.not_nil!.hit_test(overlap), app.find("badge").not_nil!).should be_true
    app.find("badge").not_nil!.as(CrymbleUI::LayerBox).z_index = 1
    renderer.render_frame(app)
    co_pixel(renderer, overlap).should eq(GREY)
    within?(app.root.not_nil!.hit_test(overlap), app.find("tag").not_nil!).should be_true
  end

  it "lets a click through a window-level LayerBox whose content takes none" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = co_panel("P", 20, 60, 300, 200, "p", 1)
      panel.add_child(CoSwatch.new(100.0, GREY))
      window.add_child(panel)
      mon = CrymbleUI::LayerBox.new(290.0, 60.0, 40.0, 60.0, z_index: 1_000_000, id: "mon")
      mon.add_child(CrymbleUI::CPUMonitor.new)
      window.add_child(mon)
      window
    end
    p = app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
    close = CrymbleUI::Vec2.new(p.x + p.width - p.close_button_size / 2.0 - p.close_button_padding, p.y + p.title_bar_height / 2.0)
    app.find("mon").not_nil!.viewport_bounds.contains_point(close).should be_true # instrument: the monitor lies over it
    app.root.not_nil!.hit_test(close).same?(p).should be_true
    edge = CrymbleUI::Vec2.new(p.x + p.width - 1.0, p.y + p.title_bar_height + 5.0) # its right resize edge
    app.find("mon").not_nil!.viewport_bounds.contains_point(edge).should be_true    # instrument: under the monitor
    app.get_cursor_for_point(edge).should eq(CrymbleUI::CursorType::SizeHorizontal)
  end

  it "keeps the window's statusbar over a panel reaching it: drawn, clicked and hovered" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 400)
      panel = co_panel("P", 20, 40, 300, 500, "p", 1) # taller than the panel area
      panel.add_child(CoSwatch.new(480.0, NAVY))
      window.add_child(panel)
      window.add_child(CrymbleUI::StatusBar.new("Ready", id: "status")) # after the panel: tree order would lose
      window
    end
    s = app.find("status").not_nil!.viewport_bounds
    p = app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
    at = CrymbleUI::Vec2.new(p.x + 50.0, s.y + s.height / 2.0)
    p.viewport_bounds.contains_point(at).should be_true # instrument: the panel reaches under the bar
    co_pixel(renderer, at).should_not eq(NAVY)
    within?(app.root.not_nil!.hit_test(at), app.find("status").not_nil!).should be_true
    edge = CrymbleUI::Vec2.new(p.x + p.width - 2.0, s.y + s.height / 2.0)
    app.get_cursor_for_point(edge).should eq(CrymbleUI::CursorType::Arrow)
  end

  it "keeps a panel's own menubar within its panel, under the panel in front" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      back = co_panel("B", 20, 60, 300, 300, "back", 1)
      back.add_child(CrymbleUI::MenuBar.new(id: "back_menu"))
      back.add_child(CoSwatch.new(200.0, GREY))
      front = co_panel("F", 100, 70, 300, 300, "front", 2)
      front.add_child(CoSwatch.new(250.0, NAVY))
      window.add_child(back)
      window.add_child(front)
      window
    end
    m = app.find("back_menu").not_nil!.viewport_bounds
    at = CrymbleUI::Vec2.new(m.right - 10.0, m.center.y)
    app.find("front").not_nil!.viewport_bounds.contains_point(at).should be_true # instrument
    co_pixel(renderer, CrymbleUI::Vec2.new(at.x, at.y + 60.0)).should eq(NAVY) # the front panel's content
    within?(app.root.not_nil!.hit_test(at), app.find("front").not_nil!).should be_true
    co_pixel(renderer, at).should_not eq(co_pixel(renderer, CrymbleUI::Vec2.new(m.x + 5.0, m.center.y))) # not the menubar
  end

  it "stops a dragged panel's title bar at the statusbar" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 400)
      window.add_child(CrymbleUI::StatusBar.new("Ready", id: "status"))
      panel = co_panel("P", 20, 40, 300, 200, "p", 1)
      window.add_child(panel)
      window
    end
    p = app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
    s = app.find("status").not_nil!.viewport_bounds
    grab = CrymbleUI::Vec2.new(p.x + 40.0, p.y + 8.0)
    into_bar = CrymbleUI::Vec2.new(grab.x, s.y + s.height - 4.0)
    app.handle_mouse_down(grab)
    app.handle_mouse_move(into_bar)
    p.interaction_mode.should eq(CrymbleUI::InteractionMode::Dragging) # instrument
    (p.y + p.title_bar_height).should be <= s.y # while dragging (the release re-constrains anyway)
    app.handle_mouse_up(into_bar)
  end

  it "is one order: the renderer's, a capture's and collect_all_layers', whatever the creation order" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = co_panel("P", 20, 60, 400, 300, "p", 1)
      b = CrymbleUI::ScrollView.new(max_height: 100.0, id: "late").tap(&.set_content(CoSwatch.new(300.0, GREY)))
      a = CrymbleUI::ScrollView.new(max_height: 100.0, id: "early").tap(&.set_content(CoSwatch.new(300.0, INNER)))
      panel.add_child(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(a); v.add_child(b) }) # created b, a
      window.add_child(panel)
      window
    end
    order = co_order(app)
    renderer.cached_layers.not_nil!.should eq(order)
    CrymbleUI::Layer.composite_order(app.root.not_nil!).should eq(order)
    order.index!(app.find("early").not_nil!.layer.not_nil!).should be < order.index!(app.find("late").not_nil!.layer.not_nil!)
  end

  it "places every layer once, each after the layer it is painted into and before that layer's next sibling" do
    app, renderer, vm = co_grid(CoDepthTwoAdapter.new(true))
    order = co_order(app)
    order.uniq(&.object_id).size.should eq(order.size)
    index = order.each_with_index.to_h
    order.each do |layer|
      owner = layer.owner_widget || next
      next unless x = owner.painting_layer
      next unless x_owner = x.owner_widget
      next if owner.same?(x_owner)
      (index[x] < index[layer]).should be_true
      later = [x_owner.layer].compact
      x_owner.each_owned_layer { |l| later << l } if x_owner.responds_to?(:each_owned_layer)
      nxt = later.select { |l| l.z_index > x.z_index }.map { |l| index[l]? }.compact.min?
      (index[layer] < nxt).should be_true if nxt
    end
  end

  # The stale layer as it arises: on the CELL (a VirtualMatrix sets render_layer on the widget it hosts), the layer
  # owner inside it inherits it.
  it "counts, and places, a layer owner painted into a layer nobody owns when not strict" do
    app, renderer, vm = co_grid(CoNestedGridAdapter.new)
    sv = app.find("sv_3_0").not_nil!
    cell = sv.parent.not_nil!
    stale = CrymbleUI::Layer.new("stale", CrymbleUI::Rect.zero)
    strict = CrymbleUI::Layer.strict_nesting
    before = CrymbleUI::Layer.orphaned_nestings
    kept = cell.render_layer
    begin
      cell.render_layer = stale
      expect_raises(CrymbleUI::CompositeOrderError) { CrymbleUI::Layer.composite_order(app.root.not_nil!) }
      CrymbleUI::Layer.strict_nesting = false
      order = CrymbleUI::Layer.composite_order(app.root.not_nil!)
      (CrymbleUI::Layer.orphaned_nestings - before).should eq(1)
      layer = sv.layer.not_nil!
      order.count(layer).should eq(1)
      content = order.index!(vm.layer.not_nil!)
      order.index!(layer).should be > content # under where the cell's parent paints: the grid content
      order.index!(layer).should be < order.index!(vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!)
    ensure
      CrymbleUI::Layer.strict_nesting = strict
      cell.render_layer = kept
    end
  end

  # A cell's painting layer follows the sticky count: when the band goes, its former header cells paint into the
  # grid's content, and no frame meets a painting layer that left the tree (strict: it would raise).
  it "follows a sticky header switched off and on, the grid's cells re-homed each time" do
    adapter = CoTogglingStickyAdapter.new
    orphans = CrymbleUI::Layer.orphaned_nestings
    app, renderer, vm = co_grid(adapter)
    header_band = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!
    vm.active_cells[{0, 0}].painting_layer.should be(header_band) # instrument: painted into the band
    adapter.sticky = false
    adapter.invalidate_all!
    renderer.settle_rendering(app)
    vm.active_cells[{0, 0}]?.try(&.painting_layer).should be(vm.layer)
    adapter.sticky = true
    adapter.invalidate_all!
    renderer.settle_rendering(app)
    band = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!
    vm.active_cells[{0, 0}].painting_layer.should be(band)
    CrymbleUI::Layer.orphaned_nestings.should eq(orphans)
  end

  # The order is walked once per re-collect - O(widgets), each widget once, each layer emitted once - and nothing
  # re-collects while a grid scrolls.
  it "walks each widget once per re-collect and none while a grid scrolls" do
    app, renderer, vm = co_grid(CoPlainGridAdapter.new)
    root = app.root.not_nil!
    widgets = 0
    count = uninitialized Proc(CrymbleUI::Widget, Nil)
    count = ->(w : CrymbleUI::Widget) { widgets += 1; w.children.each { |c| count.call(c) }; nil }
    count.call(root)
    owned = 0
    tally = uninitialized Proc(CrymbleUI::Widget, Nil)
    tally = ->(w : CrymbleUI::Widget) { owned += 1 if w.layer; w.each_owned_layer { owned += 1 } if w.responds_to?(:each_owned_layer); w.children.each { |c| tally.call(c) }; nil }
    tally.call(root)
    CrymbleUI::Layer.composite_walk_visits = 0
    CrymbleUI::Layer.composite_emits = 0
    CrymbleUI::Layer.composite_order(root)
    CrymbleUI::Layer.composite_walk_visits.should eq(widgets)
    CrymbleUI::Layer.composite_emits.should eq(owned)
    before = CrymbleUI::LayerRenderer.frame_layer_recollect_count
    20.times { |i| vm.scroll_offset = CrymbleUI::Vec2.new(0.0, (i + 1) * 7.0); renderer.render_frame(app) }
    CrymbleUI::LayerRenderer.frame_layer_recollect_count.should eq(before)
  end

  # A hit test through containers that rank nothing and hold no boundary walks their children as they are - no
  # sort, no allocation, on every mouse move.
  it "hit-tests plain containers without allocating" do
    column = CrymbleUI::VStack.new(spacing: 0.0)
    300.times { column.add_child(CoSwatch.new(2.0, GREY)) }
    column.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 600.0)), CrymbleUI::Vec2.zero)
    point = CrymbleUI::Vec2.new(10.0, 3.0)
    column.hit_test(point) # warm
    before = GC.stats.total_bytes
    100.times { column.hit_test(point) }
    (GC.stats.total_bytes - before).should eq(0)
  end

  # Every hit test that walks children walks them in the one order: none iterates its children by itself.
  it "leaves no hit test walking its children outside children_in_hit_order" do
    offenders = [] of String
    src_glob("#{__DIR__}/../../src/**/*.cr").each do |path|
      lines = File.read_lines(path)
      lines.each_with_index do |line, i|
        next unless line =~ /^(\s*)def hit_test\b/
        indent = $1
        body = lines[(i + 1)..].take_while { |l| !(l.starts_with?("#{indent}end") && l.strip == "end") }
        body.each_with_index do |b, k|
          code = b.sub(/#.*/, "")
          offenders << "#{Path[path].basename}:#{i + k + 2}" if code =~ /children(?!_in_hit_order)\S*\.(reverse|each|select|find|map|reject|sort|to_a)/
        end
      end
    end
    offenders.should eq([] of String)
  end

  it "keeps the drag ghost above everything, a popup of any z included" do
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      chip = CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip").tap(&.add_child(CoSwatch.new(20.0, NAVY, 20.0)))
      window.add_child(CrymbleUI::VStack.new.tap(&.add_child(chip)))
      high = CrymbleUI::Popup.new(width: 200.0, height: 200.0, z_index: 20_000, id: "high")
      high.target_x, high.target_y = 100.0, 100.0
      high.add_child(CoSwatch.new(200.0, GREY))
      window.add_overlay(high)
      window
    end
    from = app.find("chip").not_nil!.viewport_bounds.center
    app.handle_mouse_down(from)
    app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
    app.handle_mouse_move(CrymbleUI::Vec2.new(150.0, 150.0))
    renderer.render_frame(app)
    ghost = app.drag_manager.ghost_layer.not_nil!
    renderer.cached_layers.not_nil!.last.should be(ghost)
  end

  # Two popups in the tree, equal z, overlapping, created in the opposite of their tree order: drawn and clicked
  # the same way - by tree order.
  it "orders equal-z popups in the tree by tree order, for drawing and for clicks alike" do
    popups = [] of CrymbleUI::Popup
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      later = CrymbleUI::Popup.new(width: 100.0, height: 80.0, id: "later") # created first, placed second
      earlier = CrymbleUI::Popup.new(width: 100.0, height: 80.0, id: "earlier")
      earlier.target_x, earlier.target_y = 100.0, 100.0
      later.target_x, later.target_y = 140.0, 120.0
      earlier.add_child(CoSwatch.new(80.0, INNER))
      later.add_child(CoSwatch.new(80.0, INNER2))
      window.add_child(earlier)
      window.add_child(later)
      popups = [earlier, later]
      window
    end
    overlap = CrymbleUI::Vec2.new(160.0, 150.0)
    co_pixel(renderer, overlap).should eq(INNER2)
    within?(app.root.not_nil!.hit_test(overlap), popups[1]).should be_true
  end

  # The rank a widget gets is asked of the owner of the layer it is painted into (paint) and of its parent (hit):
  # the same widget, for every layer owner of a rich scene.
  it "ranks every layer owner the same for painting and for hit testing" do
    app, renderer, vm = co_grid(CoDepthTwoAdapter.new(true))
    rank = ->(ranker : CrymbleUI::Widget?, w : CrymbleUI::Widget) { ranker && ranker.ranks_children? ? ranker.composite_rank(w) : 0 }
    checked = 0
    co_order(app).each do |layer|
      owner = layer.owner_widget || next
      paint_ranker = owner.painting_layer.try(&.owner_widget)
      rank.call(owner.parent, owner).should eq(rank.call(paint_ranker, owner))
      checked += 1
    end
    (checked > 10).should be_true # instrument: a rich scene
  end


  # A popup inside an opened popup is an overlay too: it composites right above its parent, not below it among the
  # popups of the tree.
  it "composites a popup nested in an opened popup above its parent" do
    popups = [] of CrymbleUI::Popup
    app, renderer = co_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      outer = CrymbleUI::Popup.new(width: 200.0, height: 150.0, id: "outer")
      outer.target_x, outer.target_y = 100.0, 100.0
      outer.add_child(CoSwatch.new(150.0, GREY))
      inner = CrymbleUI::Popup.new(width: 80.0, height: 60.0, id: "inner_pop")
      inner.target_x, inner.target_y = 150.0, 150.0
      inner.add_child(CoSwatch.new(60.0, INNER))
      outer.add_child(inner)
      window.add_overlay(outer)
      popups = [outer, inner]
      window
    end
    at = CrymbleUI::Vec2.new(170.0, 170.0)
    popups[0].viewport_bounds.contains_point(at).should be_true # instrument: over the outer popup
    co_pixel(renderer, at).should eq(INNER)
  end

end
