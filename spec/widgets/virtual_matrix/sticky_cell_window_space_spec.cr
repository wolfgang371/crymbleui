require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/driver"

# A STICKY CELL IS WHERE IT IS PAINTED. The matrix moves its sticky cells itself (sticky_reposition writes their
# bounds screen-relative on every scroll), so anything placed from one - its viewport_bounds, a drag ghost, the drag
# decal, the change glow, the cursor band, a dropdown, a delivered click - must take its bounds as they are, and
# subtract the scroll only for the content cells, which keep their laid-out bounds while their layer composites
# shifted.
#
# Read from the composited frame: every cell a solid, unique colour, found by scanning the WHOLE frame for its
# first pixel (never starting at the predicted spot). A cell counts only when its expected rect lies wholly inside
# the region its layer shows (a content cell: the content viewport minus the sticky bands over it), and each layer
# must yield a minimum of counted cells, so the check cannot pass on an empty set.

private def scw_colour(r : Int32, c : Int32) : CrymbleUI::Color
  CrymbleUI::Color.new((30 + r * 7).to_u8, (40 + c * 13).to_u8, 170_u8, 255_u8)
end

# Fills the cell it is laid out in.
class ScwFill < CrymbleUI::Widget
  property measure_height : Float64? = nil

  def initialize(@color : CrymbleUI::Color)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 40.0,
      @measure_height || (constraints.max_height.finite? ? constraints.max_height : 10.0))
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# 30 rows x 12 columns: rows 0-1 and column 0 sticky, the header (0,2)-(0,3) merged; fractional column widths (whole
# pixels only after truncation, so a sum of float widths drifts from where cells are placed).
class ScwAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  # cells the change glow washes, at a frozen alpha
  property glowing = [] of {Int32, Int32}
  # a widget to put in a cell instead of its fill
  property special = {} of {Int32, Int32} => Proc(CrymbleUI::Widget)
  # the drag box of a cell, when larger than its box
  property drag_boxes = {} of {Int32, Int32} => CrymbleUI::VirtualMatrix::Region
  getter moves = [] of { {Int32, Int32}, {Int32, Int32} }

  def initialize(@sticky_rows = 2, @sticky_cols = 1, @corner_span = false)
  end

  def has_active_highlights? : Bool
    !@glowing.empty?
  end

  def cell_highlight_alpha(row : Int32, col : Int32) : UInt8
    @glowing.includes?({row, col}) ? 200_u8 : 0_u8
  end

  def cell_get_drag_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @drag_boxes[{row, col}]? || cell_get_bounding_box(row, col)
  end

  def cell_move(from_row : Int32, from_col : Int32, to_row : Int32, to_col : Int32) : Tuple(Int32, Int32)
    @moves << { {from_row, from_col}, {to_row, to_col} }
    {to_row, to_col}
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(@sticky_rows...30).to_a + (0...@sticky_rows).to_a.reverse, (@sticky_cols...12).to_a + (0...@sticky_cols).to_a.reverse}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    {Array.new(30, 1.0), (0...12).map { |c| c.even? ? 4.37 : 5.61 }}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {0, 0}, {0, 1} } if @corner_span && row == 0 && col <= 1
    return { {0, 2}, {0, 3} } if row == 0 && (col == 2 || col == 3)
    { {row, col}, {row, col} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    @special[{row, col}]?.try(&.call) || ScwFill.new(scw_colour(row, col))
  end
end

class ScwApp < CrymbleUI::App
  def initialize(&@make : -> CrymbleUI::Widget)
    super()
  end

  def build : CrymbleUI::Widget
    @make.call
  end
end


# The grid in a panel (offset in the window), scrolled by `scroll`; `in_view`: inside a scroll view (scrolled
# (0, 40) as well), below a filler. Its cursor overlay paints nothing unless a case asks for the theme's delta (the
# frame scans read every cell, under the cursor's bands too); its layers are there either way.
private def scw_grid(scroll : CrymbleUI::Vec2, adapter = ScwAdapter.new, in_view = false,
                     cursor_highlight_delta = 0) : {ScwApp, CrymbleUI::Testing::TestRenderer, CrymbleUI::VirtualMatrix}
  renderer = CrymbleUI::Testing::TestRenderer.new(700, 480)
  app = ScwApp.new do
    window = CrymbleUI::Window.new("W", 700, 480)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 40.0, 560.0, 400.0, id: "p")
    vm = CrymbleUI::VirtualMatrix.new(adapter, id: "grid", cursor_highlight_delta: cursor_highlight_delta)
    if in_view
      outer = CrymbleUI::ScrollView.new(max_height: 330.0, id: "outer")
      outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
        v.add_child(ScwFill.new(CrymbleUI::Color.new(90, 90, 90, 255)).tap { |f| f.measure_height = 60.0 })
        v.add_child(ScwBox.new(520.0, 300.0, vm))
        v.add_child(ScwFill.new(CrymbleUI::Color.new(90, 90, 90, 255)).tap { |f| f.measure_height = 400.0 })
      end)
      panel.add_child(outer)
    else
      panel.add_child(vm)
    end
    window.add_child(panel)
    window
  end
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  vm = app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)
  if in_view
    app.find("outer").not_nil!.as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 40.0))
    renderer.settle_rendering(app)
  end
  vm.scroll_offset = scroll
  renderer.settle_rendering(app)
  {app, renderer, vm}
