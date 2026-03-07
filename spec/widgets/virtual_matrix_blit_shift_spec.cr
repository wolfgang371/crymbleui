require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"
require "../../src/testing/configurable_matrix_adapter"

# DSL-style app for blit-shift correctness testing.
# Uses default adapter: cell text = "row,col".
# 100×20 grid in 1400×900 window gives plenty of scrollable content.
class BlitShiftTestApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 1400, 900) do
      widget(CrymbleUI::VirtualMatrix.new(rows: 100, cols: 20, id: "blit_grid"))
    end
  end
end

# Local subclass: use Text instead of TextInput for headless spec testing
class BlitShiftDemoAdapter < ConfigurableMatrixAdapter
  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new(text: @data[{row, col}])
  end
end

# DSL-style demo app for blit-shift tests with compound cells and sticky headers
class BlitShiftDemoApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    adapter = BlitShiftDemoAdapter.new(
      nrhl: 2, nchl: 2, rhs: 3, chs: 3, lrs: 10, lcs: 10
    )

    window("Test", 1400, 900) do
      expanded do
        widget(CrymbleUI::VirtualMatrix.new(
          adapter: adapter,
          id: "blit_grid",
          cursor_highlight_delta: -30,
          content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
        ))
      end
    end
  end
end

# Blit-shift scroll correctness tests.
#
# The blit-shift optimization (layer_renderer.cr:1321-1368) replaces full-recenter
# (clear + re-render all) with a smarter approach: copy overlapping buffer content
# to a temp, clear, restore at new position, then render only edge cells.
#
# These tests verify the blit-shift path doesn't corrupt cell data or cause blank rows.

