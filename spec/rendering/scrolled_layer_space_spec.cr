require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A LAYER INSIDE SCROLLED CONTENT is painted in its owner's content space (its buffer does not change when an ancestor
# scrolls - only the composite moves), placed where it is drawn, and clipped by every scroller around it. Read from the
# composited window pixels. Content is an L-marker: a 4px top band and a 4px left stripe over a body colour, so a
# shift by a scroll (>= 8 here) on either axis shows.

private BAND   = CrymbleUI::Color.new(220, 40, 40, 255)
private STRIPE = CrymbleUI::Color.new(40, 40, 220, 255)
private BODY   = CrymbleUI::Color.new(40, 200, 40, 255)
private FILL   = CrymbleUI::Color.new(90, 90, 90, 255)

# A block of one colour.
class SlsSwatch < CrymbleUI::Widget
  def initialize(@width : Float64, @height : Float64, @color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width, @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# The L-marker: body, a left stripe, a top band. `recolour` changes its body (a content change).
class SlsMarker < SlsSwatch
  @body = BODY

  def initialize(width : Float64, height : Float64, id : String? = nil)
    super(width, height, BODY, id)
  end

  def recolour(@body : CrymbleUI::Color) : Nil
    invalidate_primitive_cache
    mark_needs_render
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @body),
     CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, 4.0, bounds.height), STRIPE),
     CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, 4.0), BAND)].map(&.as(CrymbleUI::DrawPrimitive))
  end
end

class SlsApp < CrymbleUI::App
  def initialize(&@make : -> CrymbleUI::Widget)
    super()
  end

  def build : CrymbleUI::Widget
    @make.call
  end
end

private def sls_run(&make : -> CrymbleUI::Widget) : {SlsApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(700, 500)
  app = SlsApp.new(&make)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {app, renderer}
end

private def sls_pixel(renderer, x : Float64, y : Float64) : CrymbleUI::Color
  renderer.backend.get_pixel(x.to_i, y.to_i).not_nil!
end

# The marker's corner is at (x, y): the band along the top, the stripe down the left, the body inside.
private def marker_at(renderer, x : Float64, y : Float64) : Nil
  sls_pixel(renderer, x + 12.0, y + 2.0).should eq(BAND)
  sls_pixel(renderer, x + 12.0, y + 6.0).should eq(BODY)
  sls_pixel(renderer, x + 2.0, y + 12.0).should eq(STRIPE)
  sls_pixel(renderer, x + 6.0, y + 12.0).should eq(BODY)
end

# A panel holding a scroll view (both axes) over wide content with a small scroll view in it holding the marker,
# `above` below the content's top.
private def nested_views(above = 100.0, inner_height = 60.0, panel_x = 20.0) : {SlsApp, CrymbleUI::Testing::TestRenderer}
  sls_run do
    window = CrymbleUI::Window.new("W", 700, 500)
    panel = CrymbleUI::WindowPanel.new("P", panel_x, 40.0, 500.0, 420.0, id: "p")
    outer = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 300.0, id: "outer")
    inner = CrymbleUI::ScrollView.new(max_height: inner_height, id: "inner")
    inner.set_content(SlsMarker.new(300.0, 200.0, id: "marker"))
    outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
      v.add_child(SlsSwatch.new(900.0, above, FILL))
      v.add_child(CrymbleUI::HStack.new(spacing: 0.0).tap { |h| h.add_child(SlsSwatch.new(30.0, 60.0, FILL)); h.add_child(inner) })
      v.add_child(SlsSwatch.new(900.0, 600.0, FILL))
    end)
    panel.add_child(outer)
    window.add_child(panel)
    window
  end
end

private def scroll(app, renderer, id : String, x : Float64, y : Float64) : Nil
  app.find(id).not_nil!.as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(x, y))
  renderer.settle_rendering(app)
end

# A raise repaints every layer the panel holds (its nested layers are marked) - a full repaint, no scroll change.
private def raise_panel(app, renderer, id : String) : Nil
  CrymbleUI::LayerRenderer.rendered_layer_ids.clear
  app.find(id).not_nil!.as(CrymbleUI::WindowPanel).bring_to_front
  renderer.render_frame(app)
end


private HEAD   = CrymbleUI::Color.new(0, 0, 90, 255)
private SIDE   = CrymbleUI::Color.new(120, 0, 120, 255)
private CELL   = CrymbleUI::Color.new(230, 230, 230, 255)
private SPAN   = CrymbleUI::Color.new(250, 150, 0, 255)

# Fills the cell it is laid out in.
class SlsFill < CrymbleUI::Widget
  def initialize(@color : CrymbleUI::Color)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 40.0,
      constraints.max_height.finite? ? constraints.max_height : 10.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# 40 rows x 12 columns: row 0 a sticky header (header cells (0,1)-(0,2) merged, SPAN), column 0 a sticky column