end

# Lays its one child out at a fixed size.
class ScwBox < CrymbleUI::Widget
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

# A region's painted rect in the WINDOW (the matrix's space moved to where the matrix is painted).
private def scw_window(vm : CrymbleUI::VirtualMatrix, rect : CrymbleUI::Rect) : CrymbleUI::Rect
  at = vm.viewport_bounds.position
  CrymbleUI::Rect.new(at.x + rect.x, at.y + rect.y, rect.width, rect.height)
end

private def scw_snapshot(renderer) : Array(CrymbleUI::Color)
  renderer.backend.get_pixels(0, 0, renderer.backend.width, renderer.backend.height)
end

# The bounding box of the pixels that differ between two frames - one mark switched on between them.
private def scw_diff_box(renderer, before : Array(CrymbleUI::Color), after : Array(CrymbleUI::Color)) : CrymbleUI::Rect?
  w = renderer.backend.width
  xs = [] of Int32
  ys = [] of Int32
  before.each_with_index do |colour, i|
    next if colour == after[i]
    xs << i % w
    ys << i // w
  end
  return nil if xs.empty?
  CrymbleUI::Rect.new(xs.min.to_f64, ys.min.to_f64, (xs.max - xs.min + 1).to_f64, (ys.max - ys.min + 1).to_f64)
end

# The whole-pixel rect a mark over `rect` covers.
private def scw_pixels_of(rect : CrymbleUI::Rect) : CrymbleUI::Rect
  x0 = rect.x.floor
  y0 = rect.y.floor
  CrymbleUI::Rect.new(x0, y0, rect.right.ceil - x0, rect.bottom.ceil - y0)
end

# The first pixel of every colour in the frame, scanned row by row from the top-left.
private def scw_first_pixels(renderer) : Hash(CrymbleUI::Color, {Int32, Int32})
  seen = Hash(CrymbleUI::Color, {Int32, Int32}).new
  renderer.backend.height.times do |y|
    renderer.backend.width.times do |x|
      colour = renderer.backend.get_pixel(x, y).not_nil!
      seen[colour] = {x, y} unless seen.has_key?(colour)
    end
  end
  seen
end

# Which layer a cell is painted into, and the window region that layer shows it in: a sticky band or the corner as
# its layer's rect, the content cells' region as the content layer minus the bands over it.
private def scw_region(vm : CrymbleUI::VirtualMatrix, cell : CrymbleUI::Widget) : {String, CrymbleUI::Rect}
  sv = vm.content_scroll_view.not_nil!
  corner = sv.sticky_corner_layer.not_nil!.bounds
  case cell.render_layer
  when sv.sticky_row_layer    then {"row", sv.sticky_row_layer.not_nil!.bounds}
  when sv.sticky_col_layer    then {"col", sv.sticky_col_layer.not_nil!.bounds}
  when sv.sticky_corner_layer then {"corner", corner}
  else
    content = vm.layer.not_nil!.bounds
    {"content", CrymbleUI::Rect.new(corner.right, corner.bottom, content.right - corner.right, content.bottom - corner.bottom)}
  end
end

private def scw_inside?(outer : CrymbleUI::Rect, inner : CrymbleUI::Rect) : Bool
  inner.x >= outer.x && inner.y >= outer.y && inner.right <= outer.right && inner.bottom <= outer.bottom
end

