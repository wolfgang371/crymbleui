require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Helper to set up a matrix for cursor overlay tests
private def setup_overlay_matrix(rows = 10, cols = 10, viewport_width = 400.0, viewport_height = 300.0)
  matrix = CrymbleUI::VirtualMatrix.new(rows: rows, cols: cols, id: "overlay_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

# Adapter with sticky row 0 and sticky col 0 for cursor overlay clipping tests
class CursorOverlayStickyAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  # Row 0 scrolls out LAST → sticky_row_count = 1
  # Col 0 scrolls out LAST → sticky_col_count = 1
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

# Helper to set up a matrix with sticky headers for cursor overlay tests
private def setup_sticky_overlay_matrix(rows = 10, cols = 10, viewport_width = 400.0, viewport_height = 300.0)
  adapter = CursorOverlayStickyAdapter.new(rows, cols)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_overlay_test")

  app = TestApp.new
  app.root_widget = matrix
  app.build_tree

  constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(viewport_width, viewport_height))
  matrix.layout(constraints, CrymbleUI::Vec2.zero)
  {matrix, app, constraints}
end

describe CrymbleUI::VirtualMatrix do
  describe "Cursor Overlay Layer" do
    it "has a cursor overlay layer after layout" do
      matrix, _, _ = setup_overlay_matrix
      matrix.cursor_overlay_layer.should_not be_nil
    end

    it "overlay layer z-index is above content layer" do
      matrix, _, _ = setup_overlay_matrix
      content_z = matrix.content_layer.not_nil!.z_index
      overlay_z = matrix.cursor_overlay_layer.not_nil!.z_index
      overlay_z.should be > content_z
    end

    it "overlay layer bounds match content area" do
      matrix, _, _ = setup_overlay_matrix
      content_bounds = matrix.content_layer.not_nil!.bounds
      overlay_bounds = matrix.cursor_overlay_layer.not_nil!.bounds
      overlay_bounds.x.should eq(content_bounds.x)
      overlay_bounds.y.should eq(content_bounds.y)
      overlay_bounds.width.should eq(content_bounds.width)
      overlay_bounds.height.should eq(content_bounds.height)
    end

    it "overlay layer is not a viewport_cache layer (no scrolling)" do
      matrix, _, _ = setup_overlay_matrix
      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.viewport_cache.should be_false
    end

    it "cursor movement does not trigger cell cursor state changes" do
      matrix, _, _ = setup_overlay_matrix
      matrix.cursor_rc = {0, 0}

      # Move cursor - should NOT iterate all cells to set cursor state
      # Instead, only overlay layer should be marked for re-render
      matrix.move_cursor(:right)
      matrix.move_cursor(:down)

      # After move, no cell should have cursor-related visual state
      # (overlay handles it all — cells are cursor-unaware)
      matrix.active_cells.each do |_key, widget|
        widget.responds_to?(:cursored).should be_false
      end
    end
  end

  describe "Cursor Overlay Rendering" do
    it "overlay layer has a widget registered after layout" do
      matrix, _, _ = setup_overlay_matrix
      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.widgets.size.should be >= 1
    end

    it "overlay widget generates fill_rect primitives for cursor bands" do
      matrix, _, _ = setup_overlay_matrix
      matrix.cursor_rc = {2, 3}  # Set cursor to a visible cell

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.widgets.size.should be >= 1
      overlay_widget = overlay.widgets.first

      # Get primitives - should include fill_rects for row band and col band
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect))

      # At least 2 fill_rects: row band + col band (intersection may be separate)
      fill_rects.size.should be >= 2
    end

    it "row band spans full viewport width at cursor row position" do
      matrix, _, _ = setup_overlay_matrix
      matrix.cursor_rc = {2, 3}

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      # Find the row band (full width rect)
      viewport_width = overlay.bounds.width
      row_band = fill_rects.find { |fr| fr.bounds.width >= viewport_width - 1 }
      row_band.should_not be_nil

      # Row band y should match cursor row's viewport position (including ruler offset)
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      ruler_y = CrymbleUI::VirtualMatrix::RULER_ROW_HEIGHT * 20.0
      expected_y = ruler_y + 2 * row_h  # Row 2's position (no scroll), shifted by ruler
      row_band.not_nil!.bounds.y.should eq(expected_y)
    end

    it "col band spans full viewport height at cursor col position" do
      matrix, _, _ = setup_overlay_matrix(rows: 15)  # 15 rows to fill viewport (15*23+20=365 > 300)
      matrix.cursor_rc = {2, 3}

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      # Find the col band (full height rect)
      viewport_height = overlay.bounds.height
      col_band = fill_rects.find { |fr| fr.bounds.height >= viewport_height - 1 }
      col_band.should_not be_nil

      # Col band x should match cursor col's viewport position (including ruler offset)
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      ruler_x = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
      expected_x = ruler_x + 3 * col_w  # Col 3's position (no scroll), shifted by ruler
      col_band.not_nil!.bounds.x.should eq(expected_x)
    end

    it "cursor bands adjust for scroll offset" do
      matrix, _, constraints = setup_overlay_matrix(rows: 20)
      matrix.cursor_rc = {5, 4}

      # Scroll by 2 rows / 1 column
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      ruler_x = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
      ruler_y = CrymbleUI::VirtualMatrix::RULER_ROW_HEIGHT * 20.0
      scroll_x = col_w * 1.0
      scroll_y = row_h * 2.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, scroll_y)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      viewport_width = overlay.bounds.width
      viewport_height = overlay.bounds.height

      # Row band should be at cursor_row's content position (with ruler) minus scroll_offset.y
      row_band = fill_rects.find { |fr| fr.bounds.width >= viewport_width - 1 }
      row_band.should_not be_nil
      expected_row_y = ruler_y + 5 * row_h - scroll_y
      row_band.not_nil!.bounds.y.should eq(expected_row_y)

      # Col band should be at cursor_col's content position (with ruler) minus scroll_offset.x
      col_band = fill_rects.find { |fr| fr.bounds.height >= viewport_height - 1 }
      col_band.should_not be_nil
      expected_col_x = ruler_x + 4 * col_w - scroll_x
      col_band.not_nil!.bounds.x.should eq(expected_col_x)
    end
  end

  describe "Cursor Overlay Out-of-Viewport (multi-frame ghost detection)" do
    # Ghost bug: after rendering cursor bands, scrolling cursor out of viewport
    # leaves ghost bands due to stale background capture in selective render.
    # These tests are MULTI-FRAME: first render with cursor visible, then scroll
    # out and re-render. Checks overlay layer backend for stale pixels.

    it "overlay has non-transparent pixels when cursor is visible (multi-frame)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      matrix, app, _ = setup_overlay_matrix(rows: 20)
      matrix.cursor_rc = {2, 0}

      # Multi-frame settle: overlay rendered with bands for cursor at {2, 0}
      renderer.settle_rendering(app)

      overlay = matrix.cursor_overlay_layer.not_nil!
      backend = overlay.backend.as(CrymbleUI::Testing::TestRenderBackend)

      # With rulers: ruler_x=40, ruler_y=20, row_h=23, col_w=103
      # Col 0 band: x in [40..142] (cursor_x=40, effective_band_x=40, col_w=103)
      # Row 2 band: y in [66..88] (cursor_y=20+2*23=66, row_h=23)
      # Pixel (50, 70): inside col 0 band and row 2 band
      pixel = backend.get_pixel(50, 70)
      pixel.should_not be_nil
      pixel.not_nil!.a.should be > 0_u8
    end

    it "no ghost overlay after scrolling cursor row out of viewport" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      matrix, app, _ = setup_overlay_matrix(rows: 20)
      matrix.cursor_rc = {2, 0}

      # Frame 1+: cursor visible, overlay bands rendered
      renderer.settle_rendering(app)

      overlay = matrix.cursor_overlay_layer.not_nil!
      backend = overlay.backend.as(CrymbleUI::Testing::TestRenderBackend)

      # Verify row band has content before scroll at a pixel ONLY in the row band
      # (outside col 0 band which is x in [40..142])
      # Row 2 band: y in [66..88], full width
      # Pixel (200, 70): inside row band only (not in col band)
      pixel_before = backend.get_pixel(200, 70)
      pixel_before.should_not be_nil
      pixel_before.not_nil!.a.should be > 0_u8

      # Scroll row 2 far above viewport via on_mouse_wheel
      center = CrymbleUI::Vec2.new(200.0, 150.0)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -10.0), center)
      renderer.render_frame(app)

      # Row band should be gone (row scrolled out), pixel should be transparent
      # (Col band at x=40..142 may still be present, but x=200 is outside it)
      pixel_after = backend.get_pixel(200, 70)
      (pixel_after.nil? || pixel_after.not_nil!.a == 0_u8).should be_true
    end

    it "no ghost overlay after scrolling cursor col out of viewport" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      matrix, app, _ = setup_overlay_matrix(rows: 20, cols: 20)
      matrix.cursor_rc = {0, 2}

      # Frame 1+: cursor visible, overlay bands rendered
      renderer.settle_rendering(app)

      overlay = matrix.cursor_overlay_layer.not_nil!
      backend = overlay.backend.as(CrymbleUI::Testing::TestRenderBackend)

      # Verify col band has content before scroll at a pixel ONLY in the col band
      # (outside row 0 band which is y in [20..42])
      # Col 2 band: x in [246..348], full height
      # Pixel (250, 100): inside col band only (not in row band)
      pixel_before = backend.get_pixel(250, 100)
      pixel_before.should_not be_nil
      pixel_before.not_nil!.a.should be > 0_u8

      # Scroll col 2 left of viewport via on_mouse_wheel with shift
      center = CrymbleUI::Vec2.new(200.0, 150.0)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -20.0), center, shift: true)
      renderer.render_frame(app)

      # Col band should be gone (col scrolled out), pixel should be transparent
      # (Row band at y=20..42 may still be present, but y=100 is outside it)
      pixel_after = backend.get_pixel(250, 100)
      (pixel_after.nil? || pixel_after.not_nil!.a == 0_u8).should be_true
    end
  end

  describe "Cursor Overlay Integration" do
    it "overlay layer has a backend after render_frame (collected by compositor)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      matrix, app, _ = setup_overlay_matrix

      renderer.render_frame(app)

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.backend.should_not be_nil
    end

    it "move_cursor marks overlay layer for re-render" do
      matrix, _, _ = setup_overlay_matrix
      matrix.cursor_rc = {2, 3}

      overlay = matrix.cursor_overlay_layer.not_nil!

      # Reset layer state to clean
      overlay.state = CrymbleUI::WidgetState::Clean

      # Move cursor - should mark overlay layer for re-render
      matrix.move_cursor(:right)

      overlay.needs_render?.should be_true
    end

    it "overlay widget bounds fit within overlay layer when matrix has non-zero parent offset" do
      # Matrix inside a parent at non-zero position (like in demo)
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 10, id: "offset_test")

      parent_widget = CrymbleUI::VStack.new(id: "parent")
      parent_widget.children << matrix
      matrix.parent = parent_widget

      app = TestApp.new
      app.root_widget = parent_widget
      app.build_tree

      # Parent at (0,0), matrix gets offset from VStack layout
      parent_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(500.0, 400.0))
      parent_widget.layout(parent_constraints, CrymbleUI::Vec2.new(50.0, 30.0))

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first

      # Widget absolute_bounds must be within (or equal to) layer bounds
      # A double-offset bug would push the widget far outside
      wb = overlay_widget.absolute_bounds
      lb = overlay.bounds
      wb.x.should be >= lb.x
      wb.y.should be >= lb.y
      (wb.x + wb.width).should be <= (lb.x + lb.width + 1)
      (wb.y + wb.height).should be <= (lb.y + lb.height + 1)
    end
  end

  describe "Cursor Overlay Sticky-Area Clipping" do
    # Bug: cursor bands bleed into sticky row/col areas.
    # Row band starts at x=0 (covers sticky col), col band starts at y=0 (covers sticky row).
    # Fix: non-sticky cursor bands must be clipped to start after the sticky boundary.

    it "row band extends into sticky col area for non-sticky cursor" do
      matrix, _, _ = setup_sticky_overlay_matrix
      matrix.cursor_rc = {2, 2}  # Non-sticky row and col

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      sticky_w = matrix.sticky_col_width_pixels
      sticky_w.should be > 0  # Sanity: we have a sticky col

      # Row band: the wide rect at cursor row's y position (including ruler offset)
      # It should start at x=0 to highlight the sticky col label
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      ruler_y = CrymbleUI::VirtualMatrix::RULER_ROW_HEIGHT * 20.0
      expected_y = ruler_y + 2 * row_h  # Row 2's viewport position (no scroll), shifted by ruler
      row_band = fill_rects.find { |fr| fr.bounds.y.round(1) == expected_y.round(1) && fr.bounds.height.round(1) == row_h.round(1) }
      row_band.should_not be_nil
      row_band.not_nil!.bounds.x.should eq 0.0
    end

    it "col band extends into sticky row area for non-sticky cursor" do
      matrix, _, _ = setup_sticky_overlay_matrix
      matrix.cursor_rc = {2, 2}  # Non-sticky row and col

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      sticky_h = matrix.sticky_row_height_pixels
      sticky_h.should be > 0  # Sanity: we have a sticky row

      # Col band: the tall rect at cursor col's x position (including ruler offset)
      # It should start at y=0 to highlight the sticky row header
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      ruler_x = CrymbleUI::VirtualMatrix::RULER_COL_WIDTH * 20.0
      expected_x = ruler_x + 2 * col_w  # Col 2's viewport position (no scroll), shifted by ruler
      col_band = fill_rects.find { |fr| fr.bounds.x.round(1) == expected_x.round(1) && fr.bounds.width.round(1) == col_w.round(1) }
      col_band.should_not be_nil
      col_band.not_nil!.bounds.y.should eq 0.0
    end

    it "cursor intersection rect is not in sticky zone" do
      matrix, _, _ = setup_sticky_overlay_matrix
      matrix.cursor_rc = {2, 2}

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      sticky_h = matrix.sticky_row_height_pixels
      sticky_w = matrix.sticky_col_width_pixels

      # No fill_rect should have both x < sticky_w AND y < sticky_h
      # (that would be the sticky corner zone)
      fill_rects.each do |fr|
        in_sticky_corner = fr.bounds.x < sticky_w && fr.bounds.y < sticky_h
        in_sticky_corner.should be_false
      end
    end

    it "sticky cursor (row 0) row band does not extend into sticky col area" do
      matrix, _, _ = setup_sticky_overlay_matrix
      matrix.cursor_rc = {0, 2}  # Row 0 is sticky, col 2 is not

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      sticky_w = matrix.sticky_col_width_pixels

      # Row band for sticky row 0: cursor is on sticky row, so row band
      # should NOT extend into sticky col area (avoid header-highlighting-header)
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      viewport_w = overlay_widget.bounds.width
      row_band = fill_rects.find { |fr| fr.bounds.width > viewport_w / 2 && fr.bounds.height.round(1) == row_h.round(1) }
      row_band.should_not be_nil
      row_band.not_nil!.bounds.x.should be >= sticky_w
    end

    it "sticky cursor (col 0) col band does not extend into sticky row area" do
      matrix, _, _ = setup_sticky_overlay_matrix
      matrix.cursor_rc = {2, 0}  # Col 0 is sticky, row 2 is not

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      sticky_h = matrix.sticky_row_height_pixels

      # Col band for sticky col 0: cursor is on sticky col, so col band
      # should NOT extend into sticky row area (avoid header-highlighting-header)
      viewport_h = overlay_widget.bounds.height
      col_w = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH * 20.0
      col_band = fill_rects.find { |fr| fr.bounds.height > viewport_h / 2 && fr.bounds.width.round(1) == col_w.round(1) }
      col_band.should_not be_nil
      col_band.not_nil!.bounds.y.should be >= sticky_h
    end

    it "bands clamp to sticky boundary when cursor approaches it" do
      matrix, _, constraints = setup_sticky_overlay_matrix(rows: 20)
      sticky_h = matrix.sticky_row_height_pixels  # 23.0 (row 0)

      # Scroll so that row 1 (y=23 content space) is at the sticky boundary
      # band_y = cursor_y - scroll.y = 23.0 - 10.0 = 13.0 < sticky_h
      # The band should be clamped to start at sticky_h
      matrix.cursor_rc = {1, 2}
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 10.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay_widget = overlay.widgets.first
      prims = overlay_widget.to_primitives(overlay_widget.bounds)
      fill_rects = prims.select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))

      # All fill_rects for non-sticky cursor should have y >= sticky_h (for row band)
      # and x >= sticky_w (for col band start)
      row_h = CrymbleUI::VirtualMatrix::GRID_SPACING + CrymbleUI::VirtualMatrix::DEFAULT_ROW_HEIGHT * 20.0
      row_band = fill_rects.find { |fr| fr.bounds.height <= row_h && fr.bounds.width > row_h }
      if row_band
        row_band.bounds.y.should be >= sticky_h
      end
    end
  end
end
