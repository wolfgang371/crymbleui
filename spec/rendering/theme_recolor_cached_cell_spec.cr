require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# A Theme.set must recolor a CACHED matrix cell with no rebuild.
#
# FINDING (investigated): the simple cached-primitives fix — add `widget_backend_rev_fresh?`
# (@last_rendered_rev == primitive_cache_rev) to the viewport_cache fast path at layer_renderer.cr:992
# — is NECESSARY but NOT SUFFICIENT. Selective rendering only VISITS dirty cells, so on a partial
# render (edit one cell) the other cells are never reached by the fast-path check and keep their stale
# buffer pixels (measured: frame_widget_count=1, not 75). A full render (mark_needs_layout, what
# Ctrl+Shift+T does) visits more but not cleanly all (measured: 57/75 with that check).
#
# Recoloring the WHOLE matrix buffer on a theme swap — including non-dirty, non-visited slots — needs
# PER-SLOT BUFFER keying: the buffer re-blits a slot iff slot_rev != {widget primitive-cache key,
# pos}, so a global theme_rev bump invalidates every slot. So the recolor lands with the cached-primitives
# key PLUS per-slot buffer keying, not the cached-primitives key alone; the assertion below is the target contract.
#
# (Today the Ctrl+Shift+T toggle still recolors via mark_needs_layout re-rendering existing instances;
# this is about the version-keyed path doing it without forcing a full relayout.)

private class P2MatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    20
  end

  def col_count : Int32
    5
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

private def lr
  CrymbleUI::LayerRenderer
end

describe "theme swap recolors cached matrix cells" do
  it "re-renders non-dirtied cached cells after a theme swap (per-slot keyed on node.version)" do
    CrymbleUI::Theme.set(:light)
    matrix = CrymbleUI::VirtualMatrix.new(P2MatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}
    renderer.settle_rendering(app)

    # On-SCREEN cells (the viewport), not active_cells — the latter includes the off-buffer creation
    # margin (150px) which is never rendered into the viewport_cache buffer, so it would overcount.
    vis = matrix.visible_cell_indices
    visible = vis[:rows].size * vis[:cols].size

    # Swap theme, then a PARTIAL render (edit one cell). Every visible cell must recolor because
    # theme_rev moved every slot's primitive-cache key — NOT fast-path the stale light buffer pixels.
    CrymbleUI::Theme.set(:dark)
    renderer.reset_counters
    lr.reset_frame_counters
    CrymbleUI::Widget.focus_manager.handle_text_input('X')
    renderer.render_frame(app)

    lr.frame_widget_count.should be >= visible
  ensure
    CrymbleUI::Theme.set(:light)
  end
end
