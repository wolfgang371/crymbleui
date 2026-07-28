require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/virtual_matrix"

# A widget standing on a discarded LAYER must have its backends released.
#
# This is the headless mirror of spec/autotest/backend_leak_rss_autotest.cr, and it exists because
# of how that leak evaded us: a layer-hosted widget falls through BOTH teardown nets. It is not in
# any parent's @children, so dispose_subtree cannot reach it (VirtualMatrix cells live in
# layer.widgets); and Layer.cleanup_orphaned_layers released only the layer's OWN surface, leaving
# every per-widget surface standing on it stranded. Under SFML those are driver-side textures the
# collector cannot see, so the process just grew — 16 panels leaked 160 textures per open/close
# cycle with the floor rising monotonically and never returning.
#
# Headless cannot reproduce the memory symptom at all (a TestRenderBackend's payload is an ordinary
# Crystal array the collector reclaims by itself, which is exactly why several headless-derived fix
# attempts measured as no-ops). So this asserts the STRUCTURAL fact underneath the symptom —
# "release was called on the discarded widget's backends" — which is deterministic, fast, and true
# on both backends. The SFML autotest remains the witness that release actually frees driver memory.

private class ReleaseCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(
      constraints.max_width.finite? ? constraints.max_width : 80.0,
      constraints.max_height.finite? ? constraints.max_height : 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  # Must paint something: a widget with no primitives is skipped by the renderer and never gets a
  # backend, which would make the assertions below vacuous.
  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
        CrymbleUI::Color.new(30, 90, 160, 255))
    end
  end
end

private class ReleaseAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    ReleaseCell.new
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...12).to_a, (0...4).to_a}
  end
end

private class LayerHostApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property panels = 1

  def build : CrymbleUI::Widget
    n = @panels
    window("LayerHosted", 500, 400) do
      vstack do
        n.times do |i|
          window_panel("P#{i}", x: 10.0, y: 10.0, width: 300.0, height: 200.0, id: "p#{i}") do
            widget(CrymbleUI::VirtualMatrix.new(ReleaseAdapter.new, id: "m#{i}"))
          end
        end
      end
    end
  end
end

# Every backend held by a widget standing on a layer, including its @children subtree.
private def layer_hosted_backends(root : CrymbleUI::Widget) : Array(CrymbleUI::RenderBackend)
  found = [] of CrymbleUI::RenderBackend
  CrymbleUI::Layer.active_layers(root).each do |layer|
    layer.widgets.each { |w| collect_backends(w, found) }
  end
  found
end

private def collect_backends(w : CrymbleUI::Widget, into : Array(CrymbleUI::RenderBackend))
  w.widget_backend.try { |b| into << b }
  w.background_backend.try { |b| into << b }
  w.children.each { |c| collect_backends(c, into) }
end

describe "layer-hosted backend release" do
  it "releases the backends of widgets standing on a layer that is discarded" do
    app = LayerHostApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    renderer.settle_rendering(app)

    held = layer_hosted_backends(app.root.not_nil!)
    # Non-vacuity: if the fixture never put a rendered widget on a layer, "all released" would be
    # trivially true and the spec would pin nothing.
    held.should_not be_empty,
      "fixture produced no layer-hosted backends — it cannot witness the release defect"
    held.none?(&.disposed?).should be_true,
      "backends were already disposed while still live — the fixture is measuring the wrong thing"

    # Drop the panel: its content layer becomes orphaned, taking every cell standing on it.
    app.panels = 0
    app.request_rebuild
    renderer.settle_rendering(app)

    leaked = held.reject(&.disposed?)
    leaked.should be_empty,
      "#{leaked.size} of #{held.size} layer-hosted backends were never released — under SFML each " \
      "is a driver-side texture the collector cannot reclaim, so the process grows on every " \
      "open/close cycle"
  end

  it "leaves the backends of a layer that SURVIVES the rebuild untouched" do
    app = LayerHostApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    renderer.settle_rendering(app)

    # A rebuild that keeps the panel must not release anything the live tree still draws with.
    app.request_rebuild
    renderer.settle_rendering(app)

    live = layer_hosted_backends(app.root.not_nil!)
    live.should_not be_empty, "the live tree lost its layer-hosted backends entirely"
    live.count(&.disposed?).should eq(0),
      "the sweep disposed a backend the LIVE tree still holds — next draw reads freed memory"
  end
end
