require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# A GRID CELL THAT OWNS A LAYER lives like any widget: composited from the frame its cell appears, freed when its
# cell leaves (and repainted if the adapter hands it back), and a scroll view that cannot move passes the wheel
# on. Here every cell holds a ScrollView - a layer owner - whose content paints its ROW's own colour, so a frame
# that still shows another row's pixels, or none, reads as wrong. All input goes through the App.

private def loc_colour(row : Int32) : CrymbleUI::Color
  CrymbleUI::Color.new(0, (60 + row * 3) % 250, 40, 255)
end

class LocSwatch < CrymbleUI::Widget
  def initialize(@height : Float64, @color : CrymbleUI::Color, @width : Float64? = nil)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width || (constraints.max_width.finite? ? constraints.max_width : 80.0), @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# A Button that counts its clicks and its exits.
class LocButton < CrymbleUI::Button
  getter clicks = 0
  getter exits = 0

  def initialize(id : String)
    super("b", id: id, padding: 2.0, on_click: -> { @clicks += 1; nil })
  end

  def on_mouse_exit
    @exits += 1
    super
  end
end

# A grid of 2x2 text cells: a layer owner with several layers (content, sticky bands, overlays) to nest in a cell.
class LocTiny
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    2
  end

  def col_count : Int32
    2
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row}#{col}")
  end
end

# A sticky header row (0) and a sticky column (0); 60 rows by 12 columns, so the grid scrolls both ways. Each cell
# holds a layer owner of `kind`: a ScrollView (painting its row's colour), a LayerBox, or a whole grid.
class LocShape
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @made = {} of Tuple(Int32, Int32) => CrymbleUI::Widget

  # `merged`: column 2, rows 2..12 are one cell. `reuse`: cell_paint hands back the widget it made before. `tall`:
  # rows four lines high, and a ScrollView with room for a scrollbar thumb.
  def initialize(@kind = :scroll, @merged = false, @reuse = false, @tall = false)
    self.custom_row_heights = Array.new(60, 4.0) if @tall
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...60).to_a + [0], (1...12).to_a + [0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {2, 2}, {12, 2} } if @merged && col == 2 && 2 <= row <= 12
    { {row, col}, {row, col} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    @reuse ? (@made[{row, col}] ||= make(row, col)) : make(row, col)
  end

  private def make(row : Int32, col : Int32) : CrymbleUI::Widget
    case @kind
    when :layer_box
      CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil).tap(&.add_child(LocSwatch.new(14.0, loc_colour(row))))
    when :matrix
      CrymbleUI::VirtualMatrix.new(adapter: LocTiny.new)
    when :text # no layer owner at all: the plain grid
      CrymbleUI::Text.new("#{row}.#{col}")
    when :plain_button # the cell IS a Button: the grid forwards a click on its cell to it
      LocButton.new("b_#{row}_#{col}")
    when :button # a ScrollView holding a Button and a TextInput: input reaching into a layer owner
      sv = CrymbleUI::ScrollView.new(max_height: 14.0, id: "sv_#{row}_#{col}")
      sv.set_content(CrymbleUI::HStack.new(spacing: 2.0).tap do |h|
        h.add_child(LocButton.new("b_#{row}_#{col}"))
        h.add_child(CrymbleUI::TextInput.new(value: "t", id: "t_#{row}_#{col}"))
      end)
      sv
    else
      sv = CrymbleUI::ScrollView.new(max_height: @tall ? 70.0 : 14.0, id: "sv_#{row}_#{col}")
      sv.set_content(LocSwatch.new(@tall ? 200.0 : 40.0, loc_colour(row)))
      sv
    end
  end
end

class LocApp < CrymbleUI::App
  getter shape : CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@shape : CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter = LocShape.new)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 600, 400)
    # its cursor overlay paints nothing (delta 0 - its layers are there): the cases read cells' pixels
    vm = CrymbleUI::VirtualMatrix.new(adapter: @shape, id: "grid", cursor_highlight_delta: 0)
    window.add_child(vm)
    window
  end
end

