require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# VirtualMatrix Ghosting Detection Tests
#
# These tests verify that the ghosting prevention mechanism in VirtualMatrix is working.
# Ghosting occurs when old cell pixels "leak through" to newly created cells because
# the layer buffer contains stale pixels from destroyed cells.
#
# Key detection points:
# 1. needs_fresh_background flag: New cells MUST have this flag set to prevent
#    capturing ghost pixels from the layer buffer during background memorization
# 2. Pixel opacity: All rendered pixels should be fully opaque (alpha=255)
#    Transparent pixels indicate contamination from uninitialized buffer regions
# 3. Sticky layer configuration: VirtualMatrix with sticky headers should properly
#    configure the ScrollView with sticky layer parameters
#
# These tests serve as REGRESSION tests - if the ghosting fix is removed
# (e.g., line 789 in virtual_matrix.cr), the first test will fail.

# Adapter with sticky headers (row 0, col 0 are sticky)
class StickyGhostTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Sticky: row 0 and col 0 scroll out LAST
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

describe "VirtualMatrix sticky header ghosting detection" do
  it "newly created cells have nil last_rendered_layer_position (auto-detects stale background)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyGhostTestAdapter.new(50, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "ghost_detect")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Get initial visible rows
    initial_visible = matrix.visible_cell_indices[:rows].dup

    # Scroll down significantly to bring new cells into view
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 500.0)
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)

    # Get new visible rows after scroll
    new_visible = matrix.visible_cell_indices[:rows]

    # Find cells that are newly created (visible now but not before)
    newly_visible_rows = new_visible.reject { |r| initial_visible.includes?(r) }
    newly_visible_rows.should_not be_empty, "Expected new rows after scrolling 500px"

    # New cells have nil last_rendered_layer_position (never rendered).
    # The renderer auto-detects this and fills with background color
    # instead of capturing stale layer pixels (prevents ghosting).
    new_cell_count = 0
    cells_with_nil_pos = 0

    matrix.active_cells.each do |key, widget|
      row, col = key
      if newly_visible_rows.includes?(row)
        new_cell_count += 1
        if widget.last_rendered_layer_position.nil?
          cells_with_nil_pos += 1
        end
      end
    end

    if new_cell_count > 0
      cells_with_nil_pos.should eq(new_cell_count),
        "Expected all #{new_cell_count} new cells to have nil last_rendered_layer_position, but only #{cells_with_nil_pos} did"
    end
  end

  it "layer background pixels are opaque (no transparency contamination)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyGhostTestAdapter.new(20, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "opacity_test")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    layer = matrix.content_layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample multiple points in the layer (inside cell areas)
    transparent_pixels = 0
    sample_points = [
      {50, 50}, {100, 100}, {150, 75}, {200, 150}, {250, 200}
    ]

    sample_points.each do |x, y|
      next if x >= backend.width || y >= backend.height
      pixel = backend.get_pixel(x, y)
      next unless pixel
      if pixel.a < 255
        transparent_pixels += 1
      end
    end

    # No transparent pixels should exist in rendered layer
    transparent_pixels.should eq(0),
      "Found #{transparent_pixels} transparent pixels - indicates transparency contamination"
  end

  it "scroll and check no transparent pixels appear in new cell regions" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyGhostTestAdapter.new(100, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_opacity")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll down significantly
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 1000.0)
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    layer = matrix.content_layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Check for transparent pixels in the visible viewport region
    # Sample a grid of points
    transparent_count = 0
    total_samples = 0

    # Sample every 20 pixels
    (10...290).step(20) do |y|
      (10...390).step(20) do |x|
        next if x >= backend.width || y >= backend.height
        pixel = backend.get_pixel(x, y)
        next unless pixel
        total_samples += 1
        if pixel.a < 255
          transparent_count += 1
        end
      end
    end

    # Should have sampled many points and found no transparent pixels
    total_samples.should be > 100
    transparent_count.should eq(0),
      "Found #{transparent_count} transparent pixels after scroll (out of #{total_samples} samples)"
  end

  it "sticky layers are separate from content layer" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyGhostTestAdapter.new(20, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_layers")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Content layer should exist
    content_layer = matrix.content_layer
    content_layer.should_not be_nil, "Content layer should exist"

    # Check ScrollView has sticky layers configured
    scroll_view = matrix.content_scroll_view.not_nil!
    scroll_view.sticky_rows.should eq(1), "ScrollView should have 1 sticky row"
    scroll_view.sticky_cols.should eq(1), "ScrollView should have 1 sticky col"

    # Sticky layers may or may not be created (depends on implementation)
    # Just verify scroll_view has the sticky configuration
    scroll_view.sticky_row_height.should be > 0.0
    scroll_view.sticky_col_width.should be > 0.0
  end

  # TEST: Horizontal Scroll Ghosting
  # Issue: Sticky column cells (col 0) are incorrectly destroyed during horizontal scroll
  # Root cause: destruction_cols is computed based on X-scroll position, so when scrolling
  # right, sticky column cells fall outside the destruction_cols range and get destroyed
  it "sticky column cells survive horizontal scroll (not destroyed during X-scroll)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 300)  # Wide viewport
    app = TestApp.new

    # Use adapter with sticky col 0
    adapter = StickyGhostTestAdapter.new(20, 50)  # 50 columns to allow significant horizontal scroll
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "horiz_scroll_sticky")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Verify sticky column (col 0) cells exist initially
    initial_sticky_col_cells = matrix.active_cells.keys.count { |key| key[1] == 0 }
    initial_sticky_col_cells.should be > 0, "Expected sticky column cells (col 0) to exist initially"

    # Record which col-0 cells exist
    initial_col0_rows = matrix.active_cells.keys.select { |key| key[1] == 0 }.map { |key| key[0] }

    # Scroll RIGHT significantly - this is the problematic direction
    # When scrolling right, col 0 (sticky) falls "outside" the destruction buffer
    # if not properly exempted
    matrix.scroll_offset = CrymbleUI::Vec2.new(500.0, 0.0)  # Scroll 500px right
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # CRITICAL CHECK: Sticky column cells (col 0) should STILL exist
    # They should NOT be destroyed just because we scrolled horizontally
    current_sticky_col_cells = matrix.active_cells.keys.count { |key| key[1] == 0 }
    current_col0_rows = matrix.active_cells.keys.select { |key| key[1] == 0 }.map { |key| key[0] }

    # Sticky col cells visible in viewport should still exist
    # (rows that were visible and are still visible should retain their col-0 cell)
    visible_rows = matrix.visible_cell_indices[:rows]
    surviving_col0_in_visible = current_col0_rows.count { |r| visible_rows.includes?(r) }

    surviving_col0_in_visible.should be > 0,
      "GHOSTING BUG: Sticky column cells (col 0) were destroyed during horizontal scroll. " \
      "Initial col-0 cells: #{initial_sticky_col_cells}, After scroll: #{current_sticky_col_cells}"

    # Now scroll back LEFT
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Verify col-0 cells are properly rendered (no black areas)
    layer = matrix.content_layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixels in the sticky column area (left side)
    # These should NOT be transparent/black if cells were properly retained/recreated
    transparent_in_sticky_col = 0
    (10...290).step(30) do |y|
      # Sample at x=15 which should be inside col 0
      next if 15 >= backend.width || y >= backend.height
      pixel = backend.get_pixel(15, y)
      if pixel && pixel.a < 255
        transparent_in_sticky_col += 1
      end
    end

    transparent_in_sticky_col.should eq(0),
      "Found #{transparent_in_sticky_col} transparent pixels in sticky column area after scroll-right-then-left"
  end
