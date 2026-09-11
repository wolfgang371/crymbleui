require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# WHAT THE PLACEMENT PASS COSTS PER FRAME, with a budget on it.
#
# `docs/PLACEMENT_CASES.md` named a `cache_perf_baseline_spec` as the perf guard for UC-13; no such
# file exists in this repo, so the claim was unguarded prose. This is the guard.
#
# The rule is O(1) per visible cell and allocates nothing, but it grew several terms over
# 2026-09-08..11 and "it should still be cheap" is not a measurement. Both numbers are printed
# because the second is the pessimistic one: `update_ink_regions` assigns a region to every active
# cell each frame, but only the cells that can be SEEN are marked for repaint (I7), so the
# `to_primitives`-for-everything figure is a ceiling nobody pays.
describe "placement cost" do
  it "places ~400 cells per frame well inside a frame budget" do
    adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 40, 12)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "perf")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 600)
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 600.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    matrix.auto_size = true
    matrix.pre_render_flush

    cells = matrix.active_cells.size
    # the pass itself, over a scroll — every carrier changes, so nothing is skipped as unchanged
    started = Time.instant
    frames = 400
    frames.times { |i| matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64); matrix.pre_render_flush }
    per_frame = (Time.instant - started).total_milliseconds / frames

    # and the rule alone, called once per visible cell per frame
    placements = 0
    started2 = Time.instant
    frames.times do |i|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, i.to_f64)
      matrix.pre_render_flush
      matrix.active_cells.each { |_k, w| w.to_primitives(w.bounds); placements += 1 }
    end
    with_paint = (Time.instant - started2).total_milliseconds / frames

    puts "\n  [perf] #{cells} active cells | pre_render_flush #{per_frame.round(3)} ms/frame | " \
         "+ to_primitives for every cell #{with_paint.round(3)} ms/frame (#{placements // frames}/frame)"
    # 0.363 ms measured on 2026-09-11 for 397 cells. The budget is an ORDER of magnitude above it,
    # because this runs on whatever machine CI gives it: what it catches is a term that turns the
    # pass super-linear or starts allocating, not a 20% drift.
    per_frame.should be < 4.0,
      "the placement pass cost #{per_frame.round(3)} ms/frame for #{cells} cells"
    with_paint.should be < 40.0,
      "repainting every cell cost #{with_paint.round(3)} ms/frame for #{cells} cells"
  end
end
