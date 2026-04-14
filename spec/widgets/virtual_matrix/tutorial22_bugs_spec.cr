require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/checkbox"
require "../../../src/testing/test_renderer"

# Test adapter mimicking Tutorial 22: 2 sticky rows + 2 sticky cols,
# with Button/Checkbox at specific cells.
class Tutorial22TestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  getter button_clicked : Bool = false
  getter checkbox_clicked : Bool = false

  def initialize(@data_rows : Int32 = 20, @data_cols : Int32 = 20)
    @total_rows = 2 + @data_rows
    @total_cols = 2 + @data_cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows = (2...@total_rows).to_a + [1, 0]
    cols = (2...@total_cols).to_a + [1, 0]
    {rows, cols}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    row_heights = Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 }
    col_widths = Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }
    {row_heights, col_widths}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if row < 2 && col < 2
      CrymbleUI::Text.new("")
    elsif col < 2
      CrymbleUI::Text.new("r#{col + 1}_#{row}")
    elsif row < 2
      CrymbleUI::Text.new("c#{row + 1}_#{col}")
    elsif row == 4 && col == 4
      CrymbleUI::Checkbox.new("Check") { @checkbox_clicked = true }
    elsif row == 5 && col == 4
      CrymbleUI::Button.new("Click") { @button_clicked = true }
    else
      CrymbleUI::TextInput.new(value: "(#{row},#{col})", mode: CrymbleUI::TextInputMode::QuickEntry)
    end
  end
end

# Adapter with merged headers (cell_get_bounding_box) matching tutorial-22 pattern.
# - Corner cells (row < 2 && col < 2): span cols 0..1
# - Row headers (col < 2): span 4 (col 0) or 2 (col 1) data rows
# - Col headers (row < 2): span 4 (row 0) or 2 (row 1) data cols
# - Data cells: no merge
class MergedHeaderTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@data_rows : Int32 = 1000, @data_cols : Int32 = 1000)
    @total_rows = 2 + @data_rows
    @total_cols = 2 + @data_cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...@total_rows).to_a + [1, 0], (2...@total_cols).to_a + [1, 0]}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    {Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 },
     Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    if row < 2 && col < 2
      { {row, 0}, {row, 1} }
    elsif col < 2 && row >= 2
      span = col == 0 ? 4 : 2
      start = 2 + ((row - 2) // span) * span
      { {start, col}, {start + span - 1, col} }
    elsif row < 2 && col >= 2
      span = row == 0 ? 4 : 2
      start = 2 + ((col - 2) // span) * span
      { {row, start}, {row, start + span - 1} }
    else
      { {row, col}, {row, col} }
    end
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if row < 2 && col < 2
      CrymbleUI::Text.new("")
    elsif col < 2
      CrymbleUI::Text.new("r#{col + 1}_#{row}")
    elsif row < 2
      CrymbleUI::Text.new("c#{row + 1}_#{col}")
    else
      CrymbleUI::Text.new("(#{row},#{col})")
    end
  end
end

# DSL-style app: creates NEW VirtualMatrix + MergedHeaderTestAdapter on each build().
# Switching grid_size triggers rebuild → reconciliation with merged headers + scroll offset.
class AdapterSwitchDSLApp < CrymbleUI::App
  property grid_size : Int32 = 1000

  def build : CrymbleUI::Widget
    adapter = MergedHeaderTestAdapter.new(data_rows: grid_size, data_cols: grid_size)
    CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "t22_switch")
  end
end

# Setup with VirtualMatrix as root (no parent offset) — for Enter/Space tests.
private def setup_tutorial22_matrix(viewport_width = 600.0, viewport_height = 400.0)
  adapter = Tutorial22TestAdapter.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "t22_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  renderer = CrymbleUI::Testing::TestRenderer.new(viewport_width.to_i, viewport_height.to_i)
  renderer.settle_rendering(app)

  {matrix, app, renderer, adapter}
end

# Setup with VirtualMatrix inside VStack(padding) — creates non-zero absolute_bounds
# offset, exposing the coordinate space mismatch bug in blit_plan.
private def setup_tutorial22_with_offset(padding = 10.0, viewport_width = 600, viewport_height = 400)
  adapter = Tutorial22TestAdapter.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "t22_offset")

  vstack = CrymbleUI::VStack.new(padding: padding, id: "wrapper")
  vstack.add_child(matrix)

  app = TestApp.new
  app.root_widget = vstack
  app.build_tree

  renderer = CrymbleUI::Testing::TestRenderer.new(viewport_width, viewport_height)
  renderer.settle_rendering(app)

  {matrix, app, renderer, adapter}