# (SIDE); a cell holds a small scroll view with the marker when `nested`.
class SlsGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  property cell_color = CELL

  def initialize(@nested = false)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...40).to_a + [0], (1...12).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {0, 1}, {0, 2} } if row == 0 && (col == 1 || col == 2)
    { {row, col}, {row, col} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return SlsFill.new(SPAN) if row == 0 && (col == 1 || col == 2)
    return SlsFill.new(HEAD) if row == 0
    return SlsFill.new(SIDE) if col == 0
    return SlsFill.new(@cell_color) unless @nested && row == 3 && col == 2
    CrymbleUI::ScrollView.new(max_height: 20.0, id: "cell_sv").tap(&.set_content(SlsMarker.new(60.0, 100.0))) # narrower than the cell: no horizontal bar
  end
end

# Lays its one child out at a fixed size.
class SlsBox < CrymbleUI::Widget
  def initialize(@width : Float64, @height : Float64, child : CrymbleUI::Widget)
    super(id: nil)
    add_child(child)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width, @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    children.each(&.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(@width, @height)), CrymbleUI::Vec2.zero))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A layer box whose flush scrolls the view around it, once armed - moving the layers composited before it after
# they were rendered, which the render loop's order argument says no flush does.
class SlsScrollingFlush < CrymbleUI::LayerBox
  property arm : CrymbleUI::ScrollView? = nil

  def pre_render_flush
    super
    if view = @arm
      @arm = nil
      view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 20.0))
    end
  end
end

# A grid inside a scroll view (both axes) in a panel, fillers above and below it; its cursor overlay paints nothing
# (cursor_highlight_delta 0 - its layers are there, in their place), since the scenes read cells under its bands.
# `boxed`: the grid at a fixed 360x200 (it scrolls itself) instead of shrunk to its content.
private def grid_in_view(nested = false, boxed = false) : {SlsApp, CrymbleUI::Testing::TestRenderer}
  sls_run do
    window = CrymbleUI::Window.new("W", 700, 500)
    panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 560.0, 440.0, id: "p")
    outer = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 320.0, id: "outer")
    grid = CrymbleUI::VirtualMatrix.new(adapter: SlsGridAdapter.new(nested), id: "grid", cursor_highlight_delta: 0)
    grid.shrink_to_content = !boxed
    outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
      v.add_child(SlsSwatch.new(900.0, 100.0, FILL))
      v.add_child(CrymbleUI::HStack.new(spacing: 0.0).tap { |h| h.add_child(SlsSwatch.new(30.0, 200.0, FILL)); h.add_child(boxed ? SlsBox.new(360.0, 200.0, grid) : grid) })
      v.add_child(SlsSwatch.new(900.0, 600.0, FILL))
    end)
    panel.add_child(outer)
    window.add_child(panel)
    window
  end
end

private def grid_of(app) : CrymbleUI::VirtualMatrix
  app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)
end

# The colour a grid cell is drawn in, sampled a few pixels into it at its painted position (its absolute
# position minus the outer scroll, by hand).
private def cell_pixel(renderer, grid, row, col, outer_scroll : CrymbleUI::Vec2) : CrymbleUI::Color
  cell = grid.active_cells[{row, col}]
  abs = cell.absolute_bounds
  # a content cell is shifted by the grid's scroll; a sticky cell's bounds already hold it
  shift = cell.render_layer.same?(grid.layer) ? grid.scroll_offset : CrymbleUI::Vec2.zero
  sls_pixel(renderer, abs.x - shift.x - outer_scroll.x + 3.0, abs.y - shift.y - outer_scroll.y + 3.0)
end