describe "VirtualMatrix blit-shift scroll correctness" do
  it "preserves correct cell data after scrolling past cache_extent", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    initial_origin = content_layer.buffer_origin

    # Scroll down past cache_extent (100px) to trigger blit-shift.
    # SCROLL_SPEED = 30px per event, 7 events = 210px → well past boundary.
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!

    # Verify blit-shift was triggered: buffer_origin should have changed
    content_layer.buffer_origin.should_not eq(initial_origin),
      "Buffer origin didn't change after scrolling 210px — blit-shift was NOT triggered. " \
      "Initial: #{initial_origin}, Current: #{content_layer.buffer_origin}, " \
      "scroll_offset: #{matrix.scroll_offset}"

    # Verify: every active cell's text matches its grid coordinates.
    # DefaultAdapter produces "row,col" text for cell at (row, col).
    # If blit-shift corrupts the display, cells may show wrong data.
    wrong_cells = [] of {Tuple(Int32, Int32), String, String}
    matrix.active_cells.each do |key, widget|
      row, col = key
      expected_text = "#{row},#{col}"
      if text_widget = widget.as?(CrymbleUI::Text)
        unless text_widget.text == expected_text
          wrong_cells << {key, text_widget.text, expected_text}
        end
      end
    end

    wrong_cells.should be_empty,
      "Cell data corrupted after blit-shift scroll (#{wrong_cells.size} bad cells): " \
      "#{wrong_cells.first(5).map { |w| "(#{w[0]}): got #{w[1].inspect}, expected #{w[2].inspect}" }.join(", ")}"
  end

  it "has no blank rows after scroll down + scroll back to top", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Record initial active rows at col 0
    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    initial_rows = matrix.active_cells.keys
      .select { |k| k[1] == 0 }
      .map(&.[](0))
      .sort

    # Scroll down past cache_extent (7 events = 210px)
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    # Scroll back to top (7 events = 210px up)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)

    # Should be back near the top
    matrix.scroll_offset.y.should be <= 10.0,
      "Expected to be near top after round-trip, but scroll_offset.y = #{matrix.scroll_offset.y}"

    # Check: no gaps in active row indices at col 0
    active_rows = matrix.active_cells.keys
      .select { |k| k[1] == 0 }
      .map(&.[](0))
      .sort

    active_rows.size.should be > 5,
      "Expected many active rows at col 0 after round-trip, got #{active_rows.size}"

    # Check for gaps in the active row sequence
    gaps = [] of Tuple(Int32, Int32)
    (0...active_rows.size - 1).each do |i|
      diff = active_rows[i + 1] - active_rows[i]
      if diff > 1
        gaps << {active_rows[i], active_rows[i + 1]}
      end
    end

    gaps.should be_empty,
      "Gaps found in row sequence after blit-shift round-trip: " \
      "#{gaps.map { |g| "rows #{g[0] + 1}..#{g[1] - 1} missing" }.join(", ")}. " \
      "Active rows at col 0: #{active_rows}"
  end

  it "cell positions match content-space coordinates after blit-shift", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Scroll past cache_extent to trigger blit-shift
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)

    # Geometry constants
    frame_height = 20.0
    grid_spacing = 3.0
    row_height = grid_spacing + 1.0 * frame_height  # 23px
    col_width = grid_spacing + 5.0 * frame_height   # 103px
    ruler_row_h = 1.0 * frame_height  # 20px
    ruler_col_w = 2.0 * frame_height  # 40px

    # Check that each active cell's y-position matches expected content-space position.
    # Content-space y for row R = ruler_row_h + R * row_height
    mispositioned = [] of {Tuple(Int32, Int32), Float64, Float64}
    matrix.active_cells.each do |key, widget|
      row, col = key
      expected_y = ruler_row_h + row * row_height
      expected_x = ruler_col_w + col * col_width
      actual_y = widget.bounds.y
      actual_x = widget.bounds.x

      # Allow 1px tolerance for rounding
      if (actual_y - expected_y).abs > 1.0
        mispositioned << {key, actual_y, expected_y}
      end
      if (actual_x - expected_x).abs > 1.0
        mispositioned << {key, actual_x, expected_x}
      end
    end

    mispositioned.should be_empty,
      "Cell positions wrong after blit-shift (#{mispositioned.size} bad): " \
      "#{mispositioned.first(5).map { |m| "(#{m[0]}): actual=#{m[1]}, expected=#{m[2]}" }.join(", ")}"
  end

  it "composited pixels are non-blank at visible cell positions after blit-shift", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Scroll past cache_extent
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    layer = matrix.content_layer.not_nil!

    # Find 3 cells near the viewport center that should definitely be visible
    scroll_y = matrix.scroll_offset.y
    viewport_h = layer.bounds.height
    mid_content_y = scroll_y + viewport_h / 2.0

    # Calculate which row is at the viewport center
    row_height = 23.0  # GRID_SPACING(3) + DEFAULT_ROW_HEIGHT(1.0) * frame_height(20)
    ruler_row_h = 20.0
    mid_row = ((mid_content_y - ruler_row_h) / row_height).to_i32
    mid_row = mid_row.clamp(0, 99)

    # Check that these rows have active cells
    test_col = 2  # Pick a middle column
    [{mid_row, test_col}, {mid_row + 1, test_col}, {mid_row - 1, test_col}].each do |key|
      next if key[0] < 0 || key[0] >= 100
      matrix.active_cells.has_key?(key).should be_true,
        "Cell (#{key[0]}, #{key[1]}) should exist near viewport center " \
        "(scroll_y=#{scroll_y.round(1)}, mid_content_y=#{mid_content_y.round(1)})"
    end

    # Check that the composited window buffer has non-white pixels at cell positions.
    # After compositing, cells render colored "barcode" text on the window buffer.
    # Window background is white (255,255,255).
    window_buf = renderer.backend
    white = CrymbleUI::Color.new(255, 255, 255, 255)

    # Screen position of mid_row cell = content_layer position +
    #   (cell_content_y - scroll_offset) in viewport
    layer_x = layer.bounds.x.to_i
    layer_y = layer.bounds.y.to_i
    cell_content_y = ruler_row_h + mid_row * row_height
    cell_screen_y = layer_y + (cell_content_y - scroll_y).to_i + 5  # +5 offset into cell
    cell_content_x = 40.0 + test_col * 103.0  # ruler_col_w + col * col_width
    cell_screen_x = layer_x + (cell_content_x - matrix.scroll_offset.x).to_i + 5

    # Sample a few pixels — at least some should be non-white (cell content rendered)
    non_white_count = 0
    5.times do |dx|
      5.times do |dy|
        px = cell_screen_x + dx
        py = cell_screen_y + dy
        next if px < 0 || px >= window_buf.width || py < 0 || py >= window_buf.height
        pixel = window_buf.get_pixel(px, py)
        non_white_count += 1 if pixel && pixel != white
      end
    end

    non_white_count.should be > 0,
      "No rendered pixels found at cell (#{mid_row}, #{test_col}) screen position " \
      "(#{cell_screen_x}, #{cell_screen_y}) after blit-shift. " \
      "All 25 sampled pixels were white — cell was not composited."
  end
end

# Demo-config tests: compound cells + sticky headers with blit-shift
describe "VirtualMatrix blit-shift with demo config" do
  it "data cells have correct values after scrolling past cache_extent", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    initial_origin = content_layer.buffer_origin

    # Scroll down 7 events (210px) — past cache_extent to trigger blit-shift
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!

    # Verify blit-shift was triggered
    content_layer.buffer_origin.should_not eq(initial_origin),
      "Buffer origin didn't change — blit-shift was NOT triggered"

    # nchl=2 means row header levels = 2, data cells start at grid row 2
    # nrhl=2 means col header levels = 2, data cells start at grid col 2
    # Data cell at grid(R, C) where R>=2 and C>=2 has text "(R-2, C-2)"
    nchl = 2
    nrhl = 2

    wrong_data_cells = [] of {Tuple(Int32, Int32), String, String}
    matrix.active_cells.each do |key, widget|
      row, col = key
      # Only check data cells (not headers)
      next if row < nchl || col < nrhl

      expected_data_row = row - nchl
      expected_data_col = col - nrhl
      expected_text = "(#{expected_data_row},#{expected_data_col})"

      if text_widget = widget.as?(CrymbleUI::Text)
        unless text_widget.text == expected_text
          wrong_data_cells << {key, text_widget.text, expected_text}
        end
      end
    end

    wrong_data_cells.should be_empty,
      "Data cell text corrupted after blit-shift scroll (#{wrong_data_cells.size} bad): " \
      "#{wrong_data_cells.first(5).map { |w| "grid(#{w[0]}): got #{w[1].inspect}, expected #{w[2].inspect}" }.join(", ")}. " \
      "scroll_offset=#{matrix.scroll_offset}"
  end

  it "no gaps in data rows after scroll round-trip", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Scroll down past cache_extent
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    # Scroll back to top
    7.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)

    # Should be back near top
    matrix.scroll_offset.y.should be <= 10.0,
      "Expected near top, got scroll_offset.y = #{matrix.scroll_offset.y}"

    # Check for gaps in data cell rows at first data column (col=2)
    data_col = 2
    nchl = 2
    active_data_rows = matrix.active_cells.keys
      .select { |k| k[1] == data_col && k[0] >= nchl }
      .map(&.[](0))
      .sort

    active_data_rows.size.should be > 5,
      "Expected many data rows at col #{data_col} after round-trip, got #{active_data_rows.size}"

    # Consecutive data rows should differ by exactly 1
    gaps = [] of Tuple(Int32, Int32)
    (0...active_data_rows.size - 1).each do |i|
      diff = active_data_rows[i + 1] - active_data_rows[i]
      if diff > 1
        gaps << {active_data_rows[i], active_data_rows[i + 1]}
      end
    end

    gaps.should be_empty,
      "Gaps in data rows after blit-shift round-trip: " \
      "#{gaps.map { |g| "rows #{g[0] + 1}..#{g[1] - 1} missing" }.join(", ")}. " \
      "Active data rows at col #{data_col}: #{active_data_rows}"
  end

  it "blit-shift renders fewer cells than full recenter (performance)", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = BlitShiftDemoApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Scroll down to a stable position first (well past initial layout)
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    15.times do
      matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    # Now do a single scroll step that triggers blit-shift
    # Record widgets rendered during this step
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.reset_counters

    matrix = app.find("blit_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
    renderer.render_frame(app)

    blit_shift_widgets = CrymbleUI::LayerRenderer.frame_widget_count

    # Blit-shift should render only edge cells (new cells at the scroll boundary),
    # not ALL visible cells. At 1400×900 viewport with 23px rows:
    # ~38 visible rows × ~13 visible cols ≈ 494 cells for full recenter.
    # Blit-shift should render much fewer (only the 1-2 new edge rows × cols).
    # If this exceeds 200, blit-shift optimization is broken or not triggering.
    blit_shift_widgets.should be <= 200,
      "Blit-shift frame rendered #{blit_shift_widgets} widgets — " \
      "expected <=200 (edge cells only, not full viewport of ~494 cells)"
  end
end

# === Color-coded row adapter for pixel-level blit-shift verification ===

# A cell widget that fills its entire bounds with a solid color.
# Unlike Text widgets (which don't render in TestRenderBackend),
# this produces actual pixels we can verify with get_pixel.
class ColorFillCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  getter fill_color : CrymbleUI::Color

  def initialize(@fill_color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    size = measure(constraints)
    @bounds = CrymbleUI::Rect.new(position, size)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill_color)
    end
  end
end

# Adapter that assigns each data row a distinct fill color.
# No sticky headers, no merged cells — simplest possible setup for pixel verification.
class ColorRowAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  ROW_COLORS = [
    CrymbleUI::Color.new(255, 0, 0, 255),     # row 0: red
    CrymbleUI::Color.new(0, 255, 0, 255),      # row 1: green
    CrymbleUI::Color.new(0, 0, 255, 255),      # row 2: blue
    CrymbleUI::Color.new(255, 255, 0, 255),    # row 3: yellow
    CrymbleUI::Color.new(255, 0, 255, 255),    # row 4: magenta
    CrymbleUI::Color.new(0, 255, 255, 255),    # row 5: cyan
    CrymbleUI::Color.new(128, 0, 0, 255),      # row 6: dark red
    CrymbleUI::Color.new(0, 128, 0, 255),      # row 7: dark green
    CrymbleUI::Color.new(0, 0, 128, 255),      # row 8: dark blue
    CrymbleUI::Color.new(128, 128, 0, 255),    # row 9: olive
    CrymbleUI::Color.new(128, 0, 128, 255),    # row 10: purple
    CrymbleUI::Color.new(0, 128, 128, 255),    # row 11: teal
    CrymbleUI::Color.new(255, 128, 0, 255),    # row 12: orange
    CrymbleUI::Color.new(128, 255, 0, 255),    # row 13: chartreuse
    CrymbleUI::Color.new(0, 128, 255, 255),    # row 14: azure
    CrymbleUI::Color.new(255, 0, 128, 255),    # row 15: rose
  ]

  def initialize(@rows : Int32 = 50, @cols : Int32 = 10)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def color_for_row(row : Int32) : CrymbleUI::Color
    ROW_COLORS[row % ROW_COLORS.size]
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    ColorFillCell.new(color_for_row(row))
  end
end

# DSL-style app with color-coded rows for pixel-level testing
class ColorRowBlitShiftApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  getter! adapter : ColorRowAdapter

  def build : CrymbleUI::Widget
    @adapter = ColorRowAdapter.new(rows: 50, cols: 10)
    m = CrymbleUI::VirtualMatrix.new(
      adapter: @adapter.not_nil!,
      id: "color_grid",
    )
    m.show_rulers = false
    window("Test", 800, 600) do
      widget(m)
    end
  end
end

# Pixel-level blit-shift correctness tests.
#
# These tests verify that after a blit-shift recenter, the PIXEL CONTENT
# at buffer/viewport positions matches the expected row — not old/stale data
# from before the shift. This catches coordinate bugs in the blit-shift
# dest computation that widget-level tests (checking active_cells text) miss.
describe "VirtualMatrix blit-shift pixel correctness" do
  it "blit-shift preserves correct pixel content at buffer positions", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    adapter = app.adapter
    content_layer = matrix.content_layer.not_nil!
    initial_origin = content_layer.buffer_origin

    # Geometry: no rulers (show_rulers=false), default cell sizes
    # row_height = GRID_SPACING(3) + DEFAULT_ROW_HEIGHT(1.0) * frame_height(20) = 23px
    # col_width = GRID_SPACING(3) + DEFAULT_COLUMN_WIDTH(5.0) * frame_height(20) = 103px
    row_height = 23
    col_width = 103

    # --- Pre-scroll verification: confirm row 0 color in buffer ---
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    # Row 0's cell starts at content-space y=0, in buffer at y = 0 - buffer_origin.y
    # Sample 5px into the cell (past any grid spacing) at col 0
    pre_sample_content_y = 0 + 5  # row 0 content position + 5px offset
    pre_sample_buffer_y = (pre_sample_content_y - content_layer.buffer_origin.y).to_i
    pre_sample_content_x = 0 + 5  # col 0 content position + 5px offset
    pre_sample_buffer_x = (pre_sample_content_x - content_layer.buffer_origin.x).to_i

    pre_pixel = layer_backend.get_pixel(pre_sample_buffer_x, pre_sample_buffer_y)
    pre_pixel.should_not be_nil,
      "Pre-scroll: no pixel at buffer (#{pre_sample_buffer_x}, #{pre_sample_buffer_y})"
    pre_pixel.not_nil!.should eq(adapter.color_for_row(0)),
      "Pre-scroll: pixel at row 0 should be #{adapter.color_for_row(0)} but got #{pre_pixel}"

    # --- Scroll down past cache_extent to trigger blit-shift ---
    # cache_extent = 100px, SCROLL_SPEED = 30px per event
    # 7 events = 210px → well past the 100px boundary
    center = CrymbleUI::Vec2.new(400.0, 300.0)
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Verify blit-shift was triggered: buffer_origin should have changed
    content_layer.buffer_origin.should_not eq(initial_origin),
      "Buffer origin didn't change after scrolling 210px — blit-shift NOT triggered. " \
      "Initial: #{initial_origin}, Current: #{content_layer.buffer_origin}, " \
      "scroll_offset: #{matrix.scroll_offset}"

    scroll_y = matrix.scroll_offset.y  # Should be ~210px

    # --- Post-scroll pixel verification ---
    # For each visible row, verify the pixel color in the layer buffer matches
    # the expected color for that row number.
    #
    # Content-space Y for row R = R * row_height (no rulers)
    # Buffer Y for content-space Y = content_y - buffer_origin.y
    # Viewport shows rows whose content_y is in [scroll_y, scroll_y + viewport_h)
    viewport_h = content_layer.bounds.height
    buf_origin = content_layer.buffer_origin

    # Calculate which rows are visible in the viewport
    first_visible_row = (scroll_y / row_height).to_i
    last_visible_row = ((scroll_y + viewport_h) / row_height).to_i
    last_visible_row = {last_visible_row, 49}.min

    # Sample the CENTER of each visible row's cell at col 0
    wrong_pixels = [] of {Int32, CrymbleUI::Color, CrymbleUI::Color}
    (first_visible_row..last_visible_row).each do |row|
      content_y = row * row_height + row_height // 2  # Center of cell vertically
      content_x = col_width // 2                       # Center of col 0 cell
      buffer_y = (content_y - buf_origin.y).to_i
      buffer_x = (content_x - buf_origin.x).to_i

      # Skip if outside buffer bounds
      next if buffer_x < 0 || buffer_x >= layer_backend.width
      next if buffer_y < 0 || buffer_y >= layer_backend.height

      pixel = layer_backend.get_pixel(buffer_x, buffer_y)
      next unless pixel  # Out of bounds

      expected_color = adapter.color_for_row(row)
      bg_color = content_layer.background_color

      # Pixel should be either the expected row color or the grid spacing bg color
      # (if we hit the 3px gap between cells). Skip background-colored pixels.
      next if pixel == bg_color

      unless pixel == expected_color
        wrong_pixels << {row, pixel, expected_color}
      end
    end

    wrong_pixels.should be_empty,
      "Pixel content wrong after blit-shift (#{wrong_pixels.size} rows): " \
      "#{wrong_pixels.first(5).map { |w| "row #{w[0]}: got #{w[1]} expected #{w[2]}" }.join(", ")}. " \
      "scroll_y=#{scroll_y.round(1)}, buffer_origin=#{buf_origin}, " \
      "visible_rows=#{first_visible_row}..#{last_visible_row}"
  end

  it "blit-shift preserves correct pixel content after scroll round-trip", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    adapter = app.adapter
    row_height = 23
    col_width = 103
    center = CrymbleUI::Vec2.new(400.0, 300.0)

    # Scroll down past cache_extent (210px)
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    # Scroll back up to top (210px)
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    buf_origin = content_layer.buffer_origin
    scroll_y = matrix.scroll_offset.y

    # After round-trip, should be near top
    scroll_y.should be <= 10.0,
      "Expected near top after round-trip, got scroll_y=#{scroll_y}"

    # Verify pixel colors match expected rows near the top
    viewport_h = content_layer.bounds.height
    first_visible_row = (scroll_y / row_height).to_i
    last_visible_row = ((scroll_y + viewport_h) / row_height).to_i
    last_visible_row = {last_visible_row, 49}.min

    wrong_pixels = [] of {Int32, CrymbleUI::Color, CrymbleUI::Color}
    (first_visible_row..last_visible_row).each do |row|
      content_y = row * row_height + row_height // 2
      content_x = col_width // 2
      buffer_y = (content_y - buf_origin.y).to_i
      buffer_x = (content_x - buf_origin.x).to_i

      next if buffer_x < 0 || buffer_x >= layer_backend.width
      next if buffer_y < 0 || buffer_y >= layer_backend.height

      pixel = layer_backend.get_pixel(buffer_x, buffer_y)
      next unless pixel

      expected_color = adapter.color_for_row(row)
      bg_color = content_layer.background_color
      next if pixel == bg_color

      unless pixel == expected_color
        wrong_pixels << {row, pixel, expected_color}
      end
    end

    wrong_pixels.should be_empty,
      "Pixel content wrong after round-trip blit-shift (#{wrong_pixels.size} rows): " \
      "#{wrong_pixels.first(5).map { |w| "row #{w[0]}: got #{w[1]} expected #{w[2]}" }.join(", ")}. " \
      "scroll_y=#{scroll_y.round(1)}, buffer_origin=#{buf_origin}"
  end

  it "blit-shift preserves correct column pixels after horizontal scroll", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    adapter = app.adapter
    row_height = 23
    col_width = 103
    center = CrymbleUI::Vec2.new(400.0, 300.0)

    # Scroll right past cache_extent (210px horizontal)
    # on_mouse_wheel with shift=true does horizontal scroll
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    buf_origin = content_layer.buffer_origin
    scroll_x = matrix.scroll_offset.x
    scroll_y = matrix.scroll_offset.y

    scroll_x.should be > 100.0,
      "Expected significant horizontal scroll, got scroll_x=#{scroll_x}"

    # Verify: pixel colors for visible rows at a visible column
    # Row colors should still be correct regardless of horizontal scroll position
    viewport_h = content_layer.bounds.height
    first_visible_row = (scroll_y / row_height).to_i
    last_visible_row = ((scroll_y + viewport_h) / row_height).to_i
    last_visible_row = {last_visible_row, 49}.min

    # Pick a column that's visible after horizontal scroll
    first_visible_col = (scroll_x / col_width).to_i

    wrong_pixels = [] of {Int32, CrymbleUI::Color, CrymbleUI::Color}
    (first_visible_row..last_visible_row).each do |row|
      content_y = row * row_height + row_height // 2
      content_x = first_visible_col * col_width + col_width // 2
      buffer_y = (content_y - buf_origin.y).to_i
      buffer_x = (content_x - buf_origin.x).to_i

      next if buffer_x < 0 || buffer_x >= layer_backend.width
      next if buffer_y < 0 || buffer_y >= layer_backend.height

      pixel = layer_backend.get_pixel(buffer_x, buffer_y)
      next unless pixel

      expected_color = adapter.color_for_row(row)
      bg_color = content_layer.background_color
      next if pixel == bg_color

      unless pixel == expected_color
        wrong_pixels << {row, pixel, expected_color}
      end
    end

    wrong_pixels.should be_empty,
      "Pixel content wrong after horizontal blit-shift (#{wrong_pixels.size} rows): " \
      "#{wrong_pixels.first(5).map { |w| "row #{w[0]}: got #{w[1]} expected #{w[2]}" }.join(", ")}. " \
      "scroll_x=#{scroll_x.round(1)}, scroll_y=#{scroll_y.round(1)}, buffer_origin=#{buf_origin}"
  end
end

# Blit-shift boundary cell invalidation tests.
#
# After blit-shift, cells that were partially clipped at the old buffer boundary
# need their widget_backend invalidated (set to nil) so the full render path
# creates a fresh backend. Without this, the fast-path blit can reproduce
# truncated rendering from the old clipped position (SFML-specific, but the
# invalidation logic is testable headlessly).
describe "VirtualMatrix blit-shift boundary cell invalidation" do
  it "invalidates widget_backends of cells at old buffer boundary", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    initial_origin = content_layer.buffer_origin

    # Scroll to trigger blit-shift
    center = CrymbleUI::Vec2.new(400.0, 300.0)
    CrymbleUI::LayerRenderer.reset_frame_counters
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!

    # Verify blit-shift was triggered
    content_layer.buffer_origin.should_not eq(initial_origin),
      "Buffer origin didn't change — blit-shift NOT triggered"

    # Verify boundary cells were detected and invalidated
    CrymbleUI::LayerRenderer.frame_boundary_cells_invalidated.should be > 0,
      "No boundary cells invalidated after blit-shift — invalidation logic didn't run"
  end

  it "renders correct pixels at the overlap boundary after vertical blit-shift", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    adapter = app.adapter
    row_height = 23
    center = CrymbleUI::Vec2.new(400.0, 300.0)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    old_origin = content_layer.buffer_origin
    buf_h = content_layer.backend.not_nil!.height

    # Scroll to trigger blit-shift
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    new_origin = content_layer.buffer_origin
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # The overlap boundary in new buffer coordinates:
    # overlap_h = buf_h - (new_origin.y - old_origin.y).abs
    shift_y = (new_origin.y - old_origin.y).abs.to_i
    overlap_h = buf_h - shift_y

    # Find rows whose cells CROSS the overlap boundary (old bottom edge):
    # Cell at old_buf_y needs old_buf_y + row_height > buf_h → old_buf_y > buf_h - row_height
    # In new buffer: new_buf_y = old_buf_y - shift_y
    # These rows are at new_buf_y around (overlap_h - row_height)..(overlap_h)
    boundary_row_content_y = (overlap_h + new_origin.y).to_i  # content-space Y at overlap edge
    boundary_row = boundary_row_content_y // row_height

    # Check pixels at the overlap boundary row — specifically the BOTTOM pixels
    # of the cell that crosses the boundary. These are the pixels that would be
    # garbled without the invalidation fix.
    wrong_pixels = [] of {Int32, Int32, CrymbleUI::Color, CrymbleUI::Color}
    bg_color = content_layer.background_color

    # Check a few rows around the boundary
    ((boundary_row - 1)..[boundary_row + 2, 49].min).each do |row|
      next if row < 0
      # Sample bottom quarter of each cell (where truncation would occur)
      content_y = row * row_height + (row_height * 3 // 4)
      content_x = 50 + 5  # col 0, 5px in
      buffer_y = (content_y - new_origin.y).to_i
      buffer_x = (content_x - new_origin.x).to_i

      next if buffer_x < 0 || buffer_x >= layer_backend.width
      next if buffer_y < 0 || buffer_y >= layer_backend.height

      pixel = layer_backend.get_pixel(buffer_x, buffer_y)
      next unless pixel
      next if pixel == bg_color  # grid spacing

      expected_color = adapter.color_for_row(row)
      unless pixel == expected_color
        wrong_pixels << {row, buffer_y, pixel, expected_color}
      end
    end

    wrong_pixels.should be_empty,
      "Pixels wrong at overlap boundary (#{wrong_pixels.size}): " \
      "#{wrong_pixels.first(3).map { |w| "row #{w[0]} buf_y=#{w[1]}: got #{w[2]} expected #{w[3]}" }.join(", ")}. " \
      "shift=#{shift_y}, overlap_h=#{overlap_h}, boundary_row=#{boundary_row}"
  end

  it "renders correct pixels at the overlap boundary after horizontal blit-shift", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ColorRowBlitShiftApp.new
    app.build_tree
    renderer.settle_rendering(app)

    adapter = app.adapter
    row_height = 23
    col_width = 103
    center = CrymbleUI::Vec2.new(400.0, 300.0)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    old_origin = content_layer.buffer_origin
    buf_w = content_layer.backend.not_nil!.width

    # Horizontal scroll to trigger blit-shift
    7.times do
      matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("color_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    new_origin = content_layer.buffer_origin
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Overlap boundary in X
    shift_x = (new_origin.x - old_origin.x).abs.to_i
    overlap_w = buf_w - shift_x

    # Check visible rows at columns near the horizontal overlap boundary
    scroll_y = matrix.scroll_offset.y
    first_row = (scroll_y / row_height).to_i
    last_row = {first_row + 5, 49}.min

    boundary_content_x = (overlap_w + new_origin.x).to_i
    boundary_col = boundary_content_x // col_width

    wrong_pixels = [] of {Int32, Int32, CrymbleUI::Color, CrymbleUI::Color}
    bg_color = content_layer.background_color

    (first_row..last_row).each do |row|
      # Sample right quarter of boundary column cell
      content_y = row * row_height + row_height // 2
      content_x = boundary_col * col_width + (col_width * 3 // 4)
      buffer_y = (content_y - new_origin.y).to_i
      buffer_x = (content_x - new_origin.x).to_i

      next if buffer_x < 0 || buffer_x >= layer_backend.width
      next if buffer_y < 0 || buffer_y >= layer_backend.height

      pixel = layer_backend.get_pixel(buffer_x, buffer_y)
      next unless pixel
      next if pixel == bg_color

      expected_color = adapter.color_for_row(row)
      unless pixel == expected_color
        wrong_pixels << {row, buffer_x, pixel, expected_color}
      end
    end

    wrong_pixels.should be_empty,
      "Pixels wrong at horizontal overlap boundary (#{wrong_pixels.size}): " \
      "#{wrong_pixels.first(3).map { |w| "row #{w[0]} buf_x=#{w[1]}: got #{w[2]} expected #{w[3]}" }.join(", ")}. " \
      "shift=#{shift_x}, overlap_w=#{overlap_w}, boundary_col=#{boundary_col}"
  end
end
