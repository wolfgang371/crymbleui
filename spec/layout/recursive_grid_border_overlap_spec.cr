require "../spec_helper"
require "../../src/layout/recursive_grid"
require "../../src/layout/vstack"
require "../../src/widgets/button"
require "../../src/rendering/draw_primitive"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Border overlap tests for RecursiveGrid
#
# INVARIANT: Border FillRect primitives from different nesting levels
# must NEVER overlap (intersect). Each grid level's borders must be
# contained within its own area, not extending into nested sub-grids.

BORDER_COLOR = CrymbleUI::Color.new(200_u8, 50_u8, 50_u8, 255_u8)

private def btn(label : String) : CrymbleUI::Button
  CrymbleUI::Button.new(label, padding: 5.0)
end

# Demo-style cell: VStack with TBLR/Sub button row + content button
private def demo_cell(label : String) : CrymbleUI::VStack
  vs = CrymbleUI::VStack.new(spacing: 2.0)
  hs = CrymbleUI::HStack.new(spacing: 1.0)
  %w(T B L R Sub).each { |l| hs.add_child(CrymbleUI::Button.new(l, padding: 1.0, font_scale: -3)) }
  vs.add_child(hs)
  vs.add_child(CrymbleUI::Button.new(label, padding: 6.0))
  vs
end

CELL_BG = CrymbleUI::Color.new(200_u8, 220_u8, 240_u8, 255_u8)

private def bordered_grid(content : Array(Array(CrymbleUI::Widget)), spacing = 6.0) : CrymbleUI::RecursiveGrid
  grid = CrymbleUI::RecursiveGrid.new(content: content, spacing: spacing, cell_background_color: CELL_BG)
  grid.border_color = BORDER_COLOR
  grid
end