# Every cell whose painted rect lies wholly in its layer's region: {layer, row, col, the cell, where it is painted (by
# hand: a sticky cell at its absolute bounds, a content cell at them minus the whole scroll the grid paints with)}.
private def scw_counted(vm : CrymbleUI::VirtualMatrix) : Array({String, Int32, Int32, CrymbleUI::Widget, CrymbleUI::Vec2})
  scroll = vm.scroll_offset
  whole = CrymbleUI::Vec2.new(scroll.x.floor, scroll.y.floor)
  outer = vm.enclosing_scroll # a scroller around the grid moves all of it
  vm.active_cells.compact_map do |(r, c), cell|
    name, region = scw_region(vm, cell)
    abs = cell.absolute_bounds
    at = CrymbleUI::Vec2.new(abs.x - outer.x, abs.y - outer.y)
    at = CrymbleUI::Vec2.new(at.x - whole.x, at.y - whole.y) if name == "content"
    next unless scw_inside?(region, CrymbleUI::Rect.new(at, abs.size))
    {name, r, c, cell, at}
  end
end

private def scw_minimums(counted, layers = {"content" => 4, "row" => 3, "col" => 3, "corner" => 1}) : Nil
  by_layer = counted.group_by(&.[0])
  layers.each { |name, least| (by_layer[name]?.try(&.size) || 0).should be >= least }
end

# (1)'s check: every counted cell at its painted top-left, its viewport_bounds there (a content cell's within the
# sub-pixel of the float scroll), and cell_screen_position there.
private def scw_check_places(renderer, vm, layers = {"content" => 4, "row" => 3, "col" => 3, "corner" => 1}) : Nil
  pixels = scw_first_pixels(renderer)
  counted = scw_counted(vm)
  scw_minimums(counted, layers)
  counted.each do |(name, r, c, cell, at)|
    pixels[scw_colour(r, c)]?.should eq({at.x.to_i, at.y.to_i}) # the oracle holds: painted where predicted
    vb = cell.viewport_bounds
    if name == "content"
      (vb.x - at.x).abs.should be < 1.0 # the float scroll, not the painted whole one (pre-existing)
      (vb.y - at.y).abs.should be < 1.0
    else
      vb.position.should eq(at)
    end
    vm.cell_screen_position(r, c).should eq(vm.absolute_bounds.position + (at - vm.viewport_bounds.position)) if vm.get_top_left_cell({r, c}) == {r, c}
  end
end

private SCW_SCROLLS = {CrymbleUI::Vec2.new(37.0, 23.0), CrymbleUI::Vec2.new(37.6, 23.7)}

describe "a sticky cell is where it is painted" do
  SCW_SCROLLS.each do |scroll|
    it "places every cell's viewport_bounds at its painted top-left, scrolled #{scroll}" do
      _app, renderer, vm = scw_grid(scroll)
      vm.scroll_offset.should eq(scroll) # instrument: the scroll took
      scw_counted(vm).any? { |(_, r, c)| {r, c} == {0, 2} }.should be_true # instrument: the merged span counted
      scw_check_places(renderer, vm)
    end
  end
end

describe "a sticky cell is where it is painted, across grid shapes" do
  it "holds for sticky rows only, sticky columns only, none (rulers still on), and one axis scrolled" do
    {
      {ScwAdapter.new(2, 0), CrymbleUI::Vec2.new(37.6, 23.7), {"content" => 4, "row" => 3}},
      {ScwAdapter.new(0, 1), CrymbleUI::Vec2.new(37.6, 23.7), {"content" => 4, "col" => 3}},
      {ScwAdapter.new(0, 0), CrymbleUI::Vec2.new(37.6, 23.7), {"content" => 4}},
      {ScwAdapter.new(2, 1), CrymbleUI::Vec2.new(37.6, 0.0), {"content" => 4, "row" => 3, "col" => 3, "corner" => 1}},
      {ScwAdapter.new(2, 1, corner_span: true), CrymbleUI::Vec2.new(37.6, 23.7), {"content" => 4, "row" => 3, "col" => 3}},
    }.each do |(adapter, scroll, layers)|
      _app, renderer, vm = scw_grid(scroll, adapter)
      scw_check_places(renderer, vm, layers)
    end
  end

  it "keeps the unscrolled grid exact" do
    _app, renderer, vm = scw_grid(CrymbleUI::Vec2.zero)
    scw_check_places(renderer, vm, {"content" => 4, "row" => 3, "col" => 3, "corner" => 1})
  end

  it "draws the ruler lines on the painted column boundaries at a fractional scroll" do
    _app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7))
    band = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!.bounds
    y = (vm.viewport_bounds.y + vm.ruler_row_height_pixels / 2.0).to_i
    lines = (3..10).map do |c|
      x = vm.viewport_bounds.x + vm.painted_col(c)[0]
      next unless x > band.x + 2.0 && x < band.right - 2.0
      renderer.backend.get_pixel(x.to_i, y).not_nil!.should eq(CrymbleUI::VirtualMatrix.ruler_line_color)
      x
    end.compact
    (lines.size >= 3).should be_true # instrument: boundaries inside the band checked
  end

  it "holds for a grid inside a scrolled scroll view (both scrollers at once)" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7), in_view: true)
    app.find("outer").not_nil!.as(CrymbleUI::ScrollView).scroll_offset.y.should eq(40.0) # instrument
    scw_check_places(renderer, vm, {"content" => 4, "row" => 3, "col" => 3, "corner" => 1})
  end

  it "holds with a sticky row taller than the view: the regions and the composited bands agree" do
    adapter = ScwAdapter.new(2, 1)
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 0.0), adapter)
    vm.row_height(0, 30.0) # far taller than the grid
    renderer.settle_rendering(app)
    sv = vm.content_scroll_view.not_nil!
    (vm.sticky_row_height_pixels > sv.bounds.height).should be_true # instrument: taller than the view
    regions = sv.sticky_regions
    at = sv.absolute_bounds.position
    {sv.sticky_row_layer, sv.sticky_col_layer, sv.sticky_corner_layer}.zip({regions[:row], regions[:col], regions[:corner]}).each do |(layer, region)|
      layer.not_nil!.content_rect.should eq(CrymbleUI::Rect.new(at.x + region.x, at.y + region.y, region.width, region.height))
    end
  end
