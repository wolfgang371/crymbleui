require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# The MatrixAdapter invalidation contract at reconcile.
#
# Two exact rules replace the old dims-equality clear heuristic in copy_state_from:
#   1. CLEAR is governed by adapter IDENTITY + the announce contract: a swapped-in adapter
#      instance always clears every VM layer (it has no announce history — deliberate
#      heuristic default); a same-instance structural change must have been ANNOUNCED via
#      invalidate_all! before the rebuild — an unannounced dims drift is a contract
#      violation (raises under -Dverify_bounds; release: STDERR warning + self-heal
#      through the pending-invalidation flush).
#   2. The SIZE-CARRY (user drag-resize state) stays dims-gated and identity-INDEPENDENT —
#      exactly the pre-contract semantics. It is UX-state preservation, not the invariant's
#      guard; fresh-adapter-per-build apps (DSL matrix sugar, DirBrowser) keep their
#      resize state while still getting the correctness clear.
#
# The reconcile canary sees DIMS-drifting violations only: a same-dims structural change
# (the consumer's ghost-separator class — merged spans splitting at constant grid size) is
# invisible at reconcile time. That protection is the announce itself plus the consumer's
# cache-validation scenario.
#
# Oracles are logic-level: content-layer clear_rev + TestRenderBackend#clear_count +
# backend identity (clear_rev alone is one-sided — render_layer's full_render path clears
# without bumping it). Sticky layers are NOT used as oracles here: perform_layout clears
# them unconditionally on every layout, so they are green noise for these cases.

private class ContractAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  property row_count_val : Int32
  property col_count_val : Int32

  def initialize(@row_count_val : Int32, @col_count_val : Int32)
  end

  def row_count : Int32
    @row_count_val
  end

  def col_count : Int32
    @col_count_val
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# The held-adapter model: ONE adapter instance kept across rebuilds.
private class ContractHeldAdapterApp < CrymbleUI::App
  getter held_adapter : ContractAdapter = ContractAdapter.new(30, 12)

  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(@held_adapter, id: "contract_grid")
  end
end

# The DSL-sugar/DirBrowser model: a NEW adapter instance on every build.
private class ContractFreshAdapterApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(ContractAdapter.new(30, 12), id: "contract_grid")
  end
end

# Ruler-strip drag geometry (same derivation as virtual_matrix_resize_spec, private to
# this file): col border n sits at ruler_col_width + col_width_pixels * (n+1).
private CONTRACT_COL_BORDER_0 = 40.0 + 103.0

private def contract_setup(app : CrymbleUI::App)
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
  {renderer, matrix}
end

private def content_backend(matrix : CrymbleUI::VirtualMatrix) : CrymbleUI::Testing::TestRenderBackend
  matrix.content_layer.not_nil!.backend.as(CrymbleUI::Testing::TestRenderBackend)
end

# This file provokes the contract violation on purpose and asserts the SELF-HEAL, not the message.
# Silenced here only, so a genuine violation in another spec still shows up.
Spec.before_each { CrymbleUI::Widget.enable_warnings = false }
Spec.after_each { CrymbleUI::Widget.enable_warnings = true }

