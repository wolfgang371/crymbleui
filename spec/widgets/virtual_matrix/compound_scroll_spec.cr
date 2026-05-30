require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# Test adapter with compound cells and configurable scroll_order
class CompoundScrollAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @row_count : Int32
  @col_count : Int32

  @col_scroll_order : Array(Int32)
  @row_scroll_order : Array(Int32)
  @merges : Array(Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)))

  def initialize(@row_count, @col_count,
                 col_scroll_order : Array(Int32)? = nil,
                 row_scroll_order : Array(Int32)? = nil,
                 merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)))
    @col_scroll_order = col_scroll_order || (0...@col_count).to_a
    @row_scroll_order = row_scroll_order || (0...@row_count).to_a
    @merges = merges
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "#{row},#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {@row_scroll_order, @col_scroll_order}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end
end

# Helper to set up matrix with adapter
private def setup_compound_matrix(adapter, viewport_width = 600.0, viewport_height = 300.0, show_rulers : Bool = true)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_scroll_test")
  matrix.show_rulers = show_rulers

  # Sync bounding boxes from adapter
  adapter.invalidate_all!

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "Dynamic Handle Cell (WU2)" do
    it "merged cell handle is top-left when no scroll" do
      # Merged cell (0,2)-(0,3): spans cols 2 and 3 in row 0
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 5, merges: merges)
      matrix, _, _ = setup_compound_matrix(adapter)

      # With no scroll, handle should be top-left = (0,2)
      matrix.get_top_left_cell({0, 2}).should eq({0, 2})
      matrix.get_top_left_cell({0, 3}).should eq({0, 2})

      # The handle cell should be the one with a widget
      matrix.active_cells.has_key?({0, 2}).should be_true
    end

    it "merged cell handle changes when top-left scrolls out" do
      # Merged cell (0,2)-(0,3) with scroll_order [2,3,4,1,0]
      # Col 2 scrolls out first
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [2, 3, 4, 5, 6, 7, 8, 9, 1, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 600.0, 300.0, show_rulers: false)

      # Scroll col 2 out: need > 50px scroll threshold
      # col_w ≈ 103px, so scrolling one col past triggers full update
      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w + 5.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # After scrolling col 2 out, the dynamic handle should be (0,3)
      # because col 2 is no longer visible, col 3 is the first visible
      # col within the merged region
      visible = matrix.visible_cell_indices
      visible[:cols].should_not contain(2)  # Col 2 scrolled out
      visible[:cols].should contain(3)       # Col 3 still visible

      # The merged cell should still be rendered (via dynamic handle at (0,3))
      # Note: this test will fail until dynamic_handle_cell is implemented
      matrix.active_cells.has_key?({0, 3}).should be_true
    end

    it "merged cell not rendered when all constituent cols scroll out" do
      # Merged cell (0,2)-(0,3) with scroll_order [2,3,4,5,6,7,8,9,1,0]
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [2, 3, 4, 5, 6, 7, 8, 9, 1, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 600.0, 300.0, show_rulers: false)

      # Scroll both col 2 and col 3 out (> 50px threshold)
      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w * 2 + 5.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Both cols out → merged cell should not be rendered
      visible = matrix.visible_cell_indices
      visible[:cols].should_not contain(2)
      visible[:cols].should_not contain(3)
    end

    it "row-spanning merged cell handle changes when top row scrolls out" do
      # Merged cell (0,0)-(2,0): spans rows 0-2 in col 0
      # Use 20 rows so scrolling actually shifts rows out of viewport
      merges = [{ {0, 0}, {2, 0} }]
      adapter = CompoundScrollAdapter.new(20, 5,
        row_scroll_order: (0...20).to_a,
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 600.0, 200.0, show_rulers: false)

      # Scroll rows 0-2 out (need > 50px scroll_threshold to trigger full update)
      # row_h = 23px, 3 rows = 69px > 50px threshold
      row_h = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0)
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, row_h * 3 + 5.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Rows 0-2 scrolled out
      visible = matrix.visible_cell_indices
      visible[:rows].should_not contain(0)
      visible[:rows].should_not contain(1)
      visible[:rows].should_not contain(2)
      visible[:rows].should contain(3)

      # The merged cell should NOT be rendered since all rows 0-2 are out
      # (This is the current behavior - but with dynamic handle, if only row 0
      # scrolls out, rows 1-2 could keep the cell alive via dynamic handle)
    end

    it "non-merged cells behavior unchanged" do
      adapter = CompoundScrollAdapter.new(5, 5)
      matrix, _, _ = setup_compound_matrix(adapter)

      # Non-merged cells should work as before
      matrix.get_top_left_cell({1, 1}).should eq({1, 1})
      matrix.is_handle_cell?({1, 1}).should be_true
    end
  end

  describe "Bug D: Empty merged content cells in Done group" do
    # Reproduce task board layout: 7 rows x 13 cols
    # scroll_order: [2,3,4,1, 6,7,8,5, 10,11,12,9, 0]
    # Merged cells include empty Done blocks: {1,9}-{2,12} and {5,9}-{6,12}
    it "merged cell {1,9}-{2,12} is created when scrolling right to Done group" do
      # Build merges for task board merged cells
      merges = [
        # Row 0: status headers (4-col merges)
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        # Col 0: priority headers (2-row merges)
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
        # Empty merged blocks
        { {2, 1}, {2, 4} }, { {1, 9}, {2, 12} }, { {4, 1}, {4, 4} },
        { {4, 5}, {4, 8} }, { {6, 1}, {6, 4} }, { {5, 9}, {6, 12} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      adapter = CompoundScrollAdapter.new(7, 13, col_scroll_order: scroll_order, merges: merges)

      # Viewport width ~660px (typical task board panel width)
      matrix, _, constraints = setup_compound_matrix(adapter, 660.0, 300.0)
      # Set col 0 narrower (4.0 instead of default 5.0)
      matrix.col_width(0, 4.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)  # 103

      # Scroll right progressively — find where the Done group cells should appear
      # At scroll ≈ 350, visible_cols should include col 9
      scroll_positions = [200.0, 300.0, 350.0, 400.0, 500.0, 600.0]
      found_merged_19 = false
      found_merged_59 = false

      cell_19_bounds = nil
      cell_59_bounds = nil
      cell_19_scroll = 0.0
      active_keys_at_found = [] of Tuple(Int32, Int32)

      scroll_positions.each do |sx|
        matrix.scroll_offset = CrymbleUI::Vec2.new(sx, 0.0)
        matrix.layout(constraints, CrymbleUI::Vec2.zero)

        visible = matrix.visible_cell_indices
        if visible[:cols].includes?(9)
          # Col 9 is visible — merged cells should have active widgets
          if cell = matrix.active_cells[{1, 9}]?
            found_merged_19 = true
            cell_19_bounds = cell.bounds
            cell_19_scroll = sx
            active_keys_at_found = matrix.active_cells.keys.select { |k| k[1] >= 9 }.sort
          end
          if cell = matrix.active_cells[{5, 9}]?
            found_merged_59 = true
            cell_59_bounds = cell.bounds
          end
        end
      end

      found_merged_19.should be_true
      found_merged_59.should be_true

      # Check that the cell has proper width (4 cols = 4 * 103 = 412, minus GRID_SPACING)
      if b = cell_19_bounds
        expected_width = col_w * 4 - CrymbleUI::VirtualMatrix::GRID_SPACING
        b.width.should be_close(expected_width, 1.0)
        b.height.should be > 0.0
        # Position should be at ruler_offset + col 9's absolute x (sum of widths 0-8)
        ruler_col_w = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
        expected_x = ruler_col_w + 83.0 + 8 * col_w  # ruler + col 0 = 83, cols 1-8 = 8*103
        b.x.should be_close(expected_x, 1.0)
      end
    end
  end

  describe "Bug D: Merged content cell renders white pixels" do
    # The actual rendering test: after scrolling right, the merged cell {1,9}-{2,12}
    # should render with white background (TextInput bg) in the composited output.
    it "merged cell {1,9} has white pixels in content layer buffer after scroll" do
      merges = [
        # Row 0: status headers
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        # Col 0: priority headers
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
        # Empty merged blocks
        { {2, 1}, {2, 4} }, { {1, 9}, {2, 12} }, { {4, 1}, {4, 4} },
        { {4, 5}, {4, 8} }, { {6, 1}, {6, 4} }, { {5, 9}, {6, 12} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      adapter = CompoundScrollAdapter.new(7, 13, col_scroll_order: scroll_order, merges: merges)

      # Create matrix with TextInput cells (white bg) — same as real demo
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "bugd_test")
      adapter.invalidate_all!
      matrix.col_width(0, 4.0)
      matrix.row_height(0, 1.5)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(660, 300)
      renderer.settle_rendering(app)

      # Scroll right in steps (shift+scroll) to reach the Done group
      point = CrymbleUI::Vec2.new(330.0, 150.0)
      # 25 steps × 30px = 750px scroll (enough to make col 9 fully visible)
      25.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # At scroll=750, viewport shows content [750, 1410)
      # Merged cell {1,9} at x=907 should be visible at screen x ≈ 157
      # Verify the cell exists and has a widget_backend
      cell_19 = matrix.active_cells[{1, 9}]?
      cell_19.should_not be_nil, "Merged cell {1,9} should be active at scroll=750"
      cell_19 = cell_19.not_nil!
      cl = matrix.content_layer
      dbg = "scroll=#{matrix.scroll_offset.x.round(1)}, cell.bounds=#{cell_19.bounds}, " \
            "layer.bounds=#{cl.try(&.bounds)}, " \
            "buffer_origin=#{cl.try(&.buffer_origin)}, " \
            "parent_children=#{cell_19.parent.try(&.id)}"
      cell_19.widget_backend.should_not be_nil, "Merged cell {1,9} should have widget_backend. #{dbg}"

      # Check pixel colors in the composited window output
      # The merged cell should contain white pixels (TextInput bg = 255,255,255)
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      layer_bg = CrymbleUI::Color.new(40, 40, 40, 255) # Content layer bg

      # Sample the merged cell's widget_backend directly
      cell_backend = cell_19.widget_backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)
      # Center of cell should be white (TextInput fills entire bounds with white)
      center_x = cell_backend.width // 2
      center_y = cell_backend.height // 2
      center_pixel = cell_backend.get_pixel(center_x, center_y)
      center_pixel.should_not be_nil, "Should be able to read pixel from cell backend"
      if px = center_pixel
        px.r.should eq(255_u8), "Merged cell center pixel should be white (r=255), got r=#{px.r} g=#{px.g} b=#{px.b}"
      end

      # Also check a non-merged cell at same scroll position for comparison
      # Cell {3,9} is non-merged, also should be white
      cell_39 = matrix.active_cells[{3, 9}]?
      if c39 = cell_39
        if c39_backend = c39.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
          c39_px = c39_backend.get_pixel(c39_backend.width // 2, c39_backend.height // 2)
          if px = c39_px
            px.r.should eq(255_u8), "Non-merged cell {3,9} center should be white, got r=#{px.r}"
          end
        end
      end

      # Check the content layer buffer directly
      content_layer = matrix.content_layer
      content_layer.should_not be_nil, "Content layer should exist"
      layer_backend = content_layer.not_nil!.backend
      layer_backend.should_not be_nil, "Content layer should have backend"

      if lb = layer_backend.as?(CrymbleUI::Testing::TestRenderBackend)
        buf_origin = content_layer.not_nil!.buffer_origin
        # Cell position in buffer: content_x - buffer_origin_x
        cell_buf_x = (cell_19.bounds.x - buf_origin.x).to_i
        cell_buf_y = (cell_19.bounds.y - buf_origin.y).to_i
        # Sample in the middle of the cell's visible portion in the buffer
        sample_x = cell_buf_x + 20 # 20px into the cell
        sample_y = cell_buf_y + cell_19.bounds.height.to_i // 2
        if sample_x >= 0 && sample_x < lb.width && sample_y >= 0 && sample_y < lb.height
          buf_pixel = lb.get_pixel(sample_x, sample_y)
          if px = buf_pixel
            px.r.should eq(255_u8),
              "Content layer buffer at cell {1,9} position (#{sample_x},#{sample_y}) should be white, " \
              "got r=#{px.r} g=#{px.g} b=#{px.b}. buf_origin=#{buf_origin}, cell_bounds=#{cell_19.bounds}"
          end
        else
          fail "Cell {1,9} buffer position (#{sample_x},#{sample_y}) is outside buffer #{lb.width}x#{lb.height}"
        end
      end

      # Check the composited window backend
      window_backend = renderer.backend
      scroll_x = matrix.scroll_offset.x
      # Cell screen position = cell_content_x - scroll_x
      cell_screen_x = (cell_19.bounds.x - scroll_x).to_i
      cell_screen_y = cell_19.bounds.y.to_i
      win_sample_x = cell_screen_x + 20
      win_sample_y = cell_screen_y + cell_19.bounds.height.to_i // 2
      if win_sample_x >= 0 && win_sample_x < window_backend.width && win_sample_y >= 0 && win_sample_y < window_backend.height
        win_pixel = window_backend.get_pixel(win_sample_x, win_sample_y)
        if px = win_pixel
          px.r.should eq(255_u8),
            "Window composited output at merged cell position (#{win_sample_x},#{win_sample_y}) should be white, " \
            "got r=#{px.r} g=#{px.g} b=#{px.b}. scroll=#{scroll_x}, cell_bounds=#{cell_19.bounds}"
        end
      end
    end
  end

  describe "Bug D: Step-by-step scroll with pixel check at every position" do
    it "merged cell {1,9} has white pixels at every scroll step (forward)", tags: "slow" do
      merges = [
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
        { {2, 1}, {2, 4} }, { {1, 9}, {2, 12} }, { {4, 1}, {4, 4} },
        { {4, 5}, {4, 8} }, { {6, 1}, {6, 4} }, { {5, 9}, {6, 12} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      adapter = CompoundScrollAdapter.new(7, 13, col_scroll_order: scroll_order, merges: merges)

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "bugd_step")
      adapter.invalidate_all!
      matrix.col_width(0, 4.0)
      matrix.row_height(0, 1.5)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(660, 300)
      renderer.settle_rendering(app)

      point = CrymbleUI::Vec2.new(330.0, 150.0)
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      layer_bg = CrymbleUI::Color.new(40, 40, 40, 255)
      failures = [] of String

      # Scroll right 40 steps × 30px = 1200px total
      40.times do |step|
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)

        scroll_x = matrix.scroll_offset.x
        cell_19 = matrix.active_cells[{1, 9}]?
        next unless cell_19  # Not yet visible

        # Check: is the cell's expected screen position within the viewport?
        cell_screen_x = (cell_19.bounds.x - scroll_x).to_i
        next if cell_screen_x < 0 || cell_screen_x >= 660  # Off-screen

        # Check composited window pixel at cell position
        win_backend = renderer.backend
        sample_x = cell_screen_x + 20
        sample_y = cell_19.bounds.y.to_i + cell_19.bounds.height.to_i // 2
        next if sample_x < 0 || sample_x >= win_backend.width || sample_y < 0 || sample_y >= win_backend.height

        px = win_backend.get_pixel(sample_x, sample_y)
        next unless px

        content_layer = matrix.content_layer
        buf_origin = content_layer ? content_layer.buffer_origin : CrymbleUI::Vec2.zero

        if px.r < 200 || px.g < 200 || px.b < 200
          msg = "step=#{step} scroll=#{scroll_x.round(0)} " \
                "win(#{sample_x},#{sample_y})=RGB(#{px.r},#{px.g},#{px.b}) " \
                "cell_bounds=#{cell_19.bounds} buf_origin=#{buf_origin} " \
                "has_backend=#{!cell_19.widget_backend.nil?}"
          failures << msg

          # Save PPM screenshots for first 3 failures
          if failures.size <= 3
            win_backend.as(CrymbleUI::Testing::TestRenderBackend).save_ppm("/tmp/bugd_win_step#{step}.ppm")
            if lb = content_layer.try(&.backend)
              lb.as(CrymbleUI::Testing::TestRenderBackend).save_ppm("/tmp/bugd_buf_step#{step}.ppm")
            end
          end
        end
      end

      if failures.any?
        fail "Merged cell {1,9} not white at #{failures.size} scroll positions:\n" +
             failures.first(5).join("\n")
      end
    end

    it "merged cell {1,9} has white pixels after scroll-back-and-forward round-trip", tags: "slow" do
      merges = [
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
        { {2, 1}, {2, 4} }, { {1, 9}, {2, 12} }, { {4, 1}, {4, 4} },
        { {4, 5}, {4, 8} }, { {6, 1}, {6, 4} }, { {5, 9}, {6, 12} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      adapter = CompoundScrollAdapter.new(7, 13, col_scroll_order: scroll_order, merges: merges)

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "bugd_rt")
      adapter.invalidate_all!
      matrix.col_width(0, 4.0)
      matrix.row_height(0, 1.5)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(660, 300)
      renderer.settle_rendering(app)

      point = CrymbleUI::Vec2.new(330.0, 150.0)
      failures = [] of String

      # Phase 1: Scroll right 30 steps (900px)
      30.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # Phase 2: Scroll back left 30 steps (back to ~0)
      30.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # Phase 3: Scroll right again 40 steps — check at each step
      40.times do |step|
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)

        scroll_x = matrix.scroll_offset.x
        cell_19 = matrix.active_cells[{1, 9}]?
        next unless cell_19

        cell_screen_x = (cell_19.bounds.x - scroll_x).to_i
        next if cell_screen_x < 0 || cell_screen_x >= 660

        win_backend = renderer.backend
        sample_x = cell_screen_x + 20
        sample_y = cell_19.bounds.y.to_i + cell_19.bounds.height.to_i // 2
        next if sample_x < 0 || sample_x >= win_backend.width || sample_y < 0 || sample_y >= win_backend.height

        px = win_backend.get_pixel(sample_x, sample_y)
        next unless px

        content_layer = matrix.content_layer
        buf_origin = content_layer ? content_layer.buffer_origin : CrymbleUI::Vec2.zero

        if px.r < 200
          msg = "RT step=#{step} scroll=#{scroll_x.round(0)} " \
                "win(#{sample_x},#{sample_y})=RGB(#{px.r},#{px.g},#{px.b}) " \
                "cell_bounds=#{cell_19.bounds} buf_origin=#{buf_origin} " \
                "has_backend=#{!cell_19.widget_backend.nil?}"
          failures << msg
          if failures.size <= 3
            win_backend.as(CrymbleUI::Testing::TestRenderBackend).save_ppm("/tmp/bugd_rt_win_step#{step}.ppm")
            if lb = content_layer.try(&.backend)
              lb.as(CrymbleUI::Testing::TestRenderBackend).save_ppm("/tmp/bugd_rt_buf_step#{step}.ppm")
            end
          end
        end
      end

      if failures.any?
        fail "After round-trip, merged cell {1,9} not white at #{failures.size} positions:\n" +
             failures.first(5).join("\n")
      end
    end

    it "non-merged cell at same col is white (comparison)", tags: "slow" do
      merges = [
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
        { {2, 1}, {2, 4} }, { {1, 9}, {2, 12} }, { {4, 1}, {4, 4} },
        { {4, 5}, {4, 8} }, { {6, 1}, {6, 4} }, { {5, 9}, {6, 12} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      adapter = CompoundScrollAdapter.new(7, 13, col_scroll_order: scroll_order, merges: merges)

      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "bugd_cmp")
      adapter.invalidate_all!
      matrix.col_width(0, 4.0)
      matrix.row_height(0, 1.5)

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(660, 300)
      renderer.settle_rendering(app)

      point = CrymbleUI::Vec2.new(330.0, 150.0)
      merged_failures = [] of String
      single_failures = [] of String

      # Scroll right 40 steps
      40.times do |step|
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)

        scroll_x = matrix.scroll_offset.x

        # Check non-merged cell {3,9} (single cell)
        cell_39 = matrix.active_cells[{3, 9}]?
        if c39 = cell_39
          c39_screen_x = (c39.bounds.x - scroll_x).to_i
          if c39_screen_x >= 0 && c39_screen_x < 660
            win_backend = renderer.backend
            sx = c39_screen_x + 10
            sy = c39.bounds.y.to_i + c39.bounds.height.to_i // 2
            if sx >= 0 && sx < win_backend.width && sy >= 0 && sy < win_backend.height
              px = win_backend.get_pixel(sx, sy)
              if px && px.r < 200
                single_failures << "step=#{step} scroll=#{scroll_x.round(0)} cell39 RGB(#{px.r},#{px.g},#{px.b})"
              end
            end
          end
        end

        # Check merged cell {1,9}
        cell_19 = matrix.active_cells[{1, 9}]?
        if c19 = cell_19
          c19_screen_x = (c19.bounds.x - scroll_x).to_i
          if c19_screen_x >= 0 && c19_screen_x < 660
            win_backend = renderer.backend
            sx = c19_screen_x + 20
            sy = c19.bounds.y.to_i + c19.bounds.height.to_i // 2
            if sx >= 0 && sx < win_backend.width && sy >= 0 && sy < win_backend.height
              px = win_backend.get_pixel(sx, sy)
              if px && px.r < 200
                merged_failures << "step=#{step} scroll=#{scroll_x.round(0)} cell19 RGB(#{px.r},#{px.g},#{px.b}) bounds=#{c19.bounds}"
              end
            end
          end
        end
      end

      # Non-merged cells should always be white
      single_failures.should be_empty, "Non-merged cell {3,9} failures: #{single_failures.first(3).join(", ")}"
      # Merged cells should also be white (this is the bug test)
      merged_failures.should be_empty, "Merged cell {1,9} failures: #{merged_failures.first(3).join(", ")}"
    end
  end

  describe "Compound Cell Visible Size + pos_clipped (WU3)" do
    it "compound cell has full width when no scroll" do
      # Compound spans cols 2+3 (each ~103px)
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 10, merges: merges)
      matrix, _, _ = setup_compound_matrix(adapter, 1200.0, 300.0)

      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)

      # No scroll → compound cell at (0,2) should span 2 columns
      if cell = matrix.active_cells[{0, 2}]?
        # Width should be ~2 * col_w minus GRID_SPACING (for cell constraints)
        expected_width = col_w * 2 - CrymbleUI::VirtualMatrix::GRID_SPACING
        cell.bounds.width.should be_close(expected_width, 1.0)
      else
        fail "Cell (0,2) not found"
      end
    end

    it "compound cell keeps full width when not enough scroll to shift col out" do
      # Compound spans cols 2+3 with scroll_order [2,3,4,...,1,0]
      # At scroll_x=60, col 2 has NOT been fully shifted out (needs 103px)
      # So the compound cell should keep its full width
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [2, 3, 4, 5, 6, 7, 8, 9, 1, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 1200.0, 300.0)

      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)

      # Scroll 60px (< col_w=103): col 2 is still in visible set
      scroll_x = 60.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Handle is still (0,2), compound should be full width
      if cell = matrix.active_cells[{0, 2}]?
        full_width = col_w * 2 - CrymbleUI::VirtualMatrix::GRID_SPACING
        cell.bounds.width.should be_close(full_width, 1.0)
      end
    end

    it "content compound cell retains full width when shifting col fully scrolled" do
      # Bug A fix: Content cells have FIXED sizes in content space.
      # Compound spans cols 2+3. Even when col 2 scrolls out, the content cell
      # keeps its full 2-column width (buffer_origin handles the viewport shift).
      merges = [{ {0, 2}, {0, 3} }]
      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [2, 3, 4, 5, 6, 7, 8, 9, 1, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 1200.0, 300.0)

      col_w = (CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0)

      # Scroll col 2 fully out
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w + 5.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Dynamic handle should now be (0,3) since col 2 is out
      if cell = matrix.active_cells[{0, 3}]?
        # Content cell keeps full 2-column width (Bug A fix)
        full_width = col_w * 2 - CrymbleUI::VirtualMatrix::GRID_SPACING
        cell.bounds.width.should be_close(full_width, 1.0)
      end
    end
  end

  describe "Bug: sticky row header uses natural index instead of scroll_order position" do
    # Task board: scroll_order [2,3,4,1,6,7,8,5,10,11,12,9,0]
    # At small scroll, shifting_index=2 (col 2 is first in scroll_order).
    # Col 1 has natural index 1 < 2 but is at position 3 in scroll_order (NOT shifted).
    # Bug: reposition_sticky_cells checks `ci < shifting_index` using natural indices,
    # wrongly treating col 1 as "shifted" → no scroll adjustment applied.

    it "compound header left edge aligns with content at small horizontal scroll" do
      merges = [
        # Row 0: status headers (4-col merges)
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        # Col 0: priority headers (2-row merges)
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      row_scroll_order = [1, 2, 3, 4, 5, 6, 0]
      adapter = CompoundScrollAdapter.new(7, 13,
        col_scroll_order: scroll_order,
        row_scroll_order: row_scroll_order,
        merges: merges)

      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0 # 103

      # Scroll right by 10px — col 2 is shifting but NOT shifted out
      # shifting_index = 2, col 1 has natural index 1 < 2 but is NOT shifted
      scroll_x = 10.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # "1-Ready" header at (0,1) — compound cell spanning cols 1-4
      header = matrix.active_cells[{0, 1}]?
      header.should_not be_nil, "Header cell (0,1) should exist"

      # Left edge: compound cell pins at sticky_col_w = sticky_col_width_pixels +
      # ruler_col_width_pixels = col_w + 40. With rulers enabled by default
      # (ruler_col_width_pixels = 40px), sticky_col_w = 143, so min_screen_x = 143.
      ruler_col_w = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0  # 40px
      header.not_nil!.bounds.x.should be_close(col_w + ruler_col_w, 1.0)
    end

    it "compound header has full width when constituent col has lower natural index" do
      merges = [
        { {0, 1}, {0, 4} }, { {0, 5}, {0, 8} }, { {0, 9}, {0, 12} },
        { {1, 0}, {2, 0} }, { {3, 0}, {4, 0} }, { {5, 0}, {6, 0} },
      ]

      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      row_scroll_order = [1, 2, 3, 4, 5, 6, 0]
      adapter = CompoundScrollAdapter.new(7, 13,
        col_scroll_order: scroll_order,
        row_scroll_order: row_scroll_order,
        merges: merges)

      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0, show_rulers: false)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0 # 103
      gs = CrymbleUI::VirtualMatrix::GRID_SPACING

      # Scroll right by 10px
      matrix.scroll_offset = CrymbleUI::Vec2.new(10.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      header = matrix.active_cells[{0, 1}]?
      header.should_not be_nil

      # Width: col 1 is "behind" sticky boundary (natural index 1 < shifting_index)
      # so it's pinned at sticky_col_w. Compound width = max_right - sticky_col_w.
      # max_right = true_x(4) + col_w - scroll_x = 4*103 + 103 - 10 = 505
      # compound_w = 505 - 103 = 402, widget_w = 402 - 3 = 399
      expected_w = 4 * col_w - gs - 10.0
      header.not_nil!.bounds.width.should be_close(expected_w, 1.0)
    end

    it "non-compound sticky-row cell aligns with content at small scroll" do
      # Setup: 3x7 matrix, scroll_order [2, 1, 3, 4, 5, 6, 0]
      # Col 0 is sticky (last), row 0 is sticky (last)
      # At scroll=10, shifting_index=2, col 1 has natural index 1 < 2 but NOT shifted
      # Viewport (400px) < content (7*103=721px) so scroll is possible
      scroll_order = [2, 1, 3, 4, 5, 6, 0]
      row_scroll_order = [1, 2, 0]
      adapter = CompoundScrollAdapter.new(3, 7,
        col_scroll_order: scroll_order,
        row_scroll_order: row_scroll_order)

      matrix, _, constraints = setup_compound_matrix(adapter, 400.0, 200.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0 # 103

      # Scroll right by 10px
      scroll_x = 10.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Non-compound cell at (0,1) — single cell in sticky row, not in sticky col
      cell = matrix.active_cells[{0, 1}]?
      cell.should_not be_nil, "Cell (0,1) should exist"

      # A sticky-ROW cell is a header sitting above its column; it must track that column
      # horizontally so it stays aligned with BOTH the content layer and the column ruler,
      # which scroll uniformly (content_x − live_scroll). So at scroll=10 cell (0,1) sits at
      # its content position MINUS the scroll (= ruler + col_w − 10 = 133), aligning with
      # column 1's data — exactly what this example's name asserts. The earlier expectation
      # here pinned it at a scroll-independent slot (143), per the old StickyMath "freeze
      # not-yet-shifted columns" model; that model is the very sub-column-hscroll FREEZE the
      # uniform-scroll fix removed (see virtual_matrix_sticky_row_hscroll_spec). Pinning would
      # misalign the header from its own column and ruler.
      ruler_col_w = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0  # 40px
      cell.not_nil!.bounds.x.should be_close(col_w + ruler_col_w - scroll_x, 1.0)
    end
  end

  describe "Bug: sticky header border misalignment at fractional scroll offset" do
    # When scroll_offset has a fractional part (e.g., 5.7), the content layer
    # compositor truncates it to integer (viewport_x = scroll.to_i = 5), placing
    # content cells at integer pixel positions. But reposition_sticky_cells
    # subtracts the full Float64 scroll, creating fractional positions that
    # truncate differently when mapped to layer-local pixels → 1px misalignment.
    it "sticky header aligns with content at fractional scroll offset" do
      scroll_order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      row_scroll_order = [1, 2, 3, 4, 5, 6, 0]
      adapter = CompoundScrollAdapter.new(7, 13,
        col_scroll_order: scroll_order,
        row_scroll_order: row_scroll_order)

      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0 # 103

      # Fractional scroll to trigger truncation mismatch
      scroll_x = 5.7
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Non-compound sticky-row cell at (0,3) — col 3 is not the shifting element (col 2 shifts first)
      # Its position should match content cell alignment: integer-truncated scroll
      header = matrix.active_cells[{0, 3}]?
      header.should_not be_nil, "Header cell (0,3) should exist"

      # Content cell at col 3 has content_x = ruler_offset + 3*103 = 349
      # Content compositor uses viewport_x = scroll.to_i = 5
      # Screen position = 349 - 5 = 344
      # Sticky header should match: position should be integer (344), NOT fractional
      ruler_col_w = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0  # 40px
      content_x = ruler_col_w.to_i + 3 * col_w.to_i  # 349
      expected_screen_x = content_x - scroll_x.to_i  # 349 - 5 = 344

      # The header bounds.x (after reposition) should use integer scroll truncation
      # to align with the content layer's integer viewport offset.
      # Allow 0.5 tolerance since we're testing integer alignment.
      header_x = header.not_nil!.bounds.x
      (header_x.round - expected_screen_x).abs.should be <= 0
    end
  end

  describe "Compound X header pins at sticky boundary during hscroll" do
    # Setup: compound header {0,1}-{0,4} in sticky row 0, with col 0 sticky.
    # As data columns scroll left, the compound should PIN its left edge at
    # sticky_col_w (the boundary between sticky cols and data), NOT slide left.
    # Width shrinks as constituent columns scroll behind the boundary.

    it "compound header pins at sticky_col_w when first col partially behind boundary" do
      merges = [{ {0, 1}, {0, 4} }]

      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
        row_scroll_order: [1, 2, 3, 4, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      sticky_col_w = col_w # Just col 0

      # Scroll so col 1 is partially behind the sticky boundary
      matrix.scroll_offset = CrymbleUI::Vec2.new(50.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Find compound cell (handle might be {0,1} or shifted)
      cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
      cell.should_not be_nil, "Compound header should exist"

      # KEY: left edge must be at sticky_col_w (pinned), not below it
      cell.not_nil!.bounds.x.should be >= sticky_col_w,
        "Compound header should pin at sticky boundary (#{sticky_col_w}), " \
        "got x=#{cell.not_nil!.bounds.x}"
    end

    it "compound header width shrinks when first col scrolls fully behind boundary" do
      merges = [{ {0, 1}, {0, 4} }]

      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
        row_scroll_order: [1, 2, 3, 4, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0, show_rulers: false)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      gs = CrymbleUI::VirtualMatrix::GRID_SPACING
      full_width = 4 * col_w - gs

      # No scroll: full width (pinned at sticky_col_w, so slightly less than 4*col_w-gs)
      cell0 = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
      cell0.should_not be_nil
      cell0.not_nil!.bounds.width.should be_close(full_width, 1.0)

      # Scroll col 1 fully out
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w + 5.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
      cell.should_not be_nil, "Compound header should still exist after col 1 scrolls out"

      # Width should be less than full (one col behind boundary)
      cell.not_nil!.bounds.width.should be < full_width,
        "Width should shrink when col scrolls behind boundary, got #{cell.not_nil!.bounds.width}"
    end

    it "compound collapses when all constituent columns scroll behind boundary" do
      merges = [{ {0, 1}, {0, 4} }]

      # Use 20 cols so total content (20*103=2060) >> viewport (800), avoiding scroll clamp
      adapter = CompoundScrollAdapter.new(5, 20,
        col_scroll_order: ((1..19).to_a + [0]),
        row_scroll_order: [1, 2, 3, 4, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0

      # Scroll all 4 cols fully behind boundary (4*103+5 = 417, well within max_scroll ~1260)
      matrix.scroll_offset = CrymbleUI::Vec2.new(4 * col_w + 5.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Compound cell should either not exist or have collapsed width
      cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
      if cell
        cell.bounds.width.should be <= 1.0,
          "Collapsed compound should have near-zero width, got #{cell.bounds.width}"
      end
    end

    it "compound scrolls off with last column when only 1 visible col remains" do
      merges = [{ {0, 1}, {0, 4} }]

      # 20 cols to avoid scroll clamping
      adapter = CompoundScrollAdapter.new(5, 20,
        col_scroll_order: ((1..19).to_a + [0]),
        row_scroll_order: [1, 2, 3, 4, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      sticky_col_w = col_w

      # Scroll so only col 4 remains (cols 1-3 fully behind boundary)
      # Col 4: true_x=412, at scroll=359: unclamped=53, col_right=156 > boundary
      # Cols 1-3: col_rights all <= 103 → skipped → only col 4 visible
      matrix.scroll_offset = CrymbleUI::Vec2.new(3 * col_w + 50.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
      cell.should_not be_nil, "Compound header should exist with 1 visible col"

      # Single visible col: compound should follow it (NOT pin at boundary)
      # Reference line 189: compound_size[1]==1 → pos_regular.x (unclamped)
      cell.not_nil!.bounds.x.should be < sticky_col_w,
        "Single-col compound should scroll off (x < #{sticky_col_w}), " \
        "got x=#{cell.not_nil!.bounds.x} (pinned — wrong)"
    end

    it "compound left edge never goes below sticky_col_w across progressive scroll" do
      merges = [{ {0, 1}, {0, 4} }]

      adapter = CompoundScrollAdapter.new(5, 10,
        col_scroll_order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
        row_scroll_order: [1, 2, 3, 4, 0],
        merges: merges)
      matrix, _, constraints = setup_compound_matrix(adapter, 800.0, 300.0)

      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      sticky_col_w = col_w

      failures = [] of String

      # Scroll from 1 to 5*col_w in steps of 5px
      (1..((5 * col_w).to_i)).step(5) do |sx|
        matrix.scroll_offset = CrymbleUI::Vec2.new(sx.to_f64, 0.0)
        matrix.layout(constraints, CrymbleUI::Vec2.zero)

        cell = (1..4).each.compact_map { |c| matrix.active_cells[{0, c}]? }.first?
        next unless cell
        next if cell.bounds.width <= 1.0 # Collapsed, OK

        if cell.bounds.x < sticky_col_w - 0.5
          failures << "scroll=#{sx}: x=#{cell.bounds.x.round(1)} < sticky_col_w=#{sticky_col_w}"
        end
      end

      failures.should be_empty,
        "Compound header went below sticky boundary at #{failures.size} positions:\n" +
        failures.first(5).join("\n")
    end
  end

  # Regression: compound header cells at the RIGHT edge of the viewport are blank
  # after horizontal scroll. The compound cell width doesn't cover newly visible
  # constituent columns until one more scroll step forces a recompute.
  describe "Compound header right-edge coverage on hscroll" do
    it "compound header right edge reaches rightmost visible constituent column after hscroll" do
      # Setup: ConfigurableMatrixAdapter with 2-level col headers.
      # Col header row 0 has compound cells spanning 30 data cols each.
      # Scrolling right brings new constituent columns into view from the right edge.
      # Bug: @viewport_col_positions was cached and didn't include newly-visible columns,
      # causing compound cell width to miss right-edge columns.
      adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
      matrix, app, constraints = setup_compound_matrix(adapter, 800.0, 400.0)

      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      app.build_tree
      renderer.settle_rendering(app)

      center = CrymbleUI::Vec2.new(400.0, 200.0)
      sticky_cols = matrix.sticky_col_count
      failures = [] of String

      20.times do |step|
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
        renderer.render_frame(app)

        sticky_rows = matrix.sticky_row_count
        row0_compounds = matrix.active_cells.select { |key, widget|
          row, col = key
          row < sticky_rows && col >= sticky_cols &&
            matrix.get_bounding_box(key)[0] != matrix.get_bounding_box(key)[1]
        }

        # For each compound header, verify its right edge reaches the rightmost visible
        # constituent column. The cell is in screen-space (pinned at sticky boundary),
        # so we compare cell right edge with the content layer's viewport right edge.
        viewport_w = matrix.content_scroll_view.try { |sv|
          sv.sticky_row_layer.try(&.bounds.width)
        } || 800.0

        row0_compounds.each do |key, widget|
          bb = matrix.get_bounding_box(key)
          min_col = bb[0][1]
          max_col = bb[1][1]

          vis = matrix.visible_cell_indices[:cols]
          visible_in_compound = vis.select { |c| c >= min_col && c <= max_col }
          next if visible_in_compound.empty?

          next if widget.bounds.x < -100.0  # parked off-screen
          next if widget.bounds.width <= 1.0  # collapsed

          # The compound cell should fill its portion of the sticky_row_layer.
          # Its right edge (in layer-local coords) should reach the layer width
          # OR at least the rightmost visible column's screen position.
          cell_right_in_layer = widget.bounds.x + widget.bounds.width -
            (matrix.sticky_col_width_pixels + matrix.ruler_col_width_pixels)

          # Allow 2 column widths of tolerance (for capping + grid_spacing)
          col_px = (CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter::DEFAULT_COLUMN_WIDTH *
                    CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE).to_f64
          tolerance = col_px * 2

          if cell_right_in_layer + tolerance < viewport_w
            failures << "step=#{step} cell=#{key}: right_edge=#{cell_right_in_layer.round(1)} " \
              "viewport_w=#{viewport_w.round(1)} gap=#{(viewport_w - cell_right_in_layer).round(1)}px " \
              "(#{visible_in_compound.size} visible cols: #{visible_in_compound.first}..#{visible_in_compound.last})"
          end
        end
      end

      failures.should be_empty,
        "Compound header right edge doesn't reach viewport for some scroll positions:\n" +
        failures.first(5).join("\n")
    end

    it "compound header has non-blank pixels at right edge after scrollbar-style hscroll" do
      # Verify the VISUAL result: after scrollbar-driven horizontal scroll (deferred path),
      # the sticky_row_layer has non-background-color pixels in the header area at the
      # right portion. This catches: compound cells created but not rendered (blank).
      adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
      matrix, app, constraints = setup_compound_matrix(adapter, 800.0, 400.0)

      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      app.build_tree
      renderer.settle_rendering(app)

      sv = matrix.content_scroll_view.not_nil!
      bg_color = CrymbleUI::Color.new(230, 230, 230, 255)  # content_background_color

      # Simulate scrollbar-driven scroll (deferred path via sync_from_scroll_view)
      # by setting ScrollView offset directly — this mimics thumb drag behavior.
      failures = [] of String
      (1..30).each do |step|
        scroll_x = step * 100.0  # 100px per step to cross compound boundaries
        sv.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
        renderer.render_frame(app)

        row_layer = sv.sticky_row_layer
        next unless row_layer
        raw_backend = row_layer.backend
        next unless raw_backend.is_a?(CrymbleUI::Testing::TestRenderBackend)
        backend = raw_backend
        next if backend.width < 10 || backend.height < 10

        # Sample pixel at 75% of the layer width (right portion of header)
        sample_x = (backend.width * 0.75).to_i.clamp(0, backend.width - 1)
        # Sample in the middle of header row 1 (row 0 is at y≈0..30, row 1 at y≈33..63)
        sample_y = (backend.height * 0.7).to_i.clamp(0, backend.height - 1)
        pixel = backend.get_pixel(sample_x, sample_y)

        # The pixel should NOT be the sticky background color (which is
        # the same as content_background_color for this adapter)
        if pixel == bg_color
          failures << "step=#{step} scroll=#{scroll_x}: blank pixel at (#{sample_x},#{sample_y}) on sticky_row_layer"
        end
      end

      failures.should be_empty,
        "Compound header area has blank pixels after scrollbar-driven hscroll:\n" +
        failures.first(5).join("\n")
    end

    it "compound header cells tile viewport without gaps during hscroll" do
      # Verify: at every scroll position, compound header cells in each sticky row
      # cover the full viewport width. Any gap = visible blank area in the header.
      # Bug: the sticky cache key only updates when a full column scrolls past, so for
      # intermediate scroll steps, new compound cells at the right edge aren't created.
      adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10)
      matrix, app, constraints = setup_compound_matrix(adapter, 800.0, 400.0)

      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      app.build_tree
      renderer.settle_rendering(app)

      center = CrymbleUI::Vec2.new(400.0, 200.0)
      sticky_rows = matrix.sticky_row_count
      sticky_cols = matrix.sticky_col_count
      failures = [] of String

      # Scroll through several compound cell boundaries
      90.times do |step|
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
        renderer.render_frame(app)

        sv = matrix.content_scroll_view
        next unless sv
        row_layer = sv.sticky_row_layer
        next unless row_layer

        # For each header row, collect compound cell bounds on the sticky_row_layer
        # and check they cover from sticky_col_w to the layer's right edge.
        sticky_col_w = matrix.sticky_col_width_pixels + matrix.ruler_col_width_pixels
        layer_w = row_layer.bounds.width

        (0...sticky_rows).each do |hdr_row|
          # Collect active compound cells in this header row
          cells = matrix.active_cells.select { |k, w|
            k[0] == hdr_row && k[1] >= sticky_cols &&
              matrix.get_bounding_box(k)[0] != matrix.get_bounding_box(k)[1]
          }
          next if cells.empty?

          # Compute coverage: for each cell, what screen-space range does it cover?
          # Cell bounds are in VirtualMatrix coords; convert to layer-local.
          # Filter to cells actually visible on the layer (within layer bounds).
          covered_ranges = cells.map { |k, w|
            local_x = w.bounds.x - sticky_col_w
            local_right = local_x + w.bounds.width
            # Skip off-screen/collapsed/parked cells
            next nil if w.bounds.x < -100.0 || w.bounds.width <= 1.0
            next nil if local_right <= 0.0  # Entirely left of layer
            next nil if local_x >= layer_w  # Entirely right of layer
            {local_x, local_right}
          }.compact.sort_by { |r| r[0] }

          # Check for gaps: each range should start at or before the previous one ends
          next if covered_ranges.empty?
          # The first cell should start at or before 0 (covering the viewport left edge)
          rightmost = covered_ranges.first[1]
          covered_ranges.each_with_index do |range, i|
            next if i == 0
            gap = range[0] - rightmost
            if gap > 5.0  # Allow small tolerance for grid_spacing
              failures << "step=#{step} row=#{hdr_row}: #{gap.round(0)}px gap at x=#{rightmost.round(0)}"
              break  # One failure per row per step is enough
            end
            rightmost = {rightmost, range[1]}.max
          end

          # The last cell should reach the viewport right edge
          if rightmost + 5.0 < layer_w  # Allow tolerance
            failures << "step=#{step} row=#{hdr_row}: right edge #{rightmost.round(0)} < layer_w #{layer_w.round(0)}"
          end
        end
      end

      failures.should be_empty,
        "Compound header cells have gaps in viewport coverage:\n" +
        failures.first(5).join("\n")
    end
  end
end