end

describe "the drag ghost is where the dragged cells are painted" do
  # A press at an explicit painted point, then a move past the threshold, through App events.
  scw_ghost = ->(app : ScwApp, renderer : CrymbleUI::Testing::TestRenderer, vm : CrymbleUI::VirtualMatrix, cell : {Int32, Int32}, press : CrymbleUI::Vec2) do
    move = CrymbleUI::Vec2.new(0.0, 12.0)
    app.handle_mouse_down(press)
    app.handle_mouse_move(press + move)
    renderer.render_frame(app)
    ghost = app.drag_manager.ghost_layer.try(&.bounds)
    app.handle_mouse_up(CrymbleUI::Vec2.new(690.0, 470.0))
    renderer.settle_rendering(app)
    {ghost, move}
  end

  SCW_SCROLLS.each do |scroll|
    it "starts the ghost at a cell's painted rect: sticky boundary lines, the corner, content, the merged span - #{scroll}" do
      # (1,1): the last sticky row, the first scrolling column (partly under the band); (3,0): the sticky column,
      # the first scrolling row still shown (row 2 lies wholly under the sticky rows at this scroll)
      [{1, 1}, {3, 0}, {0, 0}, {6, 3}, {0, 2}].each do |cell|
        app, renderer, vm = scw_grid(scroll)
        box = vm.get_bounding_box(cell)
        painted = scw_window(vm, vm.painted_rect(box).not_nil!)
        press = painted.center
        ghost, move = scw_ghost.call(app, renderer, vm, cell, press)
        ghost.not_nil!.should eq(CrymbleUI::Rect.new(painted.x + move.x, painted.y + move.y, painted.width, painted.height))
        # by hand for a plain sticky cell: its absolute bounds, one gap wider and taller, cut by its band
        if cell == {1, 1} || cell == {3, 0}
          abs = vm.active_cells[cell].absolute_bounds
          _, region = scw_region(vm, vm.active_cells[cell])
          painted.should eq(CrymbleUI::Rect.new(abs.x, abs.y, abs.width + vm.grid_spacing, abs.height + vm.grid_spacing).intersection(region))
        end
      end
    end
  end

  it "takes the pinned slice of a merged header scrolled half under the sticky column" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(150.6, 0.0))
    span = vm.active_cells[{0, 2}]
    band = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!.bounds
    (span.absolute_bounds.x - band.x).abs.should be < 1.0 # instrument: pinned at the band edge
    painted = scw_window(vm, vm.painted_rect({ {0, 2}, {0, 3} }).not_nil!)
    painted.x.should eq(span.absolute_bounds.x)
    painted.width.should eq(span.absolute_bounds.width + vm.grid_spacing) # its slice, one gap wide more
    ghost, move = scw_ghost.call(app, renderer, vm, {0, 2}, painted.center)
    ghost.not_nil!.should eq(CrymbleUI::Rect.new(painted.x + move.x, painted.y + move.y, painted.width, painted.height))
  end

  it "takes the visible part of a content cell half under the sticky column" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(60.6, 0.0))
    band = vm.content_scroll_view.not_nil!.sticky_col_layer.not_nil!.bounds
    cell = vm.active_cells.keys.select { |(r, c)| r == 6 && c >= 1 }.find do |key|
      vb = vm.active_cells[key].viewport_bounds
      vb.x < band.right - 5.0 && vb.right > band.right + 5.0
    end.not_nil!
    painted = scw_window(vm, vm.painted_rect({cell, cell}).not_nil!)
    painted.x.should eq(band.right) # cut at the band - not under it
    ghost, move = scw_ghost.call(app, renderer, vm, cell, painted.center)
    ghost.not_nil!.should eq(CrymbleUI::Rect.new(painted.x + move.x, painted.y + move.y, painted.width, painted.height))
  end

  it "takes the visible cells of a drag box larger than the view" do
    adapter = ScwAdapter.new
    adapter.drag_boxes[{6, 3}] = { {6, 3}, {29, 3} }
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7), adapter)
    painted = scw_window(vm, vm.painted_rect({ {6, 3}, {29, 3} }).not_nil!)
    content = vm.layer.not_nil!.bounds
    (painted.bottom <= content.bottom).should be_true # the visible cells only
    press = scw_window(vm, vm.painted_rect({ {6, 3}, {6, 3} }).not_nil!).center
    ghost, move = scw_ghost.call(app, renderer, vm, {6, 3}, press)
    ghost.not_nil!.should eq(CrymbleUI::Rect.new(painted.x + move.x, painted.y + move.y, painted.width, painted.height))
  end

  it "starts the ghost at the painted rect inside a scrolled scroll view" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7), in_view: true)
    painted = scw_window(vm, vm.painted_rect({ {1, 4}, {1, 4} }).not_nil!)
    ghost, move = scw_ghost.call(app, renderer, vm, {1, 4}, painted.center)
    ghost.not_nil!.should eq(CrymbleUI::Rect.new(painted.x + move.x, painted.y + move.y, painted.width, painted.height))
  end

  it "shows no ghost - never a grid-sized one - for a source nothing of which is painted" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.zero)
    vm.drag_source_cell = {6, 3}
    vm.scroll_offset = CrymbleUI::Vec2.new(0.0, 400.0) # row 6 wholly out above
    renderer.settle_rendering(app)
    vm.painted_rect({ {6, 3}, {6, 3} }).should be_nil # instrument
    vm.drag_ghost_bounds.not_nil!.size.should eq(CrymbleUI::Size.new(0.0, 0.0))
  end