describe "VirtualMatrix reconcile adapter contract", tags: "slow" do
  # (a) A swapped-in adapter has no announce history: the buffer's pixels were painted
  # under an adapter this instance knows nothing about — they must be cleared even when
  # the grid DIMENSIONS happen to match (the old heuristic's blind spot).
  it "(a) adapter swap with equal dims clears the content buffer" do
    app = ContractFreshAdapterApp.new
    renderer, matrix = contract_setup(app)
    layer = matrix.content_layer.not_nil!
    backend = content_backend(matrix)
    backend.reset_counters
    rev_before = layer.clear_rev

    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_layer = new_matrix.content_layer.not_nil!
    # Same content size → the carried layer keeps its backend; the oracle counts on it.
    content_backend(new_matrix).should be backend
    new_layer.clear_rev.should be > rev_before
    backend.clear_count.should be > 0
  end

  # (b) An announced same-instance structural change is the contract kept — it must never
  # trip the violation path, in either legal ordering.
  it "(b1) same-instance announced dims change, rebuild before the flush frame" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)
    matrix.cols.should eq 12

    app.held_adapter.col_count_val = 11
    app.held_adapter.invalidate_all!
    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cols.should eq 11
  end

  it "(b2) same-instance announced dims change, flushed frame before the rebuild" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)

    app.held_adapter.col_count_val = 10
    app.held_adapter.invalidate_all!
    renderer.settle_rendering(app) # flush consumes the announce, re-reads dims on the old instance

    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cols.should eq 10
  end

  # (c) An UNANNOUNCED same-instance dims change is the contract broken.
  {% if flag?(:verify_bounds) %}
  it "(c) unannounced same-instance dims change raises under -Dverify_bounds" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)

    app.held_adapter.col_count_val = 10 # no invalidate_all! — the violation
    expect_raises(Exception, /invalidate_all!/) do
      app.rebuild
    end
  end
  {% else %}
  it "(c) unannounced same-instance dims change self-heals in release" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)
    backend = content_backend(matrix)
    backend.reset_counters
    rev_before = matrix.content_layer.not_nil!.clear_rev

    app.held_adapter.col_count_val = 10 # no invalidate_all! — the violation
    app.rebuild
    # Rendering after the rebuild is the crash guard: a stale-length size-carry would
    # raise IndexError in the layout/render walk below.
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cols.should eq 10
    # Oracle self-validation: the carried layer must keep its backend (both configs
    # overflow the viewport → same content-area size), else clear_count counts nothing.
    content_backend(new_matrix).should be backend
    new_matrix.content_layer.not_nil!.clear_rev.should be > rev_before
    backend.clear_count.should be > 0 # degraded through the flush → buffer repaired
  end
  {% end %}

  # (d) The cheap-rebuild property: a no-change rebuild on a held adapter keeps the buffer.
  it "(d) same-instance no-change rebuild keeps the content buffer" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)
    layer = matrix.content_layer.not_nil!
    backend = content_backend(matrix)
    backend.reset_counters
    rev_before = layer.clear_rev

    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    content_backend(new_matrix).should be backend
    new_matrix.content_layer.not_nil!.clear_rev.should eq rev_before
    backend.clear_count.should eq 0
  end

  # (e) Fresh-adapter-per-build consumers: the clear fires on every rebuild (rule 1) AND
  # the dims-gated size-carry still preserves their drag-resize state (rule 2) — the two
  # axes are independent.
  it "(e) fresh-adapter rebuild clears the buffer and keeps carried column widths" do
    app = ContractFreshAdapterApp.new
    renderer, matrix = contract_setup(app)

    app.handle_mouse_down(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0, 10.0))
    app.handle_mouse_move(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0 + 40.0, 10.0))
    renderer.render_frame(app)
    app.handle_mouse_up(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0 + 40.0, 10.0))
    renderer.render_frame(app)

    matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    pos_after_resize = matrix.cell_screen_position(0, 1).x
    backend = content_backend(matrix)
    backend.reset_counters

    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cell_screen_position(0, 1).x.should eq pos_after_resize
    backend.clear_count.should be > 0
  end

  # (f) The mid-drag carry: a rebuild landing between mouse_down and mouse_up must keep
  # the in-flight width (adapter-side persistence only happens at mouse_up).
  it "(f) mid-drag rebuild keeps the in-flight column width" do
    app = ContractHeldAdapterApp.new
    renderer, matrix = contract_setup(app)

    app.handle_mouse_down(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0, 10.0))
    app.handle_mouse_move(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0 + 40.0, 10.0))
    renderer.render_frame(app)

    matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    pos_mid_drag = matrix.cell_screen_position(0, 1).x

    app.rebuild
    renderer.settle_rendering(app)

    new_matrix = app.find("contract_grid").as(CrymbleUI::VirtualMatrix)
    new_matrix.cell_screen_position(0, 1).x.should eq pos_mid_drag

    app.handle_mouse_up(CrymbleUI::Vec2.new(CONTRACT_COL_BORDER_0 + 40.0, 10.0))
  end
end
