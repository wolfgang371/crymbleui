require "../spec_helper"
require "../../src/layout/recursive_grid"
require "../../src/layout/vstack"
require "../../src/layout/hstack"
require "../../src/widgets/button"

# Helper: button with consistent padding=5 for predictable sizing.
# At zoom 1.0, font_scale 0: font_size=14.0
# TestFont: width = chars * 14.0 * 0.6, height = 14.0
# Button: total = text + 2*padding
# "A" (1 char): width=8.4+10=18.4, height=14+10=24.0
# "B1" (2 chars): width=16.8+10=26.8, height=24.0
private def btn5(label : String) : CrymbleUI::Button
  CrymbleUI::Button.new(label, padding: 5.0)
end

private def make_sub(content : Array(Array(CrymbleUI::Widget))) : CrymbleUI::RecursiveGrid
  sub = CrymbleUI::RecursiveGrid.new(content: content, spacing: 6.0)
  sub.border_color = CrymbleUI::Color.new(200, 50, 50, 255)
  sub
end

private def btn(text : String) : CrymbleUI::Button
  CrymbleUI::Button.new(text, padding: 5.0)
end

private def assert_child_fills(sub : CrymbleUI::RecursiveGrid, child : CrymbleUI::Widget)
  child.bounds.x.should be_close(6.0, 0.5)
  child.bounds.y.should be_close(6.0, 0.5)
  child.bounds.width.should be_close(sub.bounds.width - 12.0, 0.5)
  child.bounds.height.should be_close(sub.bounds.height - 12.0, 0.5)
end

private def assert_h_adjacent(left : CrymbleUI::Widget, right : CrymbleUI::Widget, spacing : Float64)
  gap = right.bounds.x - (left.bounds.x + left.bounds.width)
  gap.should be_close(spacing, 0.5)
end

private def assert_v_adjacent(top : CrymbleUI::Widget, bottom : CrymbleUI::Widget, spacing : Float64)
  gap = bottom.bounds.y - (top.bounds.y + top.bounds.height)
  gap.should be_close(spacing, 0.5)
end