end

describe "the drag decal, the change glow and the cursor marks are where the cells are painted" do
  SCW_SCROLLS.each do |scroll|
    it "washes a committed source's decal over its painted rect - sticky row, sticky column, the merged span - #{scroll}" do
      [{1, 4}, {5, 0}, {0, 2}].each do |cell|
        app, renderer, vm = scw_grid(scroll)
        renderer.settle_rendering(app)
        before = scw_snapshot(renderer)
        vm.drag_source_cell = cell # a host's committed source (a cut)
        vm.mark_drag_overlay_dirty
        renderer.settle_rendering(app)
        expected = scw_pixels_of(scw_window(vm, vm.painted_rect(vm.get_bounding_box(cell)).not_nil!))
        scw_diff_box(renderer, before, scw_snapshot(renderer)).should eq(expected)
      end
    end

    it "washes the decal over a pinned span's slice and a content cell's visible part - #{scroll}" do
      [{ {0, 2}, CrymbleUI::Vec2.new(150.6, scroll.y) }, { {6, 1}, CrymbleUI::Vec2.new(60.6, scroll.y) }].each do |(cell, at_scroll)|
        app, renderer, vm = scw_grid(at_scroll)
        renderer.settle_rendering(app)
        before = scw_snapshot(renderer)
        vm.drag_source_cell = cell
        vm.mark_drag_overlay_dirty
        renderer.settle_rendering(app)
        painted = vm.painted_rect(vm.get_bounding_box(cell)).not_nil!
        x, _ = vm.painted_col(cell[1])
        (painted.x > x).should be_true # instrument: cut at the band - the lines would start under it
        scw_diff_box(renderer, before, scw_snapshot(renderer)).should eq(scw_pixels_of(scw_window(vm, painted)))
      end
    end

    it "washes the glow once over a highlighted box's painted rect - #{scroll}" do
      [{1, 4}, {5, 0}, {0, 2}].each do |cell|
        adapter = ScwAdapter.new
        app, renderer, vm = scw_grid(scroll, adapter)
        renderer.settle_rendering(app)
        before = scw_snapshot(renderer)
        adapter.glowing = cell == {0, 2} ? [{0, 2}, {0, 3}] : [cell]
        vm.mark_cursor_overlay_dirty
        renderer.settle_rendering(app)
        expected = scw_pixels_of(scw_window(vm, vm.painted_rect(vm.get_bounding_box(cell)).not_nil!))
        scw_diff_box(renderer, before, scw_snapshot(renderer)).should eq(expected)
      end
    end

    it "flashes the cursor cell over its painted cell rect - #{scroll}" do
      [{1, 4}, {6, 3}].each do |cell|
        app, renderer, vm = scw_grid(scroll, cursor_highlight_delta: CrymbleUI::Theme.current.brightness_cursor_delta)
        vm.cursor_rc = cell
        overlay = vm.cursor_overlay_widget.not_nil!
        overlay.flash_on = false
        vm.mark_cursor_overlay_dirty
        renderer.settle_rendering(app)
        before = scw_snapshot(renderer)
        overlay.flash_on = true
        vm.mark_cursor_overlay_dirty
        renderer.settle_rendering(app)
        expected = scw_pixels_of(scw_window(vm, vm.painted_rect(vm.get_bounding_box(cell), pitch: false).not_nil!))
        scw_diff_box(renderer, before, scw_snapshot(renderer)).should eq(expected)
      end
    end

    it "lays the cursor bands on the painted row and column - #{scroll}" do
      [{1, 4}, {6, 3}].each do |cell|
        app, renderer, vm = scw_grid(scroll, cursor_highlight_delta: CrymbleUI::Theme.current.brightness_cursor_delta)
        vm.cursor_rc = cell
        vm.cursor_overlay_widget.not_nil!.flash_on = false
        vm.cursor_highlight_delta = 0
        vm.mark_cursor_overlay_dirty
        renderer.settle_rendering(app)
        before = scw_snapshot(renderer)
        vm.cursor_highlight_delta = 60
        vm.mark_cursor_overlay_dirty
        renderer.settle_rendering(app)
        after = scw_snapshot(renderer)
        w = renderer.backend.width
        origin = vm.viewport_bounds.position
        row_y, row_h = vm.painted_row(cell[0])
        col_x, col_w = vm.painted_col(cell[1])
        # the row band's rows, read in a column right of the cursor's column band
        probe_x = (origin.x + col_x + col_w + 20.0).to_i
        rows = (0...renderer.backend.height).select { |y| before[y * w + probe_x] != after[y * w + probe_x] }
        rows.first.should eq((origin.y + row_y).floor.to_i)
        rows.last.should eq((origin.y + row_y + row_h).ceil.to_i - 1)
        # the column band's columns, read in a row below the cursor's row band
        probe_y = (origin.y + row_y + row_h + 30.0).to_i
        cols = (0...w).select { |x| before[probe_y * w + x] != after[probe_y * w + x] }
        cols.first.should eq((origin.x + col_x).floor.to_i)
        cols.last.should eq((origin.x + col_x + col_w).ceil.to_i - 1)
      end
    end
  end