private def loc_app(app = LocApp.new) : {CrymbleUI::Testing::TestRenderer, LocApp, CrymbleUI::VirtualMatrix}
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {renderer, app, app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)}
end

# Over the grid's vertical scrollbar: a point where the wheel reaches the grid's own scroll (no cell under it).
private def scrollbar_point(vm) : CrymbleUI::Vec2
  b = vm.absolute_bounds
  CrymbleUI::Vec2.new(b.right - CrymbleUI::ScrollView::SCROLLBAR_WIDTH / 2.0, b.y + b.height / 2.0)
end

# Where a cell's nested content shows on screen - a probe point 10px into its box - if the cell's start is inside
# the band it lives in and the probe is clear of the scrollbars.
private def shown_point(vm, key) : CrymbleUI::Vec2?
  row, col = key
  x, _ = vm.painted_col(col)
  y, _ = vm.painted_row(row)
  lo_x = col < vm.sticky_col_count ? vm.ruler_col_width_pixels : vm.ruler_col_width_pixels + vm.sticky_col_width_pixels
  lo_y = row < vm.sticky_row_count ? vm.ruler_row_height_pixels : vm.ruler_row_height_pixels + vm.sticky_row_height_pixels
  bar = CrymbleUI::ScrollView::SCROLLBAR_WIDTH
  return nil unless x >= lo_x && y >= lo_y && x + 20.0 <= vm.bounds.width - bar && y + 10.0 <= vm.bounds.height - bar
  b = vm.absolute_bounds
  CrymbleUI::Vec2.new(b.x + x + 10.0, b.y + y + 5.0)
end

# Drags the grid's scrollbar thumb by `by` along its axis (vertical: the right bar, horizontal: the bottom one) - an
# input whose cells the grid makes in the frame's flush (sync_from_scroll_view defers them), inside the render loop.
private def drag_thumb(app, vm, by : Float64, vertical = true) : Nil
  b = vm.absolute_bounds
  half = CrymbleUI::ScrollView::SCROLLBAR_WIDTH / 2.0
  from = vertical ? CrymbleUI::Vec2.new(b.right - half, b.y + 30.0) : CrymbleUI::Vec2.new(b.x + 60.0, b.bottom - half)
  to = vertical ? CrymbleUI::Vec2.new(from.x, from.y + by) : CrymbleUI::Vec2.new(from.x + by, from.y)
  app.handle_mouse_down(from)
  app.handle_mouse_move(to)
  app.handle_mouse_up(to)
end

# The cells an input revealed - newly ON SCREEN (the grid creates cells in a margin beyond the
# viewport, so a newly created cell is not yet a revealed one) - how many show their own row's colour after ONE
# frame, whether the input itself (before any frame) moved the composite set's version, and how many times that
# frame re-collected inside its render loop.
private def reveal(renderer, app, vm, & : ->) : {Int32, Int32, Bool, Int32}
  before = vm.active_cells.keys.select { |key| shown_point(vm, key) }.to_set
  version = CrymbleUI::Layer.order_version
  yield
  moved = CrymbleUI::Layer.order_version != version
  CrymbleUI::LayerRenderer.reset_frame_counters
  renderer.render_frame(app)
  in_loop = CrymbleUI::LayerRenderer.frame_in_loop_recollect_count
  revealed = shown = 0
  vm.active_cells.each_key do |key|
    next if before.includes?(key)
    next unless point = shown_point(vm, key)
    revealed += 1
    shown += 1 if renderer.backend.get_pixel(point.x.to_i, point.y.to_i) == loc_colour(key[0])
  end
  {revealed, shown, moved, in_loop}
end

private def subtree_layers(widget : CrymbleUI::Widget) : Array(CrymbleUI::Layer)
  layers = [] of CrymbleUI::Layer
  widget.each_layer_in_subtree { |layer| layers << layer }
  layers
end

private def subtree_widgets(widget : CrymbleUI::Widget, into = [] of CrymbleUI::Widget) : Array(CrymbleUI::Widget)
  into << widget
  widget.children.each { |child| subtree_widgets(child, into) }
  into
