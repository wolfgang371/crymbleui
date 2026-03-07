require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Adapter for scroll render tests - simple sequential layout, no stickies
class ScrollRenderAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

private def setup_scroll_render_matrix(rows = 100, cols = 10, viewport_width = 400.0, viewport_height = 300.0)
  adapter = ScrollRenderAdapter.new(rows, cols)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "scroll_render_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  renderer = CrymbleUI::Testing::TestRenderer.new(viewport_width.to_i, viewport_height.to_i)
  renderer.settle_rendering(app)

  {matrix, app, renderer}
end

# Adapter for compound cell scroll tests — out-of-order scroll_order with merged cells
# Mimics the task board layout: 7 rows x 13 cols with status/priority headers
class TaskBoardScrollAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
  @data : Array(Array(String))

  def initialize
    # Initialize data array
    @data = Array.new(7) do |row|
      Array.new(13) do |col|
        case {row, col}
        when {0, 1} then "1-Ready"
        when {0, 5} then "2-InWork"
        when {0, 9} then "3-Done"
        when {1, 0}, {2, 0} then "1-High"
        when {3, 0}, {4, 0} then "2-Medium"
        when {5, 0}, {6, 0} then "3-Low"
        else "#{row},#{col}"
        end
      end
    end

    # Row 0 status headers: 4-col merges
    define_merge({0, 1}, {0, 4})    # "1-Ready"
    define_merge({0, 5}, {0, 8})    # "2-InWork"
    define_merge({0, 9}, {0, 12})   # "3-Done"
    # Col 0 priority headers: 2-row merges
    define_merge({1, 0}, {2, 0})    # "1-High"
    define_merge({3, 0}, {4, 0})    # "2-Medium"
    define_merge({5, 0}, {6, 0})    # "3-Low"
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new(@data[row]?.try(&.[col]?) || "")
  end

  # Within each status group, detail cols scroll first, then ID col.
  # Col 0 (priority) scrolls last → sticky.
  # Row 0 (status header) scrolls last → sticky.
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {[1, 2, 3, 4, 5, 6, 0], [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end

  private def define_merge(top_left : Tuple(Int32, Int32), bottom_right : Tuple(Int32, Int32))
    @merges << {top_left, bottom_right}
  end
end

private def setup_compound_scroll_matrix(viewport_width = 800.0, viewport_height = 400.0)
  adapter = TaskBoardScrollAdapter.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_scroll_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

# DSL-style app that recreates VirtualMatrix on every build() (like real demo apps)
# This exercises the rebuild + reconciliation path that TestApp.root_widget= does NOT
class CompoundScrollDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    adapter = TaskBoardScrollAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "task_board")
    matrix.col_width(0, 4.0)
    matrix.row_height(0, 1.5)
    matrix
  end
end

describe CrymbleUI::VirtualMatrix do
  describe "Scroll performance: no rebuild on mouse wheel" do
    it "root stays Clean after compound matrix mouse wheel scroll" do
      matrix, app, _ = setup_compound_scroll_matrix
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      # Root must be Clean after settle
      app.root.not_nil!.needs_layout?.should be_false,
        "Root should be Clean after settle_rendering, but is NeedsLayout"

      # Simulate horizontal scroll via on_mouse_wheel
      center = CrymbleUI::Vec2.new(400.0, 200.0)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)

      # Root must still be Clean (scroll is render-only, never layout)
      app.root.not_nil!.needs_layout?.should be_false,
        "Root became NeedsLayout after on_mouse_wheel. " \
        "Scroll must not trigger mark_needs_layout propagation to root."
    end

    it "DSL app root is Clean after settle_rendering" do
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      app.root.not_nil!.needs_layout?.should be_false,
        "Root should be Clean after settle_rendering on DSL app, " \
        "but state=#{app.root.not_nil!.state}"
    end

    it "scroll does not trigger rebuild on compound matrix DSL app" do
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      CrymbleUI::App.reset_rebuild_count
      point = CrymbleUI::Vec2.new(400.0, 200.0)

      # Track where rebuilds come from
      rebuilds_from_handle = 0
      rebuilds_from_loop = 0

      # 10 horizontal scroll events (simulating SFML event loop pattern)
      10.times do |i|
        before_handle = CrymbleUI::App.rebuild_count
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        after_handle = CrymbleUI::App.rebuild_count
        rebuilds_from_handle += (after_handle - before_handle)

        # Simulate event loop rebuild check (sfml_renderer.cr line 499)
        if app.root.try(&.needs_layout?)
          app.rebuild
          rebuilds_from_loop += 1
        end
        renderer.render_frame(app)
      end

      # Scroll should NOT trigger rebuilds (it's a render-only operation)
      CrymbleUI::App.rebuild_count.should be <= 0,
        "Mouse wheel scroll triggered #{CrymbleUI::App.rebuild_count} rebuilds " \
        "(#{rebuilds_from_handle} from handle_mouse_wheel, #{rebuilds_from_loop} from event loop). " \
        "exceptions_caught=#{renderer.exceptions_caught} " \
        "last_exception=#{renderer.last_exception_message} " \
        "Scroll is a render-only operation and should never trigger rebuild."
    end

    it "scrollbar drag does not trigger rebuild on compound matrix DSL app" do
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      CrymbleUI::App.reset_rebuild_count
      rebuilds_from_drag = 0

      # Horizontal scrollbar is at the bottom of the viewport (last 16px)
      scrollbar_y = 400.0 - 8.0

      # Mouse down on horizontal scrollbar thumb (starts at left side at scroll=0)
      app.handle_mouse_down(CrymbleUI::Vec2.new(50.0, scrollbar_y))

      # Drag horizontally (10 steps)
      10.times do |i|
        before_drag = CrymbleUI::App.rebuild_count
        app.handle_mouse_move(CrymbleUI::Vec2.new(50.0 + (i + 1) * 20.0, scrollbar_y))
        after_drag = CrymbleUI::App.rebuild_count
        rebuilds_from_drag += (after_drag - before_drag)

        # Simulate SFML event loop: only rebuild on needs_layout (not needs_render)
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      app.handle_mouse_up(CrymbleUI::Vec2.new(250.0, scrollbar_y))

      # Scrollbar drag should NOT trigger rebuilds (scroll is render-only)
      CrymbleUI::App.rebuild_count.should be <= 0,
        "Scrollbar drag triggered #{CrymbleUI::App.rebuild_count} rebuilds " \
        "(#{rebuilds_from_drag} from handle_mouse_move). " \
        "exceptions_caught=#{renderer.exceptions_caught} " \
        "last_exception=#{renderer.last_exception_message} " \
        "Scroll is a render-only operation and should never trigger rebuild."
    end

    it "no sibling overlap at narrow viewport across full horizontal scroll range", tags: "slow" do
      # Use a narrower viewport (~700px) that matches real SFML demo sizing.
      # At 800px the overlap bug doesn't trigger because positions differ.
      # At ~666-700px, the StickyMath index_beyond bug + compound cell width
      # inflation combine to cause sibling overlap exceptions.
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 400)
      renderer.settle_rendering(app)

      CrymbleUI::App.reset_rebuild_count
      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # Scroll from 0 to max in fine increments to find the overlap position.
      # Total content = 83 + 12*103 = 1319px, viewport ~700px → max_scroll ≈ 619px
      # Use direct scroll_offset setting + reposition to exercise exact positions.
      scroll_step = 10.0
      max_scroll = 650.0
      scroll_x = 0.0

      while scroll_x <= max_scroll
        # Simulate scrollbar drag: set scroll offset directly via mouse wheel
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -1.0),
          CrymbleUI::Vec2.new(350.0, 200.0),
          shift: true
        )

        # Simulate SFML event loop
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)

        scroll_x += scroll_step
      end

      # Continue scrolling with larger jumps to cover full range
      30.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -3.0),
          CrymbleUI::Vec2.new(350.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      renderer.exceptions_caught.should eq(0),
        "Sibling overlap exceptions at narrow viewport (700px): " \
        "#{renderer.exceptions_caught}. " \
        "scroll_offset=#{matrix.scroll_offset} " \
        "last_exception=#{renderer.last_exception_message} " \
        "This indicates compound cell width inflation from clamped shifting columns."

      CrymbleUI::App.rebuild_count.should be <= 0,
        "Narrow viewport scroll triggered #{CrymbleUI::App.rebuild_count} rebuilds. " \
        "exceptions_caught=#{renderer.exceptions_caught}"
    end

    it "no rendering exceptions at large scroll offsets with content-layer viewport" do
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      CrymbleUI::App.reset_rebuild_count
      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # Scroll to large offsets (0 to max in 20 steps) using handle_mouse_wheel
      # which exercises the same update_visible_cells + reposition_sticky_cells path.
      # Scroll in large jumps to reach offsets where "3-Done" is partially visible.
      20.times do |i|
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), CrymbleUI::Vec2.new(400.0, 200.0), shift: true)
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      # Verify no rendering exceptions (sibling overlap) occurred
      renderer.exceptions_caught.should eq(0),
        "Rendering exceptions at large scroll offsets: #{renderer.exceptions_caught}. " \
        "scroll_offset=#{matrix.scroll_offset} " \
        "last_exception=#{renderer.last_exception_message}"

      CrymbleUI::App.rebuild_count.should be <= 0,
        "Large scroll triggered #{CrymbleUI::App.rebuild_count} rebuilds. " \
        "exceptions_caught=#{renderer.exceptions_caught} " \
        "last_exception=#{renderer.last_exception_message}"
    end
  end

  describe "Compound header visibility during fine-grained scroll" do
    it "compound header reappears promptly when scrolling back", tags: "slow" do
      # Bug: scroll right past col 1 shift-out (412px) → cell (0,1) destroyed.
      # Then scroll LEFT in small increments (< 50px threshold) → early exit
      # prevents cell recreation. "1-Ready" is missing for up to 50px of backward scroll.
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 400)
      renderer.settle_rendering(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # scroll_order: [2,3,4,1, ...] → col 1 shifts at cumulative 412px
      # First, scroll right past 412 in large steps (triggering full updates)
      50.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -0.5),
          CrymbleUI::Vec2.new(350.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      scroll_x = matrix.scroll_offset.x
      scroll_x.should be > 412.0,
        "Should have scrolled past col 1 shift-out at 412px, but only at #{scroll_x.round(1)}"

      # Verify cell (0,1) is destroyed (col 1 fully shifted out)
      ready_handle = matrix.active_cells.keys.find { |k| k[0] == 0 && (1..4).includes?(k[1]) }
      ready_handle.should be_nil,
        "1-Ready compound cell should be destroyed at scroll_x=#{scroll_x.round(1)}"

      # Now scroll LEFT in small increments (9px per step = 0.3 * SCROLL_SPEED=30)
      # This stays below the 50px threshold, hitting the early exit path.
      # After crossing below ~412px, "1-Ready" should be recreated promptly.
      missing_positions = [] of Float64
      60.times do |i|
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, 0.3),  # Positive = scroll left
          CrymbleUI::Vec2.new(350.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)

        scroll_x = matrix.scroll_offset.x
        # Col 1 shifts out at cumulative 412px. Below 412, col 1 should be visible.
        # We check from 411 down to catch the gap where the cell was destroyed
        # at scroll_x>412 but not yet recreated during backward scroll.
        next if scroll_x >= 412.0

        ready_handle = matrix.active_cells.keys.find { |k| k[0] == 0 && (1..4).includes?(k[1]) }
        unless ready_handle
          missing_positions << scroll_x
        end
      end

      missing_positions.should be_empty,
        "1-Ready compound cell missing at scroll positions " \
        "#{missing_positions.first(5).map(&.round(1))} after scrolling back left. " \
        "Cell destroyed at scroll_x>412 was not recreated during backward scroll " \
        "(early-exit path skips cell creation)."
    end
  end

  describe "Compound cell scroll positioning with out-of-order scroll_order" do
    it "compound cell handle (0,1) has non-negative X after col 2 shifts out" do
      matrix, _, constraints = setup_compound_scroll_matrix

      # Get column width for scroll calculations
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0

      # Scroll horizontally enough to shift col 2 fully out
      # Col 2 is first in scroll_order, so shifts first
      scroll_x = col_w * 1.5
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # The compound handle (0,1) for "1-Ready" should have non-negative X
      # Bug: reposition_sticky_cells uses grid-order sum which gives negative X
      # when scroll_order differs from grid order
      handle = matrix.active_cells[{0, 1}]?
      handle.should_not be_nil
      handle.not_nil!.bounds.x.should be >= 0.0,
        "Compound cell (0,1) 1-Ready has negative X=#{handle.not_nil!.bounds.x} " \
        "after scroll_x=#{scroll_x}. reposition_sticky_cells must use " \
        "StickyMath positions, not grid-order sums."
    end

    it "compound cell (0,1) stays at stable X as out-of-order cols shift" do
      matrix, _, constraints = setup_compound_scroll_matrix

      # Record initial X position of the compound handle (0,1)
      handle_before = matrix.active_cells[{0, 1}]?
      handle_before.should_not be_nil
      original_x = handle_before.not_nil!.bounds.x

      # Small scroll — not enough to shift any col out fully
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      small_scroll = col_w * 0.3
      matrix.scroll_offset = CrymbleUI::Vec2.new(small_scroll, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Col 1 hasn't shifted yet (it's 4th in scroll_order [2,3,4,1,...])
      # So the compound handle should maintain its original X position
      # (cols 2,3,4 shifting doesn't affect col 1's visual position)
      handle_after = matrix.active_cells[{0, 1}]?
      handle_after.should_not be_nil
      # The handle's viewport-relative X should not decrease when cols to its RIGHT
      # in grid order shift out before it (per scroll_order)
      handle_after.not_nil!.bounds.x.should be >= original_x - 1.0,
        "Compound cell (0,1) X dropped from #{original_x} to " \
        "#{handle_after.not_nil!.bounds.x} after small scroll. " \
        "Position should be stable while col 1 hasn't shifted."
    end

    it "compound cell width decreases as constituent cols shift out" do
      matrix, _, constraints = setup_compound_scroll_matrix

      handle_before = matrix.active_cells[{0, 1}]?
      handle_before.should_not be_nil
      original_width = handle_before.not_nil!.bounds.width

      # Scroll enough to shift col 2 out fully (first in scroll_order)
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(col_w * 1.5, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      handle_after = matrix.active_cells[{0, 1}]?
      handle_after.should_not be_nil
      # Width should decrease (lost at least one constituent column)
      handle_after.not_nil!.bounds.width.should be < original_width,
        "Compound cell width should decrease as constituent cols shift out. " \
        "Was #{original_width}, now #{handle_after.not_nil!.bounds.width}."
    end
  end

  describe "Scroll Render: buffer recenter correctness" do
    it "VirtualMatrix has clear_all_widget_backends for buffer recenter" do
      matrix, _, _ = setup_scroll_render_matrix

      # VirtualMatrix should have clear_all_widget_backends so that
      # handle_viewport_cache_scroll can clear stale backends on recenter
      # (same as ScrollView has)
      matrix.responds_to?(:clear_all_widget_backends).should be_true
    end

    it "clear_all_widget_backends clears all active cell backends" do
      matrix, app, renderer = setup_scroll_render_matrix

      # Cells should have backends after settle_rendering
      cells_with_backend = matrix.active_cells.count { |_, w| !w.widget_backend.nil? }
      cells_with_backend.should be > 0

      # Clear all backends
      matrix.clear_all_widget_backends

      # All backends should now be nil
      matrix.active_cells.each do |_key, widget|
        widget.widget_backend.should be_nil
        widget.background_backend.should be_nil
      end
    end

    it "all visible cells rendered after many cursor-down scrolls past buffer boundary" do
      matrix, app, renderer = setup_scroll_render_matrix

      row_h = 3 + matrix.get_row_height(0) * 20.0
      matrix.cursor_rc = {0, 0}

      # Scroll down enough to trigger at least one buffer recenter
      # cache_extent = 100, buffer = viewport(300) + 2*100 = 500px
      # Scrolling starts after ~13 cursor-down (cursor exits viewport)
      # After ~22 more steps, total scroll ≈ 500px → recenter
      40.times do
        matrix.move_cursor(:down)
        matrix.snap_to_cursor
        renderer.render_frame(app)
      end

      # After scrolling (with recenters), all visible cells should be rendered
      viewport_y = matrix.scroll_offset.y
      viewport_x = matrix.scroll_offset.x
      layer = matrix.content_layer.not_nil!
      viewport_h = layer.bounds.height
      viewport_w = layer.bounds.width

      visible_cells = matrix.active_cells.select do |key, widget|
        wb = widget.bounds
        wb.y + wb.height >= viewport_y && wb.y <= viewport_y + viewport_h &&
          wb.x + wb.width >= viewport_x && wb.x <= viewport_x + viewport_w
      end

      visible_cells.size.should be > 0

      cells_without_backend = visible_cells.count { |_, widget| widget.widget_backend.nil? }
      cells_without_backend.should eq(0),
        "Expected all #{visible_cells.size} visible cells to have widget_backend " \
        "after 40 cursor-down steps (includes buffer recenters), " \
        "but #{cells_without_backend} were not rendered"
    end
  end

  describe "Compound cell scroll-back width restoration" do
    # Bug: reposition_sticky_cells else branch uses widget.bounds.width (current
    # shrunken width) instead of the full compound width from bounding box cols.
    # During forward scroll, compound cells shrink correctly as constituent columns
    # shift out. During scroll-back, cells return to the else branch (all cols
    # outside viewport_col_positions) but keep their shrunken width. This creates
    # gaps between compound headers — visible as black areas in the demo.

    it "compound row header positions match initial state after scroll right then left", tags: "slow" do
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # Capture initial row-0 cell positions and widths
      initial_state = {} of {Int32, Int32} => {Float64, Float64}
      matrix.active_cells.each do |k, w|
        next unless k[0] == 0
        initial_state[k] = {w.bounds.x.round(1), w.bounds.width.round(1)}
      end

      # Scroll right to max
      40.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -1.0),
          CrymbleUI::Vec2.new(400.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      # Scroll LEFT back to scroll=0
      40.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, 1.0),
          CrymbleUI::Vec2.new(400.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      # Verify scroll returned to 0
      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset.x.should eq(0.0), "Scroll should return to 0"

      # Compare row-0 cell positions/widths to initial state
      mismatches = [] of String
      matrix.active_cells.each do |k, w|
        next unless k[0] == 0
        initial = initial_state[k]?
        next unless initial  # Cell may not have existed initially — OK
        cur_x = w.bounds.x.round(1)
        cur_w = w.bounds.width.round(1)
        init_x, init_w = initial
        if (cur_x - init_x).abs > 1.0 || (cur_w - init_w).abs > 1.0
          mismatches << "#{k}: initial(x=#{init_x},w=#{init_w}) vs after(x=#{cur_x},w=#{cur_w})"
        end
      end

      mismatches.should be_empty,
        "Row-0 compound headers don't match initial positions after scroll right+left. " \
        "The else branch in reposition_sticky_cells uses widget.bounds.width (stale shrunken " \
        "value) instead of full compound width from bounding box columns. " \
        "Mismatches: #{mismatches.join(", ")}"
    end

    it "compound col header positions match initial state after scroll down then up" do
      # Use short viewport to enable vertical scroll
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 120)
      renderer.settle_rendering(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # Capture initial col-0 cell positions and heights
      initial_state = {} of {Int32, Int32} => {Float64, Float64}
      matrix.active_cells.each do |k, w|
        next unless k[1] == 0
        initial_state[k] = {w.bounds.y.round(1), w.bounds.height.round(1)}
      end

      # Scroll down to max
      30.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -0.5),
          CrymbleUI::Vec2.new(400.0, 60.0),
          shift: false
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      # Scroll UP back to scroll=0
      30.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, 0.5),
          CrymbleUI::Vec2.new(400.0, 60.0),
          shift: false
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      # Verify scroll returned to 0
      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset.y.should eq(0.0), "Scroll should return to 0"

      # Compare col-0 cell positions/heights to initial state
      mismatches = [] of String
      matrix.active_cells.each do |k, w|
        next unless k[1] == 0
        initial = initial_state[k]?
        next unless initial
        cur_y = w.bounds.y.round(1)
        cur_h = w.bounds.height.round(1)
        init_y, init_h = initial
        if (cur_y - init_y).abs > 1.0 || (cur_h - init_h).abs > 1.0
          mismatches << "#{k}: initial(y=#{init_y},h=#{init_h}) vs after(y=#{cur_y},h=#{cur_h})"
        end
      end

      mismatches.should be_empty,
        "Col-0 compound headers don't match initial positions after scroll down+up. " \
        "Same else-branch bug for Y axis. " \
        "Mismatches: #{mismatches.join(", ")}"
    end

    it "sticky compound cell key stays as top-left during vscroll (no snap)" do
      # Bug: When "1-High" (rows 1-2, col 0) partially scrolls out,
      # dynamic_handle_cell shifts the key from {1,0} to {2,0}, destroying
      # the old widget and creating a new one. This causes a visual snap.
      # The correct behavior: sticky compound cells always keep the top-left
      # key in active_cells, since reposition_sticky_cells handles positioning.
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 120) # Short viewport for vscroll
      renderer.settle_rendering(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)

      # Verify initial state: "1-High" cell is keyed by {1,0} (top-left of merged region)
      matrix.active_cells.has_key?({1, 0}).should be_true,
        "Expected {1,0} in active_cells at scroll=0 (top-left of '1-High' compound)"

      # Scroll down incrementally. Row height ≈ 23px, SCROLL_SPEED=30, delta=-0.5 → 15px/step.
      # After ~2 steps (30px), row 1 starts to scroll out. The dynamic handle mechanism
      # would shift the key to {2,0}, destroying {1,0}. We verify this does NOT happen.
      key_destroyed = false
      replacement_created = false
      10.times do |i|
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -0.5),
          CrymbleUI::Vec2.new(400.0, 60.0),
          shift: false
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)

        matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
        if !matrix.active_cells.has_key?({1, 0})
          key_destroyed = true
        end
        if matrix.active_cells.has_key?({2, 0})
          replacement_created = true
        end
      end

      # The top-left key {1,0} must remain in active_cells throughout the scroll
      key_destroyed.should be_false,
        "Sticky compound cell {1,0} was destroyed during vscroll. " \
        "The dynamic handle mechanism shifted the key, causing a visual snap. " \
        "Sticky compounds should always use their top-left as the widget key."

      # {2,0} is a constituent of the {1,0}-{2,0} merged region — it should NOT
      # appear as a separate key in active_cells
      replacement_created.should be_false,
        "Cell {2,0} appeared as a separate key in active_cells during vscroll. " \
        "This means the compound was destroyed and recreated with a shifted key, " \
        "which causes the visual snap bug."
    end

    it "no ghost full-width row header on hscroll back-left", tags: "slow" do
      # Bug: When "1-Ready" (row 0, cols 1-4) fully scrolls out to the right,
      # then we scroll back left, the else branch in reposition_sticky_cells
      # restores full width at true_x. This creates a ghost full-width header
      # before any constituent column has re-entered the viewport.
      # The cell should stay minimal until columns actually become visible again.
      app = CompoundScrollDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
      renderer.settle_rendering(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
      initial_w = matrix.active_cells[{0, 1}].bounds.width

      # Scroll RIGHT until "1-Ready" is fully off-screen
      # Col sizes ≈ 103px each, 4 cols = 412px. At sx≈420 all cols are past sticky header.
      20.times do
        app.handle_mouse_wheel(
          CrymbleUI::Vec2.new(0.0, -1.0),
          CrymbleUI::Vec2.new(400.0, 200.0),
          shift: true
        )
        if app.root.try(&.needs_layout?)
          app.rebuild
        end
        renderer.render_frame(app)
      end

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
      # At max scroll, "1-Ready" should be minimal (all cols scrolled past)
      scrolled_w = matrix.active_cells[{0, 1}]?.try(&.bounds.width) || 0.0
      scrolled_w.should be < initial_w * 0.5,
        "After scrolling right, 1-Ready should be much smaller than initial " \
        "(got #{scrolled_w}, initial was #{initial_w})"

      # Scroll LEFT one step — cell should NOT snap to full width
      app.handle_mouse_wheel(
        CrymbleUI::Vec2.new(0.0, 1.0),
        CrymbleUI::Vec2.new(400.0, 200.0),
        shift: true
      )
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      matrix = app.find("task_board").as(CrymbleUI::VirtualMatrix)
      after_one_left_w = matrix.active_cells[{0, 1}]?.try(&.bounds.width) || 0.0

      # One scroll step (30px) should NOT restore full width.
      # With the bug, the cell snaps from minimal to full 409px.
      after_one_left_w.should be < initial_w * 0.5,
        "After one scroll-left step from max-right, 1-Ready should still be small " \
        "(got #{after_one_left_w}, initial was #{initial_w}). " \
        "Ghost full-width header appeared before any column re-entered viewport."
    end
  end
end