describe "a layer inside scrolled content" do
  it "repaints its content where it is laid out after an ancestor scrolled" do
    app, renderer = nested_views
    inner = app.find("inner").not_nil!
    scroll(app, renderer, "outer", 6.0, 8.0)
    abs = inner.absolute_bounds
    corner = {abs.x - 6.0, abs.y - 8.0} # by hand: laid out, minus the outer scroll
    marker_at(renderer, *corner)          # control: before any repaint (the buffer from before the scroll)
    raise_panel(app, renderer, "p")
    CrymbleUI::LayerRenderer.rendered_layer_ids.should contain(inner.layer.not_nil!.id) # instrument: repainted
    marker_at(renderer, *corner)
  end

  # A layer renders at its owner's content position exactly as laid out - not recovered from its window position
  # (content - scroll + scroll loses the last bit for some values; at whole or quarter pixels and 0.1 scroll steps
  # it never moved a pixel, so this is asserted on the origin itself).
  it "keeps a scrolled layer's render origin exactly where its owner is laid out" do
    app, _ = nested_views(panel_x: 19.8572680088178)
    inner = app.find("inner").not_nil!.as(CrymbleUI::ScrollView)
    outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
    layer = inner.layer.not_nil!
    lossy = 0
    (1..400).each do |k|
      s = k * 0.6180339887498949
      outer.set_scroll_offset_for_test(CrymbleUI::Vec2.new(s, 0.0))
      x = inner.absolute_bounds.x
      lossy += 1 unless (x - s) + s == x
      layer.content_rect.x.should eq(x)
      layer.bounds.x.should eq(x - s)
    end
    (lossy > 0).should be_true # instrument: the sweep holds values the round trip does not recover
  end

  # Past the viewport cache's margin (100px): the scroll (150) exceeds margin + the inner viewport (40), so a
  # full repaint culls the inner layer's widgets against its buffer window - which must sit in content space.
  it "repaints what changed after an ancestor scrolled past the cache margin" do
    app, renderer = nested_views(above: 200.0, inner_height: 40.0)
    inner = app.find("inner").not_nil!
    scroll(app, renderer, "outer", 0.0, 150.0)
    abs = inner.absolute_bounds
    (abs.y - 150.0 > app.find("outer").not_nil!.viewport_bounds.y).should be_true # instrument: inside the view
    app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
    raise_panel(app, renderer, "p") # a full repaint: the one that culls (a selective one paints what changed)
    CrymbleUI::LayerRenderer.rendered_layer_ids.should contain(inner.layer.not_nil!.id) # instrument: repainted
    sls_pixel(renderer, abs.x + 20.0, abs.y - 150.0 + 20.0).should eq(CrymbleUI::Color.new(200, 200, 0, 255))
  end

  it "moves a scrolled view's layer without repainting it" do
    app, renderer = nested_views
    inner = app.find("inner").not_nil!
    CrymbleUI::LayerRenderer.rendered_layer_ids.clear
    scroll(app, renderer, "outer", 6.0, 8.0)
    CrymbleUI::LayerRenderer.rendered_layer_ids.should_not contain(inner.layer.not_nil!.id)
    abs = inner.absolute_bounds
    marker_at(renderer, abs.x - 6.0, abs.y - 8.0)
  end

  it "places a grid inside a scrolled view where it is drawn, through its own scrolls and a repaint" do
    app, renderer = grid_in_view
    grid = grid_of(app)
    scroll(app, renderer, "outer", 0.0, 60.0)
    at = CrymbleUI::Vec2.new(0.0, 60.0)
    cell_pixel(renderer, grid, 0, 4, at).should eq(HEAD)
    cell_pixel(renderer, grid, 0, 1, at).should eq(SPAN)
    cell_pixel(renderer, grid, 5, 0, at).should eq(SIDE)
    cell_pixel(renderer, grid, 5, 3, at).should eq(CELL)
    # the grid's own scroll, one row and one column, no settle (the sticky blit plans, the content blit)
    grid.scroll_offset = CrymbleUI::Vec2.new(grid.get_col_width(1) * 20.0 + 3.0, 26.0)
    renderer.render_frame(app)
    cell_pixel(renderer, grid, 0, 4, at).should eq(HEAD)
    cell_pixel(renderer, grid, 0, 1, at).should eq(SPAN)
    cell_pixel(renderer, grid, 6, 0, at).should eq(SIDE)
    cell_pixel(renderer, grid, 6, 3, at).should eq(CELL)
    raise_panel(app, renderer, "p")
    cell_pixel(renderer, grid, 0, 4, at).should eq(HEAD)
    cell_pixel(renderer, grid, 6, 3, at).should eq(CELL)
  end

  it "repaints a grid cell's scroll view where it is laid out after the grid scrolled" do
    app, renderer = grid_in_view(nested: true)
    grid = grid_of(app)
    grid.scroll_offset = CrymbleUI::Vec2.new(0.0, 8.0)
    renderer.settle_rendering(app)
    sv = app.find("cell_sv").not_nil!
    abs = sv.absolute_bounds
    raise_panel(app, renderer, "p")
    CrymbleUI::LayerRenderer.rendered_layer_ids.should contain(sv.layer.not_nil!.id) # instrument
    marker_at(renderer, abs.x, abs.y - 8.0)
  end

  it "clips a nested view to the scroll view around it, at the top and at the left" do
    app, renderer = nested_views
    inner = app.find("inner").not_nil!
    view = app.find("outer").not_nil!.viewport_bounds
    scroll(app, renderer, "outer", 40.0, 130.0) # inner: 30 left of the view's left edge by 10, top 30 above it
    abs = inner.absolute_bounds
    (abs.y - 130.0 < view.y && abs.x - 40.0 < view.x).should be_true # instrument: past both edges
    {BODY, BAND, STRIPE}.includes?(sls_pixel(renderer, view.x + 50.0, view.y - 3.0)).should be_false # nothing above
    {BODY, BAND, STRIPE}.includes?(sls_pixel(renderer, view.x - 3.0, view.y + 10.0)).should be_false # nothing left
    # inside the view: the marker's body where the band and the stripe were clipped away (the source moved too)
    sls_pixel(renderer, view.x + 2.0, view.y + 2.0).should eq(BODY)
    sls_pixel(renderer, view.x + 50.0, view.y + 5.0).should eq(BODY)
  end

  it "clips a nested view by the farthest scroller when the nearer one does not scroll" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
      middle = CrymbleUI::ScrollView.new(max_height: 1000.0, id: "middle") # taller than its content: never scrolls
      inner = CrymbleUI::ScrollView.new(max_height: 60.0, id: "inner").tap(&.set_content(SlsMarker.new(300.0, 200.0)))
      middle.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(inner); v.add_child(SlsSwatch.new(400.0, 200.0, FILL)) })
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(400.0, 100.0, FILL)); v.add_child(middle); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    view = app.find("outer").not_nil!.viewport_bounds
    scroll(app, renderer, "outer", 0.0, 130.0)
    {BODY, BAND, STRIPE}.includes?(sls_pixel(renderer, view.x + 50.0, view.y - 3.0)).should be_false
    sls_pixel(renderer, view.x + 50.0, view.y + 5.0).should eq(BODY)
  end

  it "clips a grid inside a scrolled view to that view" do
    app, renderer = grid_in_view
    view = app.find("outer").not_nil!.viewport_bounds
    scroll(app, renderer, "outer", 0.0, 150.0) # the grid's top 50 above the view
    x = grid_of(app).absolute_bounds.x + 80.0
    {HEAD, SPAN, CELL, SIDE}.includes?(sls_pixel(renderer, x, view.y - 3.0)).should be_false
    {HEAD, SPAN, CELL, SIDE}.includes?(sls_pixel(renderer, x, view.y + 3.0)).should be_true
  end

  # A LayerBox in a panel's content (not at window level): its layer where it is laid out, clicks on it reach it,
  # and the panel clips it at its left edge.
  it "places a LayerBox in a panel where it is laid out, clipped by the panel" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 60.0, 40.0, 400.0, 300.0, id: "p")
      box = CrymbleUI::LayerBox.new(-30.0, 40.0, 100.0, 50.0, z_index: 5, id: "box")
      box.add_child(SlsSwatch.new(100.0, 50.0, SPAN, id: "box_fill"))
      panel.add_child(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(380.0, 20.0, FILL)); v.add_child(box) })
      window.add_child(panel)
      window
    end
    box = app.find("box").not_nil!
    abs = box.absolute_bounds
    p = app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
    (abs.x < p.x).should be_true # instrument: it reaches past the panel's left edge
    sls_pixel(renderer, p.x + 10.0, abs.y + 10.0).should eq(SPAN)
    sls_pixel(renderer, p.x - 5.0, abs.y + 10.0).should_not eq(SPAN)
    app.root.not_nil!.hit_test(CrymbleUI::Vec2.new(p.x + 10.0, abs.y + 10.0)).try(&.id).should eq("box_fill")
  end


  # A popup placed inside scrolled content (a tree popup, not a Window overlay) places itself in window space: at
  # its target, clamped into where its parent is drawn, never clipped by the scroller, clickable where drawn.
  it "places a popup inside a scrolled view at its target, unclipped, clickable - and keeps it there on a scroll" do
    popups = [] of CrymbleUI::Popup
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(max_height: 200.0, id: "outer")
      anchor = CrymbleUI::VStack.new(spacing: 0.0, id: "anchor")
      anchor.add_child(SlsSwatch.new(400.0, 300.0, FILL))
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(400.0, 300.0, FILL)); v.add_child(anchor); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
    scroll(app, renderer, "outer", 0.0, 250.0) # the anchor drawn 50 below the view's top
    anchor = app.find("anchor").not_nil!
    drawn = anchor.viewport_bounds
    view = outer.viewport_bounds
    popup = CrymbleUI::Popup.new(width: 120.0, height: 200.0, id: "pop") # taller than the view below its target
    popup.add_child(SlsSwatch.new(120.0, 200.0, SPAN))
    popup.target_x, popup.target_y = drawn.x + 20.0, drawn.y + 10.0
    anchor.add_child(popup)
    renderer.settle_rendering(app)
    at = CrymbleUI::Vec2.new(drawn.x + 30.0, drawn.y + 20.0)
    sls_pixel(renderer, at.x, at.y).should eq(SPAN) # at its target (not snapped to the anchor's unscrolled top)
    below = CrymbleUI::Vec2.new(drawn.x + 30.0, view.bottom + 5.0)
    (drawn.y + 10.0 + 200.0 > view.bottom).should be_true # instrument: it reaches past the view
    sls_pixel(renderer, below.x, below.y).should eq(SPAN) # not clipped by the scroller
    hit = app.root.not_nil!.hit_test(below).not_nil!
    (hit.same?(popup) || hit.parent.same?(popup)).should be_true # clickable where it is drawn
    # open, then the view scrolled (no layout): the popup stays where it opened
    outer.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -2.0), outer.absolute_bounds.center)
    renderer.render_frame(app)
    sls_pixel(renderer, at.x, at.y).should eq(SPAN)
  end

  it "places a popup without a target inside a scrolled view where it is laid out, as painted" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
      anchor = CrymbleUI::VStack.new(spacing: 0.0, id: "anchor")
      anchor.add_child(SlsSwatch.new(300.0, 150.0, FILL))
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(400.0, 300.0, FILL)); v.add_child(anchor); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    scroll(app, renderer, "outer", 0.0, 250.0)
    anchor = app.find("anchor").not_nil!
    popup = CrymbleUI::Popup.new(width: 80.0, height: 60.0, id: "pop")
    popup.add_child(SlsSwatch.new(80.0, 60.0, SPAN))
    anchor.add_child(popup)
    renderer.settle_rendering(app)
    at = popup.absolute_bounds # an overlay's own space is the window: where it is drawn
    laid = anchor.viewport_bounds.position + CrymbleUI::Vec2.new(0.0, 150.0) # by hand: its stack slot, as painted
    (at.x - laid.x).abs.should be < 0.01
    (at.y - laid.y).abs.should be < 0.01
    sls_pixel(renderer, at.x + 5.0, at.y + 5.0).should eq(SPAN)
  end

  it "clamps a popup inside a scrolled view into where its parent is drawn" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
      anchor = CrymbleUI::VStack.new(spacing: 0.0, id: "anchor")
      anchor.add_child(SlsSwatch.new(300.0, 150.0, FILL))
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(400.0, 300.0, FILL)); v.add_child(anchor); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    scroll(app, renderer, "outer", 0.0, 250.0)
    anchor = app.find("anchor").not_nil!
    drawn = anchor.viewport_bounds
    popup = CrymbleUI::Popup.new(width: 80.0, height: 60.0, id: "pop")
    popup.add_child(SlsSwatch.new(80.0, 60.0, SPAN))
    anchor.add_child(popup) # (the anchor stacks it: its drawn rect is taken once it holds the popup)
    renderer.settle_rendering(app)
    drawn = anchor.viewport_bounds
    popup.target_x, popup.target_y = drawn.right - 20.0, drawn.bottom - 10.0 # spills past the right and bottom
    popup.mark_needs_layout
    renderer.settle_rendering(app)
    sls_pixel(renderer, drawn.right - 5.0, drawn.bottom - 5.0).should eq(SPAN) # pulled in at the drawn corner
    sls_pixel(renderer, drawn.right - 75.0, drawn.bottom - 55.0).should eq(SPAN)
    # above and left of it, the scroll (250) larger than that offset: pulled in at the drawn top-left, by hand
    popup.target_x, popup.target_y = drawn.x - 30.0, drawn.y - 40.0
    popup.mark_needs_layout
    renderer.settle_rendering(app)
    sls_pixel(renderer, drawn.x + 5.0, drawn.y + 5.0).should eq(SPAN)
    sls_pixel(renderer, drawn.x + 75.0, drawn.y + 55.0).should eq(SPAN)
    sls_pixel(renderer, drawn.x + 85.0, drawn.y + 65.0).should eq(FILL) # control: its size, no more
    # the view scrolled 30 more: the popup stays where it opened; a layout clamps it again, against where its
    # parent is drawn now
    scroll(app, renderer, "outer", 0.0, 280.0)
    now = anchor.viewport_bounds
    (now.y - (drawn.y - 30.0)).abs.should be < 0.01 # instrument: drawn 30 higher
    sls_pixel(renderer, drawn.x + 5.0, drawn.y + 5.0).should eq(SPAN)
    popup.mark_needs_layout
    renderer.settle_rendering(app)
    sls_pixel(renderer, now.x + 5.0, now.y + 5.0).should eq(SPAN)
    sls_pixel(renderer, now.x + 5.0, now.y + 65.0).should eq(FILL)
  end

  # Far down the content (400), so it comes back with the outer scrolled well past the cache margin.
  it "shows a nested view's new content in the first frame it scrolls back into view" do
    app, renderer = nested_views(above: 400.0)
    outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
    inner = app.find("inner").not_nil!
    view = outer.viewport_bounds
    until inner.absolute_bounds.bottom - outer.scroll_offset.y < view.y # wheel it fully out above (no layout)
      outer.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), outer.absolute_bounds.center)
      renderer.render_frame(app)
    end
    CrymbleUI::LayerRenderer.rendered_layer_ids.clear
    app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
    renderer.render_frame(app)
    CrymbleUI::LayerRenderer.rendered_layer_ids.should_not contain(inner.layer.not_nil!.id) # instrument: skipped out of view
    until inner.absolute_bounds.bottom - outer.scroll_offset.y > view.y + 30.0 # and back: the first frame it shows
      outer.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), outer.absolute_bounds.center)
      renderer.render_frame(app)
    end
    v = inner.visible_bounds.not_nil!
    sls_pixel(renderer, v.x + 20.0, v.bottom - 22.0).should eq(CrymbleUI::Color.new(200, 200, 0, 255)) # above its horizontal bar
  end

  it "repaints a nested view that changes while partly clipped" do
    app, renderer = nested_views
    view = app.find("outer").not_nil!.viewport_bounds
    scroll(app, renderer, "outer", 0.0, 130.0) # inner half above the view
    app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
    renderer.render_frame(app)
    sls_pixel(renderer, view.x + 60.0, view.y + 10.0).should eq(CrymbleUI::Color.new(200, 200, 0, 255))
  end

  it "keeps a nested view's scrollbar: a scroll view does not clip its own chrome" do
    app, renderer = nested_views
    v = app.find("inner").not_nil!.viewport_bounds
    bar = sls_pixel(renderer, v.right - 8.0, v.y + 30.0)
    beside = sls_pixel(renderer, v.right + 5.0, v.y + 30.0) # control: the outer content next to the view
    sls_pixel(renderer, v.right - 30.0, v.y + 30.0).should eq(BODY) # control: the content left of the bar
    bar.should_not eq(BODY)
    bar.should_not eq(beside)
  end

  it "keeps a grid's scrollbars: the matrix does not clip its own chrome" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 400.0, 300.0, id: "p")
      grid = CrymbleUI::VirtualMatrix.new(adapter: SlsGridAdapter.new, id: "grid", cursor_highlight_delta: 0)
      panel.add_child(grid)
      window.add_child(panel)
      window
    end
    sv = grid_of(app).content_scroll_view.not_nil!
    bar = sv.scrollbar_layer.not_nil!.bounds
    theme = CrymbleUI::Theme.current
    right = sls_pixel(renderer, bar.right - 4.0, bar.y + bar.height / 2.0)
    bottom = sls_pixel(renderer, bar.x + bar.width / 2.0, bar.bottom - 4.0)
    {theme.scrollbar_track, theme.scrollbar_thumb}.includes?(right).should be_true
    {theme.scrollbar_track, theme.scrollbar_thumb}.includes?(bottom).should be_true
  end


  # A column and a row of a grid inside a scrolled view resized (the content blit shift, both axes): the cells past
  # the boundary where they are drawn.
  it "shifts a scrolled view's grid's cells right with a resize" do
    app, renderer = grid_in_view
    grid = grid_of(app)
    scroll(app, renderer, "outer", 6.0, 8.0)
    at = CrymbleUI::Vec2.new(6.0, 8.0)
    abs = grid.absolute_bounds
    col_border = abs.x + grid.ruler_col_width_pixels + (0..2).sum { |c| 3.0 + grid.get_col_width(c) * 20.0 }
    press = CrymbleUI::Vec2.new(col_border, abs.y + grid.ruler_row_height_pixels / 2.0)
    grid.on_mouse_down(press)
    grid.resize_axis.to_s.should eq("Col") # instrument
    grid.on_mouse_move(press + CrymbleUI::Vec2.new(24.0, 0.0))
    renderer.render_frame(app)
    grid.on_mouse_up(press + CrymbleUI::Vec2.new(24.0, 0.0))
    renderer.render_frame(app)
    cell_pixel(renderer, grid, 5, 3, at).should eq(CELL)
    row_border = abs.y + grid.ruler_row_height_pixels + (0..3).sum { |r| 3.0 + grid.get_row_height(r) * 20.0 }
    press = CrymbleUI::Vec2.new(abs.x + grid.ruler_col_width_pixels / 2.0, row_border)
    grid.on_mouse_down(press)
    grid.resize_axis.to_s.should eq("Row") # instrument
    grid.on_mouse_move(press + CrymbleUI::Vec2.new(0.0, 12.0))
    renderer.render_frame(app)
    grid.on_mouse_up(press + CrymbleUI::Vec2.new(0.0, 12.0))
    renderer.render_frame(app)
    cell_pixel(renderer, grid, 6, 3, at).should eq(CELL)
  end

  # The inner view scrolled past its cache margin on both axes (the buffer re-centre), the outer scrolled first.
  it "re-centres a nested view's buffer in place after an ancestor scrolled" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
      inner = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 80.0, max_width: 200.0, id: "inner")
      inner.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
        20.times do |r|
          v.add_child(CrymbleUI::HStack.new(spacing: 0.0).tap do |h|
            20.times { |c| h.add_child(SlsSwatch.new(30.0, 30.0, (r + c).even? ? BODY : STRIPE, id: "t_#{r}_#{c}")) }
          end)
        end
      end)
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(400.0, 100.0, FILL)); v.add_child(inner); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    inner = app.find("inner").not_nil!.as(CrymbleUI::ScrollView)
    s = 25.0 # most of a tile: a slot key taken in window space moves a tile across the copied block's edge
    scroll(app, renderer, "outer", 0.0, s)
    30.times do # past the 100px margin on both axes, no layout
      inner.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), inner.absolute_bounds.center)
      inner.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), inner.absolute_bounds.center, shift: true)
      renderer.render_frame(app)
      break if inner.scroll_offset.x >= 150.0 && inner.scroll_offset.y >= 150.0
    end
    (inner.scroll_offset.x >= 150.0 && inner.scroll_offset.y >= 150.0).should be_true # instrument
    # and back up 90 (re-centring again on the way): the edges of the copied blocks come into view
    back = inner.scroll_offset
    until back.y - inner.scroll_offset.y >= 90.0
      inner.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), inner.absolute_bounds.center)
      renderer.render_frame(app)
    end
    view = inner.viewport_bounds
    checked = 0
    20.times do |r|
      20.times do |c|
        t = app.find("t_#{r}_#{c}").not_nil!.absolute_bounds
        x = t.x - inner.scroll_offset.x
        y = t.y - inner.scroll_offset.y - s
        next unless x >= view.x && y >= view.y && x + 30.0 <= view.right - 16.0 && y + 30.0 <= view.bottom - 16.0 # clear of the bars
        colour = (r + c).even? ? BODY : STRIPE
        {% for d in [{2, 2}, {27, 2}, {2, 27}, {27, 27}, {15, 15}] %}
          sls_pixel(renderer, x + {{d[0]}}, y + {{d[1]}}).should eq(colour)
        {% end %}
        checked += 1
      end
    end
    (checked >= 2).should be_true # instrument: whole tiles in view
  end

  # An opaque layer whose bounds reach where its clip cut them away (a grid's sticky band scrolled above the view)
  # does not occlude what lies there: a small view above the scroll view keeps repainting.
  it "does not count as covered what an opaque layer's clip cut away" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 560.0, 440.0, id: "p")
      small = CrymbleUI::ScrollView.new(max_height: 20.0, max_width: 150.0, id: "small").tap(&.set_content(SlsMarker.new(120.0, 40.0, id: "marker")))
      outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
      grid = CrymbleUI::VirtualMatrix.new(adapter: SlsGridAdapter.new, id: "grid", cursor_highlight_delta: 0)
      grid.shrink_to_content = true
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(grid); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
      row = CrymbleUI::HStack.new(spacing: 0.0).tap { |h| h.add_child(SlsSwatch.new(150.0, 20.0, FILL)); h.add_child(small) } # within the band's x range
      panel.add_child(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(row); v.add_child(SlsSwatch.new(400.0, 10.0, FILL)); v.add_child(outer) })
      window.add_child(panel)
      window
    end
    small = app.find("small").not_nil!
    band = grid_of(app).content_scroll_view.not_nil!.sticky_row_layer.not_nil!
    s = band.content_rect.y - small.viewport_bounds.y + 5.0 # the band's top 5px above the small view (past the occluder inset)
    scroll(app, renderer, "outer", 0.0, s)
    (band.background_color.a == 255_u8).should be_true                            # instrument: opaque
    band.bounds.contains?(small.layer.not_nil!.bounds).should be_true           # instrument: its bounds cover it
    app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
    renderer.render_frame(app)
    v = small.viewport_bounds
    sls_pixel(renderer, v.x + 20.0, v.y + 10.0).should eq(CrymbleUI::Color.new(200, 200, 0, 255))
  end

  it "shows a grid's changed cells in the first frame it scrolls back into view" do
    app, renderer = grid_in_view
    outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
    grid = grid_of(app)
    view = outer.viewport_bounds
    until grid.absolute_bounds.bottom - outer.scroll_offset.y < view.y
      outer.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), outer.absolute_bounds.center)
      renderer.render_frame(app)
    end
    adapter = grid.adapter.as(SlsGridAdapter)
    adapter.cell_color = CrymbleUI::Color.new(200, 200, 0, 255)
    adapter.invalidate_all!
    renderer.render_frame(app)
    until grid.absolute_bounds.y - outer.scroll_offset.y >= view.y
      outer.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), outer.absolute_bounds.center)
      renderer.render_frame(app)
    end
    cell_pixel(renderer, grid, 5, 3, outer.scroll_offset).should eq(CrymbleUI::Color.new(200, 200, 0, 255))
  end

  # A panel's live resize runs its layout in the frame's flush: a nested view it brings into view is painted in
  # that very frame, with what changed while it was hidden.
  it "paints a nested view a panel resize reveals, in that frame" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 400.0, 200.0, id: "p")
      outer = CrymbleUI::ScrollView.new(id: "outer") # fills the panel: the panel's size is its viewport
      inner = CrymbleUI::ScrollView.new(max_height: 40.0, id: "inner").tap(&.set_content(SlsMarker.new(200.0, 80.0, id: "marker")))
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlsSwatch.new(380.0, 250.0, FILL)); v.add_child(inner); v.add_child(SlsSwatch.new(380.0, 300.0, FILL)) })
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    p = app.find("p").not_nil!.as(CrymbleUI::WindowPanel)
    inner = app.find("inner").not_nil!
    view = app.find("outer").not_nil!.viewport_bounds
    (inner.viewport_bounds.y > view.bottom).should be_true # instrument: below the view, clipped away
    app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
    renderer.render_frame(app)
    edge = CrymbleUI::Vec2.new(p.x + 100.0, p.y + p.height - 2.0)
    p.on_mouse_down(edge)
    p.on_mouse_move(edge + CrymbleUI::Vec2.new(0.0, 150.0))
    renderer.render_frame(app)
    v = inner.viewport_bounds
    (v.bottom < app.find("outer").not_nil!.viewport_bounds.bottom).should be_true # instrument: revealed by that frame's layout
    sls_pixel(renderer, v.x + 20.0, v.y + 20.0).should eq(CrymbleUI::Color.new(200, 200, 0, 255))
  end

  # A grid inside a scrolled view dragged by its own scrollbar (the deferred flush): where it composites and where
  # its cells are drawn agree in that very frame.
  it "keeps a scrolled view's grid in place through a scrollbar drag, in the drag's frame" do
    app, renderer = grid_in_view(boxed: true)
    grid = grid_of(app)
    scroll(app, renderer, "outer", 0.0, 60.0)
    sv = grid.content_scroll_view.not_nil!
    abs = sv.absolute_bounds
    thumb = CrymbleUI::Vec2.new(abs.right - 8.0, abs.y + CrymbleUI::ScrollView::ARROW_SIZE + 4.0)
    sv.on_mouse_down(thumb)
    sv.on_mouse_move(thumb + CrymbleUI::Vec2.new(0.0, 20.0))
    renderer.render_frame(app)
    (grid.scroll_offset.y > 0).should be_true # instrument: the drag scrolled the grid
    # the first content row painted wholly below the sticky band
    band = sv.sticky_row_layer.not_nil!.bounds
    row = grid.active_cells.keys.select { |(r, c)| c == 1 && r > 0 }.map(&.[0]).sort!.find! do |r|
      grid.active_cells[{r, 1}].absolute_bounds.y - grid.scroll_offset.y - 60.0 > band.bottom
    end
    cell_pixel(renderer, grid, row, 1, CrymbleUI::Vec2.new(0.0, 60.0)).should eq(CELL)
  end

  # The walks a frame takes (parent-chain steps: Widget.absolute_bounds_count) over four nested views in a scrolled
  # view, against HEAD before content-space layers, counted the same way (per step in every geometry walk) -
  # measured 909 steady, 2742 for an outer scroll, 3533 for a raise (repainting everything). Every layer's window
  # position now takes two walks (content rect, enclosing scroll) and the composite clip one per phase; a size is
  # read without the scroll walk (Layer#size).
  {% unless flag?(:cache_validation) %} # the validator's second render per frame inflates every counter
  it "walks the parent chain no more than before, steady, scrolled and raised" do
    app, renderer = sls_run do
      window = CrymbleUI::Window.new("W", 700, 500)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
      outer = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 300.0, id: "outer")
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
        v.add_child(SlsSwatch.new(900.0, 100.0, FILL))
        4.times do
          inner = CrymbleUI::ScrollView.new(max_height: 60.0)
          inner.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |iv| 10.times { iv.add_child(SlsSwatch.new(300.0, 20.0, FILL)) } })
          v.add_child(CrymbleUI::HStack.new(spacing: 0.0).tap { |h| h.add_child(SlsSwatch.new(30.0, 60.0, FILL)); h.add_child(inner) })
        end
        v.add_child(SlsSwatch.new(900.0, 600.0, FILL))
      end)
      panel.add_child(outer)
      window.add_child(panel)
      window
    end
    steps = ->(change : -> Nil) do
      change.call
      CrymbleUI::Widget.reset_absolute_bounds_count
      renderer.render_frame(app)
      CrymbleUI::Widget.absolute_bounds_count
    end
    steps.call(->{ nil })
    (steps.call(->{ app.find("outer").not_nil!.as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(6.0, 30.0)) }) <= 2742).should be_true
    (steps.call(->{ nil }) <= 909).should be_true
    (steps.call(->{ app.find("p").not_nil!.as(CrymbleUI::WindowPanel).bring_to_front }) <= 3533).should be_true
  end
  {% end %}

  {% if flag?(:verify_bounds) %}
    it "raises when a flush moves a layer after its turn in the render loop" do
      app, renderer = sls_run do
        window = CrymbleUI::Window.new("W", 700, 500)
        panel = CrymbleUI::WindowPanel.new("P", 20.0, 40.0, 500.0, 420.0, id: "p")
        outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
        inner = CrymbleUI::ScrollView.new(max_height: 40.0, id: "inner").tap(&.set_content(SlsMarker.new(200.0, 80.0, id: "marker")))
        box = SlsScrollingFlush.new(0.0, 0.0, 100.0, 40.0, id: "box").tap(&.add_child(SlsSwatch.new(100.0, 40.0, FILL)))
        outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(inner); v.add_child(box); v.add_child(SlsSwatch.new(400.0, 600.0, FILL)) })
        panel.add_child(outer)
        window.add_child(panel)
        window
      end
      box = app.find("box").not_nil!.as(SlsScrollingFlush)
      renderer.render_frame(app) # control: unarmed, the same repaint composites
      box.arm = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
      app.find("marker").not_nil!.as(SlsMarker).recolour(CrymbleUI::Color.new(200, 200, 0, 255))
      box.mark_needs_render
      expect_raises(CrymbleUI::LayerSpaceError, /inner/) { renderer.render_frame(app) }
    end

    it "raises for a panel under a scroller: its rect is window space" do
      app, renderer = sls_run do
        window = CrymbleUI::Window.new("W", 700, 500)
        outer = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer")
        outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
          v.add_child(CrymbleUI::WindowPanel.new("Q", 20.0, 40.0, 200.0, 100.0, id: "q"))
          v.add_child(SlsSwatch.new(400.0, 600.0, FILL))
        end)
        window.add_child(outer)
        window
      end
      expect_raises(CrymbleUI::LayerSpaceError, /Q/) { scroll(app, renderer, "outer", 0.0, 10.0) }
    end
  {% end %}
end