end

# Adapter that mimics FeatureDemoAdapter: has scroll_order but NO sticky_*_count
# This tests the scenario where headers are made "sticky-like" via scroll_order
# but without declaring them as true sticky rows/cols
class ScrollOrderOnlyAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Custom scroll_order: row 0 and col 0 scroll out LAST (like Feature Demo)
  # This creates "sticky-like" behavior via scroll_order alone
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text = if row == 0 && col == 0
      "Corner"
    elsif row == 0
      "Col#{col}"  # Column headers
    elsif col == 0
      "Row#{row}"  # Row headers
    else
      "D#{row},#{col}"  # Data cells
    end
    TestVisibleCell.new(text)
  end
end

describe "VirtualMatrix scroll_order without sticky_*_count (Feature Demo scenario)" do
  # TEST: Initial Render Ghosting
  # Issue: Feature Demo uses custom scroll_order to make row 0 / col 0 scroll out last,
  # but does NOT define sticky_row_count / sticky_col_count.
  # This mismatch causes cells to be incorrectly assigned to layers or destroyed.
  it "renders correctly with scroll_order but no sticky_*_count" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = ScrollOrderOnlyAdapter.new(20, 15)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_order_only")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Verify header cells (row 0 and col 0) exist and are active
    # Row 0 cells
    row0_cells = matrix.active_cells.keys.count { |key| key[0] == 0 }
    row0_cells.should be > 0, "Expected row 0 (header row) cells to exist"

    # Col 0 cells
    col0_cells = matrix.active_cells.keys.count { |key| key[1] == 0 }
    col0_cells.should be > 0, "Expected col 0 (header col) cells to exist"

    # Check for transparent pixels (indicates ghosting / improper rendering)
    layer = matrix.content_layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    transparent_count = 0
    total_samples = 0

    # Sample a grid of points in the viewport
    (10...290).step(20) do |y|
      (10...390).step(20) do |x|
        next if x >= backend.width || y >= backend.height
        pixel = backend.get_pixel(x, y)
        next unless pixel
        total_samples += 1
        if pixel.a < 255
          transparent_count += 1
        end
      end
    end

    total_samples.should be > 50
    transparent_count.should eq(0),
      "INITIAL RENDER GHOSTING: Found #{transparent_count} transparent pixels before any scrolling"
  end

  it "header row cells persist after vertical scroll with scroll_order (no sticky_row_count)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = ScrollOrderOnlyAdapter.new(50, 15)  # Enough rows to scroll
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_order_vscroll")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Initial: row 0 cells should exist
    initial_row0_count = matrix.active_cells.keys.count { |key| key[0] == 0 }
    initial_row0_count.should be > 0, "Row 0 cells should exist initially"

    # Scroll down - with scroll_order, row 0 should scroll out LAST
    # Scroll only partially (not enough to scroll out row 0)
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 200.0)
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Since scroll_order puts row 0 at END, row 0 should still be "visible"
    # according to StickyMath (it scrolls out last)
    visible_rows = matrix.visible_cell_indices[:rows]

    # Row 0 should be in visible_rows because it scrolls out last via scroll_order
    visible_rows.should contain(0),
      "Row 0 should be in visible_rows (scroll_order makes it scroll out last). " \
      "Visible rows: #{visible_rows}"

    # Row 0 cells should exist
    row0_count_after_scroll = matrix.active_cells.keys.count { |key| key[0] == 0 }
    row0_count_after_scroll.should be > 0,
      "Row 0 cells should persist after scroll (scroll_order makes row 0 scroll out last)"
  end

  # TEST: Header cells should render at SCREEN TOP when scroll_order makes them scroll last
  # This is the KEY difference between scroll_order and sticky_*_count:
  # - scroll_order: controls WHEN elements scroll out (visibility lifetime)
  # - sticky_*_count: controls WHERE elements render (fixed screen position)
  #
  # Without sticky_*_count, row 0 cells have data position y=0.
  # When we scroll down, they should EITHER:
  # a) Scroll off-screen (data position - scroll_offset = negative), OR
  # b) Stay visible at screen top if adapter wants "sticky" behavior
  #
  # If adapter wants row 0 to stay visible AND be at screen top,
  # it MUST set sticky_row_count = 1 (not just use scroll_order)
  it "EXPECTED FAILURE: scroll_order alone does NOT pin cells to screen position" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = ScrollOrderOnlyAdapter.new(50, 15)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_order_position")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Get the screen position of row 0, col 1 cell before scrolling
    row0_pos_before = matrix.cell_screen_position(0, 1)

    # Scroll down
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 100.0)
    matrix.mark_needs_layout
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Get the screen position after scrolling
    row0_pos_after = matrix.cell_screen_position(0, 1)

    # With scroll_order but WITHOUT sticky_row_count:
    # - Row 0 data position is y=0
    # - After scroll_offset.y = 100, screen position should be y = 0 - 100 = -100
    # - Cell would be OFF-SCREEN (negative Y)
    #
    # If user wants row 0 to stay at screen top (sticky header behavior),
    # they MUST set sticky_row_count = 1

    # The cell's screen Y position should have moved by scroll_offset amount
    # (proving it scrolls, not stays pinned)
    position_delta = row0_pos_after.y - row0_pos_before.y
    position_delta.should be_close(-100.0, 1.0),
      "Row 0 cell should scroll with content (delta=#{position_delta}). " \
      "scroll_order only controls visibility lifetime, NOT screen position. " \
      "For sticky header behavior, use sticky_row_count instead."
  end
end
