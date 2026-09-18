require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# A LAYER IS PAINTED BY ITS CELLS PLUS ITS CLEAR, AND THE GRID LINES ARE THE CLEAR'S SHARE.
#
# row_height_pixels is `grid_spacing + content` (virtual_matrix.cr:2851) while the cell is laid out
# at `row_sizes[row] - grid_spacing` (sticky_reposition.cr:145, blit_plan.cr:217). So between every
# pair of rows there is a grid_spacing strip that NO cell ever paints. It is the layer's clear that
# keeps those strips clean, which makes "was the layer cleared?" a question with visible consequences
# rather than a bookkeeping detail.
#
# THE FAULT (Wolfgang, 2026-09-16, screenshot and then his own -Dprobe log): drag the scrollbar thumb
# quickly to the bottom and quickly back to the very top, and the rank column shows each number with
# remnants of other numbers under it. His log caught it exactly - rows 438..454 became rows 0..19 in
# one frame, and twenty frames later the strips between the new cells still held the old rows' glyph
# pixels (grey 85,85,85 and text 204,204,204 where the clear colour is 26,26,26).
#
# WHY NOTHING CLEARED. A jump that large does not MOVE sticky cells, it destroys and recreates them:
#   - reposition_sticky_cells only clears `if any_changed`, and nothing moved, so any_changed is
#     false (his log: "reposition pass ran, any_changed=false");
#   - the blit path DOES clear the buffer, but sticky_cells_can_use_blit_plan? requires at least one
#     sticky cell with a cached widget_backend, and every cell is brand new, so it bails;
#   - update_visible_cells then calls sync_cells_to_layers(new_cells), which marks only the NEW cells
#     for render (virtual_matrix.cr:2714).
# Each new cell paints its own box. Nothing paints the strips. The old ink stays.
#
# This is NOT specific to headers or clusters: grid_spacing sits between every row and every column.
# It shows on the STICKY layers because they are the ones whose repaint can skip the clear.
class StickyJumpAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Row 0 and col 0 scroll out LAST, i.e. they are the sticky header and the sticky column.
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# TestVisibleCell fills its whole box with this and nothing else does, so a pixel of this colour
# outside every cell box is ink a cell left behind.
CELL_INK = CrymbleUI::Color.new(45, 50, 55, 255)

private def sticky_col_ink_outside_cells(matrix, renderer) : Array(Tuple(Int32, Int32))
  sv = matrix.content_scroll_view.not_nil!
  layer = sv.sticky_col_layer.not_nil!
  # `.as(TestRenderBackend)`, not the bare union: get_pixel exists only on the headless backend, and
  # `layer.backend` is typed (CrSFMLBackend | TestRenderBackend). Crystal 1.21 let the call through;
  # `latest`, which CI compiles with, rejects it — so this spec passed here and broke the public CI
  # build. The same cast is the established idiom in virtual_matrix/drag_highlight_spec.cr.
  backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
  vm_abs = matrix.absolute_bounds
  dx = vm_abs.x - layer.bounds.x
  dy = vm_abs.y - layer.bounds.y

  # Where each widget on the layer lands in buffer coordinates, by the arithmetic the blit uses
  # (blit_plan.cr:177-178): dest = PixelSnap.origin(vm_abs + widget.bounds - layer.bounds).
  boxes = layer.widgets.map do |w|
    b = w.bounds
    ox = CrymbleUI::PixelSnap.origin(dx + b.x)
    oy = CrymbleUI::PixelSnap.origin(dy + b.y)
    {ox, oy,
     CrymbleUI::PixelSnap.origin(dx + b.x + b.width) - ox,
     CrymbleUI::PixelSnap.origin(dy + b.y + b.height) - oy}
  end

  # Only the part of the buffer that is actually displayed: the texture is routinely larger.
  w = {backend.width, CrymbleUI::PixelSnap.origin(layer.bounds.width)}.min
  h = {backend.height, CrymbleUI::PixelSnap.origin(layer.bounds.height)}.min

  found = [] of Tuple(Int32, Int32)
  y = 0
  while y < h
    x = 0
    while x < w
      unless boxes.any? { |(bx, by, bw, bh)| x >= bx && x < bx + bw && y >= by && y < by + bh }
        if px = backend.get_pixel(x, y)
          found << {x, y} if px.r == CELL_INK.r && px.g == CELL_INK.g && px.b == CELL_INK.b
        end
      end
      x += 1
    end
    y += 1
  end
  found
end

describe "VirtualMatrix sticky column, jumped in one frame" do
  it "leaves no cell ink in the grid-spacing strips after every sticky cell is recreated at once" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(StickyJumpAdapter.new(600, 8), id: "sticky_jump")
    app.root_widget = matrix
    app.build_tree
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Away, far enough that not one of the sticky cells now on screen survives the trip back, and to
    # an offset that is deliberately NOT a whole number of rows: the old cells then straddle the row
    # grid the new ones will land on, so their ink covers the strips between them.
    # Only the SCROLLING part of the sticky column: row 0 is the sticky header row and never
    # leaves, so including it would put row 0 in both sets and the check below could never hold.
    scrolling_sticky = ->(m : CrymbleUI::VirtualMatrix) do
      m.active_cells.keys.select { |k| k[1] < m.sticky_col_count && k[0] >= m.sticky_row_count }
        .map { |k| k[0] }.to_set
    end
    rows_before = scrolling_sticky.call(matrix)
    # Through the WHEEL, not through `matrix.scroll_offset =`. The property setter calls
    # apply_scroll directly; the real gesture goes ScrollView -> sync_from_scroll_view, which DEFERS
    # the cell create/destroy to pre_render_flush — and that deferred frame is where the fault lives.
    # One event of this size is a thumb slammed across the track, not a wheel roll.
    mb = matrix.absolute_bounds
    centre = CrymbleUI::Vec2.new(mb.x + mb.width / 2, mb.y + mb.height / 2)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -134.0), centre)
    renderer.settle_rendering(app)
    rows_away = scrolling_sticky.call(matrix)

    # Instrument check: the trip really does replace every sticky cell, which is the precondition
    # for the fault. If these sets overlapped, cells would MOVE and the reposition path would clear.
    rows_before.empty?.should be_false
    (rows_before & rows_away).empty?.should be_true

    # ...and back to the very top in ONE step, the way a thumb slammed into the end stop arrives.
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 500.0), centre)
    renderer.settle_rendering(app)

    stale = sticky_col_ink_outside_cells(matrix, renderer)
    stale.should be_empty
  end
end
