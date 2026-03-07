require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/scroll_view"
require "../../../src/testing/test_renderer"

# TDD: These tests define the CORRECT behavior after refactoring VirtualMatrix to use ScrollView.
# Initially they will FAIL because VirtualMatrix doesn't have a ScrollView yet.

describe "VirtualMatrix ScrollView Refactor" do
  describe "architecture" do
    it "contains a ScrollView for content area" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "arch_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # VirtualMatrix should expose content_scroll_view getter (not scroll_view - that's a DSL method)
      matrix.content_scroll_view.should_not be_nil
    end

    it "does NOT have custom scrollbar_layer" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50)
      # After refactor, scrollbar_layer should be removed
      matrix.responds_to?(:scrollbar_layer).should be_false
    end
  end

  describe "focus and keyboard" do
    it "acquires focus on mouse down" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "focus_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # Simulate click on matrix
      click_point = CrymbleUI::Vec2.new(200.0, 150.0)
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)

      # VirtualMatrix should now be focused
      CrymbleUI::Widget.focus_manager.not_nil!.focused_widget.should eq matrix
    end

    it "moves cursor with arrow keys after focus" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "arrow_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # Click to focus - clicking also moves cursor to clicked cell
      click_point = CrymbleUI::Vec2.new(200.0, 150.0)
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)

      # Record cursor position after click (click moves cursor to clicked cell)
      start_row, start_col = matrix.cursor_rc

      # Press Right arrow - cursor should move right by 1
      CrymbleUI::Widget.focus_manager.not_nil!.handle_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      matrix.cursor_rc.should eq({start_row, start_col + 1})

      # Press Down arrow - cursor should move down by 1
      CrymbleUI::Widget.focus_manager.not_nil!.handle_key_down(SF::Keyboard::Key::Down, control: false, shift: false)
      matrix.cursor_rc.should eq({start_row + 1, start_col + 1})
    end

  end

  describe "scrollbars via ScrollView" do
    it "shows vertical scrollbar when content exceeds height" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 10, id: "vscroll_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # ScrollView should show vertical scrollbar for 100 rows in 300px height
      # Verify by checking content_size > viewport_size (the condition for scrollbar visibility)
      scroll_view = matrix.content_scroll_view.not_nil!
      scroll_view.content_size.height.should be > scroll_view.viewport_size.height
    end

    it "shows horizontal scrollbar when content exceeds width" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 50, id: "hscroll_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # ScrollView should show horizontal scrollbar for 50 columns in 400px width
      # Verify by checking content_size > viewport_size (the condition for scrollbar visibility)
      scroll_view = matrix.content_scroll_view.not_nil!
      scroll_view.content_size.width.should be > scroll_view.viewport_size.width
    end
  end

  describe "performance" do
    it "scrolls without excessive layout calls" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 50, id: "perf_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)
      renderer.reset_counters

      # Scroll 10 times
      scroll_point = CrymbleUI::Vec2.new(200.0, 150.0)
      10.times do
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), scroll_point)
      end
      renderer.render_frame(app)

      # With ScrollView's viewport_cache, should not trigger 10 full layouts
      renderer.layout_count.should be <= 5
    end
  end

  # ============================================
  # TEST MODE: Architecture Refactor Tests
  # These tests define the CORRECT behavior after removing fixed header layers
  # and using adapter-based scroll_order instead of sticky_rows/sticky_cols.
  # ============================================

  describe "architecture refactor: no fixed header layers" do
    it "does NOT have sticky_col_header_layer method" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "no_col_header_layer")
      # After refactor, sticky_col_header_layer method should not exist
      matrix.responds_to?(:sticky_col_header_layer).should be_false
    end

    it "does NOT have sticky_row_header_layer method" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "no_row_header_layer")
      # After refactor, sticky_row_header_layer method should not exist
      matrix.responds_to?(:sticky_row_header_layer).should be_false
    end

    it "does NOT have sticky_corner_layer method" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "no_corner_layer")
      # After refactor, sticky_corner_layer method should not exist
      matrix.responds_to?(:sticky_corner_layer).should be_false
    end

    it "does NOT have on_header_row callback" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10)
      # After refactor, on_header_row should not exist
      matrix.responds_to?(:on_header_row).should be_false
    end

    it "does NOT have on_header_col callback" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10)
      # After refactor, on_header_col should not exist
      matrix.responds_to?(:on_header_col).should be_false
    end

    it "does NOT have on_corner callback" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10)
      # After refactor, on_corner should not exist
      matrix.responds_to?(:on_corner).should be_false
    end

    it "does NOT have sticky_rows property" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10)
      # After refactor, sticky_rows property should not exist
      matrix.responds_to?(:sticky_rows).should be_false
    end

    it "does NOT have sticky_cols property" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10)
      # After refactor, sticky_cols property should not exist
      matrix.responds_to?(:sticky_cols).should be_false
    end
  end

  describe "architecture refactor: adapter-based scroll_order" do
    it "uses adapter get_scrollorder for row eviction order" do
      # Create adapter with custom scroll order (row 0 scrolls out LAST)
      adapter = ScrollOrderTestAdapter.new(10, 10)
      adapter.custom_row_order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]  # Row 0 last (sticky)

      matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "row_scroll_order")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # Scroll down far enough that early rows scroll out
      # Row 0 should remain visible (it's last in scroll_order)
      large_scroll = CrymbleUI::Vec2.new(0.0, -50.0)  # Scroll down a lot
      5.times { matrix.on_mouse_wheel(large_scroll, CrymbleUI::Vec2.new(200.0, 150.0)) }
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Row 0 should still be visible (sticky via scroll_order)
      matrix.visible_cell_indices[:rows].should contain(0)
    end

    it "uses adapter get_scrollorder for column eviction order" do
      # Create adapter with custom scroll order (col 0 scrolls out LAST)
      adapter = ScrollOrderTestAdapter.new(10, 10)
      adapter.custom_col_order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]  # Col 0 last (sticky)

      matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "col_scroll_order")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # Scroll right far enough that early cols scroll out
      # Col 0 should remain visible (it's last in scroll_order)
      large_scroll = CrymbleUI::Vec2.new(0.0, -50.0)  # Horizontal scroll with shift
      5.times { matrix.on_mouse_wheel(large_scroll, CrymbleUI::Vec2.new(200.0, 150.0), shift: true) }
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Col 0 should still be visible (sticky via scroll_order)
      matrix.visible_cell_indices[:cols].should contain(0)
    end
  end

  describe "scrollbar visibility fix" do
    it "registers scrollbars in scrollbar_layer without content_widget" do
      # ScrollView with no content_widget set (like VirtualMatrix uses it)
      scroll_view = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, id: "no_content_sv")
      scroll_view.viewport_size = CrymbleUI::Size.new(200.0, 200.0)
      scroll_view.content_size = CrymbleUI::Size.new(1000.0, 1000.0)  # Larger than viewport

      app = TestApp.new
      app.root_widget = scroll_view
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 200.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Scrollbar layer should have this widget registered for scrollbar rendering
      # CURRENTLY FAILS: registration is inside `if content = @content_widget` block
      scroll_view.scrollbar_layer.not_nil!.widgets.should contain(scroll_view)
    end

    it "VirtualMatrix scrollbars are visible at right/bottom edges" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scrollbar_visible")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # The ScrollView inside VirtualMatrix should have scrollbar layer with widget registered
      scroll_view = matrix.content_scroll_view.not_nil!
      scroll_view.scrollbar_layer.not_nil!.widgets.should contain(scroll_view)
    end
  end

  describe "pixel-accurate scrolling" do
    it "maintains fractional scroll offset precision" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "fractional_scroll")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Set a fractional scroll offset
      matrix.scroll_offset = CrymbleUI::Vec2.new(12.7, 45.3)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # After layout, scroll offset should maintain fractional precision
      matrix.scroll_offset.x.should be_close(12.7, 0.01)
      matrix.scroll_offset.y.should be_close(45.3, 0.01)
    end

    it "cache key does not round scroll offset" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "cache_key_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

      # First layout at offset 0.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      initial_cells = matrix.active_cell_count

      # Small scroll (0.05 pixels) - should NOT trigger cell recreation
      # (visible indices unchanged, just viewport panning)
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.05, 0.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Cells should be the same (no recreation for sub-pixel scroll)
      matrix.active_cell_count.should eq initial_cells
    end
  end
end

# Test adapter with customizable scroll order
class ScrollOrderTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @data : Array(Array(String))
  property custom_row_order : Array(Int32)?
  property custom_col_order : Array(Int32)?

  def initialize(@rows : Int32, @cols : Int32)
    @data = Array.new(@rows) { |r| Array.new(@cols) { |c| "#{r},#{c}" } }
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {
      @custom_row_order || (0...@rows).to_a,
      @custom_col_order || (0...@cols).to_a,
    }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end