end

# THE DETACH CLAIM, around `trigger` and one frame: every cell that left is detached with its GPU freed - each
# layer of its subtree without a backend and out of that frame's composite list, each widget without its own
# surfaces - and the registry moved by exactly the layers that left and came (no more, no fewer: a double retire
# or a missed register shows). What else stands on the grid's layers (rulers, overlays) is still there. Returns
# how many cells, and how many of their layers, left.
private def judge_detach(renderer, app, vm, &) : {Int32, Int32}
  before = vm.active_cells.values
  kept = before.to_set
  registry = CrymbleUI::Layer.registry_size
  sv = vm.content_scroll_view.not_nil!
  grid_layers = [vm.content_layer, sv.sticky_row_layer, sv.sticky_col_layer, sv.sticky_corner_layer].compact
  others = grid_layers.flat_map { |layer| layer.widgets.reject { |w| kept.includes?(w) }.map { |w| {layer, w} } }
  yield
  renderer.render_frame(app)
  detached = before.select(&.parent.nil?)
  attached = vm.active_cells.values.reject { |w| kept.includes?(w) }
  left = detached.sum { |w| subtree_layers(w).size }
  came = attached.sum { |w| subtree_layers(w).size }
  composited = renderer.cached_layers.not_nil!
  detached.each do |cell|
    subtree_layers(cell).each do |layer|
      layer.backend.should be_nil
      composited.includes?(layer).should be_false
    end
    subtree_widgets(cell).each do |w|
      w.widget_backend.should be_nil
      w.background_backend.should be_nil
      w.rendered_to_layer_at_current_bounds?.should be_false
      w.primitives_node.should be_nil # out of the global zoom/theme Sources' dependents
      w.@slot_buffer_pos.should be_nil # no slot it could be skipped against when it returns
    end
  end
  CrymbleUI::Layer.registry_size.should eq(registry - left + came)
  others.each { |(layer, w)| layer.widgets.includes?(w).should be_true }
  {detached.size, left}
end

# Nests: an outer ScrollView holding, between a short filler and a tall one, `inner` - for the wheel's chain with no grid, or
# around a grid.
class LocNestApp < CrymbleUI::App
  def initialize(&@inner : -> CrymbleUI::Widget)
    super()
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 600, 400)
    outer = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 300.0, id: "outer")
    outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
      v.add_child(LocSwatch.new(30.0, CrymbleUI::Color.new(90, 90, 90, 255), width: 1200.0)) # room to scroll a notch
      v.add_child(@inner.call)
      v.add_child(LocSwatch.new(900.0, CrymbleUI::Color.new(90, 90, 90, 255), width: 1200.0))
    end)
    window.add_child(outer)
    window
  end
end

private def nest_app(&inner : -> CrymbleUI::Widget) : {CrymbleUI::Testing::TestRenderer, LocNestApp}
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  app = LocNestApp.new(&inner)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {renderer, app}
end

# A vertical scroll view (14px over 40px of content) at the top of a scroll view that scrolls both ways.
private def nested_views : {CrymbleUI::Testing::TestRenderer, LocNestApp, CrymbleUI::ScrollView, CrymbleUI::ScrollView}
  renderer, app = nest_app do
    CrymbleUI::ScrollView.new(max_height: 14.0, id: "inner").tap(&.set_content(LocSwatch.new(40.0, loc_colour(1))))
  end
  {renderer, app, app.find("outer").not_nil!.as(CrymbleUI::ScrollView), app.find("inner").not_nil!.as(CrymbleUI::ScrollView)}
end

# A point over `view`, asserted to reach it (the wheel is then sent where the claim is about).
private def over(app, view : CrymbleUI::Widget, inset = 5.0) : CrymbleUI::Vec2
  at = view.viewport_bounds.position + CrymbleUI::Vec2.new(inset, inset)
  app.widget_at(at).not_nil!.widget_in_tree?(view).should be_true # instrument: the point is over the view
  at
end