end

describe CrymbleUI::VirtualMatrix, tags: "slow" do
  describe "Bug 1: Sticky header blit_plan positions with parent offset" do
    it "sticky row cells are blitted at correct positions after vertical scroll" do
      matrix, app, renderer, _ = setup_tutorial22_with_offset(padding: 10.0)

      # Precondition: VirtualMatrix has non-zero absolute offset from VStack padding
      matrix.absolute_bounds.x.should be > 0,
        "Test setup error: VirtualMatrix should have non-zero absolute X offset"
      matrix.absolute_bounds.y.should be > 0,
        "Test setup error: VirtualMatrix should have non-zero absolute Y offset"

      # Scroll down to trigger blit_plan path on next render.
      # Vertical scroll should NOT change sticky row positions (they're fixed in Y).
      abs = matrix.absolute_bounds
      center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)

      sv = matrix.content_scroll_view.not_nil!
      row_layer = sv.sticky_row_layer.not_nil!
      row_backend = row_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
      vm_abs = matrix.absolute_bounds

      # Verify cell content appears at expected layer-local positions.
      # For each sticky row cell, sample a pixel from its widget_backend interior
      # and check it matches the corresponding layer backend pixel.
      verified = 0
      matrix.active_cells.each do |key, widget|
        row, col = key
        next unless row < 2 && col >= 2  # Sticky row cells (non-corner)

        wb = widget.widget_backend
        next unless wb
        wb_backend = wb.as(CrymbleUI::Testing::TestRenderBackend)
        next if wb_backend.width < 6 || wb_backend.height < 6

        # Sample interior pixel from widget_backend (5px in to avoid borders)
        cell_pixel = wb_backend.get_pixel(5, 5)
        next unless cell_pixel

        # Expected layer-local position: same formula as blit_plan fix
        dest_x = (vm_abs.x + widget.bounds.x - row_layer.bounds.x).to_i
        dest_y = (vm_abs.y + widget.bounds.y - row_layer.bounds.y).to_i

        # Verify the cell pixel landed at the right spot in the layer
        layer_pixel = row_backend.get_pixel(dest_x + 5, dest_y + 5)
        layer_pixel.should_not be_nil,
          "Cell #{key}: expected pixel at layer (#{dest_x + 5}, #{dest_y + 5}) is nil (off-screen?). " \
          "vm_abs=(#{vm_abs.x},#{vm_abs.y}), cell bounds=(#{widget.bounds.x},#{widget.bounds.y}), " \
          "layer bounds=(#{row_layer.bounds.x},#{row_layer.bounds.y})"
        layer_pixel.should eq(cell_pixel),
          "Cell #{key}: pixel mismatch at layer (#{dest_x + 5}, #{dest_y + 5}). " \
          "Expected #{cell_pixel} (from widget_backend), got #{layer_pixel}. " \
          "blit_plan dest coords may not account for VirtualMatrix's absolute offset."
        verified += 1
      end

      verified.should be > 0,
        "No sticky row cells were verified — test setup may be broken"
    end

    it "sticky col cells are blitted at correct positions after horizontal scroll" do
      matrix, app, renderer, _ = setup_tutorial22_with_offset(padding: 10.0)

      matrix.absolute_bounds.x.should be > 0
      matrix.absolute_bounds.y.should be > 0

      # Scroll right to trigger blit_plan path
      abs = matrix.absolute_bounds
      center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
      renderer.render_frame(app)

      sv = matrix.content_scroll_view.not_nil!
      col_layer = sv.sticky_col_layer.not_nil!
      col_backend = col_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
      vm_abs = matrix.absolute_bounds

      verified = 0
      matrix.active_cells.each do |key, widget|
        row, col = key
        next unless col < 2 && row >= 2  # Sticky col cells (non-corner)

        wb = widget.widget_backend
        next unless wb
        wb_backend = wb.as(CrymbleUI::Testing::TestRenderBackend)
        next if wb_backend.width < 6 || wb_backend.height < 6

        cell_pixel = wb_backend.get_pixel(5, 5)
        next unless cell_pixel

        dest_x = (vm_abs.x + widget.bounds.x - col_layer.bounds.x).to_i
        dest_y = (vm_abs.y + widget.bounds.y - col_layer.bounds.y).to_i

        layer_pixel = col_backend.get_pixel(dest_x + 5, dest_y + 5)
        layer_pixel.should_not be_nil,
          "Cell #{key}: expected pixel at layer (#{dest_x + 5}, #{dest_y + 5}) is nil (off-screen?). " \
          "vm_abs=(#{vm_abs.x},#{vm_abs.y}), cell bounds=(#{widget.bounds.x},#{widget.bounds.y}), " \
          "layer bounds=(#{col_layer.bounds.x},#{col_layer.bounds.y})"
        layer_pixel.should eq(cell_pixel),
          "Cell #{key}: pixel mismatch at layer (#{dest_x + 5}, #{dest_y + 5}). " \
          "Expected #{cell_pixel} (from widget_backend), got #{layer_pixel}. " \
          "blit_plan dest coords may not account for VirtualMatrix's absolute offset."
        verified += 1
      end

      verified.should be > 0,
        "No sticky col cells were verified — test setup may be broken"
    end
  end

  describe "Bug 2: Button/Checkbox activation via Enter key in VirtualMatrix" do
    it "Button trigger_click fires when Enter is pressed on focused Button cell" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Give focus to the matrix
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Navigate cursor to Button cell at (5, 4) using set_cursor_from_cell
      # (cursor_rc= is a reconcile_property plain setter, doesn't call update_proxy_focus)
      matrix.set_cursor_from_cell({5, 4})
      matrix.snap_to_cursor(for_edit: true)
      renderer.render_frame(app)

      # Verify the cell is a Button
      cell = matrix.active_cells[{5, 4}]?
      cell.should_not be_nil, "Button cell at (5,4) should exist in active_cells"
      cell.not_nil!.should be_a(CrymbleUI::Button)

      # Press Enter
      adapter.button_clicked.should be_false
      matrix.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)

      adapter.button_clicked.should be_true,
        "Button callback was not triggered by Enter key. " \
        "VirtualMatrix should call trigger_click as fallback when proxy doesn't handle Enter."
    end

    it "Checkbox callback fires when Enter is pressed on focused Checkbox cell" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Give focus to the matrix
      CrymbleUI::Widget.focus_manager.focus(matrix)

      # Navigate cursor to Checkbox cell at (4, 4)
      matrix.set_cursor_from_cell({4, 4})
      matrix.snap_to_cursor(for_edit: true)
      renderer.render_frame(app)

      # Verify the cell is a Checkbox
      cell = matrix.active_cells[{4, 4}]?
      cell.should_not be_nil, "Checkbox cell at (4,4) should exist in active_cells"
      cell.not_nil!.should be_a(CrymbleUI::Checkbox)

      # Press Enter
      adapter.checkbox_clicked.should be_false
      matrix.on_key_down(SF::Keyboard::Key::Enter, control: false, shift: false)

      adapter.checkbox_clicked.should be_true,
        "Checkbox callback was not triggered by Enter key. " \
        "VirtualMatrix should call trigger_click as fallback when proxy doesn't handle Enter."
    end

    it "Space also triggers click on Button cell" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      CrymbleUI::Widget.focus_manager.focus(matrix)
      matrix.set_cursor_from_cell({5, 4})
      matrix.snap_to_cursor(for_edit: true)
      renderer.render_frame(app)

      adapter.button_clicked.should be_false
      matrix.on_key_down(SF::Keyboard::Key::Space, control: false, shift: false)

      adapter.button_clicked.should be_true,
        "Button callback was not triggered by Space key. " \
        "VirtualMatrix should call trigger_click for Space as well as Enter."
    end
  end

  describe "Bug A: Rulers visible after scroll (blit_plan must not clear rulers)" do
    it "column ruler pixels remain in sticky_row_layer after vertical scroll" do
      matrix, app, renderer, _ = setup_tutorial22_with_offset(padding: 10.0)

      # The column ruler widget lives on the sticky_row_layer.
      # Its fill_rect uses RULER_BG_COLOR = Color(220, 220, 225, 255).
      sv = matrix.content_scroll_view.not_nil!
      row_layer = sv.sticky_row_layer.not_nil!
      row_backend = row_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

      ruler_h = matrix.ruler_row_height_pixels.to_i
      ruler_h.should be > 0, "Test setup: rulers should be enabled (show_rulers=true)"

      # Sample a pixel in the ruler area before scroll — should be ruler background
      pre_pixel = row_backend.get_pixel(5, ruler_h // 2)
      pre_pixel.should_not be_nil, "Pre-scroll: ruler area should have rendered content"

      # Scroll down to trigger blit_plan fast path on next render
      abs = matrix.absolute_bounds
      center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)

      # After scroll, blit_plan clears layer and only blits cells — ruler is lost.
      # The ruler area should still contain the ruler's rendered content.
      post_pixel = row_backend.get_pixel(5, ruler_h // 2)
      post_pixel.should eq(pre_pixel),
        "Ruler area pixel changed after scroll: #{pre_pixel} → #{post_pixel}. " \
        "Blit-plan fast path cleared ruler content (only blits cells, not ruler widgets)."
    end
  end

  describe "Bug B: Mouse click triggers Button callback via App event path" do
    it "clicking on a Button cell with mouse triggers its callback" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Ensure Button cell at (5, 4) is visible
      cell = matrix.active_cells[{5, 4}]?
      cell.should_not be_nil, "Button cell at (5,4) should exist in active_cells"
      cell.not_nil!.should be_a(CrymbleUI::Button)

      # Compute the screen coordinates of the Button cell center
      abs = matrix.absolute_bounds
      cell_bounds = cell.not_nil!.bounds
      click_point = CrymbleUI::Vec2.new(
        abs.x + cell_bounds.x + cell_bounds.width / 2,
        abs.y + cell_bounds.y + cell_bounds.height / 2
      )

      # Simulate full mouse click through App event path
      # App.handle_mouse_up calls hit_test → gets VirtualMatrix → trigger_click
      adapter.button_clicked.should be_false
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)

      adapter.button_clicked.should be_true,
        "Button callback not triggered by mouse click. " \
        "hit_test returns VirtualMatrix (self), so trigger_click goes to VM (no-op). " \
        "Need VirtualMatrix.trigger_click to forward to @proxy_focused_widget."
    end
  end

  describe "Bug C: Keyboard navigation after mouse click" do
    it "cursor moves right after mouse click on cell via App event path" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Click on cell (3, 2) through App event path — this is a TextInput in QuickEntry
      cell = matrix.active_cells[{3, 2}]?
      cell.should_not be_nil, "Cell (3,2) should exist in active_cells"

      abs = matrix.absolute_bounds
      cell_bounds = cell.not_nil!.bounds
      click_point = CrymbleUI::Vec2.new(
        abs.x + cell_bounds.x + cell_bounds.width / 2,
        abs.y + cell_bounds.y + cell_bounds.height / 2
      )
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)
      renderer.render_frame(app)

      # Precondition: cursor should be at (3, 2) and focus on matrix
      matrix.cursor_rc.should eq({3, 2}),
        "After mouse click on (3,2), cursor_rc should be {3, 2}"
      CrymbleUI::Widget.focus_manager.focused_widget.should eq(matrix),
        "After mouse click, VirtualMatrix should have focus"

      # Press Right arrow through focus manager (simulates SFML event path)
      handled = press_key(SF::Keyboard::Key::Right)

      matrix.cursor_rc.should eq({3, 3}),
        "After pressing Right, cursor should move from (3,2) to (3,3). " \
        "Got #{matrix.cursor_rc}. on_key_down may not be handling arrow keys after mouse click."
    end

    it "cursor moves down after mouse click on cell via App event path" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Click on cell (3, 2) through App event path
      cell = matrix.active_cells[{3, 2}]?
      cell.should_not be_nil

      abs = matrix.absolute_bounds
      cell_bounds = cell.not_nil!.bounds
      click_point = CrymbleUI::Vec2.new(
        abs.x + cell_bounds.x + cell_bounds.width / 2,
        abs.y + cell_bounds.y + cell_bounds.height / 2
      )
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)
      renderer.render_frame(app)

      matrix.cursor_rc.should eq({3, 2})

      # Press Down arrow
      press_key(SF::Keyboard::Key::Down)

      matrix.cursor_rc.should eq({4, 2}),
        "After pressing Down, cursor should move from (3,2) to (4,2). " \
        "Got #{matrix.cursor_rc}."
    end

    it "on_key_down returns true for arrow keys (prevents focus escape)" do
      matrix, app, renderer, adapter = setup_tutorial22_matrix

      # Click on cell (3, 2) through App event path
      cell = matrix.active_cells[{3, 2}]?
      cell.should_not be_nil

      abs = matrix.absolute_bounds
      cell_bounds = cell.not_nil!.bounds
      click_point = CrymbleUI::Vec2.new(
        abs.x + cell_bounds.x + cell_bounds.width / 2,
        abs.y + cell_bounds.y + cell_bounds.height / 2
      )
      app.handle_mouse_down(click_point)
      app.handle_mouse_up(click_point)
      renderer.render_frame(app)

      # on_key_down should return true for all arrow keys, preventing focus escape
      # to sibling widgets (like the "leaf_row_span -" button in tutorial-22)
      result_up = matrix.on_key_down(SF::Keyboard::Key::Up, control: false, shift: false)
      result_up.should be_true,
        "on_key_down returned false for Up after mouse click — " \
        "this would cause FocusManager.navigate(:up) to escape to a sibling widget"

      result_right = matrix.on_key_down(SF::Keyboard::Key::Right, control: false, shift: false)
      result_right.should be_true,
        "on_key_down returned false for Right after mouse click"

      result_down = matrix.on_key_down(SF::Keyboard::Key::Down, control: false, shift: false)
      result_down.should be_true,
        "on_key_down returned false for Down after mouse click"

      result_left = matrix.on_key_down(SF::Keyboard::Key::Left, control: false, shift: false)
      result_left.should be_true,
        "on_key_down returned false for Left after mouse click"
    end
  end

  describe "Bug: Sibling overlap after adapter switch with merged headers" do
    # Test adapter with cell_get_bounding_box (merged headers) matching tutorial-22 pattern.
    # Mutable grid_size so the DSL app can switch adapters.
    it "no sibling overlap when switching to larger adapter while scrolled right" do
      # DSL-style app: creates NEW VirtualMatrix + adapter on each build()
      app = AdapterSwitchDSLApp.new
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      renderer.settle_rendering(app)

      # Get the matrix and scroll far right
      matrix = app.find("t22_switch").as(CrymbleUI::VirtualMatrix)
      # Set scroll_offset to position near col ~999 (each data col = 5px * base_size)
      # With 1000 data cols + 2 sticky cols, content is wide. Scroll to ~80% of max.
      matrix.scroll_offset = CrymbleUI::Vec2.new(3000.0, 0.0)
      renderer.render_frame(app)

      pre_exceptions = renderer.exceptions_caught

      # Switch to 10000² grid (larger — so scroll offset is still valid)
      app.grid_size = 10000
      app.rebuild
      renderer.settle_rendering(app)

      renderer.exceptions_caught.should eq(pre_exceptions),
        "Sibling overlap after adapter switch! exceptions_caught increased from " \
        "#{pre_exceptions} to #{renderer.exceptions_caught}. " \
        "Last exception: #{renderer.last_exception_message}"

      # Also verify no zero-width cells among VISIBLE active cells
      # (cells parked off-screen at -1000 are expected to have zero size)
      new_matrix = app.find("t22_switch").as(CrymbleUI::VirtualMatrix)
      zero_width_cells = [] of Tuple(Int32, Int32)
      new_matrix.active_cells.each do |key, widget|
        next if widget.bounds.x < 0 || widget.bounds.y < 0  # off-screen ghost (OFFSCREEN_PARK)
        if widget.bounds.width <= 0.01 && widget.bounds.height > 0.01
          zero_width_cells << key
        end
      end
      zero_width_cells.should be_empty,
        "Found zero-width cells after adapter switch: #{zero_width_cells.first(5)}. " \
        "Merged header cells may not be sized correctly after adapter change."
    end

    it "no sibling overlap when switching to smaller adapter while scrolled right" do
      app = AdapterSwitchDSLApp.new
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      renderer.settle_rendering(app)

      matrix = app.find("t22_switch").as(CrymbleUI::VirtualMatrix)
      # Scroll far right — this offset will exceed max for the 100² grid
      matrix.scroll_offset = CrymbleUI::Vec2.new(3000.0, 0.0)
      renderer.render_frame(app)

      pre_exceptions = renderer.exceptions_caught

      # Switch to 100² grid (smaller — scroll must be clamped)
      app.grid_size = 100
      app.rebuild
      renderer.settle_rendering(app)

      renderer.exceptions_caught.should eq(pre_exceptions),
        "Sibling overlap after adapter switch to smaller grid! exceptions_caught increased from " \
        "#{pre_exceptions} to #{renderer.exceptions_caught}. " \
        "Last exception: #{renderer.last_exception_message}"
    end

    it "no exception loop on repeated render after adapter switch" do
      app = AdapterSwitchDSLApp.new
      app.build_tree

      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      renderer.settle_rendering(app)

      matrix = app.find("t22_switch").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset = CrymbleUI::Vec2.new(3000.0, 0.0)
      renderer.render_frame(app)

      # Switch adapter
      app.grid_size = 10000
      app.rebuild

      # Render several frames — if graceful degradation works, exceptions should not grow
      10.times { renderer.render_frame(app) }
      exceptions_after_10 = renderer.exceptions_caught

      # At most 1-2 exceptions are acceptable (initial recovery), but not unbounded growth
      exceptions_after_10.should be <= 2,
        "Exception loop detected! #{exceptions_after_10} exceptions after 10 frames. " \
        "handle_frame_exception recovery (reset_all_caches + mark_needs_layout) isn't working — " \
        "same overlap error recurs every frame. Last: #{renderer.last_exception_message}"
    end
  end

  describe "Bug (a)/(b): Sticky col cells at shifted-out rows" do
    it "no two sticky-col cells overlap vertically after scrolling down" do
      matrix, app, renderer, _ = setup_tutorial22_matrix(viewport_width: 600.0, viewport_height: 400.0)

      # Scroll down significantly to shift rows out of viewport
      abs = matrix.absolute_bounds
      center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
      5.times { matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), center) }
      renderer.render_frame(app)

      matrix.scroll_offset.y.should be > 50.0,
        "Test setup: should have scrolled down significantly"

      # Collect all sticky-col cells (col < 2, row >= 2) — these are row headers
      sticky_col_cells = [] of {Tuple(Int32, Int32), CrymbleUI::Rect}
      matrix.active_cells.each do |key, widget|
        row, col = key
        next unless col < 2 && row >= 2  # Sticky col cells (non-corner)
        sticky_col_cells << {key, widget.bounds}
      end

      sticky_col_cells.size.should be > 2,
        "Test setup: should have multiple sticky-col cells"

      # Check no overlap: for each pair of cells in the same column,
      # their Y ranges should not overlap
      sticky_col_cells.each_with_index do |(key1, b1), i|
        sticky_col_cells.each_with_index do |(key2, b2), j|
          next if j <= i
          next unless key1[1] == key2[1]  # Same column
          next if b1.height <= 0.01 || b2.height <= 0.01  # Skip collapsed cells

          # Check Y overlap: one cell's top should be >= other cell's bottom (or vice versa)
          overlap = !(b1.y + b1.height <= b2.y + 0.5 || b2.y + b2.height <= b1.y + 0.5)
          overlap.should be_false,
            "Sticky-col cells #{key1} and #{key2} overlap! " \
            "Cell #{key1}: y=#{b1.y.round(1)}, h=#{b1.height.round(1)} (bottom=#{(b1.y + b1.height).round(1)}). " \
            "Cell #{key2}: y=#{b2.y.round(1)}, h=#{b2.height.round(1)} (bottom=#{(b2.y + b2.height).round(1)}). " \
            "Shifted-out rows may be using content-space Y without scroll subtraction."
        end
      end
    end

    it "sticky-col cells for shifted-out rows are positioned off-screen (not at content-space Y)" do
      matrix, app, renderer, _ = setup_tutorial22_matrix(viewport_width: 600.0, viewport_height: 400.0)

      # Scroll down to shift some rows out
      abs = matrix.absolute_bounds
      center = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
      5.times { matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), center) }
      renderer.render_frame(app)

      scroll_y = matrix.scroll_offset.y
      viewport_h = matrix.bounds.height
      sticky_row_h = matrix.sticky_row_height_pixels + matrix.ruler_row_height_pixels

      # For each sticky-col cell: its Y position should place it within the viewport
      # (between sticky_row_h and viewport_h) OR off-screen (negative Y or Y > viewport_h).
      # The bug puts shifted-out rows at content-space Y (large positive values),
      # which lands them ON-SCREEN overlapping visible cells.
      matrix.active_cells.each do |key, widget|
        row, col = key
        next unless col < 2 && row >= 2  # Sticky col cells
        next if widget.bounds.height <= 0.01  # Skip collapsed

        cell_y = widget.bounds.y
        cell_bottom = cell_y + widget.bounds.height

        # Cell should either be in the visible region or completely off-screen
        in_visible = cell_y >= (sticky_row_h - 1) && cell_y < viewport_h
        off_screen_above = cell_bottom <= sticky_row_h
        off_screen_below = cell_y >= viewport_h

        valid = in_visible || off_screen_above || off_screen_below

        valid.should be_true,
          "Sticky-col cell #{key} at y=#{cell_y.round(1)} (height=#{widget.bounds.height.round(1)}) " \
          "is neither in visible region [#{sticky_row_h.round(1)}, #{viewport_h.round(1)}) " \
          "nor off-screen. scroll_y=#{scroll_y.round(1)}. " \
          "Shifted-out row may be using content-space Y without scroll subtraction."
      end
    end
  end
end