end

# A merged CONTENT cell (5,2)-(9,5): scrolled far enough, its key in the active set is a handle inside it, not its
# top-left.
class ScwMergedContentAdapter < ScwAdapter
  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {5, 2}, {9, 5} } if (5..9).includes?(row) && (2..5).includes?(col)
    super
  end
end

describe "painted_rect of a region cutting a merged cell" do
  it "counts the merged cell by its box, not by the handle it is keyed by" do
    _app, _renderer, vm = scw_grid(CrymbleUI::Vec2.new(260.0, 117.0), ScwMergedContentAdapter.new)
    handle = vm.active_cells.keys.find { |key| vm.get_top_left_cell(key) == {5, 2} }.not_nil!
    handle.should_not eq({5, 2}) # instrument: keyed by a handle inside the box
    whole = vm.painted_rect({ {5, 2}, {9, 5} }).not_nil!
    vm.painted_rect({ {5, 2}, {5, 2} }).should eq(whole) # its top-left alone meets the box
  end
end

# Widths whose fraction nearly reaches a pixel, so a sum of float widths drifts from the placed cells fast.
class ScwWideFractionAdapter < ScwAdapter
  def get_sizes : {Array(Float64), Array(Float64)}
    {Array.new(30, 1.0), Array.new(12, 4.4975)}
  end
