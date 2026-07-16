require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/popup"
require "../../src/dsl/builder"

# Layer-discovery invariant guard.
#
# The render pass (LayerRenderer#collect_layers) and the compositor
# (Layer.active_layers, the @@all_layers registry filtered by in_tree?) must
# discover the SAME in-tree owned layers. If a widget owns a layer that
# collect_layers doesn't reach, its widget never renders into a backend and the
# layer is invisible — the exact failure that shipped for drag_overlay_layer.
#
# `active_layers` is registry-derived, INDEPENDENT of each_owned_layer, so it is
# a non-tautological oracle: a forgotten publish still appears in active_layers
# and trips the subset check.

# Detector: owns a REGISTERED layer it never publishes (no `layer` override, no
# each_owned_layer). Proves the subset guard discriminates a real miss.
private class UnpublishedLayerWidget < CrymbleUI::Widget
  getter my_layer : CrymbleUI::Layer?

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(10.0, 10.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(10.0, 10.0))
    @my_layer ||= CrymbleUI::Layer.new("unpublished_#{id}", @bounds, owner_widget: self)
  end
end

module CrymbleUI
  class LayerDiscoveryApp < App
    def build : Widget
      window("LayerDiscovery", 600, 400) do
        vstack do
          widget(VirtualMatrix.new(rows: 8, cols: 8, id: "vm"))
        end
        popup(x: 50.0, y: 50.0, id: "pop") do
          text("popup")
        end
      end
    end
  end

  class DetectorApp < App
    getter detector = UnpublishedLayerWidget.new(id: "det")

    def build : Widget
      window("Detector", 400, 300) do
        vstack do
          widget(detector)
        end
      end
    end
  end
end

# Every layer id prefix a default VirtualMatrix (+ its child ScrollView) must materialize.
private EXPECTED_LAYER_PREFIXES = %w[matrix_content cursor_overlay drag_overlay scrollbar sticky_row sticky_col sticky_corner]

describe "layer discovery invariant" do
  it "every in-tree registered layer is render-collected: active_layers ⊆ cached_layers" do
    app = CrymbleUI::LayerDiscoveryApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app.build_tree
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    cached = renderer.cached_layers.not_nil!
    cached_set = cached.to_set
    active = CrymbleUI::Layer.active_layers(root)
    active_ids = active.map(&.id)

    # (1) No vacuous pass: each expected layer type actually materialized.
    EXPECTED_LAYER_PREFIXES.each do |prefix|
      active_ids.any?(&.starts_with?(prefix)).should be_true, "no active layer with prefix '#{prefix}' — guard would pass vacuously"
    end
    # ...and the popup's overlay layer is present (exercises the overlays path).
    active_ids.any?(&.includes?("pop")).should be_true

    # (2) The invariant: no registered in-tree layer is uncollected.
    active.each do |layer|
      cached_set.includes?(layer).should be_true, "active layer '#{layer.id}' is NOT render-collected → would be invisible"
    end

    # (3) Composite-once: the collected set has no duplicate layer objects.
    cached.size.should eq(cached_set.size)
  end

  it "each_owned_layer yields only auxiliary layers, never the primary, pairwise-distinct" do
    app = CrymbleUI::LayerDiscoveryApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("vm").as(CrymbleUI::VirtualMatrix)
    primary = vm.layer
    aux = [] of CrymbleUI::Layer
    vm.each_owned_layer { |l| aux << l }

    aux.each { |l| l.should_not be(primary) } # never the primary (content_layer)
    aux.uniq(&.object_id).size.should eq(aux.size) # pairwise distinct
    aux.map(&.id).any?(&.starts_with?("cursor_overlay")).should be_true
    aux.map(&.id).any?(&.starts_with?("drag_overlay")).should be_true
  end

  it "the subset guard discriminates a registered-but-unpublished layer (non-vacuous)" do
    app = CrymbleUI::DetectorApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app.build_tree
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    det_layer = app.detector.my_layer.not_nil!
    active = CrymbleUI::Layer.active_layers(root)
    cached_set = renderer.cached_layers.not_nil!.to_set

    active.includes?(det_layer).should be_true    # registered + in-tree
    cached_set.includes?(det_layer).should be_false # never published → uncollected
  end
end
