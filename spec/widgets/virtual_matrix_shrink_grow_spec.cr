require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Regression specs for the "rank column blank + ghost row" bug triggered by:
#   adapter row count shrinks (filter narrows) + viewport bounds grow
#     (Filter section collapses, matrix gets more vertical space)
#
# The user-visible symptom after that sequence was:
#   - the last now-visible data row's sticky-col cell rendered blank (no ink)
#   - the cursor-column highlight band stopped one row short
#   - sometimes an extra "ghost row" of the old cursor band persisted below
#
# Three underlying bugs:
#   1. flush_invalidate_all didn't mark cursor_overlay_layer needs_clear,
#      so pixels outside the (now smaller) highlight region persisted.
#   2. When bounds grew BUT the pre-allocated backend still fit, no re-render
#      was triggered for cursor_overlay, leaving the newly-exposed area with
#      stale/uninitialized pixels.
#   3. sticky_cells_can_use_blit_plan? silently skipped cells that lacked a
#      cached widget_backend (rows that became visible only after bounds grow).
#      The fast path then blitted only the N-1 cached cells, leaving the newly-
#      visible cell's area on the layer untouched — blank.

# Adapter whose row count can be changed dynamically, with 1 sticky row (col
# headers at tail) + 1 sticky col (row headers at tail). Mirrors embrace's
# Pivot::Hierarchic sticky layout.
# Expose private methods for spec access
class CrymbleUI::VirtualMatrix
  def sticky_cells_can_use_blit_plan_for_spec
    sticky_cells_can_use_blit_plan?
  end

  def compute_sticky_blit_plans_for_spec
    compute_sticky_blit_plans
  end
end

class ShrinkingStickyAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  property data_rows : Int32

  def initialize(@data_rows : Int32, @data_cols : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    total_rows = 1 + @data_rows
    total_cols = 1 + @data_cols
    rows = (1...total_rows).to_a + [0]
    cols = (1...total_cols).to_a + [0]
    {rows, cols}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    bg = if col == 0
      CrymbleUI::Color.new(180, 210, 255, 255)    # sticky col bg
    else
      CrymbleUI::Color.new(255, 255, 255, 255)    # content
    end
    CrymbleUI::TextInput.new(
      value: "R#{row}C#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry,
      background_color: bg,
    )
  end
end

describe "VirtualMatrix shrink+grow invariants" do
    it "Bug 3: every visible sticky-col cell has non-bg pixels after shrink+grow" do
        renderer = CrymbleUI::Testing::TestRenderer.new(800, 800)
        app = TestApp.new
        adapter = ShrinkingStickyAdapter.new(20, 3)
        matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "vm")
        app.root_widget = matrix
        app.build_tree

        # Phase 1: small viewport — only first few rows visible in the sticky col
        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 180.0)), CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)
        # At this viewport, later rows have no widget_backend yet (never rendered)

        # Phase 2: shrink + grow — exact trigger
        adapter.data_rows = 10
        adapter.invalidate_all!
        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 700.0)), CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        sv = matrix.@content_scroll_view.not_nil!
        sc = sv.sticky_col_layer.not_nil!
        backend = sc.backend.not_nil!

        # Sample every sticky-col cell's center; every one should have at least
        # some TextInput ink (not just the sticky bg color).
        bg_r, bg_g, bg_b = 180_u8, 210_u8, 255_u8
        blank_rows = [] of Int32
        matrix.@active_cells.each do |key, widget|
            next unless key[1] == 0                # sticky col only
            next if key[0] == 0                    # skip col-header row
            abs = widget.absolute_bounds
            cx = (abs.x - sc.bounds.x + abs.width / 2).to_i
            cy = (abs.y - sc.bounds.y + abs.height / 2).to_i
            next if cx < 0 || cy < 0 || cx >= backend.width || cy >= backend.height

            # Scan a small horizontal strip for any non-bg pixel
            any_ink = false
            (-2..2).each do |dy|
                (-30..30).each do |dx|
                    px = backend.get_pixel(cx + dx, cy + dy)
                    next unless px
                    dr = (px.r.to_i - bg_r.to_i).abs
                    dg = (px.g.to_i - bg_g.to_i).abs
                    db = (px.b.to_i - bg_b.to_i).abs
                    any_ink = true if (dr + dg + db) > 30
                end
            end
            blank_rows << key[0] unless any_ink
        end

        blank_rows.empty?.should be_true,
            "sticky-col cells with no text pixels after shrink+grow: #{blank_rows.inspect}"
    end

    it "Bug 3: cells that lack widget_backend get routed to render_list (not silently skipped)" do
        # Structural regression for the decision-point bug. Before the fix, the
        # blit-plan builder silently skipped sticky cells that had no cached
        # widget_backend (newly visible after bounds grow), leaving their layer
        # area blank. After the fix, those cells must end up in the
        # blit_plan_render_widgets list so they render normally after blits.
        renderer = CrymbleUI::Testing::TestRenderer.new(600, 600)
        app = TestApp.new
        adapter = ShrinkingStickyAdapter.new(20, 3)
        matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "vm")
        app.root_widget = matrix
        app.build_tree

        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(500.0, 150.0)), CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        adapter.data_rows = 10
        adapter.invalidate_all!
        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(500.0, 500.0)), CrymbleUI::Vec2.zero)

        # Sanity: some sticky-col cells should be freshly created (no backend yet)
        cells_without_backend = matrix.@active_cells.select { |k, w| k[1] == 0 && w.widget_backend.nil? }
        cells_without_backend.size.should be > 0,
          "test setup didn't create any cells without backend — adjust viewport sizes"

        # Trigger the blit-plan computation path directly, then inspect the
        # sticky_col_layer's render list. Every backend-less sticky-col cell
        # must be scheduled for a normal render (via blit_plan_render_widgets)
        # — not silently skipped.
        sv = matrix.@content_scroll_view.not_nil!
        sc = sv.sticky_col_layer.not_nil!
        matrix.as(CrymbleUI::VirtualMatrix).compute_sticky_blit_plans_for_spec
        render_list = sc.blit_plan_render_widgets || [] of CrymbleUI::Widget
        cells_without_backend.each do |k, widget|
            next if widget.bounds.x < -100.0   # off-screen is OK to skip
            render_list.includes?(widget).should be_true,
              "cell at #{k.inspect} has no widget_backend and is not in sticky_col.blit_plan_render_widgets — will render blank"
        end
    end

    it "Bugs 1+2: cursor_overlay_layer has no stale pixels beyond the new data extent" do
        renderer = CrymbleUI::Testing::TestRenderer.new(800, 800)
        app = TestApp.new
        adapter = ShrinkingStickyAdapter.new(20, 3)
        matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "vm")
        app.root_widget = matrix
        app.build_tree

        # Phase 1: large-enough viewport so cursor band covers rows 0..N
        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 600.0)), CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        # Phase 2: shrink adapter + invalidate (no bounds change yet)
        adapter.data_rows = 5
        adapter.invalidate_all!
        renderer.settle_rendering(app)

        # Phase 3: bounds-grow path (here we keep bounds larger than Phase 2's
        # overlay would have been). Simulate the real-world scenario.
        matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 700.0)), CrymbleUI::Vec2.zero)
        renderer.settle_rendering(app)

        overlay = matrix.@cursor_overlay_layer.not_nil!
        backend = overlay.backend.not_nil!

        # Compute expected data extent: ruler + N rows × row_height
        fh = CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE * CrymbleUI::FontSizing.zoom_factor
        gs = (CrymbleUI::VirtualMatrix::GRID_SPACING_BASE * CrymbleUI::FontSizing.zoom_factor).round.to_i
        row_h = (gs + fh).to_i
        ruler = row_h
        expected_max_y = ruler + matrix.@rows * row_h

        # Any non-transparent pixels beyond expected_max_y are ghosts from before
        # the shrink.
        ghost_count = 0
        y_start = expected_max_y + 5
        y_end = {expected_max_y + 150, backend.height - 1}.min
        if y_end > y_start
            (y_start..y_end).each do |y|
                (5..80).each do |x|
                    px = backend.get_pixel(x, y)
                    next unless px
                    ghost_count += 1 if px.a > 10
                end
            end
        end
        ghost_count.should eq(0),
            "cursor_overlay has #{ghost_count} non-transparent pixels beyond expected extent (y>#{expected_max_y})"
    end
end