describe "RecursiveGrid comprehensive bounds" do
  # Ground truth values measured from the original working implementation.
  # Computed with TestFont (monospace: width=chars*size*0.6, height=size),
  # font_size=14.0 (scale 0, zoom 1.0), Button padding=5.
  #
  # Run date: 2026-03-25

  describe "simple_2x2" do
    # 2×2 grid with spacing=4
    # Natural cell size: 18.4 × 24.0 (single-char button with padding=5)
    # Layout:
    #   col0 x=0,   width=18.4
    #   col1 x=22.4 (18.4+4), width=18.4
    #   row0 y=0,   height=24.0
    #   row1 y=28.0 (24.0+4), height=24.0
    # Grid total: 40.8 × 52.0
    it "4 buttons in 2x2 grid with spacing=4 have correct bounds" do
      btn_a = btn5("A")
      btn_b = btn5("B")
      btn_c = btn5("C")
      btn_d = btn5("D")

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn_a, btn_b], [btn_c, btn_d]],
        spacing: 4.0
      )

      grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Grid bounds
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(40.8, 0.5)
      grid.bounds.height.should be_close(52.0, 0.5)

      # btn_a [0,0]
      btn_a.bounds.x.should be_close(0.0, 0.5)
      btn_a.bounds.y.should be_close(0.0, 0.5)
      btn_a.bounds.width.should be_close(18.4, 0.5)
      btn_a.bounds.height.should be_close(24.0, 0.5)

      # btn_b [0,1]
      btn_b.bounds.x.should be_close(22.4, 0.5)
      btn_b.bounds.y.should be_close(0.0, 0.5)
      btn_b.bounds.width.should be_close(18.4, 0.5)
      btn_b.bounds.height.should be_close(24.0, 0.5)

      # btn_c [1,0]
      btn_c.bounds.x.should be_close(0.0, 0.5)
      btn_c.bounds.y.should be_close(28.0, 0.5)
      btn_c.bounds.width.should be_close(18.4, 0.5)
      btn_c.bounds.height.should be_close(24.0, 0.5)

      # btn_d [1,1]
      btn_d.bounds.x.should be_close(22.4, 0.5)
      btn_d.bounds.y.should be_close(28.0, 0.5)
      btn_d.bounds.width.should be_close(18.4, 0.5)
      btn_d.bounds.height.should be_close(24.0, 0.5)
    end
  end

  describe "spanning_A_B1_B2" do
    # Grid: [[A, nested([[B1],[B2]])]], spacing=3
    # "A" (1 char, pad=5): natural 18.4 × 24.0
    # "B1","B2" (2 chars, pad=5): natural 26.8 × 24.0
    # nested(spacing=3): width=26.8, height=24+3+24=51 → but B1/B2 each get 25.5 inside
    # Wait: nested has spacing=3: height = 24+3+24 = 51? But actual shows height=54
    # Actual nested: width=26.8+ε ≈ 26.8, height=54.0 (each B gets 27 → 25.5+3+25.5)
    # Actual: btn_b1 height=25.5, btn_b2 y=28.5 (25.5+3), nested height=54.0
    # A spans full nested height: 54.0
    # Grid: width=18.4+3+26.8=48.2, height=54.0
    it "btn_a spans 2 rows, B1/B2 stack in nested with spacing=3" do
      btn_a  = btn5("A")
      btn_b1 = btn5("B1")
      btn_b2 = btn5("B2")

      nested = CrymbleUI::RecursiveGrid.new(
        content: [[btn_b1], [btn_b2]],
        spacing: 3.0
      )
      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn_a, nested]],
        spacing: 3.0
      )

      grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Grid bounds
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(48.2, 0.5)
      grid.bounds.height.should be_close(54.0, 0.5)

      # btn_a spans full height (0..54)
      btn_a.bounds.x.should be_close(0.0, 0.5)
      btn_a.bounds.y.should be_close(0.0, 0.5)
      btn_a.bounds.width.should be_close(18.4, 0.5)
      btn_a.bounds.height.should be_close(54.0, 0.5)

      # nested grid at right of A, full height
      nested.bounds.x.should be_close(21.4, 0.5)
      nested.bounds.y.should be_close(0.0, 0.5)
      nested.bounds.width.should be_close(26.8, 0.5)
      nested.bounds.height.should be_close(54.0, 0.5)

      # btn_b1 in nested: top row
      btn_b1.bounds.x.should be_close(0.0, 0.5)
      btn_b1.bounds.y.should be_close(0.0, 0.5)
      btn_b1.bounds.width.should be_close(26.8, 0.5)
      btn_b1.bounds.height.should be_close(25.5, 0.5)

      # btn_b2 in nested: bottom row (y = 25.5+3 = 28.5)
      btn_b2.bounds.x.should be_close(0.0, 0.5)
      btn_b2.bounds.y.should be_close(28.5, 0.5)
      btn_b2.bounds.width.should be_close(26.8, 0.5)
      btn_b2.bounds.height.should be_close(25.5, 0.5)
    end
  end

  describe "3x3_with_nested_at_1_1" do
    # 3×3 outer grid where [1,1] is a 2×2 nested RecursiveGrid, spacing=0
    # Nested is 2×2: expands physical row 1 to 2 rows, physical col 1 to 2 cols
    # Physical layout (5 rows × 5 cols would be wrong — only 4×4 here):
    #
    #   physical rows: 0=row0(h=24), 1=row1_a(h=24), 2=row1_b(h=24), 3=row2(h=24)  → 4 physical rows
    #   Wait: nested(2×2) occupies 2 physical rows and 2 physical cols
    #
    # Actual grid size: 107.2 × 96.0
    # 3 outer cols with col1 expanded to 2 physical cols:
    #   col0: x=0, w=18.4
    #   col1a: x=18.4, w=35.2
    #   col1b: x=53.6, w=35.2 → 70.4 total for nested width
    #   col2: x=88.8, w=18.4
    # 3 outer rows with row1 expanded to 2 physical rows:
    #   row0: y=0, h=24
    #   row1a: y=24, h=24
    #   row1b: y=48, h=24 → 48 total for nested height
    #   row2: y=72, h=24
    #
    # btn00[0,0]: (0,0,18.4,24)
    # btn01[0,1]: (18.4,0,70.4,24) — spans 2 physical cols (col1a+col1b)
    # btn02[0,2]: (88.8,0,18.4,24)
    # btn10[1,0]: (0,24,18.4,48) — spans 2 physical rows
    # nested[1,1]: (18.4,24,70.4,48)
    # btn12[1,2]: (88.8,24,18.4,48) — spans 2 physical rows
    # btn20[2,0]: (0,72,18.4,24)
    # btn21[2,1]: (18.4,72,70.4,24) — spans 2 physical cols
    # btn22[2,2]: (88.8,72,18.4,24)
    #
    # Inside nested (spacing=0, each cell 35.2×24):
    # btn_n00: (0,0,35.2,24), btn_n01: (35.2,0,35.2,24)
    # btn_n10: (0,24,35.2,24), btn_n11: (35.2,24,35.2,24)
    it "verifies ALL bounds including spanning for adjacent cells" do
      btn00 = btn5("A")
      btn01 = btn5("B")
      btn02 = btn5("C")
      btn10 = btn5("D")
      btn12 = btn5("E")
      btn20 = btn5("F")
      btn21 = btn5("G")
      btn22 = btn5("H")

      btn_n00 = btn5("n00")
      btn_n01 = btn5("n01")
      btn_n10 = btn5("n10")
      btn_n11 = btn5("n11")

      nested = CrymbleUI::RecursiveGrid.new(
        content: [[btn_n00, btn_n01], [btn_n10, btn_n11]],
        spacing: 0.0
      )
      grid = CrymbleUI::RecursiveGrid.new(
        content: [
          [btn00, btn01, btn02],
          [btn10, nested, btn12],
          [btn20, btn21, btn22],
        ],
        spacing: 0.0
      )

      grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Grid total bounds
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(107.2, 0.5)
      grid.bounds.height.should be_close(96.0, 0.5)

      # Row 0 cells (all at y=0, height=24)
      btn00.bounds.x.should be_close(0.0, 0.5)
      btn00.bounds.y.should be_close(0.0, 0.5)
      btn00.bounds.width.should be_close(18.4, 0.5)
      btn00.bounds.height.should be_close(24.0, 0.5)

      btn01.bounds.x.should be_close(18.4, 0.5)
      btn01.bounds.y.should be_close(0.0, 0.5)
      btn01.bounds.width.should be_close(70.4, 0.5)
      btn01.bounds.height.should be_close(24.0, 0.5)

      btn02.bounds.x.should be_close(88.8, 0.5)
      btn02.bounds.y.should be_close(0.0, 0.5)
      btn02.bounds.width.should be_close(18.4, 0.5)
      btn02.bounds.height.should be_close(24.0, 0.5)

      # Row 1 (y=24): btn10, nested, btn12 — spanning cells
      btn10.bounds.x.should be_close(0.0, 0.5)
      btn10.bounds.y.should be_close(24.0, 0.5)
      btn10.bounds.width.should be_close(18.4, 0.5)
      btn10.bounds.height.should be_close(48.0, 0.5)  # spans 2 physical rows

      nested.bounds.x.should be_close(18.4, 0.5)
      nested.bounds.y.should be_close(24.0, 0.5)
      nested.bounds.width.should be_close(70.4, 0.5)
      nested.bounds.height.should be_close(48.0, 0.5)

      btn12.bounds.x.should be_close(88.8, 0.5)
      btn12.bounds.y.should be_close(24.0, 0.5)
      btn12.bounds.width.should be_close(18.4, 0.5)
      btn12.bounds.height.should be_close(48.0, 0.5)  # spans 2 physical rows

      # Row 2 cells (y=72, height=24)
      btn20.bounds.x.should be_close(0.0, 0.5)
      btn20.bounds.y.should be_close(72.0, 0.5)
      btn20.bounds.width.should be_close(18.4, 0.5)
      btn20.bounds.height.should be_close(24.0, 0.5)

      btn21.bounds.x.should be_close(18.4, 0.5)
      btn21.bounds.y.should be_close(72.0, 0.5)
      btn21.bounds.width.should be_close(70.4, 0.5)
      btn21.bounds.height.should be_close(24.0, 0.5)

      btn22.bounds.x.should be_close(88.8, 0.5)
      btn22.bounds.y.should be_close(72.0, 0.5)
      btn22.bounds.width.should be_close(18.4, 0.5)
      btn22.bounds.height.should be_close(24.0, 0.5)

      # Nested contents (relative to nested grid, which is at (18.4,24))
      # 2×2 nested, spacing=0, each cell 35.2×24
      btn_n00.bounds.x.should be_close(0.0, 0.5)
      btn_n00.bounds.y.should be_close(0.0, 0.5)
      btn_n00.bounds.width.should be_close(35.2, 0.5)
      btn_n00.bounds.height.should be_close(24.0, 0.5)

      btn_n01.bounds.x.should be_close(35.2, 0.5)
      btn_n01.bounds.y.should be_close(0.0, 0.5)
      btn_n01.bounds.width.should be_close(35.2, 0.5)
      btn_n01.bounds.height.should be_close(24.0, 0.5)

      btn_n10.bounds.x.should be_close(0.0, 0.5)
      btn_n10.bounds.y.should be_close(24.0, 0.5)
      btn_n10.bounds.width.should be_close(35.2, 0.5)
      btn_n10.bounds.height.should be_close(24.0, 0.5)

      btn_n11.bounds.x.should be_close(35.2, 0.5)
      btn_n11.bounds.y.should be_close(24.0, 0.5)
      btn_n11.bounds.width.should be_close(35.2, 0.5)
      btn_n11.bounds.height.should be_close(24.0, 0.5)
    end
  end

  describe "all_subgrids_2x2_with_border" do
    # 2×2 outer grid where ALL cells are 1×1 RecursiveGrids with border_color, spacing=0
    # border_padding = BORDER_WIDTH + 4 = 2 + 4 = 6.0
    # Each sub-grid wraps a button; button fills content area = sub - 2*6 = sub - 12
    # Natural button: 18.4 × 24.0 → sub-grid natural: (18.4+12) × (24+12) = 30.4 × 36.0
    # Outer grid (spacing=0): 60.8 × 72.0
    # Sub positions: sub_a(0,0), sub_b(30.4,0), sub_c(0,36), sub_d(30.4,36)
    # Each button inside its sub-grid at (6,6), size 18.4×24
    it "each sub-grid child fills content area (bounds - 2*border_padding)" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      btn_a = btn5("A")
      btn_b = btn5("B")
      btn_c = btn5("C")
      btn_d = btn5("D")

      sub_a = CrymbleUI::RecursiveGrid.new(content: [[btn_a]])
      sub_b = CrymbleUI::RecursiveGrid.new(content: [[btn_b]])
      sub_c = CrymbleUI::RecursiveGrid.new(content: [[btn_c]])
      sub_d = CrymbleUI::RecursiveGrid.new(content: [[btn_d]])
      [sub_a, sub_b, sub_c, sub_d].each { |s| s.border_color = border_color }

      outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub_a, sub_b], [sub_c, sub_d]],
        spacing: 0.0
      )

      outer.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Outer grid
      outer.bounds.x.should be_close(0.0, 0.5)
      outer.bounds.y.should be_close(0.0, 0.5)
      outer.bounds.width.should be_close(60.8, 0.5)
      outer.bounds.height.should be_close(72.0, 0.5)

      # Sub-grid positions
      sub_a.bounds.x.should be_close(0.0, 0.5)
      sub_a.bounds.y.should be_close(0.0, 0.5)
      sub_a.bounds.width.should be_close(30.4, 0.5)
      sub_a.bounds.height.should be_close(36.0, 0.5)

      sub_b.bounds.x.should be_close(30.4, 0.5)
      sub_b.bounds.y.should be_close(0.0, 0.5)
      sub_b.bounds.width.should be_close(30.4, 0.5)
      sub_b.bounds.height.should be_close(36.0, 0.5)

      sub_c.bounds.x.should be_close(0.0, 0.5)
      sub_c.bounds.y.should be_close(36.0, 0.5)
      sub_c.bounds.width.should be_close(30.4, 0.5)
      sub_c.bounds.height.should be_close(36.0, 0.5)

      sub_d.bounds.x.should be_close(30.4, 0.5)
      sub_d.bounds.y.should be_close(36.0, 0.5)
      sub_d.bounds.width.should be_close(30.4, 0.5)
      sub_d.bounds.height.should be_close(36.0, 0.5)

      # Each button inside its sub-grid at (border_padding, border_padding)
      # and fills content area: 30.4-12=18.4 × 36-12=24
      [btn_a, btn_b, btn_c, btn_d].each do |btn|
        btn.bounds.x.should be_close(border_padding, 0.5)  # 6.0
        btn.bounds.y.should be_close(border_padding, 0.5)  # 6.0
        btn.bounds.width.should be_close(18.4, 0.5)
        btn.bounds.height.should be_close(24.0, 0.5)
      end

      # Structural invariant: each button fills sub-grid content area
      [sub_a, sub_b, sub_c, sub_d].zip([btn_a, btn_b, btn_c, btn_d]).each do |sub, btn|
        expected_w = sub.bounds.width - 2.0 * border_padding
        expected_h = sub.bounds.height - 2.0 * border_padding
        btn.bounds.width.should be_close(expected_w, 0.5)
        btn.bounds.height.should be_close(expected_h, 0.5)
      end
    end
  end

  describe "deep_nesting_3_levels" do
    # 3-level deep nesting: outer → mid → inner → button
    # Each level has border_color → border_padding=6.0 per level
    # inner_btn natural: 18.4 × 24.0
    # inner_grid: (18.4+12) × (24+12) = 30.4 × 36.0
    # mid_grid:   (30.4+12) × (36+12) = 42.4 × 48.0
    # outer_grid: (42.4+12) × (48+12) = 54.4 × 60.0
    #
    # Positions (all relative to their parent):
    # outer_grid: (0,0,54.4,60)
    # mid_grid:   (6,6,42.4,48)
    # inner_grid: (6,6,30.4,36)
    # inner_btn:  (6,6,18.4,24)
    it "each level's content is inset by border_padding from parent" do
      border_color = CrymbleUI::Color.new(100, 150, 200, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      inner_btn = btn5("X")

      inner_grid = CrymbleUI::RecursiveGrid.new(content: [[inner_btn]])
      inner_grid.border_color = border_color

      mid_grid = CrymbleUI::RecursiveGrid.new(content: [[inner_grid]])
      mid_grid.border_color = border_color

      outer_grid = CrymbleUI::RecursiveGrid.new(content: [[mid_grid]])
      outer_grid.border_color = border_color

      outer_grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # outer_grid
      outer_grid.bounds.x.should be_close(0.0, 0.5)
      outer_grid.bounds.y.should be_close(0.0, 0.5)
      outer_grid.bounds.width.should be_close(54.4, 0.5)
      outer_grid.bounds.height.should be_close(60.0, 0.5)

      # mid_grid inside outer_grid at (border_padding, border_padding)
      mid_grid.bounds.x.should be_close(6.0, 0.5)
      mid_grid.bounds.y.should be_close(6.0, 0.5)
      mid_grid.bounds.width.should be_close(42.4, 0.5)
      mid_grid.bounds.height.should be_close(48.0, 0.5)

      # inner_grid inside mid_grid at (border_padding, border_padding)
      inner_grid.bounds.x.should be_close(6.0, 0.5)
      inner_grid.bounds.y.should be_close(6.0, 0.5)
      inner_grid.bounds.width.should be_close(30.4, 0.5)
      inner_grid.bounds.height.should be_close(36.0, 0.5)

      # inner_btn inside inner_grid at (border_padding, border_padding)
      inner_btn.bounds.x.should be_close(6.0, 0.5)
      inner_btn.bounds.y.should be_close(6.0, 0.5)
      inner_btn.bounds.width.should be_close(18.4, 0.5)
      inner_btn.bounds.height.should be_close(24.0, 0.5)

      # Structural: each child fills content area of its parent
      mid_grid.bounds.width.should be_close(outer_grid.bounds.width - 2.0 * border_padding, 0.5)
      mid_grid.bounds.height.should be_close(outer_grid.bounds.height - 2.0 * border_padding, 0.5)
      inner_grid.bounds.width.should be_close(mid_grid.bounds.width - 2.0 * border_padding, 0.5)
      inner_grid.bounds.height.should be_close(mid_grid.bounds.height - 2.0 * border_padding, 0.5)
      inner_btn.bounds.width.should be_close(inner_grid.bounds.width - 2.0 * border_padding, 0.5)
      inner_btn.bounds.height.should be_close(inner_grid.bounds.height - 2.0 * border_padding, 0.5)
    end
  end

  describe "deep_nesting_with_mixed" do
    # 2×2 outer: [0,0]=P, [0,1]=Q, [1,0]=R, [1,1]=outer_nested(inner_grid(S))
    # outer_nested has border_color (border_padding=6)
    # inner_grid has border_color (border_padding=6)
    # spacing=0 in outer grid
    #
    # Natural sizes (spacing=0):
    #   S: 18.4×24 (1 char "S")
    #   inner_grid: (18.4+12)×(24+12) = 30.4×36
    #   outer_nested: (30.4+12)×(36+12) = 42.4×48
    #   P,Q,R: 18.4×24
    #
    # Column widths: col0=max(P_w, R_w)=18.4, col1=max(Q_w, outer_nested_w)=42.4
    # Row heights: row0=max(P_h, Q_h)=24, row1=max(R_h, outer_nested_h)=48
    #
    # Layout:
    #   P(0,0): (0,0,18.4,24)
    #   Q(0,1): (18.4,0,42.4,24)
    #   R(1,0): (0,24,18.4,48)
    #   outer_nested(1,1): (18.4,24,42.4,48)
    #   inner_grid (inside outer_nested): (6,6,30.4,36)
    #   S (inside inner_grid): (6,6,18.4,24)
    it "2x2 with 2-level deep nesting at [1,1] — all bounds verified" do
      border_color = CrymbleUI::Color.new(100, 150, 200, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      btn00 = btn5("P")
      btn01 = btn5("Q")
      btn10 = btn5("R")
      deepest_btn = btn5("S")

      inner_grid = CrymbleUI::RecursiveGrid.new(content: [[deepest_btn]])
      inner_grid.border_color = border_color
      outer_nested = CrymbleUI::RecursiveGrid.new(content: [[inner_grid]])
      outer_nested.border_color = border_color

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn00, btn01], [btn10, outer_nested]],
        spacing: 0.0
      )

      grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Outer grid
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(60.8, 0.5)
      grid.bounds.height.should be_close(72.0, 0.5)

      # btn00 [0,0]
      btn00.bounds.x.should be_close(0.0, 0.5)
      btn00.bounds.y.should be_close(0.0, 0.5)
      btn00.bounds.width.should be_close(18.4, 0.5)
      btn00.bounds.height.should be_close(24.0, 0.5)

      # btn01 [0,1]
      btn01.bounds.x.should be_close(18.4, 0.5)
      btn01.bounds.y.should be_close(0.0, 0.5)
      btn01.bounds.width.should be_close(42.4, 0.5)
      btn01.bounds.height.should be_close(24.0, 0.5)

      # btn10 [1,0]
      btn10.bounds.x.should be_close(0.0, 0.5)
      btn10.bounds.y.should be_close(24.0, 0.5)
      btn10.bounds.width.should be_close(18.4, 0.5)
      btn10.bounds.height.should be_close(48.0, 0.5)

      # outer_nested [1,1]
      outer_nested.bounds.x.should be_close(18.4, 0.5)
      outer_nested.bounds.y.should be_close(24.0, 0.5)
      outer_nested.bounds.width.should be_close(42.4, 0.5)
      outer_nested.bounds.height.should be_close(48.0, 0.5)

      # inner_grid inside outer_nested (relative to outer_nested, at border_padding)
      inner_grid.bounds.x.should be_close(6.0, 0.5)
      inner_grid.bounds.y.should be_close(6.0, 0.5)
      inner_grid.bounds.width.should be_close(30.4, 0.5)
      inner_grid.bounds.height.should be_close(36.0, 0.5)

      # deepest_btn inside inner_grid (relative to inner_grid, at border_padding)
      deepest_btn.bounds.x.should be_close(6.0, 0.5)
      deepest_btn.bounds.y.should be_close(6.0, 0.5)
      deepest_btn.bounds.width.should be_close(18.4, 0.5)
      deepest_btn.bounds.height.should be_close(24.0, 0.5)

      # Structural invariants
      outer_nested.bounds.height.should be_close(btn10.bounds.height, 0.5)
      inner_grid.bounds.width.should be_close(outer_nested.bounds.width - 2.0 * border_padding, 0.5)
      inner_grid.bounds.height.should be_close(outer_nested.bounds.height - 2.0 * border_padding, 0.5)
      deepest_btn.bounds.width.should be_close(inner_grid.bounds.width - 2.0 * border_padding, 0.5)
      deepest_btn.bounds.height.should be_close(inner_grid.bounds.height - 2.0 * border_padding, 0.5)
    end
  end

  describe "tight_constraints_larger_than_natural" do
    # 2×2 grid (spacing=0) given 2× its natural size (73.6 × 96.0)
    # Natural size: 36.8 × 48.0 (two 18.4×24 buttons per row/col)
    # With 2× constraints, scale_x=2, scale_y=2
    # Each cell: 36.8×48 (2× natural)
    # Positions:
    #   A(0,0): (0,0,36.8,48)
    #   B(0,1): (36.8,0,36.8,48)
    #   C(1,0): (0,48,36.8,48)
    #   D(1,1): (36.8,48,36.8,48)
    it "proportional scaling distributes 2× space equally to all cells" do
      btn_a = btn5("A")
      btn_b = btn5("B")
      btn_c = btn5("C")
      btn_d = btn5("D")

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn_a, btn_b], [btn_c, btn_d]],
        spacing: 0.0
      )

      natural_size = grid.measure(CrymbleUI::BoxConstraints.new)
      natural_size.width.should be_close(36.8, 0.5)
      natural_size.height.should be_close(48.0, 0.5)

      large_w = natural_size.width * 2.0   # 73.6
      large_h = natural_size.height * 2.0  # 96.0
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(large_w, large_h))
      grid.layout(constraints, CrymbleUI::Vec2.zero)

      # Grid fills tight constraint
      grid.bounds.width.should be_close(73.6, 0.5)
      grid.bounds.height.should be_close(96.0, 0.5)

      # btn_a [0,0]
      btn_a.bounds.x.should be_close(0.0, 0.5)
      btn_a.bounds.y.should be_close(0.0, 0.5)
      btn_a.bounds.width.should be_close(36.8, 0.5)
      btn_a.bounds.height.should be_close(48.0, 0.5)

      # btn_b [0,1]
      btn_b.bounds.x.should be_close(36.8, 0.5)
      btn_b.bounds.y.should be_close(0.0, 0.5)
      btn_b.bounds.width.should be_close(36.8, 0.5)
      btn_b.bounds.height.should be_close(48.0, 0.5)

      # btn_c [1,0]
      btn_c.bounds.x.should be_close(0.0, 0.5)
      btn_c.bounds.y.should be_close(48.0, 0.5)
      btn_c.bounds.width.should be_close(36.8, 0.5)
      btn_c.bounds.height.should be_close(48.0, 0.5)

      # btn_d [1,1]
      btn_d.bounds.x.should be_close(36.8, 0.5)
      btn_d.bounds.y.should be_close(48.0, 0.5)
      btn_d.bounds.width.should be_close(36.8, 0.5)
      btn_d.bounds.height.should be_close(48.0, 0.5)

      # Total coverage
      (btn_a.bounds.width + btn_b.bounds.width).should be_close(73.6, 0.5)
      (btn_a.bounds.height + btn_c.bounds.height).should be_close(96.0, 0.5)
    end
  end

  describe "tight_constraints_equal_to_natural" do
    # 2×2 grid (spacing=0) given exact natural-size constraints → no scaling
    # Natural: 36.8 × 48.0
    # Same layout as unconstrained:
    #   A(0,0): (0,0,18.4,24), B(0,1): (18.4,0,18.4,24)
    #   C(1,0): (0,24,18.4,24), D(1,1): (18.4,24,18.4,24)
    it "no scaling when constraints match natural size" do
      btn_a = btn5("A")
      btn_b = btn5("B")
      btn_c = btn5("C")
      btn_d = btn5("D")

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn_a, btn_b], [btn_c, btn_d]],
        spacing: 0.0
      )

      natural_size = grid.measure(CrymbleUI::BoxConstraints.new)
      natural_size.width.should be_close(36.8, 0.5)
      natural_size.height.should be_close(48.0, 0.5)

      constraints = CrymbleUI::BoxConstraints.tight(natural_size)
      grid.layout(constraints, CrymbleUI::Vec2.zero)

      # Grid exactly fills natural size
      grid.bounds.width.should be_close(36.8, 0.5)
      grid.bounds.height.should be_close(48.0, 0.5)

      # btn_a [0,0]
      btn_a.bounds.x.should be_close(0.0, 0.5)
      btn_a.bounds.y.should be_close(0.0, 0.5)
      btn_a.bounds.width.should be_close(18.4, 0.5)
      btn_a.bounds.height.should be_close(24.0, 0.5)

      # btn_b [0,1]
      btn_b.bounds.x.should be_close(18.4, 0.5)
      btn_b.bounds.y.should be_close(0.0, 0.5)
      btn_b.bounds.width.should be_close(18.4, 0.5)
      btn_b.bounds.height.should be_close(24.0, 0.5)

      # btn_c [1,0]
      btn_c.bounds.x.should be_close(0.0, 0.5)
      btn_c.bounds.y.should be_close(24.0, 0.5)
      btn_c.bounds.width.should be_close(18.4, 0.5)
      btn_c.bounds.height.should be_close(24.0, 0.5)

      # btn_d [1,1]
      btn_d.bounds.x.should be_close(18.4, 0.5)
      btn_d.bounds.y.should be_close(24.0, 0.5)
      btn_d.bounds.width.should be_close(18.4, 0.5)
      btn_d.bounds.height.should be_close(24.0, 0.5)
    end
  end

  describe "with_cell_background_color" do
    # 2×2 grid with cell_background_color: non-RecursiveGrid cells wrapped in VStack
    # spacing=0; VStack wrappers are the grid's children
    # Same positions as unconstrained 2×2 with identical buttons:
    #   w0(wraps A): (0,0,18.4,24), w1(wraps B): (18.4,0,18.4,24)
    #   w2(wraps C): (0,24,18.4,24), w3(wraps D): (18.4,24,18.4,24)
    # Grid total: 36.8×48.0
    it "VStack wrappers are grid children and fill cell bounds" do
      cell_bg = CrymbleUI::Color.new(200, 220, 240, 255)

      btn_a = btn5("A")
      btn_b = btn5("B")
      btn_c = btn5("C")
      btn_d = btn5("D")

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[btn_a, btn_b], [btn_c, btn_d]],
        spacing: 0.0,
        cell_background_color: cell_bg
      )

      grid.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Grid bounds
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(36.8, 0.5)
      grid.bounds.height.should be_close(48.0, 0.5)

      # Children should be 4 VStack wrappers (not the original buttons)
      grid.children.size.should eq(4)
      grid.children.each { |c| c.should be_a(CrymbleUI::VStack) }

      w0, w1, w2, w3 = grid.children[0], grid.children[1], grid.children[2], grid.children[3]

      # w0 (wraps A) at [0,0]
      w0.bounds.x.should be_close(0.0, 0.5)
      w0.bounds.y.should be_close(0.0, 0.5)
      w0.bounds.width.should be_close(18.4, 0.5)
      w0.bounds.height.should be_close(24.0, 0.5)

      # w1 (wraps B) at [0,1]
      w1.bounds.x.should be_close(18.4, 0.5)
      w1.bounds.y.should be_close(0.0, 0.5)
      w1.bounds.width.should be_close(18.4, 0.5)
      w1.bounds.height.should be_close(24.0, 0.5)

      # w2 (wraps C) at [1,0]
      w2.bounds.x.should be_close(0.0, 0.5)
      w2.bounds.y.should be_close(24.0, 0.5)
      w2.bounds.width.should be_close(18.4, 0.5)
      w2.bounds.height.should be_close(24.0, 0.5)

      # w3 (wraps D) at [1,1]
      w3.bounds.x.should be_close(18.4, 0.5)
      w3.bounds.y.should be_close(24.0, 0.5)
      w3.bounds.width.should be_close(18.4, 0.5)
      w3.bounds.height.should be_close(24.0, 0.5)
    end
  end

  # ============================================================
  # Tests T1-T12: Real demo complexity with multi-cell sub-grids
  # ============================================================

  describe "T1: screenshot 19-34 — mixed 1×1 and 1×2 sub-grids" do
    # Exact layout from /tmp/2026-03-25_19-34.png:
    # Row 0: [Sub(Hello), Sub(1)]           — two 1×1 sub-grids
    # Row 1: [Sub([2, 4]), Sub([3, 5])]     — two 1×2 sub-grids
    # All with border_color, cell_bg, tight 1.5×
    it "all widget bounds correct with tight 1.5× constraints" do
      hello = btn("Hello"); b1 = btn("1")
      b2 = btn("2"); b4 = btn("4"); b3 = btn("3"); b5 = btn("5")

      sub_hello = make_sub([[hello.as(CrymbleUI::Widget)]])
      sub_1 = make_sub([[b1.as(CrymbleUI::Widget)]])
      sub_24 = make_sub([[b2.as(CrymbleUI::Widget), b4.as(CrymbleUI::Widget)]])
      sub_35 = make_sub([[b3.as(CrymbleUI::Widget), b5.as(CrymbleUI::Widget)]])

      grid = CrymbleUI::RecursiveGrid.new(
        content: [
          [sub_hello.as(CrymbleUI::Widget), sub_1.as(CrymbleUI::Widget)],
          [sub_24.as(CrymbleUI::Widget), sub_35.as(CrymbleUI::Widget)],
        ],
        spacing: 6.0, cell_background_color: CrymbleUI::Color.new(180, 200, 220, 255)
      )

      natural = grid.measure(CrymbleUI::BoxConstraints.new)
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 1.5, natural.height * 1.5))
      grid.layout(tight, CrymbleUI::Vec2.zero)

      # Print ALL bounds for measurement

      # Structural invariants:
      # 1. Single-nested sub-grids: child fills content area
      assert_child_fills(sub_hello, sub_hello.children.first)
      assert_child_fills(sub_1, sub_1.children.first)

      # 2. Multi-cell sub-grids: children inside border, non-overlapping
      b2.bounds.x.should be >= 5.5
      b4.bounds.x.should be > b2.bounds.x + b2.bounds.width
      b3.bounds.x.should be >= 5.5
      b5.bounds.x.should be > b3.bounds.x + b3.bounds.width

      # 3. Sub-grids in same row: non-overlapping
      assert_h_adjacent(sub_hello, sub_1, 6.0)
      assert_h_adjacent(sub_24, sub_35, 6.0)

      # 4. Sub-grids in same column: vertically adjacent
      assert_v_adjacent(sub_hello, sub_24, 6.0)
      assert_v_adjacent(sub_1, sub_35, 6.0)

      # 5. Same column → same width
      sub_hello.bounds.width.should be_close(sub_24.bounds.width, 0.5)
      sub_1.bounds.width.should be_close(sub_35.bounds.width, 0.5)

      # 6. Same row → same height
      sub_hello.bounds.height.should be_close(sub_1.bounds.height, 0.5)
      sub_24.bounds.height.should be_close(sub_35.bounds.height, 0.5)

      # 7. Grid fills tight constraints
      grid.bounds.width.should be_close(natural.width * 1.5, 0.5)
      grid.bounds.height.should be_close(natural.height * 1.5, 0.5)

      # 8. Red rectangles are positive and complete
      [sub_hello, sub_1, sub_24, sub_35].each do |sub|
        sub.bounds.width.should be > 0
        sub.bounds.height.should be > 0
      end
    end
  end

  describe "T2: plain 2×2 with tight 1.5× constraints" do
    it "all buttons have correct bounds with proportional scaling" do
      hello = btn("Hello"); b1 = btn("1"); b2 = btn("2"); b3 = btn("3")

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[hello.as(CrymbleUI::Widget), b1.as(CrymbleUI::Widget)],
                  [b2.as(CrymbleUI::Widget), b3.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )

      natural = grid.measure(CrymbleUI::BoxConstraints.new)
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 1.5, natural.height * 1.5))
      grid.layout(tight, CrymbleUI::Vec2.zero)


      # Grid fills tight constraints
      grid.bounds.width.should be_close(natural.width * 1.5, 0.5)
      grid.bounds.height.should be_close(natural.height * 1.5, 0.5)

      # Horizontal non-overlap
      assert_h_adjacent(hello, b1, 6.0)
      assert_h_adjacent(b2, b3, 6.0)

      # Vertical non-overlap
      assert_v_adjacent(hello, b2, 6.0)
      assert_v_adjacent(b1, b3, 6.0)

      # Same column same width
      hello.bounds.width.should be_close(b2.bounds.width, 0.5)
      b1.bounds.width.should be_close(b3.bounds.width, 0.5)

      # Same row same height
      hello.bounds.height.should be_close(b1.bounds.height, 0.5)
      b2.bounds.height.should be_close(b3.bounds.height, 0.5)
    end
  end

  describe "T3: one cell becomes sub-grid (mixed plain + 1×2 sub)" do
    # [[Hello, 1], [Sub([2, 4]), 3]]
    # Sub-grid at [1,0] has 2 columns — virtual column expansion in parent
    # With cell_background_color: plain cells wrapped in VStack (check wrapper bounds)
    it "sub-grid and plain cells have correct bounds" do
      hello = btn("Hello"); b1 = btn("1"); b3 = btn("3")
      b2 = btn("2"); b4 = btn("4")

      sub_24 = make_sub([[b2.as(CrymbleUI::Widget), b4.as(CrymbleUI::Widget)]])

      grid = CrymbleUI::RecursiveGrid.new(
        content: [[hello.as(CrymbleUI::Widget), b1.as(CrymbleUI::Widget)],
                  [sub_24.as(CrymbleUI::Widget), b3.as(CrymbleUI::Widget)]],
        spacing: 6.0, cell_background_color: CrymbleUI::Color.new(180, 200, 220, 255)
      )

      natural = grid.measure(CrymbleUI::BoxConstraints.new)
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 1.5, natural.height * 1.5))
      grid.layout(tight, CrymbleUI::Vec2.zero)

      # Grid children: VStack wrappers for plain cells + sub_24 (RecursiveGrid not wrapped)
      # Access wrappers by grid.children (ordered by element enumeration)
      children = grid.children.to_a


      # Grid fills tight constraints
      grid.bounds.width.should be_close(natural.width * 1.5, 0.5)

      # Sub-grid red rectangle: positive and properly sized
      sub_24.bounds.width.should be > 0
      sub_24.bounds.height.should be > 0

      # Sub-grid children inside border
      b2.bounds.x.should be >= 5.5
      b4.bounds.x.should be > b2.bounds.x + b2.bounds.width

      # Non-overlap: sub_24 and the wrapper for b3 (both in row 1)
      # Find the wrapper for b3 (it's a VStack child of grid that contains b3)
      wrapper_b3 = children.find { |c| c.is_a?(CrymbleUI::VStack) && c.bounds.y > 30 && c.bounds.x > 50 }
      if wrapper_b3
        (sub_24.bounds.x + sub_24.bounds.width).should be < wrapper_b3.bounds.x + 0.5
      end

      # Hello's wrapper spans full width matching sub_24
      wrapper_hello = children.find { |c| c.is_a?(CrymbleUI::VStack) && c.bounds.y < 1 && c.bounds.x < 1 }
      if wrapper_hello
        wrapper_hello.bounds.width.should be_close(sub_24.bounds.width, 0.5)
      end
    end
  end

  describe "all_nested_2x1_column_alignment" do
    # 2×1 outer grid where ALL cells are bordered sub-grids with DIFFERENT column widths.
    # This is the key regression scenario: in the all-nested case (no direct leaf widgets),
    # the broken code does a flat measure of leaf widgets without accounting for
    # sub-grid border_padding, causing incorrect column alignment.
    #
    # sub_top = [[A(1-char), BCD(3-char)]] with border_color
    # sub_bot = [[CD(2-char), D(1-char)]] with border_color
    # border_padding=6.0 per sub-grid
    #
    # Button natural widths: A=18.4, BCD=35.2, CD=26.8, D=18.4
    # Sub-grid border adds 2*6=12 to each dimension.
    # Outer virtual col widths (correct): col0=max(18.4+12, 26.8+12)=38.8, col1=max(35.2+12,18.4+12)=47.2
    # Both outer cells (sub_top, sub_bot) have width=38.8+47.2=86.0
    # Inside sub_top (content=86-12=74 wide): col0=38.8-12=26.8? No — parent_col_widths gives
    #   content widths; col0 content=26.8, col1 content=35.2
    # Ground truth from fixed code (bfa3647):
    #   outer: 86.0×72.0
    #   sub_top: (0,0,86.0,36), sub_bot: (0,36,86.0,36)
    #   a: (6,6,38.8,24), b: (44.8,6,35.2,24)
    #   c: (6,6,38.8,24), d: (44.8,6,35.2,24)
    # Invariant: a.width == c.width (same outer col0), b.width == d.width (same outer col1)
    it "2x1 all-nested: column 0 and column 1 align correctly across both rows" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      btn_a = btn5("A")    # 1 char: 18.4 wide
      btn_b = btn5("BCD")  # 3 chars: 35.2 wide
      btn_c = btn5("CD")   # 2 chars: 26.8 wide
      btn_d = btn5("D")    # 1 char: 18.4 wide

      sub_top = CrymbleUI::RecursiveGrid.new(content: [[btn_a, btn_b]], spacing: 0.0)
      sub_top.border_color = border_color

      sub_bot = CrymbleUI::RecursiveGrid.new(content: [[btn_c, btn_d]], spacing: 0.0)
      sub_bot.border_color = border_color

      outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub_top.as(CrymbleUI::Widget)], [sub_bot.as(CrymbleUI::Widget)]],
        spacing: 0.0
      )

      outer.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Outer grid total size
      outer.bounds.x.should be_close(0.0, 0.5)
      outer.bounds.y.should be_close(0.0, 0.5)
      outer.bounds.width.should be_close(86.0, 0.5)
      outer.bounds.height.should be_close(72.0, 0.5)

      # Both sub-grids span the full outer width
      sub_top.bounds.x.should be_close(0.0, 0.5)
      sub_top.bounds.y.should be_close(0.0, 0.5)
      sub_top.bounds.width.should be_close(86.0, 0.5)
      sub_top.bounds.height.should be_close(36.0, 0.5)

      sub_bot.bounds.x.should be_close(0.0, 0.5)
      sub_bot.bounds.y.should be_close(36.0, 0.5)
      sub_bot.bounds.width.should be_close(86.0, 0.5)
      sub_bot.bounds.height.should be_close(36.0, 0.5)

      # btn_a [sub_top, col0]: x=border_padding, width=38.8
      btn_a.bounds.x.should be_close(6.0, 0.5)
      btn_a.bounds.y.should be_close(6.0, 0.5)
      btn_a.bounds.width.should be_close(38.8, 0.5)
      btn_a.bounds.height.should be_close(24.0, 0.5)

      # btn_b [sub_top, col1]: x=border_padding+col0_width=44.8, width=35.2
      btn_b.bounds.x.should be_close(44.8, 0.5)
      btn_b.bounds.y.should be_close(6.0, 0.5)
      btn_b.bounds.width.should be_close(35.2, 0.5)
      btn_b.bounds.height.should be_close(24.0, 0.5)

      # btn_c [sub_bot, col0]: same x and width as btn_a (column alignment)
      btn_c.bounds.x.should be_close(6.0, 0.5)
      btn_c.bounds.y.should be_close(6.0, 0.5)
      btn_c.bounds.width.should be_close(38.8, 0.5)
      btn_c.bounds.height.should be_close(24.0, 0.5)

      # btn_d [sub_bot, col1]: same x and width as btn_b (column alignment)
      btn_d.bounds.x.should be_close(44.8, 0.5)
      btn_d.bounds.y.should be_close(6.0, 0.5)
      btn_d.bounds.width.should be_close(35.2, 0.5)
      btn_d.bounds.height.should be_close(24.0, 0.5)

      # Key invariant: column alignment — same column → same x offset and width
      btn_a.bounds.x.should be_close(btn_c.bounds.x, 0.5)
      btn_a.bounds.width.should be_close(btn_c.bounds.width, 0.5)
      btn_b.bounds.x.should be_close(btn_d.bounds.x, 0.5)
      btn_b.bounds.width.should be_close(btn_d.bounds.width, 0.5)

      # Structural: buttons fill content area within their sub-grid
      btn_a.bounds.width.should be_close(btn_c.bounds.width, 0.5)  # col alignment
      btn_b.bounds.x.should be_close(btn_a.bounds.x + btn_a.bounds.width, 0.5)  # adjacent
    end
  end

  describe "all_nested_2x1_tight_constraints" do
    # Same 2×1 all-nested scenario as above, but with tight 2× natural constraints.
    # This exercises both column alignment AND proportional scaling together.
    # The bug compounds: without border accounting, both the natural size AND
    # the scaled column widths are wrong.
    #
    # Ground truth from fixed code (bfa3647):
    #   Natural: 86.0×72.0
    #   Tight 2×: outer=172.0×144.0
    #   sub_top: (0,0,172,72), sub_bot: (0,72,172,72)
    #   a: (6,6,77.6,60), b: (83.6,6,82.4,60)
    #   c: (6,6,77.6,60), d: (83.6,6,82.4,60)
    it "2x1 all-nested with tight 2x constraints: column alignment preserved under scaling" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      btn_a = btn5("A"); btn_b = btn5("BCD"); btn_c = btn5("CD"); btn_d = btn5("D")

      sub_top = CrymbleUI::RecursiveGrid.new(content: [[btn_a, btn_b]], spacing: 0.0)
      sub_top.border_color = border_color

      sub_bot = CrymbleUI::RecursiveGrid.new(content: [[btn_c, btn_d]], spacing: 0.0)
      sub_bot.border_color = border_color

      outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub_top.as(CrymbleUI::Widget)], [sub_bot.as(CrymbleUI::Widget)]],
        spacing: 0.0
      )

      natural = outer.measure(CrymbleUI::BoxConstraints.new)
      natural.width.should be_close(86.0, 0.5)
      natural.height.should be_close(72.0, 0.5)

      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 2.0, natural.height * 2.0))
      outer.layout(tight, CrymbleUI::Vec2.zero)

      # Outer fills tight constraint
      outer.bounds.width.should be_close(172.0, 0.5)
      outer.bounds.height.should be_close(144.0, 0.5)

      # Both sub-grids fill full width, half height each
      sub_top.bounds.x.should be_close(0.0, 0.5)
      sub_top.bounds.y.should be_close(0.0, 0.5)
      sub_top.bounds.width.should be_close(172.0, 0.5)
      sub_top.bounds.height.should be_close(72.0, 0.5)

      sub_bot.bounds.x.should be_close(0.0, 0.5)
      sub_bot.bounds.y.should be_close(72.0, 0.5)
      sub_bot.bounds.width.should be_close(172.0, 0.5)
      sub_bot.bounds.height.should be_close(72.0, 0.5)

      # btn_a [sub_top, col0]: at (6,6), width=77.6
      btn_a.bounds.x.should be_close(6.0, 0.5)
      btn_a.bounds.y.should be_close(6.0, 0.5)
      btn_a.bounds.width.should be_close(77.6, 0.5)
      btn_a.bounds.height.should be_close(60.0, 0.5)

      # btn_b [sub_top, col1]: at (83.6,6), width=82.4
      btn_b.bounds.x.should be_close(83.6, 0.5)
      btn_b.bounds.y.should be_close(6.0, 0.5)
      btn_b.bounds.width.should be_close(82.4, 0.5)
      btn_b.bounds.height.should be_close(60.0, 0.5)

      # btn_c [sub_bot, col0]: same as btn_a (column alignment preserved under scaling)
      btn_c.bounds.x.should be_close(6.0, 0.5)
      btn_c.bounds.y.should be_close(6.0, 0.5)
      btn_c.bounds.width.should be_close(77.6, 0.5)
      btn_c.bounds.height.should be_close(60.0, 0.5)

      # btn_d [sub_bot, col1]: same as btn_b (column alignment preserved under scaling)
      btn_d.bounds.x.should be_close(83.6, 0.5)
      btn_d.bounds.y.should be_close(6.0, 0.5)
      btn_d.bounds.width.should be_close(82.4, 0.5)
      btn_d.bounds.height.should be_close(60.0, 0.5)

      # Column alignment preserved under scaling
      btn_a.bounds.x.should be_close(btn_c.bounds.x, 0.5)
      btn_a.bounds.width.should be_close(btn_c.bounds.width, 0.5)
      btn_b.bounds.x.should be_close(btn_d.bounds.x, 0.5)
      btn_b.bounds.width.should be_close(btn_d.bounds.width, 0.5)

      # Content fills available space
      (btn_a.bounds.width + btn_b.bounds.width).should be_close(
        sub_top.bounds.width - 2.0 * border_padding, 0.5)
    end
  end

  describe "all_nested_3x1_varying_column_counts" do
    # 3×1 outer grid where ALL cells are bordered sub-grids with DIFFERENT numbers of columns.
    # Row 0: 3-column sub-grid [A, BC, DEF]
    # Row 1: 2-column sub-grid [D, E]
    # Row 2: 1-column sub-grid [F]
    # All with border_color, spacing=4.0 within each sub-grid, spacing=4.0 in outer.
    # Column alignment: col0 of rows 1 and 2 should match col0 of row 0.
    #
    # Ground truth from fixed code (bfa3647):
    #   outer: 124.4×116.0
    #   sub0: (0,0,124.4,36), sub1: (0,40,124.4,36), sub2: (0,80,124.4,36)
    #   a: (6,6,30.4,24), b: (40.4,6,38.8,24), c: (83.2,6,35.2,24)
    #   d: (6,6,30.4,24), e: (40.4,6,78.0,24)
    #   f: (6,6,112.4,24)
    it "3x1 all-nested: different column counts but col0 aligns across all rows" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      btn_a = btn5("A"); btn_b = btn5("BC"); btn_c = btn5("DEF")
      sub0 = CrymbleUI::RecursiveGrid.new(content: [[btn_a, btn_b, btn_c]], spacing: 4.0)
      sub0.border_color = border_color

      btn_d = btn5("D"); btn_e = btn5("E")
      sub1 = CrymbleUI::RecursiveGrid.new(content: [[btn_d, btn_e]], spacing: 4.0)
      sub1.border_color = border_color

      btn_f = btn5("F")
      sub2 = CrymbleUI::RecursiveGrid.new(content: [[btn_f]], spacing: 4.0)
      sub2.border_color = border_color

      outer = CrymbleUI::RecursiveGrid.new(
        content: [
          [sub0.as(CrymbleUI::Widget)],
          [sub1.as(CrymbleUI::Widget)],
          [sub2.as(CrymbleUI::Widget)]
        ],
        spacing: 4.0
      )

      outer.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Outer total size
      outer.bounds.x.should be_close(0.0, 0.5)
      outer.bounds.y.should be_close(0.0, 0.5)
      outer.bounds.width.should be_close(124.4, 0.5)
      outer.bounds.height.should be_close(116.0, 0.5)

      # All 3 sub-grids span full outer width
      sub0.bounds.x.should be_close(0.0, 0.5)
      sub0.bounds.y.should be_close(0.0, 0.5)
      sub0.bounds.width.should be_close(124.4, 0.5)
      sub0.bounds.height.should be_close(36.0, 0.5)

      sub1.bounds.x.should be_close(0.0, 0.5)
      sub1.bounds.y.should be_close(40.0, 0.5)  # 36 + 4 (spacing)
      sub1.bounds.width.should be_close(124.4, 0.5)
      sub1.bounds.height.should be_close(36.0, 0.5)

      sub2.bounds.x.should be_close(0.0, 0.5)
      sub2.bounds.y.should be_close(80.0, 0.5)  # 36+4+36+4
      sub2.bounds.width.should be_close(124.4, 0.5)
      sub2.bounds.height.should be_close(36.0, 0.5)

      # Row 0 (3-column): a, b, c
      btn_a.bounds.x.should be_close(6.0, 0.5)
      btn_a.bounds.y.should be_close(6.0, 0.5)
      btn_a.bounds.width.should be_close(30.4, 0.5)
      btn_a.bounds.height.should be_close(24.0, 0.5)

      btn_b.bounds.x.should be_close(40.4, 0.5)
      btn_b.bounds.y.should be_close(6.0, 0.5)
      btn_b.bounds.width.should be_close(38.8, 0.5)
      btn_b.bounds.height.should be_close(24.0, 0.5)

      btn_c.bounds.x.should be_close(83.2, 0.5)
      btn_c.bounds.y.should be_close(6.0, 0.5)
      btn_c.bounds.width.should be_close(35.2, 0.5)
      btn_c.bounds.height.should be_close(24.0, 0.5)

      # Row 1 (2-column): d aligns with a (col0), e fills remaining
      btn_d.bounds.x.should be_close(6.0, 0.5)
      btn_d.bounds.y.should be_close(6.0, 0.5)
      btn_d.bounds.width.should be_close(30.4, 0.5)
      btn_d.bounds.height.should be_close(24.0, 0.5)

      btn_e.bounds.x.should be_close(40.4, 0.5)
      btn_e.bounds.y.should be_close(6.0, 0.5)
      btn_e.bounds.width.should be_close(78.0, 0.5)  # absorbs remaining cols
      btn_e.bounds.height.should be_close(24.0, 0.5)

      # Row 2 (1-column): f fills full content width
      btn_f.bounds.x.should be_close(6.0, 0.5)
      btn_f.bounds.y.should be_close(6.0, 0.5)
      btn_f.bounds.width.should be_close(112.4, 0.5)  # 124.4 - 2*6
      btn_f.bounds.height.should be_close(24.0, 0.5)

      # Key invariant: col0 alignment — btn_a, btn_d, btn_f all start at x=border_padding
      btn_a.bounds.x.should be_close(btn_d.bounds.x, 0.5)
      btn_a.bounds.x.should be_close(btn_f.bounds.x, 0.5)

      # btn_a and btn_d have same width (same outer virtual col0)
      btn_a.bounds.width.should be_close(btn_d.bounds.width, 0.5)
    end
  end

  describe "all_nested_2x2_different_col_widths_per_row" do
    # 2×2 outer grid where ALL cells are bordered sub-grids.
    # Each sub-grid has different internal column widths.
    # Tests column alignment within each outer column (col0 and col1).
    #
    # Layout:
    #   [sub_tl([A, BCD]), sub_tr([CD])]
    #   [sub_bl([D, E]),   sub_br([FGHI])]
    # All sub-grids have border_color, spacing=0.
    #
    # Ground truth from fixed code (bfa3647):
    #   outer: 133.2×72.0
    #   sub_tl: (0,0,77.6,36), sub_tr: (77.6,0,55.6,36)
    #   sub_bl: (0,36,77.6,36), sub_br: (77.6,36,55.6,36)
    #   t1_a: (6,6,30.4,24), t1_b: (36.4,6,35.2,24)
    #   t2_c: (6,6,43.6,24)
    #   b1_d: (6,6,30.4,24), b1_e: (36.4,6,35.2,24)
    #   b2_f: (6,6,43.6,24)
    it "2x2 all-nested: left-column grids align col0, right-column grids align their content" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      t1_a = btn5("A"); t1_b = btn5("BCD")
      sub_tl = CrymbleUI::RecursiveGrid.new(content: [[t1_a, t1_b]], spacing: 0.0)
      sub_tl.border_color = border_color

      t2_c = btn5("CD")
      sub_tr = CrymbleUI::RecursiveGrid.new(content: [[t2_c]], spacing: 0.0)
      sub_tr.border_color = border_color

      b1_d = btn5("D"); b1_e = btn5("E")
      sub_bl = CrymbleUI::RecursiveGrid.new(content: [[b1_d, b1_e]], spacing: 0.0)
      sub_bl.border_color = border_color

      b2_f = btn5("FGHI")
      sub_br = CrymbleUI::RecursiveGrid.new(content: [[b2_f]], spacing: 0.0)
      sub_br.border_color = border_color

      outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub_tl.as(CrymbleUI::Widget), sub_tr.as(CrymbleUI::Widget)],
                  [sub_bl.as(CrymbleUI::Widget), sub_br.as(CrymbleUI::Widget)]],
        spacing: 0.0
      )

      outer.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # Outer total size
      outer.bounds.x.should be_close(0.0, 0.5)
      outer.bounds.y.should be_close(0.0, 0.5)
      outer.bounds.width.should be_close(133.2, 0.5)
      outer.bounds.height.should be_close(72.0, 0.5)

      # Top row sub-grids
      sub_tl.bounds.x.should be_close(0.0, 0.5)
      sub_tl.bounds.y.should be_close(0.0, 0.5)
      sub_tl.bounds.width.should be_close(77.6, 0.5)
      sub_tl.bounds.height.should be_close(36.0, 0.5)

      sub_tr.bounds.x.should be_close(77.6, 0.5)
      sub_tr.bounds.y.should be_close(0.0, 0.5)
      sub_tr.bounds.width.should be_close(55.6, 0.5)
      sub_tr.bounds.height.should be_close(36.0, 0.5)

      # Bottom row sub-grids
      sub_bl.bounds.x.should be_close(0.0, 0.5)
      sub_bl.bounds.y.should be_close(36.0, 0.5)
      sub_bl.bounds.width.should be_close(77.6, 0.5)
      sub_bl.bounds.height.should be_close(36.0, 0.5)

      sub_br.bounds.x.should be_close(77.6, 0.5)
      sub_br.bounds.y.should be_close(36.0, 0.5)
      sub_br.bounds.width.should be_close(55.6, 0.5)
      sub_br.bounds.height.should be_close(36.0, 0.5)

      # sub_tl contents: [A, BCD] at (6,6)
      t1_a.bounds.x.should be_close(6.0, 0.5)
      t1_a.bounds.y.should be_close(6.0, 0.5)
      t1_a.bounds.width.should be_close(30.4, 0.5)
      t1_a.bounds.height.should be_close(24.0, 0.5)

      t1_b.bounds.x.should be_close(36.4, 0.5)
      t1_b.bounds.y.should be_close(6.0, 0.5)
      t1_b.bounds.width.should be_close(35.2, 0.5)
      t1_b.bounds.height.should be_close(24.0, 0.5)

      # sub_tr contents: [CD] fills content area
      t2_c.bounds.x.should be_close(6.0, 0.5)
      t2_c.bounds.y.should be_close(6.0, 0.5)
      t2_c.bounds.width.should be_close(43.6, 0.5)
      t2_c.bounds.height.should be_close(24.0, 0.5)

      # sub_bl contents: [D, E] aligns with sub_tl
      b1_d.bounds.x.should be_close(6.0, 0.5)
      b1_d.bounds.y.should be_close(6.0, 0.5)
      b1_d.bounds.width.should be_close(30.4, 0.5)
      b1_d.bounds.height.should be_close(24.0, 0.5)

      b1_e.bounds.x.should be_close(36.4, 0.5)
      b1_e.bounds.y.should be_close(6.0, 0.5)
      b1_e.bounds.width.should be_close(35.2, 0.5)
      b1_e.bounds.height.should be_close(24.0, 0.5)

      # sub_br contents: [FGHI] fills content area
      b2_f.bounds.x.should be_close(6.0, 0.5)
      b2_f.bounds.y.should be_close(6.0, 0.5)
      b2_f.bounds.width.should be_close(43.6, 0.5)
      b2_f.bounds.height.should be_close(24.0, 0.5)

      # Key invariant: same outer column → same sub-grid width
      sub_tl.bounds.width.should be_close(sub_bl.bounds.width, 0.5)
      sub_tr.bounds.width.should be_close(sub_br.bounds.width, 0.5)

      # Column alignment within outer col0 grids: t1_a and b1_d have same width
      t1_a.bounds.width.should be_close(b1_d.bounds.width, 0.5)
      t1_a.bounds.x.should be_close(b1_d.bounds.x, 0.5)
      t1_b.bounds.width.should be_close(b1_e.bounds.width, 0.5)
      t1_b.bounds.x.should be_close(b1_e.bounds.x, 0.5)
    end
  end

  describe "all_nested_fieldlist_like_tight" do
    # 2×1 outer grid simulating the fieldlist use case:
    # Row 0: bordered sub-grid with [Person(6ch), Time(4ch), Project(7ch)]
    # Row 1: bordered sub-grid with [Alloc(5ch), Budget(6ch)]
    # Tight 1.5× natural constraints.
    # Column 0 of row 0 (Person) must align with col 0 of row 1 (Alloc).
    #
    # Button widths (6px/char * 1.4 factor + 10px padding):
    #   Person(6ch):  6*14*0.6+10=60.4, Time(4ch): 4*14*0.6+10=43.6,
    #   Project(7ch): 7*14*0.6+10=68.8, Alloc(5ch): 5*14*0.6+10=52.0,
    #   Budget(6ch):  60.4
    # Wait — btn5 uses padding=5, font_scale=0 → size=14:
    #   "Person"(6ch): w=6*14*0.6+10=60.4, h=14+10=24
    #   "Time"(4ch):   w=4*14*0.6+10=43.6, h=24
    #   "Project"(7ch): w=7*14*0.6+10=68.8, h=24
    #   "Alloc"(5ch):   w=5*14*0.6+10=52.0, h=24
    #   "Budget"(6ch):  w=60.4, h=24
    # sub_row0 natural: [60.4,43.6,68.8]+12ea border + 2*4 spacing = 60.4+12+43.6+12+68.8+12+8=216.8
    # sub_row1 natural: [52.0,60.4]+12ea + 4 spacing = 52+12+60.4+12+4=140.4
    # outer col0=216.8 (dominates), outer natural=216.8+12+4=232.8? No, outer is 1-col Nx1 grid.
    # Outer is Nx1: only 1 outer col. Each outer row gets same width.
    # Ground truth from fixed code (bfa3647):
    #   Natural outer: 216.8×76.0 (row0=36, spacing=4, row1=36)
    #   Tight 1.5×: outer=325.2×114.0
    #   sub_row0: (0,0,325.2,55), sub_row1: (0,59,325.2,55)
    #   person: (6,6,109.987,43), time_b: (119.987,6,84.465,43), project: (208.452,6,110.748,43)
    #   allocation: (6,6,109.987,43), budget: (119.987,6,199.213,43)
    it "fieldlist-like: person and allocation align in col0 after 1.5x scaling" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      border_padding = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      person = btn5("Person")     # 6 chars
      time_b = btn5("Time")       # 4 chars
      project_b = btn5("Project") # 7 chars
      sub_row0 = CrymbleUI::RecursiveGrid.new(content: [[person, time_b, project_b]], spacing: 4.0)
      sub_row0.border_color = border_color

      allocation = btn5("Alloc")  # 5 chars
      budget = btn5("Budget")     # 6 chars
      sub_row1 = CrymbleUI::RecursiveGrid.new(content: [[allocation, budget]], spacing: 4.0)
      sub_row1.border_color = border_color

      outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub_row0.as(CrymbleUI::Widget)], [sub_row1.as(CrymbleUI::Widget)]],
        spacing: 4.0
      )

      natural = outer.measure(CrymbleUI::BoxConstraints.new)
      natural.width.should be_close(216.8, 0.5)
      natural.height.should be_close(76.0, 0.5)

      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 1.5, natural.height * 1.5))
      outer.layout(tight, CrymbleUI::Vec2.zero)

      # Outer fills tight constraint
      outer.bounds.width.should be_close(325.2, 0.5)
      outer.bounds.height.should be_close(114.0, 0.5)

      # Both sub-grids span full outer width
      sub_row0.bounds.x.should be_close(0.0, 0.5)
      sub_row0.bounds.y.should be_close(0.0, 0.5)
      sub_row0.bounds.width.should be_close(325.2, 0.5)
      sub_row0.bounds.height.should be_close(55.0, 0.5)

      sub_row1.bounds.x.should be_close(0.0, 0.5)
      sub_row1.bounds.y.should be_close(59.0, 0.5)  # 55 + 4 spacing
      sub_row1.bounds.width.should be_close(325.2, 0.5)
      sub_row1.bounds.height.should be_close(55.0, 0.5)

      # sub_row0 buttons
      person.bounds.x.should be_close(6.0, 0.5)
      person.bounds.y.should be_close(6.0, 0.5)
      person.bounds.width.should be_close(109.987, 0.5)
      person.bounds.height.should be_close(43.0, 0.5)

      time_b.bounds.x.should be_close(119.987, 0.5)
      time_b.bounds.y.should be_close(6.0, 0.5)
      time_b.bounds.width.should be_close(84.465, 0.5)
      time_b.bounds.height.should be_close(43.0, 0.5)

      project_b.bounds.x.should be_close(208.452, 0.5)
      project_b.bounds.y.should be_close(6.0, 0.5)
      project_b.bounds.width.should be_close(110.748, 0.5)
      project_b.bounds.height.should be_close(43.0, 0.5)

      # sub_row1 buttons
      allocation.bounds.x.should be_close(6.0, 0.5)
      allocation.bounds.y.should be_close(6.0, 0.5)
      allocation.bounds.width.should be_close(109.987, 0.5)
      allocation.bounds.height.should be_close(43.0, 0.5)

      budget.bounds.x.should be_close(119.987, 0.5)
      budget.bounds.y.should be_close(6.0, 0.5)
      budget.bounds.width.should be_close(199.213, 0.5)
      budget.bounds.height.should be_close(43.0, 0.5)

      # Key invariant: column 0 alignment — person and allocation start at same x
      person.bounds.x.should be_close(allocation.bounds.x, 0.5)

      # Key invariant: column 0 width matches between rows
      person.bounds.width.should be_close(allocation.bounds.width, 0.5)

      # Column 1 of row0 aligns with col1 of row1
      time_b.bounds.x.should be_close(budget.bounds.x, 0.5)
    end
  end

  describe "exact_demo_layout_mixed_nesting" do
    # Exact demo layout: 3×2 outer grid with mixed nesting depths.
    # Matches the interactive grid structure from recursive_grid_demo.cr:
    # Row 0: [Sub(Hello), Sub(Sub(4))]  — single-nested, double-nested
    # Row 1: [Sub(5),     Sub(Sub(6))]  — single-nested, double-nested
    # Row 2: [Sub(2),     Sub(3)]       — single-nested, single-nested
    #
    # Outer grid: spacing=4.0, cell_background_color=cell_bg (but all cells are RecursiveGrids
    #   so no VStack wrapping — sub-grids used directly)
    # Sub-grids: border_color set (bp=6.0), spacing=6.0 (edit mode)
    # Deep-nested: outer has border_color, inner has border_color, inner contains button
    #
    # Button sizing: "Hello"(5ch)=50.4×24, "4","5","6","2","3"(1ch)=18.4×24
    # Single-nested sub natural size = btn + 2*bp = btn + 12
    #   hello_sub: (50.4+12)×(24+12) = 62.4×36
    #   sub2,sub3,sub5: (18.4+12)×(24+12) = 30.4×36
    # Double-nested (outer wraps inner wraps btn):
    #   btn natural: 18.4×24
    #   inner: (18.4+12)×(24+12) = 30.4×36
    #   outer: (30.4+12)×(36+12) = 42.4×48
    #
    # Outer col widths (spacing=4, natural, all sub-grids used as cells):
    #   col0 = max(hello_sub.w, sub5.w, sub2.w) = max(62.4, 30.4, 30.4) = 62.4
    #   col1 = max(sub4_outer.w, sub6_outer.w, sub3.w) = max(42.4, 42.4, 30.4) = 42.4
    # Outer row heights:
    #   row0 = max(hello_sub.h, sub4_outer.h) = max(36, 48) = 48
    #   row1 = max(sub5.h, sub6_outer.h) = max(36, 48) = 48
    #   row2 = max(sub2.h, sub3.h) = max(36, 36) = 36
    # Natural outer: (62.4+4+42.4)×(48+4+48+4+36) = 108.8×140
    #
    # With 1.5× tight: outer = 163.2×210
    # Scale factors:
    #   x_scale = (163.2 - 8) / (62.4 + 42.4) = 155.2 / 104.8 ≈ 1.4809...
    #   Actually scale_to_fill divides available by total:
    #   available_w = 163.2 - 0 (no border) - 4*(2-1) = 163.2 - 4 = 159.2
    #   col0_scaled = 62.4 * 159.2 / 104.8 ≈ 94.695..., col1_scaled = 42.4 * 159.2 / 104.8 ≈ 64.504...
    #   available_h = 210 - 4*(3-1) = 210 - 8 = 202
    #   row0_scaled = 48 * 202 / 132 ≈ 73.45..., row1_scaled = 48 * ... ≈ 73.45..., row2_scaled = 36 * ... ≈ 55.09...
    # Ground truth obtained by running original (441e594): see hardcoded values below.

    it "exact demo layout: mixed nesting depths with borders and tight constraints" do
      border_color = CrymbleUI::Color.new(200, 50, 50, 255)
      cell_bg = CrymbleUI::Color.new(180, 200, 220, 255)
      bp = CrymbleUI::RecursiveGrid::BORDER_WIDTH + 4.0  # = 6.0

      # Single-nested sub-grid: wraps a button
      hello_btn = CrymbleUI::Button.new("Hello", padding: 5.0)
      hello_sub = CrymbleUI::RecursiveGrid.new(
        content: [[hello_btn.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      hello_sub.border_color = border_color

      btn5_widget = CrymbleUI::Button.new("5", padding: 5.0)
      sub5 = CrymbleUI::RecursiveGrid.new(
        content: [[btn5_widget.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub5.border_color = border_color

      btn2 = CrymbleUI::Button.new("2", padding: 5.0)
      sub2 = CrymbleUI::RecursiveGrid.new(
        content: [[btn2.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub2.border_color = border_color

      btn3 = CrymbleUI::Button.new("3", padding: 5.0)
      sub3 = CrymbleUI::RecursiveGrid.new(
        content: [[btn3.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub3.border_color = border_color

      # Double-nested: inner wraps button, outer wraps inner
      btn4 = CrymbleUI::Button.new("4", padding: 5.0)
      sub4_inner = CrymbleUI::RecursiveGrid.new(
        content: [[btn4.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub4_inner.border_color = border_color
      sub4_outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub4_inner.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub4_outer.border_color = border_color

      btn6 = CrymbleUI::Button.new("6", padding: 5.0)
      sub6_inner = CrymbleUI::RecursiveGrid.new(
        content: [[btn6.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub6_inner.border_color = border_color
      sub6_outer = CrymbleUI::RecursiveGrid.new(
        content: [[sub6_inner.as(CrymbleUI::Widget)]],
        spacing: 6.0
      )
      sub6_outer.border_color = border_color

      # Outer 3×2 grid with cell_background_color
      # (all cells are RecursiveGrid → no VStack wrapping)
      grid = CrymbleUI::RecursiveGrid.new(
        content: [
          [hello_sub.as(CrymbleUI::Widget), sub4_outer.as(CrymbleUI::Widget)],
          [sub5.as(CrymbleUI::Widget),       sub6_outer.as(CrymbleUI::Widget)],
          [sub2.as(CrymbleUI::Widget),        sub3.as(CrymbleUI::Widget)],
        ],
        spacing: 4.0,
        cell_background_color: cell_bg
      )

      # Measure natural size, then layout with 1.5× tight constraints
      natural = grid.measure(CrymbleUI::BoxConstraints.new)
      tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(natural.width * 1.5, natural.height * 1.5))
      grid.layout(tight, CrymbleUI::Vec2.zero)

      # Structural invariants (independent of exact pixel values):
      # 1. Single-nested: child is inside parent at (bp, bp), fills content area
      [
        {hello_sub, hello_btn.as(CrymbleUI::Widget)},
        {sub5,      btn5_widget.as(CrymbleUI::Widget)},
        {sub2,      btn2.as(CrymbleUI::Widget)},
        {sub3,      btn3.as(CrymbleUI::Widget)},
      ].each do |sub, btn|
        child = sub.children.first
        child.bounds.x.should be_close(bp, 0.5)
        child.bounds.y.should be_close(bp, 0.5)
        child.bounds.width.should be_close(sub.bounds.width - 2.0 * bp, 0.5)
        child.bounds.height.should be_close(sub.bounds.height - 2.0 * bp, 0.5)
      end

      # 2. Double-nested: outer→inner at (bp,bp), inner→btn at (bp,bp)
      [
        {sub4_outer, sub4_inner, btn4},
        {sub6_outer, sub6_inner, btn6},
      ].each do |outer_sub, inner_sub, btn|
        inner_sub.bounds.x.should be_close(bp, 0.5)
        inner_sub.bounds.y.should be_close(bp, 0.5)
        inner_sub.bounds.width.should be_close(outer_sub.bounds.width - 2.0 * bp, 0.5)
        inner_sub.bounds.height.should be_close(outer_sub.bounds.height - 2.0 * bp, 0.5)

        btn_child = inner_sub.children.first
        btn_child.bounds.x.should be_close(bp, 0.5)
        btn_child.bounds.y.should be_close(bp, 0.5)
        btn_child.bounds.width.should be_close(inner_sub.bounds.width - 2.0 * bp, 0.5)
        btn_child.bounds.height.should be_close(inner_sub.bounds.height - 2.0 * bp, 0.5)
      end

      # 3. Sub-grids in same row don't overlap (horizontal adjacency)
      (hello_sub.bounds.x + hello_sub.bounds.width + grid.spacing).should be_close(sub4_outer.bounds.x, 0.5)
      (sub5.bounds.x + sub5.bounds.width + grid.spacing).should be_close(sub6_outer.bounds.x, 0.5)
      (sub2.bounds.x + sub2.bounds.width + grid.spacing).should be_close(sub3.bounds.x, 0.5)

      # 4. Sub-grids in same column are vertically adjacent
      (hello_sub.bounds.y + hello_sub.bounds.height + grid.spacing).should be_close(sub5.bounds.y, 0.5)
      (sub5.bounds.y + sub5.bounds.height + grid.spacing).should be_close(sub2.bounds.y, 0.5)

      # 5. Grid spacing value
      grid.spacing.should be_close(4.0, 0.001)

      # 6. Sub-grids in same column have same width (column alignment)
      hello_sub.bounds.width.should be_close(sub5.bounds.width, 0.5)
      sub5.bounds.width.should be_close(sub2.bounds.width, 0.5)
      sub4_outer.bounds.width.should be_close(sub6_outer.bounds.width, 0.5)
      sub6_outer.bounds.width.should be_close(sub3.bounds.width, 0.5)

      # 7. Grid fills tight constraint
      grid.bounds.width.should be_close(natural.width * 1.5, 0.5)
      grid.bounds.height.should be_close(natural.height * 1.5, 0.5)

      # 8. Hardcoded ground truth bounds (measured from original 441e594, run 2026-03-25):
      natural.width.should be_close(110.4, 0.5)
      natural.height.should be_close(140.0, 0.5)

      # Grid bounds (1.5× tight)
      grid.bounds.x.should be_close(0.0, 0.5)
      grid.bounds.y.should be_close(0.0, 0.5)
      grid.bounds.width.should be_close(165.6, 0.5)
      grid.bounds.height.should be_close(210.0, 0.5)

      # hello_sub [0,0] — col0, row0 (scaled up to fit)
      hello_sub.bounds.x.should be_close(0.0, 0.5)
      hello_sub.bounds.y.should be_close(0.0, 0.5)
      hello_sub.bounds.width.should be_close(97.203, 0.5)
      hello_sub.bounds.height.should be_close(73.455, 0.5)

      # hello_btn inside hello_sub: at (bp, bp), fills content area
      hello_btn.bounds.x.should be_close(6.0, 0.5)
      hello_btn.bounds.y.should be_close(6.0, 0.5)
      hello_btn.bounds.width.should be_close(85.203, 0.5)
      hello_btn.bounds.height.should be_close(61.455, 0.5)

      # sub4_outer [0,1] — col1, row0 (spans same row height as hello_sub)
      sub4_outer.bounds.x.should be_close(101.203, 0.5)
      sub4_outer.bounds.y.should be_close(0.0, 0.5)
      sub4_outer.bounds.width.should be_close(64.397, 0.5)
      sub4_outer.bounds.height.should be_close(73.455, 0.5)

      # sub4_inner inside sub4_outer: at (bp, bp)
      sub4_inner.bounds.x.should be_close(6.0, 0.5)
      sub4_inner.bounds.y.should be_close(6.0, 0.5)
      sub4_inner.bounds.width.should be_close(52.397, 0.5)
      sub4_inner.bounds.height.should be_close(61.455, 0.5)

      # btn4 inside sub4_inner: at (bp, bp)
      btn4.bounds.x.should be_close(6.0, 0.5)
      btn4.bounds.y.should be_close(6.0, 0.5)
      btn4.bounds.width.should be_close(40.397, 0.5)
      btn4.bounds.height.should be_close(49.455, 0.5)

      # sub5 [1,0] — col0, row1 (same column width as hello_sub)
      sub5.bounds.x.should be_close(0.0, 0.5)
      sub5.bounds.y.should be_close(77.455, 0.5)
      sub5.bounds.width.should be_close(97.203, 0.5)
      sub5.bounds.height.should be_close(73.455, 0.5)

      # btn5 inside sub5: at (bp, bp)
      btn5_widget.bounds.x.should be_close(6.0, 0.5)
      btn5_widget.bounds.y.should be_close(6.0, 0.5)
      btn5_widget.bounds.width.should be_close(85.203, 0.5)
      btn5_widget.bounds.height.should be_close(61.455, 0.5)

      # sub6_outer [1,1] — col1, row1 (same dimensions as sub4_outer)
      sub6_outer.bounds.x.should be_close(101.203, 0.5)
      sub6_outer.bounds.y.should be_close(77.455, 0.5)
      sub6_outer.bounds.width.should be_close(64.397, 0.5)
      sub6_outer.bounds.height.should be_close(73.455, 0.5)

      # sub6_inner inside sub6_outer: at (bp, bp)
      sub6_inner.bounds.x.should be_close(6.0, 0.5)
      sub6_inner.bounds.y.should be_close(6.0, 0.5)
      sub6_inner.bounds.width.should be_close(52.397, 0.5)
      sub6_inner.bounds.height.should be_close(61.455, 0.5)

      # btn6 inside sub6_inner: at (bp, bp)
      btn6.bounds.x.should be_close(6.0, 0.5)
      btn6.bounds.y.should be_close(6.0, 0.5)
      btn6.bounds.width.should be_close(40.397, 0.5)
      btn6.bounds.height.should be_close(49.455, 0.5)

      # sub2 [2,0] — col0, row2 (shorter row height than rows 0&1)
      sub2.bounds.x.should be_close(0.0, 0.5)
      sub2.bounds.y.should be_close(154.909, 0.5)
      sub2.bounds.width.should be_close(97.203, 0.5)
      sub2.bounds.height.should be_close(55.091, 0.5)

      # btn2 inside sub2: at (bp, bp)
      btn2.bounds.x.should be_close(6.0, 0.5)
      btn2.bounds.y.should be_close(6.0, 0.5)
      btn2.bounds.width.should be_close(85.203, 0.5)
      btn2.bounds.height.should be_close(43.091, 0.5)

      # sub3 [2,1] — col1, row2 (same width as sub4/sub6 column, same height as sub2)
      sub3.bounds.x.should be_close(101.203, 0.5)
      sub3.bounds.y.should be_close(154.909, 0.5)
      sub3.bounds.width.should be_close(64.397, 0.5)
      sub3.bounds.height.should be_close(55.091, 0.5)

      # btn3 inside sub3: at (bp, bp), fills content area
      btn3.bounds.x.should be_close(6.0, 0.5)
      btn3.bounds.y.should be_close(6.0, 0.5)
      btn3.bounds.width.should be_close(52.397, 0.5)
      btn3.bounds.height.should be_close(43.091, 0.5)
    end
  end

  describe "spacing_variations" do
    # Same 2×2 grid with spacing=0 vs spacing=10
    # spacing=0: grid=36.8×48, B at x=18.4, C at y=24
    # spacing=10: grid=46.8×58, B at x=28.4 (18.4+10), C at y=34 (24+10)
    # Cell sizes unchanged: each cell still 18.4×24
    # Grid size difference: exactly 10 in each dimension (1 gap per dimension)
    it "spacing=0 vs spacing=10: positions differ by spacing, cell sizes unchanged" do
      # spacing=0
      a0 = btn5("A"); b0 = btn5("B"); c0 = btn5("C"); d0 = btn5("D")
      grid0 = CrymbleUI::RecursiveGrid.new(
        content: [[a0, b0], [c0, d0]],
        spacing: 0.0
      )
      grid0.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # spacing=10
      a10 = btn5("A"); b10 = btn5("B"); c10 = btn5("C"); d10 = btn5("D")
      grid10 = CrymbleUI::RecursiveGrid.new(
        content: [[a10, b10], [c10, d10]],
        spacing: 10.0
      )
      grid10.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      # spacing=0: all positions
      grid0.bounds.width.should be_close(36.8, 0.5)
      grid0.bounds.height.should be_close(48.0, 0.5)
      a0.bounds.x.should be_close(0.0, 0.5)
      a0.bounds.y.should be_close(0.0, 0.5)
      a0.bounds.width.should be_close(18.4, 0.5)
      a0.bounds.height.should be_close(24.0, 0.5)
      b0.bounds.x.should be_close(18.4, 0.5)
      b0.bounds.y.should be_close(0.0, 0.5)
      b0.bounds.width.should be_close(18.4, 0.5)
      b0.bounds.height.should be_close(24.0, 0.5)
      c0.bounds.x.should be_close(0.0, 0.5)
      c0.bounds.y.should be_close(24.0, 0.5)
      c0.bounds.width.should be_close(18.4, 0.5)
      c0.bounds.height.should be_close(24.0, 0.5)
      d0.bounds.x.should be_close(18.4, 0.5)
      d0.bounds.y.should be_close(24.0, 0.5)
      d0.bounds.width.should be_close(18.4, 0.5)
      d0.bounds.height.should be_close(24.0, 0.5)

      # spacing=10: all positions
      grid10.bounds.width.should be_close(46.8, 0.5)
      grid10.bounds.height.should be_close(58.0, 0.5)
      a10.bounds.x.should be_close(0.0, 0.5)
      a10.bounds.y.should be_close(0.0, 0.5)
      a10.bounds.width.should be_close(18.4, 0.5)
      a10.bounds.height.should be_close(24.0, 0.5)
      b10.bounds.x.should be_close(28.4, 0.5)
      b10.bounds.y.should be_close(0.0, 0.5)
      b10.bounds.width.should be_close(18.4, 0.5)
      b10.bounds.height.should be_close(24.0, 0.5)
      c10.bounds.x.should be_close(0.0, 0.5)
      c10.bounds.y.should be_close(34.0, 0.5)
      c10.bounds.width.should be_close(18.4, 0.5)
      c10.bounds.height.should be_close(24.0, 0.5)
      d10.bounds.x.should be_close(28.4, 0.5)
      d10.bounds.y.should be_close(34.0, 0.5)
      d10.bounds.width.should be_close(18.4, 0.5)
      d10.bounds.height.should be_close(24.0, 0.5)

      # Size difference = exactly one spacing gap per dimension
      (grid10.bounds.width - grid0.bounds.width).should be_close(10.0, 0.5)
      (grid10.bounds.height - grid0.bounds.height).should be_close(10.0, 0.5)

      # Cell sizes are spacing-independent
      a0.bounds.width.should be_close(a10.bounds.width, 0.5)
      a0.bounds.height.should be_close(a10.bounds.height, 0.5)
    end
  end
end
