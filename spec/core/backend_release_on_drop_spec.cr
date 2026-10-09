require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/testing/surface_leaks"
require "../../src/testing/configurable_matrix_adapter"

# A RENDER SURFACE THE TREE DROPS IS RELEASED, whichever path drops it. Under SFML a surface is a driver-side
# RenderTexture the collector cannot see, so one that is dropped without `dispose` is gone for the session - and a
# zoom step dropped every texture on screen, a far grid scroll every cell texture, a recovered frame the whole
# working set. Asked the general way (the census, unreachable but unreleased), each path in turn, on one app holding
# every kind of owner: a combo popup, a drag chip, tabs over a ScrollView and a tree, a grid with sticky headers.
# Every example also asks the reverse - nothing the live tree still reaches was released - and that no frame raised.

# A widget that raises once while armed - a frame exception for the recovery path to recover from.
class BrdBomb < CrymbleUI::Widget
  class_property armed = false

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 16.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    if BrdBomb.armed
      BrdBomb.armed = false
      raise "armed"
    end
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
      CrymbleUI::Color.new(200, 60, 60, 255)).as(CrymbleUI::DrawPrimitive)]
  end
end

class BrdApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Release", 1000, 900) do
      window_panel("A", x: 10.0, y: 10.0, width: 440.0, height: 300.0, id: "pa") do
        vstack(spacing: 4.0) do
          hstack(spacing: 6.0) do
            combo_box(items: ["alpha", "beta", "gamma"], width: 120.0, id: "combo") { |_i, _v| }
            widget(BrdBomb.new(id: "bomb"))
            widget(CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip").tap(&.add_child(CrymbleUI::Text.new("chip"))))
          end
          tabs(id: "tabs") do
            tab("one") do
              scroll_view(id: "sv", max_height: 120.0) do
                vstack(spacing: 2.0) { 40.times { |i| button("Button #{i}", id: "b#{i}") { } } }
              end
            end
            tab("two") do
              tree_node("node", expanded: true, id: "tree") do
                6.times { |i| button("Leaf #{i}", id: "t#{i}") { } }
              end
            end
          end
        end
      end
      window_panel("G", x: 460.0, y: 10.0, width: 420.0, height: 300.0, id: "pg") do
        widget(CrymbleUI::VirtualMatrix.new(ConfigurableMatrixAdapter.new(1, 1, 400, 10, 1, 1), id: "grid"))
      end
    end
  end
end

# The fixture, settled, with the census recording since before the first build - a surface the act drops was made
# before the act.
private def brd_fixture : {BrdApp, CrymbleUI::Testing::TestRenderer}
  CrymbleUI::FontSizing.reset_zoom
  BrdBomb.armed = false
  CrymbleUI::Testing::TestRenderBackend.census_start
  app = BrdApp.new
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(1000, 900)
  renderer.settle_rendering(app)
  {app, renderer}
end

private def brd_find(app : BrdApp, id : String) : CrymbleUI::Widget
  app.root.not_nil!.find_by_id(id) || app.root.not_nil!.as(CrymbleUI::Window).overlays.compact_map(&.find_by_id(id)).first
end

private def brd_click(app : BrdApp, renderer, id : String) : Nil
  at = brd_find(app, id).viewport_bounds.center
  app.handle_mouse_down(at)
  app.handle_mouse_up(at)
  renderer.settle_rendering(app)
end

# Runs `act` and judges every surface the fixture ever made. `swallowed`: the frame exceptions the act is meant to
# raise (the recovery path's own); any other is a failure the renderer recovered from and must not hide.
private def brd_release(app : BrdApp, renderer, swallowed = 0, &act) : Nil
  before = CrymbleUI::Testing::SurfaceLeaks.reachable(app.root.not_nil!, renderer, app)
  caught = renderer.exceptions_caught
  yield
  renderer.settle_rendering(app)
  (renderer.exceptions_caught - caught).should eq(swallowed)
  root = app.root.not_nil!
  after = CrymbleUI::Testing::SurfaceLeaks.reachable(root, renderer, app)
  created = CrymbleUI::Testing::TestRenderBackend.census_take
  (before - after).size.should be > 0 # instrument: the act dropped surfaces the tree held
  (after.size > 5).should be_true     # ...and the tree holds surfaces again (the reverse check is not vacuous)
  stranded = CrymbleUI::Testing::SurfaceLeaks.stranded(root, renderer, created, app)
  stranded.should be_empty, "#{stranded.size} of #{created.size} surfaces dropped unreleased: " \
                            "#{stranded.first(6).map { |b| "#{b.width}x#{b.height}" }.join(", ")}"
  CrymbleUI::Testing::SurfaceLeaks.disposed_live(root, renderer, app).should be_empty
end

describe "a backend setter" do
  it "releases what it replaces, and nothing when the same surface is assigned again" do
    widget = CrymbleUI::Text.new("x")
    layer = CrymbleUI::Layer.new("brd_unit", CrymbleUI::Rect.new(0.0, 0.0, 4.0, 4.0))
    first, second, bg, surface = Array.new(4) { CrymbleUI::Testing::TestRenderBackend.new(4, 4) }
    widget.widget_backend = first
    generation = widget.backend_generation
    widget.widget_backend = first
    first.disposed?.should be_false
    widget.backend_generation.should eq(generation) # the same surface: a plan naming it stays good
    widget.widget_backend = second
    first.disposed?.should be_true
    (widget.backend_generation != generation).should be_true
    widget.background_backend = bg
    widget.background_backend = bg
    bg.disposed?.should be_false
    widget.background_backend = nil
    bg.disposed?.should be_true
    layer.backend = surface
    layer.backend = surface
    surface.disposed?.should be_false
    layer.backend = nil
    surface.disposed?.should be_true
    layer.unregister
  end

  # A build that returns the same instance reconciles a widget with itself: nothing moves.
  it "leaves a background alone when a widget is reconciled with itself" do
    widget = CrymbleUI::Text.new("x")
    background = CrymbleUI::Testing::TestRenderBackend.new(4, 4)
    widget.background_backend = background
    widget.copy_state_from(widget)
    widget.background_backend.should be(background)
    background.disposed?.should be_false
  end
end

describe "a render surface the tree drops" do
  after_each { CrymbleUI::FontSizing.reset_zoom }

  it "is released by a zoom step, an open popup and a scrolled grid included" do
    app, renderer = brd_fixture
    brd_click(app, renderer, "combo")
    app.root.not_nil!.as(CrymbleUI::Window).overlays.should_not be_empty # instrument: the popup is open
    brd_find(app, "grid").as(CrymbleUI::VirtualMatrix).scroll_offset = CrymbleUI::Vec2.new(0.0, 900.0)
    renderer.settle_rendering(app)
    brd_release(app, renderer) { CrymbleUI::FontSizing.zoom_in }
  end

  it "is released by a zoom step in the middle of a drag" do
    app, renderer = brd_fixture
    chip = brd_find(app, "chip")
    from = chip.viewport_bounds.center
    app.drag_manager.begin_drag_tracking(chip, from)
    app.drag_manager.update_drag(from + CrymbleUI::Vec2.new(60.0, 40.0), app.root.not_nil!)
    renderer.settle_rendering(app)
    app.drag_manager.dragging?.should be_true # instrument: a drag with its ghost is under way
    brd_release(app, renderer) { CrymbleUI::FontSizing.zoom_in }
  end

  it "is released by frame-exception recovery, three times over, with a sticky blit plan pending" do
    app, renderer = brd_fixture
    grid = brd_find(app, "grid").as(CrymbleUI::VirtualMatrix)
    brd_release(app, renderer, swallowed: 3) do
      3.times do |i|
        grid.scroll_offset = CrymbleUI::Vec2.new(0.0, 40.0 * (i + 1)) # builds the sticky layers' blit plans
        BrdBomb.armed = true
        brd_find(app, "bomb").mark_needs_render
        made = CrymbleUI::Testing::TestRenderBackend.census_size
        renderer.render_frame(app) # raises inside the frame; recovery resets
        BrdBomb.armed.should be_false # instrument: the bomb went off
        renderer.settle_rendering(app)
        (CrymbleUI::Testing::TestRenderBackend.census_size > made).should be_true # instrument: it re-rendered
      end
    end
  end

  # Recovery is a full reset: a surface the frame that raised left half-drawn could be anywhere - an owned layer (a
  # grid's sticky bands, a ScrollView's bars), a cell a layer hosts, an overlay - and so could a one-shot request
  # describing a buffer that is gone. Asked right after the reset, before anything renders again.
  it "leaves no surface and no pending plan of the frame that raised" do
    app, renderer = brd_fixture
    brd_click(app, renderer, "combo") # an overlay with surfaces
    grid = brd_find(app, "grid").as(CrymbleUI::VirtualMatrix)
    grid.scroll_offset = CrymbleUI::Vec2.new(0.0, 80.0) # sticky plans pending
    root = app.root.not_nil!
    layers = CrymbleUI::Layer.active_layers(root)
    layers.any?(&.blit_plan).should be_true # instrument
    (CrymbleUI::Testing::SurfaceLeaks.reachable(root, renderer, app).size > 20).should be_true # instrument
    app.reset_all_caches
    CrymbleUI::Testing::SurfaceLeaks.reachable(root, renderer, app).should eq(Set{renderer.backend.object_id})
    layers.none?(&.blit_plan).should be_true
    layers.none?(&.blit_plan_render_widgets).should be_true
    renderer.settle_rendering(app)
    CrymbleUI::Testing::TestRenderBackend.census_take
  end

  it "is released by frame-exception recovery in the middle of a drag, the drag's own layers included" do
    app, renderer = brd_fixture
    chip = brd_find(app, "chip")
    from = chip.viewport_bounds.center
    app.drag_manager.begin_drag_tracking(chip, from)
    app.drag_manager.update_drag(from + CrymbleUI::Vec2.new(60.0, 40.0), app.root.not_nil!)
    renderer.settle_rendering(app)
    ghost = app.drag_manager.ghost_layer.try(&.backend).should_not be_nil # instrument: the ghost has a surface
    brd_release(app, renderer, swallowed: 1) do
      BrdBomb.armed = true
      brd_find(app, "bomb").mark_needs_render
      renderer.render_frame(app)
    end
    app.drag_manager.dragging?.should be_false # recovery cancels the drag...
    ghost.disposed?.should be_true             # ...and its ghost's surface goes with it
  end

  it "is released by a grid's full recenter" do
    app, renderer = brd_fixture
    grid = brd_find(app, "grid").as(CrymbleUI::VirtualMatrix)
    recenters = 0
    brd_release(app, renderer) do
      [3000.0, 6000.0, 9000.0].each do |y|
        grid.scroll_offset = CrymbleUI::Vec2.new(0.0, y)
        CrymbleUI::LayerRenderer.reset_frame_counters
        renderer.render_frame(app)
        recenters += CrymbleUI::LayerRenderer.frame_full_recenter_count
      end
    end
    (recenters > 0).should be_true # instrument: the buffer recentred with no overlap
  end

  it "is released when a ScrollView's children scroll out of it" do
    app, renderer = brd_fixture
    sv = brd_find(app, "sv").as(CrymbleUI::ScrollView)
    first = brd_find(app, "b0").widget_backend.should_not be_nil # instrument: a child that will leave has one
    at = sv.viewport_bounds.center
    brd_release(app, renderer) do
      10.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), at); renderer.render_frame(app) }
      first.disposed?.should be_true # the child that left released it
      2.times do
        30.times { |i| sv.scroll_offset = CrymbleUI::Vec2.new(0.0, i * 40.0); renderer.render_frame(app) }
        30.times { |i| sv.scroll_offset = CrymbleUI::Vec2.new(0.0, (29 - i) * 40.0); renderer.render_frame(app) }
      end
    end
  end

  it "is released when a layer is reallocated, its pixels carried over" do
    app, renderer = brd_fixture
    kept = 0
    brd_release(app, renderer) do
      grid_surface = brd_find(app, "grid").as(CrymbleUI::VirtualMatrix).content_layer.not_nil!.backend.not_nil!
      {"pa", "pg"}.each do |id| # past the 20% / 50px over-allocation, as a user drags the panel's bottom edge
        panel = brd_find(app, id).as(CrymbleUI::WindowPanel)
        start = CrymbleUI::Vec2.new(panel.x + 200.0, panel.y + panel.height - 1.0)
        panel.on_mouse_down(start)
        5.times do |i|
          panel.on_mouse_move(start + CrymbleUI::Vec2.new(0.0, 100.0 * (i + 1)))
          CrymbleUI::LayerRenderer.reset_frame_counters
          renderer.render_frame(app)
          kept += CrymbleUI::LayerRenderer.frame_realloc_kept_count
        end
        panel.on_mouse_up(start + CrymbleUI::Vec2.new(0.0, 500.0))
        renderer.settle_rendering(app)
      end
      grid_surface.disposed?.should be_true # the grid's cell buffer outgrew its surface: a bigger one replaced it
    end
    (kept > 0).should be_true # instrument: a realloc with an old surface ran
  end

  # A sticky layer's blit plan is built when the grid scrolls (an event) and consumed when that layer renders; a far
  # scroll recenters the content buffer first, in the same frame, and that recenter drops - releases - every cell
  # texture, the sticky ones the plans name included. That frame must still show the headers a fresh render at the
  # same scroll shows.
  it "never blits a texture a pending plan named that was dropped before the plan ran" do
    app, renderer = brd_fixture
    grid = brd_find(app, "grid").as(CrymbleUI::VirtualMatrix)
    grid.scroll_offset = CrymbleUI::Vec2.new(37.0, 120.0)
    renderer.settle_rendering(app)
    caught = renderer.exceptions_caught
    grid.scroll_offset = CrymbleUI::Vec2.new(37.0, 6000.0)
    sv = grid.content_scroll_view.not_nil!
    [sv.sticky_row_layer, sv.sticky_col_layer].compact.any?(&.blit_plan).should be_true # instrument: a plan is pending
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.render_frame(app)
    CrymbleUI::LayerRenderer.frame_full_recenter_count.should be > 0 # instrument: the recenter ran in that frame
    renderer.exceptions_caught.should eq(caught)
    CrymbleUI::Testing::TestRenderBackend.census_take

    fresh_app, fresh = brd_fixture
    brd_find(fresh_app, "grid").as(CrymbleUI::VirtualMatrix).scroll_offset = grid.scroll_offset
    fresh.settle_rendering(fresh_app)
    CrymbleUI::Testing::TestRenderBackend.census_take

    band = grid.viewport_bounds
    left, top = band.x.to_i, band.y.to_i
    header_h = (grid.sticky_row_height_pixels + grid.ruler_row_height_pixels).to_i
    header_w = (grid.sticky_col_width_pixels + grid.ruler_col_width_pixels).to_i
    (left...(left + band.width).to_i).step(3).each do |x| # the header rows
      (top...(top + header_h)).each { |y| renderer.backend.get_pixel(x, y).should eq(fresh.backend.get_pixel(x, y)) }
    end
    (left...(left + header_w)).each do |x| # the header columns
      (top...(top + band.height).to_i).step(3).each { |y| renderer.backend.get_pixel(x, y).should eq(fresh.backend.get_pixel(x, y)) }
    end
  end

  it "is released when a tab is switched away and a tree collapses" do
    app, renderer = brd_fixture
    tabs = brd_find(app, "tabs").as(CrymbleUI::Tabs)
    page_one = brd_find(app, "b0").widget_backend.should_not be_nil # instrument
    brd_release(app, renderer) do
      tabs.active = 1
      renderer.settle_rendering(app)
      page_one.disposed?.should be_true # the page switched away from released it
      leaf = brd_find(app, "t0").widget_backend.should_not be_nil # instrument
      brd_find(app, "tree").as(CrymbleUI::TreeNode).toggle # as its header click does
      renderer.settle_rendering(app)
      leaf.disposed?.should be_true # the collapsed node's leaf released it
    end
  end
end