end

# Records where a press lands, in its own space.
class ScwRecorder < ScwFill
  property got : CrymbleUI::Vec2? = nil

  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @got = point - absolute_bounds.position
  end
end

describe "what the user does on a sticky cell happens where it is painted" do
  it "clicks, drags and right-clicks sticky headers of a scrolled grid through the Driver (the grid offset in the window)" do
    {false, true}.each do |in_view|
      points = [] of CrymbleUI::Vec2
      adapter = ScwAdapter.new
      app = ScwApp.new do
        window = CrymbleUI::Window.new("W", 700, 480)
        panel = CrymbleUI::WindowPanel.new("P", 30.0, 40.0, 560.0, 400.0, id: "p")
        vm = CrymbleUI::VirtualMatrix.new(adapter, id: "grid")
        vm.on_right_click_handler = ->(at : CrymbleUI::Vec2) { points << at; nil }
        if in_view
          outer = CrymbleUI::ScrollView.new(max_height: 330.0, id: "outer")
          outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
            v.add_child(ScwFill.new(CrymbleUI::Color.new(90, 90, 90, 255)).tap { |f| f.measure_height = 60.0 })
            v.add_child(ScwBox.new(520.0, 300.0, vm))
            v.add_child(ScwFill.new(CrymbleUI::Color.new(90, 90, 90, 255)).tap { |f| f.measure_height = 400.0 })
          end)
          panel.add_child(outer)
        else
          panel.add_child(vm)
        end
        window.add_child(panel)
        window
      end
      ui = CrymbleUI::Testing::Driver.new(app, 700, 480)
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      if in_view
        ui.find("outer").as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 40.0))
        ui.settle
      end
      vm.scroll_offset = CrymbleUI::Vec2.new(37.6, 23.7)
      ui.settle
      ui.click_cell "grid", 0, 4
      ui.cursor("grid").should eq({0, 4})
      ui.click_cell "grid", 5, 0
      ui.cursor("grid").should eq({5, 0})
      ui.click_cell "grid", 0, 2 # the merged span
      ui.cursor("grid").should eq({0, 2})
      ui.right_click_cell "grid", 1, 4
      painted = scw_window(vm, vm.painted_rect({ {1, 4}, {1, 4} }).not_nil!)
      painted.contains_point(points.last).should be_true
      ui.drag_cell "grid", 1, 4, onto: {"grid", 5, 0}
      adapter.moves.last.should eq({ {1, 4}, {5, 0} })
    end
  end

  it "opens a header cell's dropdown directly below where the cell is painted" do
    adapter = ScwAdapter.new
    adapter.special[{0, 4}] = -> { CrymbleUI::ComboBox.new(items: ["Alpha", "Beta"], selected: 0, id: "hdr_combo").as(CrymbleUI::Widget) }
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7), adapter)
    combo = app.find("hdr_combo").not_nil!
    painted = combo.absolute_bounds # a sticky cell is painted at its bounds
    (painted.x - vm.active_cells[{0, 4}].absolute_bounds.x).abs.should be < 1.0 # instrument: the combo fills the cell
    at = painted.center
    vm.double_click_interval = 1.hour # the second press must count as a double-click, however slow the run
    2.times do # a double click opens the cell's editor - here its dropdown (the grid forwards it)
      app.handle_mouse_down(at)
      app.handle_mouse_up(at)
    end
    renderer.settle_rendering(app)
    popup = app.root.not_nil!.as(CrymbleUI::Window).overlays.find(&.is_a?(CrymbleUI::ComboBoxPopup)).not_nil!
    popup.absolute_bounds.x.should eq(painted.x)
    popup.absolute_bounds.y.should eq(painted.bottom)
  end

  it "composites a scroll view inside a header cell at its cell" do
    adapter = ScwAdapter.new
    marker = CrymbleUI::Color.new(250, 150, 0, 255)
    adapter.special[{0, 4}] = -> do
      CrymbleUI::ScrollView.new(max_height: 18.0, id: "hdr_sv").tap(&.set_content(ScwFill.new(marker).tap { |f| f.measure_height = 40.0 })).as(CrymbleUI::Widget)
    end
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7), adapter)
    sv = app.find("hdr_sv").not_nil!
    sv.layer.should_not be_nil # instrument: it owns a layer
    painted = vm.active_cells[{0, 4}].absolute_bounds # a sticky cell is painted at its bounds
    renderer.backend.get_pixel((painted.x + 6.0).to_i, (painted.y + 6.0).to_i).should eq(marker)
  end
