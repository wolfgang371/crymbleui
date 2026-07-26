require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Headless twin for the retired zoom_virtual_matrix_autotest (scroll-offset residue).
#
# copy_state_from preserves @last_zoom_factor across a rebuild (virtual_matrix.cr:2328)
# so the reconciled matrix does NOT see a false 1.0 -> Z transition on its first
# perform_layout. A fresh instance defaults @last_zoom_factor = 1.0; if the transfer is
# missing, handle_zoom_change (perform_layout, line 850) reads current_zoom = Z != 1.0
# and scales scroll_offset *= Z (line 891) — a residue that survives later zoom cycles.
#
# The symptom is INVISIBLE unless scroll_offset is non-zero AND zoom != 1.0 (offset *= Z
# is 0 at offset 0, and identity at Z == 1). We pin both preconditions, capture the
# post-zoom baseline S, rebuild (reconcile), run two net-zero zoom cycles, and assert
# the offset SURVIVED (== S). Plus a re-render disposition check (no pixels): the content
# layer is active after the rebuild and cells were recreated with their correct texts.
# DSL app holding a STABLE adapter instance (same identity across builds → reconcile
# carries state rather than clearing on an adapter swap). MergeableTestAdapter paints
# Text("row,col") cells, so a recreated cell's text is exactly checkable.
class ZoomReconcileDSLApp < CrymbleUI::App
  property adapter : MergeableTestAdapter = MergeableTestAdapter.new(100, 30)

  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(@adapter, id: "zoom_reconcile")
  end
end

describe "VirtualMatrix zoom-reconcile scroll-offset survival", tags: "slow" do
  it "preserves scroll_offset across a DSL rebuild + zoom cycles (no false 1.0->Z scale)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ZoomReconcileDSLApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("zoom_reconcile").as(CrymbleUI::VirtualMatrix)

    # PRECONDITION 1: non-zero scroll offset.
    matrix.scroll_offset = CrymbleUI::Vec2.new(150.0, 300.0)
    renderer.render_frame(app)
    offset0 = matrix.scroll_offset
    offset0.x.should be > 0.0
    offset0.y.should be > 0.0

    # PRECONDITION 2: zoom != 1.0. Zooming in scales the offset once (legitimately); that
    # scaled value is our baseline S for the rest of the test.
    3.times { CrymbleUI::FontSizing.zoom_in }
    renderer.render_frame(app)
    CrymbleUI::FontSizing.zoom_factor.should_not eq(1.0)
    s = matrix.scroll_offset
    s.x.should be > 0.0
    s.y.should be > 0.0

    # Drive a DSL rebuild → reconcile (copy_state_from on a fresh matrix instance).
    app.rebuild
    renderer.settle_rendering(app)
    matrix = app.find("zoom_reconcile").as(CrymbleUI::VirtualMatrix)

    # Two net-zero zoom cycles (out then back in to the starting zoom). These telescope
    # exactly, so a correct offset returns to S; the false-transition residue does not.
    2.times { CrymbleUI::FontSizing.zoom_out }
    renderer.render_frame(app)
    2.times { CrymbleUI::FontSizing.zoom_in }
    renderer.render_frame(app)

    # (1) scroll_offset SURVIVED — the residue would leave it scaled by the zoom factor.
    matrix.scroll_offset.x.should be_close(s.x, 1.0),
      "scroll_offset.x drifted: #{matrix.scroll_offset.x} vs baseline #{s.x} (false zoom-transition residue)"
    matrix.scroll_offset.y.should be_close(s.y, 1.0),
      "scroll_offset.y drifted: #{matrix.scroll_offset.y} vs baseline #{s.y} (false zoom-transition residue)"

    # (2) re-render DISPOSITION (no pixels): content layer active + cells recreated valid.
    content_layer = matrix.content_layer.not_nil!
    CrymbleUI::Layer.active_layers(app.root.not_nil!).includes?(content_layer).should be_true

    matrix.active_cell_count.should be > 0
    matrix.active_cells.each do |key, widget|
      cell = widget.as?(CrymbleUI::Text)
      cell.should_not be_nil, "cell #{key} is not a Text after rebuild"
      cell.not_nil!.text.should eq("#{key[0]},#{key[1]}"),
        "cell #{key} has wrong text #{cell.not_nil!.text.inspect} after rebuild"
    end
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end
end
