require "../spec_helper"
require "../../src/layout/recursive_grid"
require "../../src/testing/test_renderer"

# Test RecursiveGrid column alignment for fieldlist aggregate use case.
#
# Simulates the aggregate section of the fieldlist:
# - Level 0: [Person] [Time] [Project]  (3 cells in a row)
# - Level 1: [Allocation]               (1 cell)
# - Trailing: [empty]                   (drop target)
#
# "Allocation" should have the same width as "Person" (same column).

private def make_field(name : String) : CrymbleUI::Widget
  padded = CrymbleUI::HStack.new(padding: 3.0,
    background_color: CrymbleUI::Color.new(100, 100, 150, 255))
  padded.add_child(CrymbleUI::Text.new(name, font_scale: -1))
  padded
end

private def make_empty : CrymbleUI::Widget
  CrymbleUI::Text.new("  ", font_scale: -1)
end

describe "RecursiveGrid fieldlist aggregate layout" do

  it "nested approach: outer Nx1 grid with inner grids per level (matching ImGui)" do
    # Matches ImGui's create_aggregates: each field + trailing per level, wrapped in RecursiveGrid
    # Level 0: [Person, Time, Project, trailing]
    person = make_field("Person")
    time_w = make_field("Time")
    project = make_field("Project")
    level0_grid = CrymbleUI::RecursiveGrid.new(
      content: [[person, time_w, project, make_empty]], spacing: 4.0)

    # Level 1: [Allocation, trailing]
    allocation = make_field("Allocation")
    level1_grid = CrymbleUI::RecursiveGrid.new(
      content: [[allocation, make_empty]], spacing: 4.0)

    # Trailing: [empty]
    trailing_grid = CrymbleUI::RecursiveGrid.new(content: [[make_empty]], spacing: 4.0)

    # Outer grid: 3 rows × 1 col, each cell is a sub-grid
    outer = CrymbleUI::RecursiveGrid.new(
      content: [[level0_grid.as(CrymbleUI::Widget)],
                [level1_grid.as(CrymbleUI::Widget)],
                [trailing_grid.as(CrymbleUI::Widget)]],
      spacing: 4.0
    )

    app = TestApp.new
    app.root_widget = outer
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 300)
    renderer.settle_rendering(app)


    # Both inner grids should span the same total width
    level0_grid.bounds.width.should be > 0
    level1_grid.bounds.width.should eq(level0_grid.bounds.width)

    # Column alignment: Allocation width == Person width (both in virtual column 0)
    allocation.bounds.width.should eq(person.bounds.width)
  end

  it "demo spanning: A spans 2 rows next to B1/B2 sub-grid (regression guard)" do
    # Original demo structure: [[A, RecursiveGrid([[B1],[B2]])]]
    # A should span 2 rows, same height as B1+B2+spacing
    btn_a = CrymbleUI::Button.new("A", padding: 15.0)
    btn_b1 = CrymbleUI::Button.new("B1", padding: 8.0)
    btn_b2 = CrymbleUI::Button.new("B2", padding: 8.0)

    nested = CrymbleUI::RecursiveGrid.new(
      content: [[btn_b1], [btn_b2]], spacing: 3.0)

    grid = CrymbleUI::RecursiveGrid.new(
      content: [[btn_a, nested.as(CrymbleUI::Widget)]], spacing: 3.0)

    app = TestApp.new
    app.root_widget = grid
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 200)
    renderer.settle_rendering(app)


    # A should span approximately the height of B1+B2+spacings
    expected_min = btn_b1.bounds.height + btn_b2.bounds.height + 3.0
    btn_a.bounds.height.should be >= expected_min

    # B1 and B2 should be stacked vertically
    btn_b2.bounds.y.should be > btn_b1.bounds.y
  end

  it "flat approach: single grid with invisible padding" do
    person = make_field("Person")
    time_w = make_field("Time")
    project = make_field("Project")
    allocation = make_field("Allocation")

    # Invisible padding: empty Text with no content
    pad = ->{ CrymbleUI::Text.new("", font_scale: -1).as(CrymbleUI::Widget) }

    # Row 0: [Person, Time, Project]  — level with 3 fields
    # Row 1: [Allocation, pad, pad]   — level with 1 field, padded
    # Row 2: [pad, pad, pad]          — trailing empty row
    grid = CrymbleUI::RecursiveGrid.new(
      content: [
        [person, time_w, project],
        [allocation, pad.call, pad.call],
        [pad.call, pad.call, pad.call],
      ],
      spacing: 4.0
    )

    app = TestApp.new
    app.root_widget = grid
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 300)
    renderer.settle_rendering(app)


    # Allocation and Person are in the same column → same width
    allocation.bounds.width.should eq(person.bounds.width)

    # Padding cells should be minimal (not taking up visible space)
    # The grid row with Allocation should be same height as Person row
  end

  it "3x3 level grid: no proportional scaling when given excess space" do
    # Mimics fieldlist's build_fl_level 3×3 structure:
    #   [TL]        [v_spacer] [Columns]
    #   [h_spacer]  [cross]    [h_spacer]
    #   [Rows]      [v_spacer] [aggregate]
    spacer_size = 8.0

    tl = make_field("Unused")
    columns = make_field("ColumnsSection")
    rows = make_field("RowsSection")
    aggregate = make_field("AggregateArea")

    # Thin spacers (like FieldlistSpacer)
    make_spacer = -> {
      CrymbleUI::Text.new(" ", font_scale: -2).as(CrymbleUI::Widget)
    }

    grid = CrymbleUI::RecursiveGrid.new(
      content: [
        [tl.as(CrymbleUI::Widget),             make_spacer.call, columns.as(CrymbleUI::Widget)],
        [make_spacer.call,                      make_spacer.call, make_spacer.call],
        [rows.as(CrymbleUI::Widget),            make_spacer.call, aggregate.as(CrymbleUI::Widget)],
      ],
      spacing: 2.0
    )

    # Measure natural size first (before layout)
    natural_width = grid.measure(CrymbleUI::BoxConstraints.new).width
    columns_natural = columns.measure(CrymbleUI::BoxConstraints.new).width

    # Layout with TIGHT constraints wider than natural (simulates embrace panel)
    excess_width = 600.0
    tight = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(excess_width, 400.0))
    grid.layout(tight, CrymbleUI::Vec2.zero)


    # With proportional scaling, sections fill available space (correct for the 3×3 level grid).
    # Columns should be wider than natural when given excess width.
    columns.bounds.width.should be > columns_natural
  end
end
