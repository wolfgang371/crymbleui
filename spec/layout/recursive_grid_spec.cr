require "../spec_helper"
require "../../src/layout/recursive_grid"
require "../../src/layout/vstack"
require "../../src/layout/hstack"
require "../../src/widgets/button"
require "../../src/widgets/text"
require "../../src/widgets/window"
require "../../src/testing/test_render_backend"
require "../../src/testing/test_renderer"

describe CrymbleUI::RecursiveGrid do
  describe "#initialize" do
    it "creates empty grid" do
      grid = CrymbleUI::RecursiveGrid.new
      grid.children.size.should eq(0)
    end

    it "creates grid with widgets" do
      btn1 = CrymbleUI::Button.new("A")
      btn2 = CrymbleUI::Button.new("B")
      grid = CrymbleUI::RecursiveGrid.new([[btn1, btn2]])

      grid.children.size.should eq(2)
      grid.children.should contain(btn1)
      grid.children.should contain(btn2)
    end

    it "accepts id parameter" do
      grid = CrymbleUI::RecursiveGrid.new(id: "my_grid")
      grid.id.should eq("my_grid")
    end

    it "accepts spacing parameter" do
      grid = CrymbleUI::RecursiveGrid.new(spacing: 10.0)
      grid.spacing.should eq(10.0)
    end
  end

  describe "#label" do
    it "returns recursive_grid" do
      grid = CrymbleUI::RecursiveGrid.new
      grid.label.should eq("recursive_grid")
    end
  end

  describe "#measure" do
    it "returns zero size for empty grid" do
      grid = CrymbleUI::RecursiveGrid.new
      constraints = CrymbleUI::BoxConstraints.new

      size = grid.measure(constraints)

      size.width.should eq(0.0)
      size.height.should eq(0.0)
    end

    it "measures single widget" do
      btn = CrymbleUI::Button.new("Test", padding: 10.0)
      grid = CrymbleUI::RecursiveGrid.new([[btn]])
      constraints = CrymbleUI::BoxConstraints.new

      size = grid.measure(constraints)

      size.width.should be > 0.0
      size.height.should be > 0.0
    end

    it "measures 2x2 grid" do
      btn1 = CrymbleUI::Button.new("A", padding: 5.0)
      btn2 = CrymbleUI::Button.new("B", padding: 5.0)
      btn3 = CrymbleUI::Button.new("C", padding: 5.0)
      btn4 = CrymbleUI::Button.new("D", padding: 5.0)
      grid = CrymbleUI::RecursiveGrid.new([[btn1, btn2], [btn3, btn4]])
      constraints = CrymbleUI::BoxConstraints.new

      size = grid.measure(constraints)

      # Should be roughly 2x single button size
      single_size = btn1.measure(constraints)
      size.width.should be >= single_size.width * 2
      size.height.should be >= single_size.height * 2
    end

    it "includes spacing in measurement" do
      btn1 = CrymbleUI::Button.new("A", padding: 5.0)
      btn2 = CrymbleUI::Button.new("B", padding: 5.0)

      grid_no_spacing = CrymbleUI::RecursiveGrid.new([[btn1, btn2]], spacing: 0.0)
      grid_with_spacing = CrymbleUI::RecursiveGrid.new([[btn1, btn2]], spacing: 20.0)
      constraints = CrymbleUI::BoxConstraints.new

      size_no_spacing = grid_no_spacing.measure(constraints)
      size_with_spacing = grid_with_spacing.measure(constraints)

      # Spacing adds 20 pixels between columns
      size_with_spacing.width.should eq(size_no_spacing.width + 20.0)
    end
  end

  describe "#perform_layout" do
    it "positions widgets in grid" do
      btn1 = CrymbleUI::Button.new("A", padding: 5.0)
      btn2 = CrymbleUI::Button.new("B", padding: 5.0)
      btn3 = CrymbleUI::Button.new("C", padding: 5.0)
      btn4 = CrymbleUI::Button.new("D", padding: 5.0)
      grid = CrymbleUI::RecursiveGrid.new([[btn1, btn2], [btn3, btn4]])
      constraints = CrymbleUI::BoxConstraints.new
      position = CrymbleUI::Vec2.new(0.0, 0.0)

      grid.layout(constraints, position)

      # btn1 should be at top-left (0, 0)
      btn1.bounds.x.should eq(0.0)
      btn1.bounds.y.should eq(0.0)

      # btn2 should be to the right of btn1
      btn2.bounds.x.should be > 0.0
      btn2.bounds.y.should eq(0.0)

      # btn3 should be below btn1
      btn3.bounds.x.should eq(0.0)
      btn3.bounds.y.should be > 0.0

      # btn4 should be at bottom-right
      btn4.bounds.x.should be > 0.0
      btn4.bounds.y.should be > 0.0
    end

    it "applies spacing between cells" do
      btn1 = CrymbleUI::Button.new("A", padding: 5.0)
      btn2 = CrymbleUI::Button.new("B", padding: 5.0)
      grid = CrymbleUI::RecursiveGrid.new([[btn1, btn2]], spacing: 15.0)
      constraints = CrymbleUI::BoxConstraints.new
      position = CrymbleUI::Vec2.new(0.0, 0.0)

      grid.layout(constraints, position)

      # btn2 should be btn1.width + 15.0 spacing away
      expected_x = btn1.bounds.width + 15.0
      btn2.bounds.x.should eq(expected_x)
    end
  end

  describe "nested grids with spanning" do
    it "handles simple spanning" do
      btn_a = CrymbleUI::Button.new("A", padding: 5.0)
      btn_b = CrymbleUI::Button.new("B", padding: 5.0)
      btn_c = CrymbleUI::Button.new("C", padding: 5.0)

      # Nested grid with 2 rows should cause btn_a to span 2 rows
      nested = CrymbleUI::RecursiveGrid.new([[btn_b], [btn_c]])
      grid = CrymbleUI::RecursiveGrid.new([[btn_a, nested]])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # btn_a should span full height (same as btn_b + btn_c)
      btn_a.bounds.height.should be >= (btn_b.bounds.height + btn_c.bounds.height)
    end

    it "positions nested grid widgets correctly" do
      btn_a = CrymbleUI::Button.new("A", padding: 5.0)
      btn_d1 = CrymbleUI::Button.new("D1", padding: 5.0)
      btn_d2 = CrymbleUI::Button.new("D2", padding: 5.0)

      nested = CrymbleUI::RecursiveGrid.new([[btn_d1], [btn_d2]])
      grid = CrymbleUI::RecursiveGrid.new([[btn_a, nested]])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Nested grid should be positioned to the right of btn_a (in column 1)
      nested.bounds.x.should be > 0.0
      nested.bounds.y.should eq(0.0)

      # btn_d1 should be at top-left of nested grid (relative to nested)
      btn_d1.bounds.x.should eq(0.0)
      btn_d1.bounds.y.should eq(0.0)

      # btn_d2 should be below btn_d1 (within nested grid)
      btn_d2.bounds.x.should eq(btn_d1.bounds.x)
      btn_d2.bounds.y.should be > btn_d1.bounds.y
    end

    it "handles spanning when nested grid is in row 1 (not row 0)" do
      # Issue A: This is the case that differs from the simple spanning test
      # Structure: [[Hello, 2], [1, nested([[3],[4]])]]
      # Cell "1" should span 2 rows because nested grid has 2 rows
      btn_hello = CrymbleUI::Button.new("Hello", padding: 5.0)
      btn_2 = CrymbleUI::Button.new("2", padding: 5.0)
      btn_1 = CrymbleUI::Button.new("1", padding: 5.0)
      btn_3 = CrymbleUI::Button.new("3", padding: 5.0)
      btn_4 = CrymbleUI::Button.new("4", padding: 5.0)

      # Nested grid with 2 rows in position (1,1)
      nested = CrymbleUI::RecursiveGrid.new([[btn_3], [btn_4]])
      grid = CrymbleUI::RecursiveGrid.new([
        [btn_hello, btn_2],
        [btn_1, nested],
      ])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # btn_1 should span 2 rows (same height as nested grid = btn_3 + btn_4)
      nested_height = btn_3.bounds.height + btn_4.bounds.height
      btn_1.bounds.height.should be >= nested_height
    end

    it "handles spanning in edit mode (VStack cells with nested grid in row 1)" do
      # Mimics the actual demo structure in edit mode:
      # Each cell is VStack(HStack(edit buttons) + content button)
      # Structure: [[Hello_vstack, 2_vstack], [1_vstack, nested([[3_vstack],[4_vstack]])]]

      # Helper to create edit-mode cell (VStack with HStack + content button)
      create_edit_cell = ->(label : String) {
        vs = CrymbleUI::VStack.new(spacing: 2.0)
        hs = CrymbleUI::HStack.new(spacing: 1.0)
        # 5 small edit buttons like in demo
        ["T", "B", "L", "R", "Sub"].each do |btn_label|
          hs.add_child(CrymbleUI::Button.new(btn_label, padding: 1.0, font_scale: -3))
        end
        vs.add_child(hs)
        vs.add_child(CrymbleUI::Button.new(label, padding: 6.0))
        vs
      }

      cell_hello = create_edit_cell.call("Hello")
      cell_2 = create_edit_cell.call("2")
      cell_1 = create_edit_cell.call("1")
      cell_3 = create_edit_cell.call("3")
      cell_4 = create_edit_cell.call("4")

      # Nested grid with 2 rows in position (1,1)
      nested = CrymbleUI::RecursiveGrid.new([[cell_3], [cell_4]])
      grid = CrymbleUI::RecursiveGrid.new([
        [cell_hello, cell_2],
        [cell_1, nested],
      ])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # cell_1 (VStack) should span 2 rows (same height as nested grid)
      # nested grid height = cell_3.height + cell_4.height
      nested_height = cell_3.bounds.height + cell_4.bounds.height
      # Use tolerance for floating-point comparison
      (cell_1.bounds.height + 0.001).should be >= nested_height
    end

    it "handles spanning with demo-like structure (spacing + border + 2x2 nested grid)" do
      # Exactly mimics the demo in edit mode:
      # - spacing: 6.0 (edit mode spacing)
      # - border_color set on grids
      # - 2x2 nested grid (like the 3,4,5,6 block in screenshot)
      border = CrymbleUI::Color.new(200, 50, 50, 255)

      create_edit_cell = ->(label : String) {
        vs = CrymbleUI::VStack.new(spacing: 2.0)
        hs = CrymbleUI::HStack.new(spacing: 1.0)
        ["T", "B", "L", "R", "Sub"].each do |btn_label|
          hs.add_child(CrymbleUI::Button.new(btn_label, padding: 1.0, font_scale: -3))
        end
        vs.add_child(hs)
        vs.add_child(CrymbleUI::Button.new(label, padding: 6.0))
        vs
      }

      cell_hello = create_edit_cell.call("Hello")
      cell_2 = create_edit_cell.call("2")
      cell_1 = create_edit_cell.call("1")
      cell_3 = create_edit_cell.call("3")
      cell_4 = create_edit_cell.call("4")
      cell_5 = create_edit_cell.call("5")
      cell_6 = create_edit_cell.call("6")

      # 2x2 nested grid with spacing and border (like demo)
      nested = CrymbleUI::RecursiveGrid.new(
        [[cell_3, cell_5], [cell_4, cell_6]],
        spacing: 6.0
      )
      nested.border_color = border

      # Outer grid with spacing and border (like demo)
      grid = CrymbleUI::RecursiveGrid.new(
        [[cell_hello, cell_2], [cell_1, nested]],
        spacing: 6.0
      )
      grid.border_color = border

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # cell_1 should span 2 rows (same height as nested grid)
      # Account for nested grid's border padding
      cell_1.bounds.height.should be >= nested.bounds.height
    end

    it "nested grid expands to fill tight constraints" do
      # Issue B: Nested grid should fill allocated space, not just natural size
      btn_a = CrymbleUI::Button.new("A", padding: 5.0)
      btn_b = CrymbleUI::Button.new("B", padding: 5.0)

      nested = CrymbleUI::RecursiveGrid.new([[btn_a], [btn_b]])
      grid = CrymbleUI::RecursiveGrid.new([[nested]])

      # First measure to get natural size
      natural_size = grid.measure(CrymbleUI::BoxConstraints.new)

      # Give outer grid tight constraints larger than natural size
      large_constraints = CrymbleUI::BoxConstraints.tight(
        CrymbleUI::Size.new(natural_size.width + 50.0, natural_size.height + 50.0)
      )
      grid.layout(large_constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Nested grid should expand to fill allocated space
      nested.bounds.width.should eq(natural_size.width + 50.0)
      nested.bounds.height.should eq(natural_size.height + 50.0)
    end
  end

  describe "integration" do
    it "works in widget tree" do
      parent = CrymbleUI::VStack.new(id: "container")
      btn = CrymbleUI::Button.new("Test")
      grid = CrymbleUI::RecursiveGrid.new([[btn]], id: "my_grid")

      parent.add_child(grid)

      parent.children.should contain(grid)
      grid.parent.should eq(parent)
      grid.path_id.should eq("container/my_grid")
    end

    it "correctly sets children parent references" do
      btn1 = CrymbleUI::Button.new("A")
      btn2 = CrymbleUI::Button.new("B")
      grid = CrymbleUI::RecursiveGrid.new([[btn1, btn2]])

      btn1.parent.should eq(grid)
      btn2.parent.should eq(grid)
    end
  end

  describe "visual rendering with spanning (pixel test)" do
    it "VStack with background_color fills entire spanned bounds" do
      # This tests Issue A: VStack cells must visually show spanning
      # Without background_color, VStack draws nothing and spanning is invisible
      bg_color = CrymbleUI::Color.new(200, 220, 240, 255)  # Light blue

      # Create edit-mode style cell: VStack with small content and background
      cell_1 = CrymbleUI::VStack.new(spacing: 2.0, background_color: bg_color)
      small_btn = CrymbleUI::Button.new("1", padding: 5.0)
      cell_1.add_child(small_btn)

      # Create nested grid with 2 rows (will cause cell_1 to span)
      btn_3 = CrymbleUI::Button.new("3", padding: 5.0)
      btn_4 = CrymbleUI::Button.new("4", padding: 5.0)
      nested = CrymbleUI::RecursiveGrid.new([[btn_3], [btn_4]])

      grid = CrymbleUI::RecursiveGrid.new([[cell_1, nested]])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Verify spanning happened (cell_1 height >= sum of btn_3 + btn_4)
      cell_1.bounds.height.should be >= (btn_3.bounds.height + btn_4.bounds.height)

      # Now render and check pixels
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        cell_1.bounds.width.to_i + 10,
        cell_1.bounds.height.to_i + 10,
        CrymbleUI::Color.new(255, 255, 255, 255)  # White background
      )

      # Render VStack primitives
      primitives = cell_1.to_primitives(cell_1.bounds)
      primitives.each do |primitive|
        backend.execute_primitive(primitive)
      end

      # Check that pixels at BOTTOM of VStack (spanned area) are filled
      # The natural content is small_btn at top, but spanning adds height
      natural_height = small_btn.bounds.height.to_i
      spanned_height = cell_1.bounds.height.to_i

      # Sample pixel in spanned area (bottom half, should be bg_color)
      test_y = (natural_height + spanned_height) // 2  # Middle of spanned area
      test_x = cell_1.bounds.width.to_i // 2  # Center horizontally

      pixel = backend.get_pixel(test_x, test_y)
      pixel.should_not be_nil
      pixel.should eq(bg_color)
    end

    it "demo structure: 2x2 grid with nested in (1,1) - cell 2 spans" do
      # Exact demo structure: [[Hello, 1], [2, nested([[3],[4]])]]
      # Cell "2" should span 2 rows because nested has 2 rows
      bg_color = CrymbleUI::Color.new(200, 220, 240, 255)

      # Create edit-mode style cells (VStack with HStack + Button)
      create_edit_cell = ->(label : String) {
        vs = CrymbleUI::VStack.new(spacing: 2.0, background_color: bg_color)
        hs = CrymbleUI::HStack.new(spacing: 1.0)
        ["T", "B", "L", "R", "Sub"].each do |btn_label|
          hs.add_child(CrymbleUI::Button.new(btn_label, padding: 1.0, font_scale: -3))
        end
        vs.add_child(hs)
        vs.add_child(CrymbleUI::Button.new(label, padding: 6.0))
        vs
      }

      cell_hello = create_edit_cell.call("Hello")
      cell_1 = create_edit_cell.call("1")
      cell_2 = create_edit_cell.call("2")
      cell_3 = create_edit_cell.call("3")
      cell_4 = create_edit_cell.call("4")

      # Nested grid in position (1,1)
      nested = CrymbleUI::RecursiveGrid.new([[cell_3], [cell_4]], spacing: 6.0)

      # Outer grid: [[Hello, 1], [2, nested]]
      grid = CrymbleUI::RecursiveGrid.new([
        [cell_hello, cell_1],
        [cell_2, nested]
      ], spacing: 6.0)

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Cell 2 should span 2 rows (same height as nested grid)
      expected_height = cell_3.bounds.height + cell_4.bounds.height + 6.0
      cell_2.bounds.height.should be >= expected_height

      # Verify RENDERING fills the full height
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        cell_2.bounds.width.to_i + 10,
        cell_2.bounds.height.to_i + 10,
        white
      )

      primitives = cell_2.to_primitives(cell_2.bounds)
      primitives.size.should eq(1)  # One fill_rect
      primitives.each { |p| backend.execute_primitive(p) }

      # Pixel at BOTTOM of cell_2 should be bg_color (not white)
      test_y = cell_2.bounds.height.to_i - 5
      test_x = cell_2.bounds.width.to_i // 2
      backend.get_pixel(test_x, test_y).should eq(bg_color)
    end

    it "demo-like Cell structure with TestRenderer" do
      # Mimics demo's Cell-based structure exactly
      # Cell data structure (simplified from demo)
      cells = {
        "Hello" => {subgrid: false, children: nil},
        "1" => {subgrid: false, children: nil},
        "2" => {subgrid: false, children: nil},
        "4" => {subgrid: false, children: nil},
        "3" => {subgrid: false, children: nil},
      }

      bg_color = CrymbleUI::Color.new(200, 220, 240, 255)

      # Build cell widget (like demo's build_cell_widget)
      build_cell = ->(label : String) {
        vs = CrymbleUI::VStack.new(spacing: 2.0, background_color: bg_color)
        hs = CrymbleUI::HStack.new(spacing: 1.0)
        ["T", "B", "L", "R", "Sub"].each do |btn_label|
          hs.add_child(CrymbleUI::Button.new(btn_label, padding: 1.0, font_scale: -3))
        end
        vs.add_child(hs)
        vs.add_child(CrymbleUI::Button.new(label, padding: 6.0))
        vs
      }

      # Build structure: [[Hello, 1], [2, nested([[4],[3]])]]
      cell_hello = build_cell.call("Hello")
      cell_1 = build_cell.call("1")
      cell_2 = build_cell.call("2")
      cell_4 = build_cell.call("4")
      cell_3 = build_cell.call("3")

      # Create nested grid FIRST (like demo does in recursive build_grid_content)
      nested = CrymbleUI::RecursiveGrid.new([[cell_4], [cell_3]], spacing: 6.0)
      nested.border_color = CrymbleUI::Color.new(200, 50, 50, 255)

      # Create outer grid with nested
      grid = CrymbleUI::RecursiveGrid.new([
        [cell_hello, cell_1],
        [cell_2, nested]
      ], spacing: 6.0)
      grid.border_color = CrymbleUI::Color.new(200, 50, 50, 255)

      # Use TestRenderer for full pipeline
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Create minimal App-like structure
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(grid)

      # Layout (like App.prepare_layout)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # cell_2 should span (height >= cell_4 + cell_3 + spacing)
      expected_height = cell_4.bounds.height + cell_3.bounds.height + 6.0
      cell_2.bounds.height.should be >= expected_height
    end

    it "VStack WITHOUT background_color leaves spanned area empty" do
      # Negative test: without background_color, spanning is invisible
      # Create edit-mode style cell: VStack WITHOUT background_color
      cell_1 = CrymbleUI::VStack.new(spacing: 2.0)  # No background!
      small_btn = CrymbleUI::Button.new("1", padding: 5.0)
      cell_1.add_child(small_btn)

      # Create nested grid with 2 rows (will cause cell_1 to span)
      btn_3 = CrymbleUI::Button.new("3", padding: 5.0)
      btn_4 = CrymbleUI::Button.new("4", padding: 5.0)
      nested = CrymbleUI::RecursiveGrid.new([[btn_3], [btn_4]])

      grid = CrymbleUI::RecursiveGrid.new([[cell_1, nested]])

      constraints = CrymbleUI::BoxConstraints.new
      grid.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

      # Verify spanning happened
      cell_1.bounds.height.should be >= (btn_3.bounds.height + btn_4.bounds.height)

      white = CrymbleUI::Color.new(255, 255, 255, 255)
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        cell_1.bounds.width.to_i + 10,
        cell_1.bounds.height.to_i + 10,
        white
      )

      # Render VStack primitives (should be empty array!)
      primitives = cell_1.to_primitives(cell_1.bounds)
      primitives.size.should eq(0)  # No primitives without background

      # Spanned area remains white (empty)
      natural_height = small_btn.bounds.height.to_i
      spanned_height = cell_1.bounds.height.to_i
      test_y = (natural_height + spanned_height) // 2
      test_x = cell_1.bounds.width.to_i // 2

      pixel = backend.get_pixel(test_x, test_y)
      pixel.should eq(white)  # Still white - nothing rendered
    end
  end
end