private def layout_grid(grid : CrymbleUI::RecursiveGrid, width = 400.0, height = 300.0)
  renderer = CrymbleUI::Testing::TestRenderer.new(width.to_i32, height.to_i32)
  app = TestApp.new
  app.root_widget = grid
  app.build_tree
  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(width, height))
  grid.layout(constraints, CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
end

# Collect all border FillRect primitives from a grid and its nested sub-grids,
# converted to absolute coordinates. Returns array of {Rect, grid_depth}.
private def collect_border_rects(widget : CrymbleUI::Widget, depth = 0) : Array({CrymbleUI::Rect, Int32})
  result = Array({CrymbleUI::Rect, Int32}).new

  if widget.is_a?(CrymbleUI::RecursiveGrid) && widget.border_color
    abs = widget.absolute_bounds
    primitives = widget.to_primitives(widget.bounds)
    primitives.each do |prim|
      if prim.is_a?(CrymbleUI::FillRect) && prim.color == BORDER_COLOR
        # Convert widget-local rect to absolute coordinates
        abs_rect = CrymbleUI::Rect.new(
          abs.x + prim.bounds.x,
          abs.y + prim.bounds.y,
          prim.bounds.width,
          prim.bounds.height
        )
        result << {abs_rect, depth}
      end
    end
  end

  widget.children.each do |child|
    result.concat(collect_border_rects(child, depth + 1))
  end

  result
end

# Check if two rects overlap OR touch (share any area or boundary)
# Border rects from different levels must not even touch — that creates
# visual doubling (e.g., 2px outer + 2px inner = 4px combined border)
private def rects_overlap?(a : CrymbleUI::Rect, b : CrymbleUI::Rect) : Bool
  !(a.x + a.width < b.x || b.x + b.width < a.x ||
    a.y + a.height < b.y || b.y + b.height < a.y)
end

# Assert no border rects from DIFFERENT depths overlap
private def assert_no_cross_level_overlap(rects : Array({CrymbleUI::Rect, Int32}))
  rects.each_with_index do |(rect_a, depth_a), i|
    rects.each_with_index do |(rect_b, depth_b), j|
      next if i >= j          # don't double-check
      next if depth_a == depth_b  # same level can share edges
      rects_overlap?(rect_a, rect_b).should be_false,
        "Border overlap between depth #{depth_a} and #{depth_b}:\n" \
        "  rect_a: (#{rect_a.x.round(1)}, #{rect_a.y.round(1)}, #{rect_a.width.round(1)}×#{rect_a.height.round(1)})\n" \
        "  rect_b: (#{rect_b.x.round(1)}, #{rect_b.y.round(1)}, #{rect_b.width.round(1)}×#{rect_b.height.round(1)})"
    end
  end
end

# Assert that every child widget's absolute bounds is fully contained within its
# parent RecursiveGrid's content area (bounds minus border_padding).
# Children overflowing their parent's content area cause visual overlap with borders.
private def assert_children_within_parent_bounds(widget : CrymbleUI::Widget)
  if widget.is_a?(CrymbleUI::RecursiveGrid) && widget.border_color
    parent_abs = widget.absolute_bounds
    bp = 6.0 # border_padding = BORDER_WIDTH(2) + 4
    # Content area = parent bounds shrunk by border_padding on all sides
    content_left   = parent_abs.x + bp
    content_top    = parent_abs.y + bp
    content_right  = parent_abs.x + parent_abs.width - bp
    content_bottom = parent_abs.y + parent_abs.height - bp

    widget.children.each do |child|
      cab = child.absolute_bounds
      next if cab.width <= 0 || cab.height <= 0

      (cab.x >= content_left - 0.5).should be_true,
        "Child #{child.class.name}(#{child.id}) left edge #{cab.x.round(1)} overflows parent content area #{content_left.round(1)}"
      (cab.y >= content_top - 0.5).should be_true,
        "Child #{child.class.name}(#{child.id}) top edge #{cab.y.round(1)} overflows parent content area #{content_top.round(1)}"
      (cab.x + cab.width <= content_right + 0.5).should be_true,
        "Child #{child.class.name}(#{child.id}) right edge #{(cab.x + cab.width).round(1)} overflows parent content area #{content_right.round(1)}"
      (cab.y + cab.height <= content_bottom + 0.5).should be_true,
        "Child #{child.class.name}(#{child.id}) bottom edge #{(cab.y + cab.height).round(1)} overflows parent content area #{content_bottom.round(1)}"
    end
  end

  widget.children.each { |child| assert_children_within_parent_bounds(child) }
end

describe "RecursiveGrid border overlap" do
  # 1. Exact demo layout: 5 levels of nesting (5 red rects around cell 8)
  # L1: 2x3 [[2, Hello, 1], [3, L2, 5]]
  # L2: 1x1 [[L3]]
  # L3: 2x2 [[4, 6], [7, L4]]
  # L4: 1x1 [[L5]]
  # L5: 1x1 [[8]]
  it "no overlap: demo-style 5-level nesting with edit buttons" do
    l5 = bordered_grid([[demo_cell("8")]])
    l4 = bordered_grid([[l5]])
    l3 = bordered_grid([[demo_cell("4"), demo_cell("6")], [demo_cell("7"), l4]])
    l2 = bordered_grid([[l3]])
    l1 = bordered_grid([
      [demo_cell("2"), demo_cell("Hello"), demo_cell("1")],
      [demo_cell("3"), l2,                 demo_cell("5")],
    ])
    layout_grid(l1, 800.0, 600.0)
    rects = collect_border_rects(l1)
    depths = rects.map(&.[1]).uniq
    depths.size.should eq(5)
    assert_children_within_parent_bounds(l1)
    assert_no_cross_level_overlap(rects)
  end

  # 2. 4 levels, bottom-right cascade with demo_cells, tight
  it "no overlap: 4-level bottom-right cascade with edit buttons" do
    l4 = bordered_grid([[demo_cell("4")]])
    l3 = bordered_grid([[demo_cell("3"), l4]])
    l2 = bordered_grid([[l3]])
    l1 = bordered_grid([[demo_cell("1"), l2]])
    layout_grid(l1, 250.0, 200.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 3. 5 levels, each 2x1 with sub at right, demo_cells, tight
  it "no overlap: 5 levels 2x1 cascading right with edit buttons" do
    l5 = bordered_grid([[demo_cell("5a"), demo_cell("5b")]])
    l4 = bordered_grid([[demo_cell("4"), l5]])
    l3 = bordered_grid([[demo_cell("3"), l4]])
    l2 = bordered_grid([[demo_cell("2"), l3]])
    l1 = bordered_grid([[demo_cell("1"), l2]])
    layout_grid(l1, 300.0, 200.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 4. 3 levels, 2x2 at each level, demo_cells, tight
  it "no overlap: 3-level 2x2 cascade with edit buttons" do
    l3 = bordered_grid([[demo_cell("A"), demo_cell("B")], [demo_cell("C"), demo_cell("D")]])
    l2 = bordered_grid([[demo_cell("E"), l3], [demo_cell("F"), demo_cell("G")]])
    l1 = bordered_grid([[l2, demo_cell("H")], [demo_cell("I"), demo_cell("J")]])
    layout_grid(l1, 300.0, 250.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 5. Two 4-level nested sub-grids side by side, tight
  it "no overlap: two 4-level sub-grids side by side with edit buttons" do
    a3 = bordered_grid([[demo_cell("a3")]])
    a2 = bordered_grid([[demo_cell("a2"), a3]])
    a1 = bordered_grid([[a2]])
    b3 = bordered_grid([[demo_cell("b3")]])
    b2 = bordered_grid([[demo_cell("b2"), b3]])
    b1 = bordered_grid([[b2]])
    outer = bordered_grid([[a1, b1]])
    layout_grid(outer, 300.0, 200.0)
    assert_no_cross_level_overlap(collect_border_rects(outer))
    assert_children_within_parent_bounds(outer)
  end

  # 6. 5 levels, sub-grid in corner of 2x2 with demo_cells, tight
  it "no overlap: 5-level nesting in 2x2 corner" do
    l5 = bordered_grid([[demo_cell("Z")]])
    l4 = bordered_grid([[demo_cell("W"), l5]])
    l3 = bordered_grid([[l4]])
    l2 = bordered_grid([[l3]])
    l1 = bordered_grid([
      [demo_cell("A"), demo_cell("B")],
      [demo_cell("C"), l2],
    ])
    layout_grid(l1, 250.0, 200.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 7. 5 levels cascading bottom-right, 2x2 at each level
  it "no overlap: 5-level 2x2 bottom-right cascade with edit buttons" do
    l5 = bordered_grid([[demo_cell("5a"), demo_cell("5b")], [demo_cell("5c"), demo_cell("5d")]])
    l4 = bordered_grid([[demo_cell("4"), l5]])
    l3 = bordered_grid([[demo_cell("3"), l4]])
    l2 = bordered_grid([[demo_cell("2"), l3]])
    l1 = bordered_grid([[demo_cell("1"), l2]])
    layout_grid(l1, 300.0, 250.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 8. 5 levels, 2x2 at each, all demo_cells, very tight
  it "no overlap: 5-level 2x2 all demo_cells very tight" do
    l5 = bordered_grid([[demo_cell("5a"), demo_cell("5b")], [demo_cell("5c"), demo_cell("5d")]])
    l4 = bordered_grid([[demo_cell("4a"), demo_cell("4b")], [demo_cell("4c"), l5]])
    l3 = bordered_grid([[demo_cell("3a"), l4]])
    l2 = bordered_grid([[l3]])
    l1 = bordered_grid([[demo_cell("1"), l2]])
    layout_grid(l1, 280.0, 230.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 9. Demo variant: 5 levels with 2x2 inner grids, tight window
  it "no overlap: demo variant 5-level with inner 2x2" do
    l5 = bordered_grid([[demo_cell("p"), demo_cell("q")], [demo_cell("r"), demo_cell("s")]])
    l4 = bordered_grid([[l5]])
    l3 = bordered_grid([[demo_cell("m"), demo_cell("n")], [demo_cell("o"), l4]])
    l2 = bordered_grid([[l3]])
    l1 = bordered_grid([[demo_cell("x"), l2], [demo_cell("y"), demo_cell("z")]])
    layout_grid(l1, 300.0, 250.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end

  # 10. 6 levels, alternating 2x1 and 1x2, demo_cells, tight
  it "no overlap: 6-level alternating layout with edit buttons" do
    l6 = bordered_grid([[demo_cell("6")]])
    l5 = bordered_grid([[demo_cell("5"), l6]])
    l4 = bordered_grid([[demo_cell("4")], [l5]])
    l3 = bordered_grid([[demo_cell("3"), l4]])
    l2 = bordered_grid([[demo_cell("2")], [l3]])
    l1 = bordered_grid([[demo_cell("1"), l2]])
    layout_grid(l1, 280.0, 250.0)
    assert_no_cross_level_overlap(collect_border_rects(l1))
    assert_children_within_parent_bounds(l1)
  end
end
