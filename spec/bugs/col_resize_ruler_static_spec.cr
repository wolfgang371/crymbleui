require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Reproduction (TEST — no fix) of two reported VirtualMatrix column-resize bugs:
#   1. CORRECTNESS: during AND after a column resize drag the horizontal ruler
#      stays static — it does not reflect the new column widths. (Regression from
#      c8c7237: rulers became CachePolicy::Dynamic + auto-capture scroll, but the
#      size channel's mark_ruler_widgets_dirty only marks the LAYER, never touches
#      the ruler's primitive node, so the stale cached texture is re-blitted.)
#   2. PERFORMANCE: the per-mouse-move (~125 Hz) update_visible_cells is not
#      coalesced to once per frame (~60 Hz), so a drag re-lays-out all visible
#      cells several times per frame → CPU pegs. (The scroll path already defers
#      to pre_render_flush via @pending_scroll_update; resize was never given it.)
#
# A visible cell (fill_rect, for pixel tests) that ALSO counts measures, so the
# perf test can observe per-move re-layout via Widget.measure_count.
class CountingCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Widget.increment_measure_count
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), CrymbleUI::Color.new(45_u8, 50_u8, 55_u8)) }
  end
end

# 2 sticky cols (0,1) + 2 sticky rows (0,1), rest data — like the demo.
class RulerResizeAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...12).to_a + [1, 0], (2...12).to_a + [1, 0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CountingCell.new
  end
end

class RulerResizeApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(RulerResizeAdapter.new, id: "m")
  end
end

# Like RulerResizeAdapter but with a 2×2 MERGED data cell (rows 4-5, cols 3-4) that STRADDLES the
# resized data column (col 3) — exercises the content-compound blit-shift path.
class MergedDataAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...12).to_a + [1, 0], (2...12).to_a + [1, 0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CountingCell.new
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {4, 3}, {5, 4} } if (4..5).includes?(row) && (3..4).includes?(col)
    { {row, col}, {row, col} }
  end
end

class MergedDataApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(MergedDataAdapter.new, id: "m")
  end
end

private def setup_resize_matrix
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
  app = RulerResizeApp.new
  app.build_tree
  renderer.settle_rendering(app)
  {renderer, app, app.find("m").as(CrymbleUI::VirtualMatrix)}
end

# Screen coords of the border after data column `target`, in the col-ruler strip.
private def col_border(matrix, target : Int32) : {Float64, Float64}
  col_sizes = matrix.@cached_col_sizes.not_nil!
  sticky_cols = matrix.sticky_col_count
  acc = matrix.ruler_col_width_pixels + matrix.sticky_col_width_pixels
  border_local = acc + (sticky_cols..target).sum { |i| col_sizes[i].to_f64 }
  {matrix.absolute_bounds.x + border_local, matrix.ruler_row_height_pixels / 2.0}
end

# Screen coords of the border after data row `target`, in the row-ruler strip (the vertical dual).
private def row_border(matrix, target : Int32) : {Float64, Float64}
  row_sizes = matrix.@cached_row_sizes.not_nil!
  sticky_rows = matrix.sticky_row_count
  acc = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
  border_local = acc + (sticky_rows..target).sum { |i| row_sizes[i].to_f64 }
  {matrix.ruler_col_width_pixels / 2.0, matrix.absolute_bounds.y + border_local}
end

# Snapshot one horizontal scanline across the composited col-ruler strip.
private def ruler_scanline(renderer, width : Int32, y : Int32) : Array(UInt32)
  (0...width).map do |x|
    px = renderer.backend.get_pixel(x, y)
    px ? (px.r.to_u32 << 16 | px.g.to_u32 << 8 | px.b.to_u32) : 0_u32
  end
end