end

describe "input finds the cell and the border where they are painted" do
  it "maps a click just inside a content line's far edge to that cell at a fractional scroll" do
    _app, _renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7))
    rect = scw_window(vm, vm.painted_rect({ {6, 4}, {6, 4} }).not_nil!) # the line pitch: where the next cell starts
    at = CrymbleUI::Vec2.new(rect.right - 0.3, rect.bottom - 0.3)
    vm.point_to_cell(at).should eq({6, 4})
  end

  it "grabs a column border where the ruler draws it, after fractional widths" do
    # widths of 4.4975 units: 92.95px a line, placed at 92 - a float sum drifts 0.95px a column
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 0.0), ScwWideFractionAdapter.new)
    drift = 9 * (4.4975 * 20.0 + vm.grid_spacing) - vm.placed_col_cum[9] # float widths (frame height 20) against placed
    (drift > 4.0).should be_true # instrument: past the grab tolerance
    x, pitch = vm.painted_col(8)
    at = vm.viewport_bounds.position + CrymbleUI::Vec2.new(x + pitch, vm.ruler_row_height_pixels / 2.0)
    vm.on_mouse_down(vm.to_content(at))
    vm.resize_axis.to_s.should eq("Col")
    vm.resize_index.should eq(8)
    vm.on_mouse_up(vm.to_content(at))
    renderer.settle_rendering(app)
  end

  it "moves a committed source's decal with its cells when the grid scrolls" do
    app, renderer, vm = scw_grid(CrymbleUI::Vec2.new(37.6, 23.7))
    vm.drag_source_cell = {6, 4}
    vm.mark_drag_overlay_dirty
    renderer.settle_rendering(app)
    vm.content_scroll_view.not_nil!.set_scroll_offset_for_test(CrymbleUI::Vec2.new(60.0, 46.0)) # the scrollbar's path
    renderer.settle_rendering(app)
    (vm.scroll_offset.y > 23.7).should be_true # instrument: the grid followed its scrollbar
    with_decal = scw_snapshot(renderer)
    vm.drag_source_cell = nil
    vm.mark_drag_overlay_dirty
    renderer.settle_rendering(app)
    expected = scw_pixels_of(scw_window(vm, vm.painted_rect({ {6, 4}, {6, 4} }).not_nil!))
    scw_diff_box(renderer, scw_snapshot(renderer), with_decal).should eq(expected)
  end

  # The Driver aims at the span's painted slice; the grid drops on the constituent under the pointer (its drop
  # takes point_to_cell as it is), so the Driver names that. Mutation: no fallback - "not on screen".
  it "aims at a pinned span's painted slice when its top-left column lies wholly under the band (the Driver)" do
    adapter = ScwAdapter.new
    app = ScwApp.new do
      window = CrymbleUI::Window.new("W", 700, 480)
      panel = CrymbleUI::WindowPanel.new("P", 30.0, 40.0, 560.0, 400.0, id: "p")
      panel.add_child(CrymbleUI::VirtualMatrix.new(adapter, id: "grid"))
      window.add_child(panel)
      window
    end
    ui = CrymbleUI::Testing::Driver.new(app, 700, 480)
    vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
    vm.scroll_offset = CrymbleUI::Vec2.new(250.6, 0.0)
    ui.settle
    x, pitch = vm.painted_col(2)
    band = vm.ruler_col_width_pixels + vm.sticky_col_width_pixels
    (x + pitch <= band).should be_true                # instrument: column 2 wholly under the band
    vm.painted_rect({ {0, 2}, {0, 3} }).should_not be_nil # instrument: the span's slice is painted
    expect_raises(CrymbleUI::Testing::Driver::Refusal, /0,2 lies under cell 0,3/) do
      ui.drag_cell "grid", 1, 4, onto: {"grid", 0, 2}
    end
  end

  it "keeps a merged content cell's label region off the scroll's fraction" do
    regions = {117.0, 117.6}.map do |y|
      _app, _renderer, vm = scw_grid(CrymbleUI::Vec2.new(0.0, y), ScwMergedContentAdapter.new)
      key = vm.active_cells.keys.find { |k| vm.get_top_left_cell(k) == {5, 2} }.not_nil!
      vm.active_cells[key].ink_region
    end
    regions[0].should_not be_nil # instrument: the merged cell has a label region
    regions[1].should eq(regions[0]) # the painted position moved by whole pixels only: the same region
  end
end
