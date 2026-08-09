require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/testing/surface_leaks"
require "../../src/widgets/virtual_matrix"

# THE GENERAL INVARIANT: after a rebuild, no backend that the live tree can no longer reach may
# still be unreleased.
#
# spec/core/layer_hosted_backend_release_spec.cr pins the specific bug we shipped a fix for; this
# pins the CLASS. It deliberately knows nothing about where a widget was held — @children, a
# layer's widget list, a window's overlay list, or a container invented next year. It enumerates
# every backend created during the example, computes what the live tree can still reach, and
# requires the difference to be released.
#
# That framing is the lesson of the leak it was written after: the stranded surfaces belonged to
# VirtualMatrix cells, which live in `layer.widgets` and are therefore invisible to a teardown that
# walks `@children`. Any test that walked the widget tree would have been GREEN throughout. So this
# one walks the ALLOCATIONS instead and asks the live tree to account for them.
#
# Under SFML each unaccounted backend is a driver-side RenderTexture the collector cannot reclaim
# (16 shapes = ~484 MB of texture), so "unreachable but unreleased" is exactly the shape of an
# unbounded process.

private class CensusCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(
      constraints.max_width.finite? ? constraints.max_width : 80.0,
      constraints.max_height.finite? ? constraints.max_height : 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
        CrymbleUI::Color.new(70, 110, 150, 255))
    end
  end
end

private class CensusAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CensusCell.new
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...10).to_a, (0...4).to_a}
  end
end

# Several DIFFERENT kinds of holder in one tree, so the census is not accidentally specific to the
# one that leaked: layer-hosted matrix cells, plain @children, and a combo box (whose popup lives
# in the window's overlay list).
private class CensusApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property panels = 1

  def build : CrymbleUI::Widget
    n = @panels
    window("Census", 500, 400) do
      vstack do
        n.times do |i|
          window_panel("P#{i}", x: 10.0, y: 10.0, width: 300.0, height: 200.0, id: "p#{i}") do
            vstack do
              combo_box(items: ["a", "b"], width: 100.0, id: "cb#{i}") { |_i, _v| }
              widget(CrymbleUI::VirtualMatrix.new(CensusAdapter.new, id: "m#{i}"))
            end
          end
        end
      end
    end
  end
end

# Mirrors the structure that provably strands surfaces on a surviving layer: a WindowPanel sitting
# directly in the window (so the window's own layer is the survivor) with a matrix inside it. A
# reconcile builds a fresh Chrome for the panel and the old one lingers on that layer.
private class CensusPanelApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("CensusPanel", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        widget(CrymbleUI::VirtualMatrix.new(CensusAdapter.new, id: "grid"))
      end
    end
  end
end

# Reachability is computed by the library's own oracle (src/testing/surface_leaks.cr) rather than
# re-derived here: the criteria are subtle (the renderer's window buffer counts as an owner; a
# widget in a live layer's list does NOT unless its parent chain still reaches the root) and both
# were learned from false results on this spec's own first drafts. One definition, used by every
# leak hunt.

describe "unreachable backend census" do
  it "leaves no unreachable backend unreleased after the tree that owned it is discarded" do
    CrymbleUI::Testing::TestRenderBackend.census_start
    app = CensusApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    renderer.settle_rendering(app)

    app.panels = 0
    app.request_rebuild
    renderer.settle_rendering(app)

    created = CrymbleUI::Testing::TestRenderBackend.census_take
    # Non-vacuity: an empty or tiny census would make the invariant trivially true.
    created.size.should be > 10,
      "census recorded only #{created.size} backends — the fixture is not exercising the renderer"

    stranded = CrymbleUI::Testing::SurfaceLeaks.stranded(app.root.not_nil!, renderer, created)

    stranded.should be_empty,
      "#{stranded.size} of #{created.size} backends are UNREACHABLE from the live tree yet still " \
      "unreleased. Sizes: #{stranded.first(8).map { |b| "#{b.width}x#{b.height}" }.join(", ")}. " \
      "Under SFML each is a driver texture the collector cannot reclaim, so the process grows " \
      "for as long as the session lasts."
  end

  # The same invariant in the OTHER situation. Above, the tree that owned the backends was thrown
  # away wholesale and its layers went with it. Here the tree SURVIVES the rebuild — and so do its
  # layers — while individual widgets are replaced underneath them. A reconciled WindowPanel builds
  # a fresh Chrome and the old one lingers in the surviving layer's widget list until the orphan
  # sweep drops it; dropping it without releasing its surface strands a texture on a layer that is
  # very much alive. Measured before this was fixed: the sweep discarded Chrome widgets holding
  # live backends six times in a single existing spec.
  it "releases a widget dropped from a layer that SURVIVES the rebuild" do
    CrymbleUI::Testing::TestRenderBackend.census_start
    app = CensusPanelApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)

    # Rebuild repeatedly, keeping the panel: every pass replaces widgets under a surviving layer.
    # Two frames per rebuild rather than settle_rendering — that is the cadence under which the
    # stranding was observed, and settling to quiescence can hide it.
    3.times do
      app.request_rebuild
      renderer.render_frame(app)
      renderer.render_frame(app)
    end

    created = CrymbleUI::Testing::TestRenderBackend.census_take
    created.size.should be > 10,
      "census recorded only #{created.size} backends — the fixture is not exercising the renderer"

    stranded = CrymbleUI::Testing::SurfaceLeaks.stranded(app.root.not_nil!, renderer, created)

    stranded.should be_empty,
      "#{stranded.size} of #{created.size} backends were dropped from a SURVIVING layer without " \
      "being released. Sizes: #{stranded.first(8).map { |b| "#{b.width}x#{b.height}" }.join(", ")}. " \
      "This accumulates for the whole session — the layer never becomes orphaned, so nothing else " \
      "ever comes back for them."
  end

  it "does not release anything the live tree still reaches" do
    CrymbleUI::Testing::TestRenderBackend.census_start
    app = CensusApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    renderer.settle_rendering(app)

    # A rebuild that keeps the panel: whatever survives must still be usable.
    app.request_rebuild
    renderer.settle_rendering(app)

    CrymbleUI::Testing::TestRenderBackend.census_take
    live_root = app.root.not_nil!
    live = CrymbleUI::Testing::SurfaceLeaks.reachable(live_root, renderer)
    live.should_not be_empty, "the live tree holds no backends at all — the fixture proves nothing"

    # The other direction of the same invariant: reachable implies NOT released. A census that only
    # checked the unreachable half would pass an over-eager sweep that frees the live tree.
    disposed_live = [] of String
    walk = uninitialized CrymbleUI::Widget -> Nil
    walk = ->(w : CrymbleUI::Widget) do
      {w.widget_backend, w.background_backend}.each do |b|
        disposed_live << "#{w.class.name.split("::").last}##{w.path_id}" if b && b.disposed?
      end
      w.children.each { |c| walk.call(c) }
      nil
    end
    walk.call(live_root)
    disposed_live.should be_empty,
      "the live tree holds RELEASED backends (#{disposed_live.first(5).join(", ")}) — the next " \
      "draw would read freed memory"
  end
end