# Snapshot the whole composited window (RGBA per pixel) for pixel-equivalence checks.
private def capture_frame(renderer, width : Int32, height : Int32) : Array(UInt32)
  buf = renderer.backend
  Array(UInt32).new(width * height) do |i|
    px = buf.get_pixel(i % width, i // width)
    px ? (px.r.to_u32 << 24 | px.g.to_u32 << 16 | px.b.to_u32 << 8 | px.a.to_u32) : 0_u32
  end
end

# Resize data column 3 by `dx` screen px (>0 widen, <0 shrink), then assert the resize frame took the
# blit-shift path (not the clear fallback) AND is pixel-identical to a forced full re-composite of the
# same state — the ground-truth oracle for the translate + strip-clear + slot bookkeeping.
# Core: the caller has already issued mouse_down + a resize mouse_move. Render the resize frame, assert
# it took the blit-shift path (not the clear fallback), then assert it is pixel-identical to a forced
# full re-composite of the same state — the ground-truth oracle for translate + strip-clear + slots.
private def assert_shift_matches_full_render(renderer, app, matrix, label : String)
  w, h = 900, 400

  CrymbleUI::LayerRenderer.reset_frame_counters
  renderer.render_frame(app) # the resize frame — must take the blit-shift path
  after_shift = capture_frame(renderer, w, h)

  CrymbleUI::LayerRenderer.frame_blit_shift_count.should be > 0,
    "#{label}: expected the blit-shift path but blit_shift=0 (fell back to clear)"

  # Ground truth: clear the content buffer and re-composite everything from scratch.
  matrix.content_layer.not_nil!.mark_needs_clear_and_render
  renderer.render_frame(app)
  ground_truth = capture_frame(renderer, w, h)

  mismatches = 0
  first : {Int32, Int32}? = nil
  after_shift.each_with_index do |px, i|
    if px != ground_truth[i]
      mismatches += 1
      first ||= {i % w, i // w}
    end
  end
  if mismatches > 0
    diffs = [] of {Int32, Int32}
    after_shift.each_with_index { |px, i| diffs << {i % w, i // w} if px != ground_truth[i] }
    xs, ys = diffs.map(&.[0]), diffs.map(&.[1])
    puts "[#{label} diff] #{mismatches} px; x=#{xs.min}..#{xs.max} y=#{ys.min}..#{ys.max}"
  end
  mismatches.should eq(0),
    "#{label}: blit-shift diverged from a full re-render at #{mismatches} px (first at #{first})"
end

# Resize DATA column 3 by `dx` screen px (>0 widen, <0 shrink).
private def assert_col_resize_pixel_equivalent(dx : Float64, label : String)
  renderer, app, matrix = setup_resize_matrix
  bx, by = col_border(matrix, 3)
  width0 = matrix.get_col_width(3)
  app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
  app.handle_mouse_move(CrymbleUI::Vec2.new(bx + dx, by))
  (dx > 0 ? matrix.get_col_width(3) > width0 : matrix.get_col_width(3) < width0).should be_true
  assert_shift_matches_full_render(renderer, app, matrix, label)
end

# Vertical dual: resize DATA row 3 by `dy` screen px.
private def assert_row_resize_pixel_equivalent(dy : Float64, label : String)
  renderer, app, matrix = setup_resize_matrix
  bx, by = row_border(matrix, 3)
  height0 = matrix.get_row_height(3)
  app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
  app.handle_mouse_move(CrymbleUI::Vec2.new(bx, by + dy))
  (dy > 0 ? matrix.get_row_height(3) > height0 : matrix.get_row_height(3) < height0).should be_true
  assert_shift_matches_full_render(renderer, app, matrix, label)
end

# Resize DATA column 3 by `dx` with a MERGED data cell (rows 4-5, cols 3-4) straddling the boundary.
private def assert_merged_col_resize_pixel_equivalent(dx : Float64, label : String)
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 400)
  app = MergedDataApp.new
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
  bx, by = col_border(matrix, 3)
  width0 = matrix.get_col_width(3)
  app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
  app.handle_mouse_move(CrymbleUI::Vec2.new(bx + dx, by))
  (dx > 0 ? matrix.get_col_width(3) > width0 : matrix.get_col_width(3) < width0).should be_true
  assert_shift_matches_full_render(renderer, app, matrix, label)
end

# Resize STICKY column 0 by `dx` (resize_index < sticky_col_count) — shifts the whole data area.
private def assert_sticky_col_resize_pixel_equivalent(dx : Float64, label : String)
  renderer, app, matrix = setup_resize_matrix
  col_sizes = matrix.@cached_col_sizes.not_nil!
  bx = matrix.absolute_bounds.x + matrix.ruler_col_width_pixels + col_sizes[0].to_f64 # right border of sticky col 0
  by = matrix.ruler_row_height_pixels / 2.0
  width0 = matrix.get_col_width(0)
  app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
  app.handle_mouse_move(CrymbleUI::Vec2.new(bx + dx, by))
  (dx > 0 ? matrix.get_col_width(0) > width0 : matrix.get_col_width(0) < width0).should be_true
  assert_shift_matches_full_render(renderer, app, matrix, label)
end

# Vertical dual: resize STICKY row 0 by `dy` (resize_index < sticky_row_count).
private def assert_sticky_row_resize_pixel_equivalent(dy : Float64, label : String)
  renderer, app, matrix = setup_resize_matrix
  row_sizes = matrix.@cached_row_sizes.not_nil!
  bx = matrix.ruler_col_width_pixels / 2.0
  by = matrix.absolute_bounds.y + matrix.ruler_row_height_pixels + row_sizes[0].to_f64 # bottom border of sticky row 0
  height0 = matrix.get_row_height(0)
  app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
  app.handle_mouse_move(CrymbleUI::Vec2.new(bx, by + dy))
  (dy > 0 ? matrix.get_row_height(0) > height0 : matrix.get_row_height(0) < height0).should be_true
  assert_shift_matches_full_render(renderer, app, matrix, label)
end

describe "VirtualMatrix column-resize" do
  it "col ruler tracks a data-column widening (during AND after the drag)" do
    renderer, app, matrix = setup_resize_matrix
    bx, by = col_border(matrix, 3)
    yline = by.to_i

    width0 = matrix.get_col_width(3)
    before = ruler_scanline(renderer, 900, yline)

    app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
    6.times do |i|
      app.handle_mouse_move(CrymbleUI::Vec2.new(bx + 10.0 * (i + 1), by))
      renderer.render_frame(app)
    end
    during = ruler_scanline(renderer, 900, yline)
    app.handle_mouse_up(CrymbleUI::Vec2.new(bx + 60.0, by))
    renderer.render_frame(app)
    after = ruler_scanline(renderer, 900, yline)

    matrix = app.find("m").as(CrymbleUI::VirtualMatrix)
    matrix.get_col_width(3).should be > width0 # data actually resized
    during.should_not eq(before)               # ...so the ruler must have moved
    after.should_not eq(before)
  end

  it "coalesces resize reflow: mouse-moves between frames don't each re-lay-out cells" do
    renderer, app, matrix = setup_resize_matrix
    bx, by = col_border(matrix, 3)

    app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by)) # begin the resize drag

    # Many moves with NO render between them (as the real 125 Hz event stream does).
    moves = 20
    CrymbleUI::Widget.reset_measure_count
    moves.times { |i| app.handle_mouse_move(CrymbleUI::Vec2.new(bx + 5.0 * (i + 1), by)) }
    measures_during_moves = CrymbleUI::Widget.measure_count

    # Then ONE frame — the deferred reflow runs exactly once here.
    CrymbleUI::Widget.reset_measure_count
    renderer.render_frame(app)
    measures_one_frame = CrymbleUI::Widget.measure_count

    puts "\n[resize perf] #{moves} moves between frames = #{measures_during_moves} cell re-layouts; " \
         "1 frame flush = #{measures_one_frame} (uncoalesced would be ~#{moves} × per-move)"

    # The width IS applied immediately (cheap), but the expensive cell reflow must
    # be DEFERRED — the 20 moves must not each re-lay-out the grid; it happens once.
    matrix.get_col_width(3).should be > 5.0
    measures_during_moves.should eq(0)
    measures_one_frame.should be > 0
  end

  # PERF GATE: a column-resize frame must re-composite only the cells it changed
  # (the resized column + what it shifts), not EVERY visible cell. Before the fix the
  # resize marked the whole content layer dirty (mark_needs_clear_and_render), which
  # disables the per-slot skip so every visible cell touched the buffer each frame
  # (~127 re-rendered/re-blitted) → the 99% CPU. The fix reuses the content-layer
  # blit-shift (as scroll does) to translate the unchanged columns in one buffer copy,
  # so only the resized column's cells re-composite. Design: doc/plans/resize-blit-shift.md.
  #
  # We gate on the render-DISPOSITION oracle (TestRenderer#frame_dispositions), not on
  # frame_widgets_iterated: that counter is incremented at the TOP of render_single_widget
  # (before the per-slot skip), so it measures cells VISITED — a value other perf specs pin
  # to O(visible) — and it cannot fall below the visible-cell count no matter how cheap the
  # frame is. What actually collapses is the number of cells that TOUCH THE BUFFER:
  # :rendered (fresh primitives) + :blitted (cached re-blit). A shifted cell is :skipped.
  it "resize frame re-composites only the changed cells (blit-shift; was ~127, target <40)" do
    renderer, app, matrix = setup_resize_matrix
    total_cells = matrix.active_cells.size

    bx, by = col_border(matrix, 3)
    app.handle_mouse_down(CrymbleUI::Vec2.new(bx, by))
    app.handle_mouse_move(CrymbleUI::Vec2.new(bx + 30.0, by))

    CrymbleUI::Widget.reset_measure_count
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.render_frame(app) # the resize frame

    lr = CrymbleUI::LayerRenderer

    # Scope to the CONTENT-LAYER data cells (row/col past the sticky headers) — the grid the
    # blit-shift optimizes. Sticky-header + ruler layers re-render every resize frame independent
    # of this fix (their own blit-shift is a later increment), so a whole-frame count would fold in
    # that unrelated overhead. A cell that TOUCHED the buffer is :rendered (fresh) or :blitted (re-
    # blit); a translated cell is :skipped (its pixels were moved by the one buffer copy).
    sr = matrix.sticky_row_count
    sc = matrix.sticky_col_count
    data_cells = matrix.active_cells.select { |(r, c), _w| r >= sr && c >= sc }.values
    disp = ->(w : CrymbleUI::Widget) { renderer.widget_disposition(w) }
    data_recomposited = data_cells.count { |w| d = disp.call(w); d == :rendered || d == :blitted }
    data_skipped = data_cells.count { |w| disp.call(w) == :skipped }
    all = renderer.frame_dispositions.values
    puts "\n[resize frame] #{total_cells} active; #{data_cells.size} data cells: " \
         "recomposited=#{data_recomposited} skipped=#{data_skipped}; " \
         "measure=#{CrymbleUI::Widget.measure_count}; iterated=#{lr.frame_widgets_iterated}; " \
         "blit_shift=#{lr.frame_blit_shift_count}; " \
         "WHOLE-FRAME rendered=#{all.count(:rendered)} blitted=#{all.count(:blitted)} skipped=#{all.count(:skipped)}"

    # The blit-shift must actually run (not the clear fallback), and only the resized column's data
    # cells may re-composite — the columns it shifts are translated in one buffer copy (skipped),
    # far below the full-grid count.
    lr.frame_blit_shift_count.should be > 0
    data_recomposited.should be < 40
    data_skipped.should be > data_recomposited # most of the grid was translated, not re-composited

    # Guard the sticky-header translate: on a resize the sticky headers are BLITTED at their new positions
    # (via the per-layer blit-plan, now enabled during resize) instead of re-rendered — only the resized
    # line's own headers + the changed-axis ruler re-render, and ONLY the resized axis's sticky layer is
    # touched at all. Was ~53 whole-frame re-renders (full sticky clear), ~26 with the per-layer clear,
    # ~14 here (~10 content + the resized column's 2 sticky headers + the col ruler). A regression that
    # re-renders the sticky grid or wakes the unchanged-axis layer trips this.
    all.count(:rendered).should be < 20
  end

  # CORRECTNESS GATE for the blit-shift: the translated content must be pixel-identical
  # to a forced full re-composite of the same state. If the shift places pixels one column
  # off, clips a seam, or leaves a stale strip, this diverges from the ground truth.
  it "column WIDEN blit-shift matches a forced full re-render, pixel for pixel" do
    assert_col_resize_pixel_equivalent(30.0, "widen")
  end

  it "column SHRINK blit-shift matches a forced full re-render, pixel for pixel" do
    assert_col_resize_pixel_equivalent(-30.0, "shrink")
  end

  it "row TALLER blit-shift matches a forced full re-render, pixel for pixel" do
    assert_row_resize_pixel_equivalent(30.0, "row-taller")
  end

  it "row SHORTER blit-shift matches a forced full re-render, pixel for pixel" do
    assert_row_resize_pixel_equivalent(-15.0, "row-shorter")
  end

  it "STICKY-column widen blit-shifts the data area, pixel-identical to a full re-render" do
    assert_sticky_col_resize_pixel_equivalent(20.0, "sticky-col-widen")
  end

  it "STICKY-column shrink blit-shifts the data area, pixel-identical to a full re-render" do
    assert_sticky_col_resize_pixel_equivalent(-20.0, "sticky-col-shrink")
  end

  it "STICKY-row resize blit-shifts the data area, pixel-identical to a full re-render" do
    assert_sticky_row_resize_pixel_equivalent(15.0, "sticky-row-taller")
  end

  it "MERGED data cell straddling the boundary — WIDEN matches a full re-render" do
    assert_merged_col_resize_pixel_equivalent(30.0, "merged-widen")
  end

  it "MERGED data cell straddling the boundary — SHRINK matches a full re-render" do
    assert_merged_col_resize_pixel_equivalent(-20.0, "merged-shrink")
  end
end
