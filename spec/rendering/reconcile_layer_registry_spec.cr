require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/virtual_matrix"
require "../../src/dsl/builder"

# Reconcile must not leave STALE owned layers in Layer.@@all_layers, nor create a
# fresh layer per rebuild.
#
# Own-layer widgets (WindowPanel, LayerBox, Popup) create their compositing layer
# LAZILY in perform_layout (@x ||= Layer.new), never in the constructor. So a
# reconciled instance's @internal_layer is nil at copy_state_from and the carried
# @[Reconcile] layer is simply reused — there is no constructor layer to displace,
# hence no leak and no per-rebuild create+dispose churn. adopt_reconciled_layer
# re-points the carried layer's owner to the live instance; assert_no_constructor_layer
# guards that no widget ever regresses to constructor creation.

module CrymbleUI
  class PanelReconcileApp < App
    state tick : Int32 = 0

    def build : Widget
      window("W", 400, 300) do
        window_panel("P", x: 10.0, y: 10.0, width: 120.0, height: 120.0, id: "p") do
          text("hi #{tick}")
        end
      end
    end
  end

  class MatrixReconcileApp < App
    state tick : Int32 = 0

    def build : Widget
      window("W", 500, 400) do
        vstack do
          text("t #{tick}")
          widget(VirtualMatrix.new(rows: 6, cols: 6, id: "vm"))
        end
      end
    end
  end
end

describe "reconcile layer registry hygiene" do
  it "does not leak a stale constructor layer across rebuilds (WindowPanel)" do
    CrymbleUI::Layer.clear_registry
    app = CrymbleUI::PanelReconcileApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app.build_tree
    renderer.settle_rendering(app)
    baseline = CrymbleUI::Layer.registry_size # window root_layer + the one panel layer

    3.times do |i|
      app.tick = i + 1
      app.rebuild
      renderer.settle_rendering(app)
    end

    root = app.root.not_nil!
    panels = CrymbleUI::Layer.active_layers(root).count(&.id.starts_with?("panel_"))
    panels.should eq(1) # exactly the one live panel layer; no stale duplicate
    # The literal leak: reconcile must not GROW @@all_layers. With lazy creation the
    # carried layer is reused (nothing is displaced), so the registry stays flat.
    CrymbleUI::Layer.registry_size.should eq(baseline)
  end

  # VirtualMatrix calls auto_copy THEN super → auto_copy runs TWICE per reconcile.
  # Guards that the DOUBLE pass leaves the live content layer registered: pass 2 sees
  # current == incoming == the already-carried layer, which assert_no_constructor_layer's
  # same? check tolerates, and adopt keeps its owner pointed at the live instance.
  it "keeps a carried layer registered under the double auto_copy (VirtualMatrix)" do
    CrymbleUI::Layer.clear_registry
    app = CrymbleUI::MatrixReconcileApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app.build_tree
    renderer.settle_rendering(app)

    3.times do |i|
      app.tick = i + 1
      app.rebuild
      renderer.settle_rendering(app)
    end

    root = app.root.not_nil!
    vm = app.find("vm").as(CrymbleUI::VirtualMatrix)
    content = vm.content_layer.not_nil!
    active = CrymbleUI::Layer.active_layers(root)
    active.includes?(content).should be_true # the live content layer must stay registered
    # and no stale content duplicates from earlier rebuilds
    active.count(&.id.starts_with?("matrix_content_")).should eq(1)
  end
end