describe "a grid cell that owns a layer" do
  describe "is composited the frame its cell appears" do
    # Past the margin of cells the grid keeps beyond the viewport: those near it were created, and collected, at
    # startup. Dragging the scrollbar only flags the scroll; the cells are made in the frame's flush, inside the
    # render loop - so the loop re-collects.
    it "dragging the scrollbar down reveals content and sticky-column cells, each showing its own content" do
      renderer, app, vm = loc_app
      revealed, shown, _, in_loop = reveal(renderer, app, vm) { drag_thumb(app, vm, 120.0) }
      (revealed > 5).should be_true # instrument
      shown.should eq(revealed)
      in_loop.should eq(1) # instrument: made in the flush - and one re-collect for all of them
    end

    it "dragging the scrollbar right reveals content and sticky-row cells, each showing its own content" do
      renderer, app, vm = loc_app
      revealed, shown, _, in_loop = reveal(renderer, app, vm) { drag_thumb(app, vm, 200.0, vertical: false) }
      (revealed > 5).should be_true
      shown.should eq(revealed)
      in_loop.should eq(1)
    end

    it "a 2000px wheel creates and detaches cells in one flush and still shows every revealed one" do
      renderer, app, vm = loc_app
      revealed, shown, _, _ = reveal(renderer, app, vm) { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -100.0), scrollbar_point(vm)) }
      (vm.scroll_offset.y > 600.0).should be_true # instrument: far past the first screen
      (revealed > 5).should be_true
      shown.should eq(revealed)
    end

    # From the top, a short scroll only ADDS cells (the margin above is not full yet, so nothing leaves): the
    # attach alone must announce the new layers - step by step, until the cells it made come into view.
    it "scrolling a little from the top - cells only arriving - shows each one as it comes into view" do
      renderer, app, vm = loc_app
      total_revealed = 0
      3.times do # each drag starts on the thumb where it began: three short ones stay on it
        before = vm.active_cells.size
        revealed, shown, _, _ = reveal(renderer, app, vm) { drag_thumb(app, vm, 6.0) }
        (vm.active_cells.size >= before).should be_true # instrument: nothing left
        shown.should eq(revealed)
        total_revealed += revealed
      end
      (total_revealed > 5).should be_true # instrument
    end

    # Narrowing a column by its ruler border reflows in the flush (no layout) and brings the next columns into
    # view while no cell leaves - an attach with nothing else to announce the new layers.
    it "narrowing a column reveals the next columns' cells, each showing its own content" do
      renderer, app, vm = loc_app
      x, pitch = vm.painted_col(1)
      border = vm.absolute_bounds.position + CrymbleUI::Vec2.new(x + pitch - 1.0, vm.ruler_row_height_pixels / 2.0)
      before = vm.active_cells.values.to_set
      revealed, shown, _, _ = reveal(renderer, app, vm) do
        app.handle_mouse_down(border)
        app.handle_mouse_move(border - CrymbleUI::Vec2.new(70.0, 0.0))
        app.handle_mouse_up(border - CrymbleUI::Vec2.new(70.0, 0.0))
      end
      (vm.painted_col(1)[1] < pitch).should be_true                       # instrument: the column narrowed
      before.all? { |w| !w.parent.nil? }.should be_true                    # instrument: nothing left
      (revealed > 5).should be_true
      shown.should eq(revealed)
      # and the cells it attached beyond the view are in the frame's composite list already - the attach announced
      # them, so a later scroll that brings them in without anything leaving finds them collected
      attached = vm.active_cells.values.reject { |w| before.includes?(w) }
      attached.empty?.should be_false # instrument
      composited = renderer.cached_layers.not_nil!
      attached.each { |cell| subtree_layers(cell).each { |layer| composited.includes?(layer).should be_true } }
    end

    # The grid takes the wheel over its cells itself and scrolls AT ONCE (apply_scroll): its cells are made by the
    # input, between frames - the frame-start check is what re-collects.
    it "cells made by the input between frames show at the next frame" do
      renderer, app, vm = loc_app
      revealed, shown, moved, _ = reveal(renderer, app, vm) do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -20.0), vm.absolute_bounds.center)
      end
      moved.should be_true # instrument: the input itself changed the composite set, before any frame
      (revealed > 5).should be_true
      shown.should eq(revealed)
    end
  end
  describe "is detached when its cell leaves, its GPU freed" do
    after_each { CrymbleUI::FontSizing.reset_zoom }

    it "by a scroll (the keep-alive sweep)" do
      renderer, app, vm = loc_app
      cells, layers = judge_detach(renderer, app, vm) { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(vm)) }
      (cells > 10 && layers >= cells).should be_true # instrument: owners left, each with its layers
    end

    # At the content's end a scroll only REMOVES cells (no row left to arrive): the detach alone must take the
    # layers out of the frame.
    it "by a scroll at the content's end - cells only leaving" do
      renderer, app, vm = loc_app
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -200.0), scrollbar_point(vm)) # to the end
      renderer.settle_rendering(app)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 4.0), scrollbar_point(vm)) # a little back up...
      renderer.settle_rendering(app)
      before = vm.active_cells.values.to_set
      cells, _ = judge_detach(renderer, app, vm) { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -200.0), scrollbar_point(vm)) }
      (cells > 0).should be_true                                          # instrument: some left...
      vm.active_cells.values.all? { |w| before.includes?(w) }.should be_true # ...and none arrived
    end

    it "by an auto-size re-measure" do
      renderer, app, vm = loc_app
      cells, _ = judge_detach(renderer, app, vm) { vm.auto_size = true }
      (cells > 10).should be_true
    end

    it "by a zoom change" do
      renderer, app, vm = loc_app
      cells, _ = judge_detach(renderer, app, vm) { CrymbleUI::FontSizing.zoom_in }
      (cells > 10).should be_true
    end

    it "by a cell invalidation" do
      renderer, app, vm = loc_app
      key = vm.active_cells.keys.find! { |(row, col)| row > 0 && col > 0 }
      cells, layers = judge_detach(renderer, app, vm) { app.shape.invalidate_cell!(*key) }
      cells.should eq(1)
      (layers > 0).should be_true
    end

    it "by an invalidate-all" do
      renderer, app, vm = loc_app
      cells, _ = judge_detach(renderer, app, vm) { app.shape.invalidate_all! }
      (cells > 10).should be_true
    end

    it "an owner that is a LayerBox" do
      renderer, app, vm = loc_app(LocApp.new(LocShape.new(:layer_box)))
      cells, layers = judge_detach(renderer, app, vm) { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(vm)) }
      (cells > 10 && layers >= cells).should be_true
    end

    it "an owner that is a whole grid (several layers)" do
      renderer, app, vm = loc_app(LocApp.new(LocShape.new(:matrix)))
      cells, layers = judge_detach(renderer, app, vm) { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(vm)) }
      (cells > 10 && layers >= 3 * cells).should be_true
    end

    it "leaves the registry as a fresh app's after a rebuild" do
      renderer, app, _ = loc_app
      fresh = CrymbleUI::Layer.registry_size
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)))
      renderer.settle_rendering(app)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 40.0), scrollbar_point(app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)))
      app.request_rebuild
      renderer.settle_rendering(app)
      CrymbleUI::Layer.registry_size.should eq(fresh)
    end
  end
  # A merged content cell's handle MIGRATES as the grid scrolls (the grid detaches it and attaches it again in one
  # update); a widget the adapter hands straight back never left - it keeps its layer, still registered and in the
  # frame's composite list, with the surface it had.
  it "is not freed when its merged cell's handle migrates and the adapter hands it straight back" do
    renderer, app, vm = loc_app(LocApp.new(LocShape.new(merged: true, reuse: true)))
    cell = vm.active_cells.values.find! { |w| w.id == "sv_2_2" }
    layer = cell.layer.not_nil!
    surface = layer.backend.not_nil!
    key = vm.active_cells.key_for(cell)
    node = cell.primitives_node.not_nil!
    drag_thumb(app, vm, 30.0)
    renderer.render_frame(app)
    vm.active_cells.key_for(cell).should_not eq(key) # instrument: its handle moved (detached, attached again)
    cell.parent.should be(vm)
    cell.primitives_node.should be(node)
    layer.backend.should be(surface)
    CrymbleUI::Layer.active_layers(app.root.not_nil!).includes?(layer).should be_true
    renderer.cached_layers.not_nil!.includes?(layer).should be_true
  end

  # A widget an adapter hands back comes back whole: same layer, its content still on it, registered again, painted
  # in the first frame back.
  it "is handed back whole by an adapter that reuses widgets" do
    shape = LocShape.new(reuse: true)
    sv = shape.cell_paint(2, 1) # the instance the adapter will hand the grid, every time
    renderer, app, vm = loc_app(LocApp.new(shape))
    layer = sv.layer.not_nil!
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(vm))
    renderer.render_frame(app)
    sv.parent.should be_nil # instrument: it left
    layer.backend.should be_nil
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 40.0), scrollbar_point(vm))
    renderer.render_frame(app)
    sv.parent.should_not be_nil
    sv.children.empty?.should be_false # its structure intact: detached, not destroyed
    sv.layer.should be(layer)
    layer.widgets.empty?.should be_false
    CrymbleUI::Layer.active_layers(app.root.not_nil!).includes?(layer).should be_true
    at = shown_point(vm, {2, 1}).not_nil!
    renderer.backend.get_pixel(at.x.to_i, at.y.to_i).should eq(loc_colour(2))
  end

  # The grid forwards a click to its cursor cell's widget when the press and the release meet that cell; a cell that
  # left in between has its proxy dropped (detach_cell), so the release clicks nothing that left.
  it "clicks nothing when the pressed cell left before the release" do
    renderer, app, vm = loc_app(LocApp.new(LocShape.new(:plain_button)))
    button = vm.active_cells[{3, 2}].as(LocButton)
    at = shown_point(vm, {3, 2}).not_nil!
    app.handle_mouse_down(at) # control: press and release on the cell click it
    app.handle_mouse_up(at)
    renderer.render_frame(app)
    button.clicks.should eq(1)
    app.handle_mouse_down(at)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -40.0), scrollbar_point(vm))
    button.parent.should be_nil # instrument: it left between the press and the release
    app.handle_mouse_up(at)
    renderer.render_frame(app)
    button.clicks.should eq(1)
  end

  it "keeps clicks and the wheel over a cell with the grid, whatever the cell holds" do
    renderer, app, vm = loc_app(LocApp.new(LocShape.new(:button)))
    button = app.find("b_3_2").not_nil!.as(LocButton)
    sv = app.find("sv_3_2").not_nil!.as(CrymbleUI::ScrollView)
    at = button.viewport_bounds.center
    app.widget_at(at).should be(vm)
    app.handle_mouse_down(at)
    app.handle_mouse_up(at)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at)
    renderer.render_frame(app)
    button.clicks.should eq(0)
    sv.scroll_offset.y.should eq(0.0)
    (vm.scroll_offset.y > 0.0).should be_true
  end
  # DECIDED (2026-10-01): a scroller that cannot move the way the wheel goes passes it on - no overflow on that
  # axis, or already at its end; per axis; a partial move takes its axis; no latching.
  describe "passes the wheel on when it cannot move" do
    it "at its end: the outer view moves, the inner one does not" do
      renderer, app, outer, inner = nested_views
      at = over(app, inner)
      2.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) }
      took = inner.scroll_offset.y
      (took > 0.0).should be_true # instrument: the inner view took the first ones
      before = outer.scroll_offset.y
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at)
      inner.scroll_offset.y.should eq(took)
      (outer.scroll_offset.y > before).should be_true
    end

    it "at its start, wheeling up: the outer view moves up" do
      renderer, app, outer, inner = nested_views
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), outer.viewport_bounds.position + CrymbleUI::Vec2.new(20.0, 150.0))
      before = outer.scroll_offset.y
      (before > 0.0).should be_true # instrument: the outer view scrolled (over its own content)
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), at)
      inner.scroll_offset.y.should eq(0.0)
      (outer.scroll_offset.y < before).should be_true
    end

    it "with room: the inner view moves and the outer one does not" do
      renderer, app, outer, inner = nested_views
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at)
      (inner.scroll_offset.y > 0.0).should be_true
      outer.scroll_offset.should eq(CrymbleUI::Vec2.zero)
    end

    it "a partial move takes its axis: the rest is dropped, not passed on" do
      renderer, app, outer, inner = nested_views
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) # 20 of the 26 it has
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) # 6 left, 20 asked
      inner.scroll_offset.y.should eq(inner.content_size.height - inner.bounds.height)
      outer.scroll_offset.should eq(CrymbleUI::Vec2.zero)
    end

    it "per axis: a diagonal moves the inner view down and the outer one across" do
      renderer, app, outer, inner = nested_views
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(-1.0, -1.0), at)
      (inner.scroll_offset.y > 0.0).should be_true
      outer.scroll_offset.y.should eq(0.0)
      (outer.scroll_offset.x > 0.0).should be_true
    end

    it "with shift over a view that cannot scroll sideways: the outer one scrolls sideways" do
      renderer, app, outer, inner = nested_views
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at, shift: true)
      inner.scroll_offset.should eq(CrymbleUI::Vec2.zero)
      (outer.scroll_offset.x > 0.0).should be_true
      outer.scroll_offset.y.should eq(0.0)
    end

    # The leftover goes back in the INPUT frame: with shift, an inner view that moved on the axis it reads
    # (delta.x, read as y) hands on delta.y, which the outer view, swapping once, reads as x.
    it "with shift through two scroll views: the leftover is handed on unswapped" do
      renderer, app = nest_app do
        CrymbleUI::ScrollView.new(max_height: 14.0, id: "inner").tap(&.set_content(LocSwatch.new(40.0, loc_colour(1))))
      end
      inner = app.find("inner").not_nil!.as(CrymbleUI::ScrollView)
      outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
      at = over(app, inner)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(-1.0, -2.0), at, shift: true)
      (inner.scroll_offset.y > 0.0).should be_true # it read delta.x (-1) as y
      outer.scroll_offset.y.should eq(0.0)
      outer.scroll_offset.x.should eq(2.0 * CrymbleUI::ScrollView::SCROLL_WHEEL_SPEED) # delta.y (-2), read as x
    end

    it "a scroll view inside a scroll view, no grid: at its end the outer one moves" do
      renderer, app = nest_app do
        CrymbleUI::ScrollView.new(max_height: 14.0, id: "inner").tap(&.set_content(LocSwatch.new(40.0, loc_colour(1))))
      end
      inner = app.find("inner").not_nil!.as(CrymbleUI::ScrollView)
      outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
      at = over(app, inner)
      3.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at) }
      (inner.scroll_offset.y > 0.0 && outer.scroll_offset.y > 0.0).should be_true
    end

    it "a grid at its end inside a scroll view hands it on" do
      renderer, app = nest_app do
        CrymbleUI::VirtualMatrix.new(adapter: LocShape.new(:layer_box), id: "grid").tap do |vm|
          vm.max_height = 200.0
        end
      end
      vm = app.find("grid").not_nil!.as(CrymbleUI::VirtualMatrix)
      outer = app.find("outer").not_nil!.as(CrymbleUI::ScrollView)
      at = over(app, vm, 70.0) # over a content cell: the grid takes the wheel
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -200.0), at) # to the grid's end
      (vm.scroll_offset.y > 0.0).should be_true # instrument
      outer.scroll_offset.y.should eq(0.0)      # it took that one whole
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), at)
      (outer.scroll_offset.y > 0.0).should be_true
    end

    it "over the grid's scrollbar does what it does over the grid: one scroll, the grid's" do
      renderer, app, vm = loc_app(LocApp.new(LocShape.new(:layer_box)))
      app.widget_at(scrollbar_point(vm)).should be(vm.content_scroll_view) # instrument: the chrome view is hit
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), scrollbar_point(vm))
      by_bar = vm.scroll_offset
      renderer, app, vm = loc_app(LocApp.new(LocShape.new(:layer_box)))
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), vm.absolute_bounds.center)
      (by_bar.y > 0.0).should be_true # instrument
      vm.scroll_offset.should eq(by_bar)
      vm.content_scroll_view.not_nil!.scroll_offset.should eq(vm.scroll_offset)
    end
  end
  # The cost: the composite order is an O(widgets) tree walk. A grid whose cells own no layer never re-collects
  # while it scrolls; revealing many owners re-collects ONCE in the frame, not once per owner.
  describe "costs" do
    it "a plain grid's scroll re-collects nothing" do
      renderer, app, vm = loc_app(LocApp.new(LocShape.new(:text)))
      [-20.0, 20.0].each do |notches|
        CrymbleUI::LayerRenderer.reset_frame_counters
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, notches), scrollbar_point(vm))
        renderer.render_frame(app)
        CrymbleUI::LayerRenderer.frame_layer_recollect_count.should eq(0)
      end
      drag_thumb(app, vm, 120.0)
      CrymbleUI::LayerRenderer.reset_frame_counters
      renderer.render_frame(app)
      (vm.scroll_offset.y > 0.0).should be_true # instrument
      CrymbleUI::LayerRenderer.frame_layer_recollect_count.should eq(0)
    end

    it "revealing many owners re-collects once in the frame" do
      renderer, app, vm = loc_app
      drag_thumb(app, vm, 120.0)
      CrymbleUI::LayerRenderer.reset_frame_counters
      renderer.render_frame(app)
      CrymbleUI::LayerRenderer.frame_in_loop_recollect_count.should eq(1)
      CrymbleUI::LayerRenderer.frame_layer_recollect_count.should eq(1) # and none at the frame's start
    end
  end
  # A cell that left lets go of its subscriptions to the global zoom and theme (its pull node): a grid scrolled
  # down and back is at the same count each time - not one more per cell ever shown.
  it "leaves the global Sources' dependents steady over scroll cycles" do
    renderer, app, vm = loc_app
    first = vm.active_cells[{1, 1}] # a content cell at the top (sticky ones never leave)
    first.primitives_node.should_not be_nil # instrument: a cell subscribes (it rendered)
    at_top = [] of {Int32, Int32}
    3.times do
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -60.0), scrollbar_point(vm))
      renderer.render_frame(app)
      first.parent.should be_nil # instrument: the cells there have left
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 60.0), scrollbar_point(vm))
      renderer.render_frame(app)
      at_top << {CrymbleUI::FontSizing.zoom_source_dependent_count, CrymbleUI::Theme.current_source_dependent_count}
    end
    at_top[1].should eq(at_top[0])
    at_top[2].should eq(at_top[0])
  end

  # Cells an adapter hands back return one notch at a time - frames that do NOT clear the buffer, so a stale slot
  # stamp would let a returning cell be skipped and show what another cell left there.
  it "shows each cell an adapter hands back with its own content, returning on frames that keep the buffer" do
    shape = LocShape.new(reuse: true)
    views = (0..60).map { |row| shape.cell_paint(row, 1) } # the instances the adapter hands the grid, every time
    renderer, app, vm = loc_app(LocApp.new(shape))
    left = Set(Int32).new
    judged = clears = 0
    [-1.0, 1.0].each do |notch|
      120.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, notch), scrollbar_point(vm))
        renderer.render_frame(app)
        clears += 1 if vm.content_layer.not_nil!.buffer_just_cleared
        (0..60).each do |row|
          next left << row if views[row].parent.nil?
          next unless left.includes?(row) && (at = shown_point(vm, {row, 1}))
          judged += 1
          renderer.backend.get_pixel(at.x.to_i, at.y.to_i).should eq(loc_colour(row))
        end
      end
    end
    clears.should eq(0)               # instrument: every return was on a frame that kept the buffer
    (judged > 100).should be_true     # instrument: many returns judged
  end
end
