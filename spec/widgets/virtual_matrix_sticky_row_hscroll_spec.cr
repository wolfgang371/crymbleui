require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Repro for Wolfgang's scrollbar/ruler desync (2026-05-30, confirmed from a live buffer dump):
# When EVERY data row is sticky (sticky_rows >= 1, sticky_cols = 0 — the [Commits] trend view with a
# single sticky row), horizontally scrolling by LESS THAN ONE COLUMN leaves the sticky-row cells at
# their scroll-0 positions while the ruler scrolls. Root cause: reposition_sticky_cells positions
# sticky cells from the CACHED @viewport_col_positions (scroll-independent; recomputed only when a
# whole column crosses the viewport boundary) and drops the sub-column term (scroll − col_offset).

class SRHAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  # ONE row, and it's sticky → the content layer is empty (matches Wolfgang's [Commits] single row).
  # Column 1 is hugely wide (the widened c2) so the content barely overflows the wide viewport →
  # all scrolling stays within column 0 (sub-column).
  def initialize(@rows : Int32 = 1, @cols : Int32 = 4)
    self.custom_col_widths = [5.0, 45.0, 5.0, 5.0]
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # row 0 sticky (tail of row scroll order); NO sticky columns, but a NON-NATURAL column scroll
    # order (the [Commits] view sorts columns) so scroll_order[0] is a high index → shifting_index>0
    # → cols below it hit the cached-position branch.
    {(1...@rows).to_a + [0], [3, 0, 1, 2]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

class SRHApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(SRHAdapter.new, id: "m")
  end
end

describe "VirtualMatrix — sticky-row cells must follow a sub-column horizontal scroll" do
  it "a sticky-row cell scrolls left by the (sub-column) scroll amount, matching the ruler" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1100, 240)
    app = SRHApp.new
    app.build_tree
    renderer.settle_rendering(app)
    m = app.find("m").as(CrymbleUI::VirtualMatrix)

    m.sticky_row_count.should eq(1) # row 0 is sticky
    m.sticky_col_count.should eq(0)

    # The sticky-row cell (0,2) at scroll 0.
    cell = m.active_cells[{0, 2}]?
    cell.should_not be_nil
    x0 = cell.not_nil!.bounds.x

    # Scroll horizontally by LESS than one column width (col_width_pixels ≈ 103) so no whole column
    # crosses the boundary → the StickyMath cache key does not change. Horizontal wheel = Y delta + shift.
    center = CrymbleUI::Vec2.new(m.absolute_bounds.x + 200.0, m.absolute_bounds.y + 120.0)
    m.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
    renderer.render_frame(app)

    dx = m.scroll_offset.x
    dx.should be > 1.0                  # we actually scrolled
    dx.should be < 100.0                # ...by less than one column (sub-column → cache key unchanged)

    cell_after = m.active_cells[{0, 2}]?
    cell_after.should_not be_nil
    x1 = cell_after.not_nil!.bounds.x

    # The sticky-row cell must move LEFT by ~dx (it follows the content/ruler). Before the fix it
    # stayed put (x1 == x0) because the cached viewport position dropped the sub-column scroll.
    (x0 - x1).should be_close(dx, 2.0),
      "sticky-row cell (0,2) moved by #{(x0 - x1).round(1)}px for a #{dx.round(1)}px scroll (expected ~#{dx.round(1)}) " \
      "— it stayed frozen at the scroll-0 position while the ruler scrolled."
  end
end
