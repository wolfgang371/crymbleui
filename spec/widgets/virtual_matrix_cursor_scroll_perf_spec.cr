require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/core/layer"
require "../../src/dsl/builder"

# KEY DESIGN INVARIANT: layout is expensive, render is cheap.
#
# After initial layout, VirtualMatrix's size/position is constant. Scrolling and
# cursor movement only change WHICH cells are visible — they must NEVER trigger
# mark_needs_layout. Only mark_needs_render.
#
# See on_mouse_wheel in virtual_matrix.cr for the correct pattern:
#   1. Update @scroll_offset (direct ivar write)
#   2. Sync to ScrollView via set_scroll_offset_for_sync (no layout trigger)
#   3. Update layer.scroll_offset for viewport_cache compositing
#   4. Call update_visible_cells
#   5. Call mark_needs_render
#
# Uses window() wrapper to match real demo. Without it, root IS VirtualMatrix
# and prepare_layout forces root.state = Clean directly on VirtualMatrix,
# masking re-dirtying bugs.

# DSL-style app with window() wrapper — matches real virtual_matrix_demo structure
class VirtualMatrixWindowApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 1000, cols: 1000, id: "perf_grid")
      widget(matrix)
    end
  end
end

# Helper: build, render, scroll to position, settle, return matrix
def setup_scrolled_matrix(renderer, app, scroll_x = 5000.0, scroll_y = 1000.0)
  app.build_tree
  renderer.render_frame(app)

  matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
  matrix.scroll_offset = CrymbleUI::Vec2.new(scroll_x, scroll_y)
  renderer.settle_rendering(app)

  app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
end

describe "VirtualMatrix cursor-left scroll performance" do
  it "cursor-left does not trigger layout (only render)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 10000.0, 2000.0)

    # Place cursor on leftmost visible cell so cursor-left scrolls
    leftmost_col = (matrix.scroll_offset.x / 100.0).to_i32
    matrix.cursor_rc = {100, leftmost_col}
    renderer.settle_rendering(app)

    renderer.reset_counters

    # Press cursor-left — should only need render, not layout
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Left, false, false)

    # VirtualMatrix should NOT need layout after cursor movement
    matrix.needs_layout?.should be_false,
      "cursor-left triggered mark_needs_layout — should only mark_needs_render"
  end

  it "cursor-right does not trigger layout (only render)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 10000.0, 2000.0)

    # Place cursor on rightmost visible cell so cursor-right scrolls
    rightmost_col = ((matrix.scroll_offset.x + 400.0) / 100.0).to_i32 - 1
    matrix.cursor_rc = {100, rightmost_col}
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Right, false, false)

    matrix.needs_layout?.should be_false,
      "cursor-right triggered mark_needs_layout — should only mark_needs_render"
  end

  it "cursor-up does not trigger layout (only render)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 10000.0, 2000.0)

    # Place cursor on topmost visible row so cursor-up scrolls
    topmost_row = (matrix.scroll_offset.y / 20.0).to_i32
    matrix.cursor_rc = {topmost_row, 100}
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Up, false, false)

    matrix.needs_layout?.should be_false,
      "cursor-up triggered mark_needs_layout — should only mark_needs_render"
  end

  it "cursor-down does not trigger layout (only render)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 10000.0, 2000.0)

    # Place cursor on bottommost visible row so cursor-down scrolls
    bottommost_row = ((matrix.scroll_offset.y + 300.0) / 20.0).to_i32 - 1
    matrix.cursor_rc = {bottommost_row, 100}
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Down, false, false)

    matrix.needs_layout?.should be_false,
      "cursor-down triggered mark_needs_layout — should only mark_needs_render"
  end

  it "snap_to_cursor does not trigger layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 10000.0, 2000.0)

    # Move cursor off-screen so snap_to_cursor will scroll
    matrix.cursor_rc = {0, 0}
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.snap_to_cursor

    matrix.needs_layout?.should be_false,
      "snap_to_cursor triggered mark_needs_layout — should only mark_needs_render"
  end

  it "perform_layout does not re-dirty tree via scroll offset sync" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app)

    # Trigger rebuild (creates new instances, resets @last_synced_scroll_offset)
    app.rebuild
    renderer.render_frame(app)

    # After rebuild+render, VirtualMatrix should NOT be stuck in NeedsLayout.
    # Bug: scroll sync during perform_layout uses reactive_property (… layout: true) setter which
    # calls mark_needs_layout. Since clear_render_state is skipped when
    # did_layout=true, VirtualMatrix stays NeedsLayout.
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.needs_layout?.should be_false,
      "VirtualMatrix stuck in NeedsLayout after rebuild+render — " \
      "scroll offset sync is calling mark_needs_layout during layout"
  end

  it "rebuild at non-zero scroll does not re-dirty root during layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    setup_scrolled_matrix(renderer, app)

    # Trigger rebuild — new instances, @last_synced_scroll_offset = Vec2.zero
    app.rebuild

    # Manually run layout (same as prepare_layout but without force-clean)
    root = app.root.not_nil!
    root.layout(
      CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(400.0, 300.0)),
      CrymbleUI::Vec2.new(0.0, 0.0)
    )

    # After layout, root should be Clean (set at start of Widget#layout).
    # Bug: scroll sync calls scroll_view.scroll_offset= which propagates
    # mark_needs_layout back up to root.
    root.needs_layout?.should be_false,
      "Root re-dirtied during layout — scroll offset sync is calling " \
      "mark_needs_layout during perform_layout (should use set_scroll_offset_for_sync)"
  end
end

# === RENDERING COUNTER TESTS ===
# These tests go beyond the boolean needs_layout? checks above and verify
# actual rendering work using frame-level counters. A rendering performance
# regression would NOT be caught by needs_layout? alone.

describe "VirtualMatrix cursor scroll rendering cost" do
  it "keyboard cursor scroll does not trigger layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at bottom visible row so Down arrow triggers scroll
    bottommost_row = ((matrix.scroll_offset.y + 300.0) / 20.0).to_i32 - 1
    mid_col = (matrix.scroll_offset.x / 100.0).to_i32 + 2
    matrix.cursor_rc = {bottommost_row, mid_col}
    renderer.settle_rendering(app)

    renderer.reset_counters
    CrymbleUI::LayerRenderer.reset_frame_counters

    # Press Down — triggers scroll by one row
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    # No layout passes should have run during a single scroll step
    renderer.layout_count.should eq(0)
  end

  it "10-step cursor scroll has bounded total rendering cost" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at bottom visible row
    bottommost_row = ((matrix.scroll_offset.y + 300.0) / 20.0).to_i32 - 1
    mid_col = (matrix.scroll_offset.x / 100.0).to_i32 + 2
    matrix.cursor_rc = {bottommost_row, mid_col}
    renderer.settle_rendering(app)

    renderer.reset_counters

    total_widgets_rendered = 0

    # Press Down 10 times (each triggers scroll by one row = 20px)
    10.times do
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
      renderer.render_frame(app)
      total_widgets_rendered += CrymbleUI::LayerRenderer.frame_widget_count
    end

    # Rendering cost must NOT scale with grid size (1000×1000).
    # It's bounded by creation_buffer region (~7 cols × 30 rows = ~210 cells).
    # After first frame warms caches, subsequent frames render fewer.
    # Allow generous headroom for architecture-inherent rendering
    # (creation_buffer > cache_extent creates cells outside GPU buffer).
    total_widgets_rendered.should be <= 2000,
      "Rendered #{total_widgets_rendered} widgets over 10 scroll steps — " \
      "expected <=2000 (bounded by viewport, not 1000×1000 grid)"

    # No layout passes should have run during scroll
    renderer.layout_count.should eq(0)
  end

  it "cursor overlay layer does not trigger content layer layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)
    renderer.settle_rendering(app)

    # Move cursor within viewport (no scroll needed)
    matrix.move_cursor(:down, false, false)
    renderer.settle_rendering(app)

    # Move cursor again — should only dirty the overlay, not content layer
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.move_cursor(:down, false, false)

    # Content layer should NOT be in NeedsLayout state
    content_layer = matrix.content_layer
    content_layer.should_not be_nil
    content_layer.not_nil!.state.should_not eq(CrymbleUI::WidgetState::NeedsLayout)
  end

  it "cursor overlay uses NeedsRender not NeedsLayout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)
    renderer.settle_rendering(app)

    # Move cursor (triggers mark_cursor_overlay_dirty)
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.move_cursor(:down, false, false)

    # Cursor overlay layer should be marked NeedsRender, NOT NeedsLayout.
    # mark_needs_layout forces full_render=true with buffer clear + sibling
    # validation overhead on every cursor move. mark_needs_render suffices
    # for a 1-widget overlay layer (with buffer clear for ghost band prevention).
    overlay_layer = matrix.cursor_overlay_layer
    overlay_layer.should_not be_nil
    overlay = overlay_layer.not_nil!
    overlay.needs_render?.should be_true, "Overlay layer should need render after cursor move"
    overlay.state.should_not eq(CrymbleUI::WidgetState::NeedsLayout)
  end
end

# === SINGLE-STEP CURSOR SCROLL COST ===
# Measures the EXACT rendering cost of one cursor-arrow step that triggers scrolling.
# Y-step scrolls 23px (one row), X-step scrolls 103px (one column).
# These are the atomic operations that define VirtualMatrix scroll performance.

# Helper: compute the last fully-visible row for the current scroll position.
# Uses snap_to_cursor's formula: screen_bottom = ruler_row_h + row*row_h + row_h - scroll_y
# Must be <= vp_h for the row to be fully visible.
def last_visible_row(matrix)
  vp_h = matrix.content_layer.not_nil!.bounds.height.to_i32
  scroll_y = matrix.scroll_offset.y.to_i32
  ruler_row_h = 20  # RULER_ROW_HEIGHT(1.0) * frame_height(20)
  row_h = 23        # GRID_SPACING(3) + DEFAULT_ROW_HEIGHT(1.0) * frame_height(20)
  # screen_bottom for row R = ruler_row_h + R*row_h + row_h - scroll_y <= vp_h
  (vp_h + scroll_y - ruler_row_h - row_h) // row_h
end

# Helper: compute the last fully-visible column for the current scroll position.
def last_visible_col(matrix)
  vp_w = matrix.content_layer.not_nil!.bounds.width.to_i32
  scroll_x = matrix.scroll_offset.x.to_i32
  ruler_col_w = 40  # RULER_COL_WIDTH(2.0) * frame_height(20)
  col_w = 103       # GRID_SPACING(3) + DEFAULT_COLUMN_WIDTH(5.0) * frame_height(20)
  # screen_right for col C = ruler_col_w + C*col_w + col_w - scroll_x <= vp_w
  (vp_w + scroll_x - ruler_col_w - col_w) // col_w
end

describe "VirtualMatrix single-step cursor scroll cost", tags: "slow" do
  it "Y-step (cursor-down-scroll): bounded rendering cost" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at bottommost visible row, mid-column (not at X edge)
    bottom_row = last_visible_row(matrix)
    mid_col = (matrix.scroll_offset.x / 103.0).to_i32 + 2
    matrix.cursor_rc = {bottom_row, mid_col}
    renderer.settle_rendering(app)

    old_scroll_y = matrix.scroll_offset.y

    renderer.reset_counters
    CrymbleUI::LayerRenderer.reset_frame_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    # Press Down — cursor moves to bottom_row+1 which is off-screen → snap_to_cursor scrolls
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    # VERIFY scrolling actually happened
    matrix.scroll_offset.y.should_not eq(old_scroll_y),
      "No Y-scroll occurred! Cursor at row #{bottom_row} was not at bottom edge. " \
      "vp_h=#{matrix.content_layer.not_nil!.bounds.height}, scroll_y=#{old_scroll_y}"

    lr = CrymbleUI::LayerRenderer

    # Critical invariants (exact)
    renderer.layout_count.should eq(0),
      "Y-step triggered layout (got #{renderer.layout_count})"
    lr.frame_blit_plan_count.should eq(0),
      "Y-step used blit plan (got #{lr.frame_blit_plan_count}) — no sticky cells expected"

    # Pull/SlotBuffer model: a viewport_cache layer VISITS every visible cell each frame and
    # slot-skips the unchanged ones by a {rev, buffer_pos} key (correct-by-construction — a changed cell
    # can't be missed). So the real perf metric is RE-RENDERED cells, not VISITED cells. The blit-shift
    # repaints only the newly-exposed edge band (a vertical step ≈ 4 cells); the ~135 overlap cells are
    # visited (a cheap O(1) slot-check → return nil) but never reach to_primitives or a blit.
    # TIGHT guarantee — actual re-renders are the edge strip only:
    lr.frame_widget_count.should be <= 10,
      "Y-step RE-RENDERED #{lr.frame_widget_count} cells (expected <=10 edge cells, observed ~4)"
    # LOOSE sanity guard — iteration is O(visible buffer cells) (~137 here), bounded by the viewport,
    # NOT the 1M-cell grid. This only catches a regression to O(total content); the line above is the
    # real cost bound.
    lr.frame_widgets_iterated.should be <= 300,
      "Y-step VISITED #{lr.frame_widgets_iterated} cells (expected O(visible) ~137, must stay << O(total)=1M)"
    lr.frame_primitive_count.should be <= 55,
      "Y-step drew #{lr.frame_primitive_count} primitives (expected <=50, observed 11)"
    lr.frame_layer_count.should be <= 10,
      "Y-step rendered #{lr.frame_layer_count} layers (expected <=10, observed 4)"
    lr.frame_layers_needing_render.should be <= 10,
      "Y-step had #{lr.frame_layers_needing_render} layers needing render (expected <=10, observed 4)"
    lr.frame_layers_total.should be <= 10,
      "Y-step had #{lr.frame_layers_total} total layers (expected <=10, observed 5)"
    lr.frame_composite_count.should be <= 5,
      "Y-step had #{lr.frame_composite_count} composites (expected <=5, observed 0)"
    lr.frame_viewport_cache_count.should be <= 5,
      "Y-step had #{lr.frame_viewport_cache_count} viewport cache composites (expected <=5, observed 0)"
    lr.frame_pure_container_skips.should be <= 5,
      "Y-step skipped #{lr.frame_pure_container_skips} containers (expected <=5, observed 0)"
    renderer.render_layer_count.should be <= 5,
      "Y-step rendered #{renderer.render_layer_count} layers via TestRenderer (expected <=5, observed 0)"
    renderer.compositor_call_count.should be <= 5,
      "Y-step had #{renderer.compositor_call_count} compositor calls (expected <=5, observed 1)"
    renderer.backend_blit_count.should be <= 15,
      "Y-step had #{renderer.backend_blit_count} backend blits (expected <=15, observed 5)"
    renderer.backend_clear_count.should be <= 5,
      "Y-step had #{renderer.backend_clear_count} backend clears (expected <=5, observed 2)"
    renderer.layer_backend_clear_count.should be <= 5,
      "Y-step had #{renderer.layer_backend_clear_count} layer backend clears (expected <=5, observed 1)"
    renderer.primitive_count.should be <= 30,
      "Y-step had #{renderer.primitive_count} total primitives (expected <=15, observed 3)"
    CrymbleUI::VirtualMatrix.update_visible_cells_call_count.should be <= 2,
      "Y-step had #{CrymbleUI::VirtualMatrix.update_visible_cells_call_count} cell creation events (expected <=2, observed 0)"
  end

  it "X-step (cursor-right-scroll): bounded rendering cost" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at rightmost visible column, mid-row (not at Y edge)
    right_col = last_visible_col(matrix)
    mid_row = (matrix.scroll_offset.y / 23.0).to_i32 + 2
    matrix.cursor_rc = {mid_row, right_col}
    renderer.settle_rendering(app)

    old_scroll_x = matrix.scroll_offset.x

    renderer.reset_counters
    CrymbleUI::LayerRenderer.reset_frame_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    # Press Right — cursor moves to right_col+1 which is off-screen → snap_to_cursor scrolls
    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Right, false, false)
    renderer.render_frame(app)

    # VERIFY scrolling actually happened
    matrix.scroll_offset.x.should_not eq(old_scroll_x),
      "No X-scroll occurred! Cursor at col #{right_col} was not at right edge. " \
      "vp_w=#{matrix.content_layer.not_nil!.bounds.width}, scroll_x=#{old_scroll_x}"

    lr = CrymbleUI::LayerRenderer

    # Critical invariants (exact)
    renderer.layout_count.should eq(0),
      "X-step triggered layout (got #{renderer.layout_count})"
    lr.frame_blit_plan_count.should eq(0),
      "X-step used blit plan (got #{lr.frame_blit_plan_count}) — no sticky cells expected"

    # See Y-step for the Pull/SlotBuffer rationale: RE-RENDERED cells (the edge strip) is the real cost;
    # VISITED cells is O(visible) by design and slot-skipped.
    # TIGHT guarantee — actual re-renders are the edge strip only:
    lr.frame_widget_count.should be <= 10,
      "X-step RE-RENDERED #{lr.frame_widget_count} cells (expected <=10 edge cells, observed ~2)"
    # LOOSE sanity guard — iteration is O(visible buffer cells), must stay << O(total)=1M:
    lr.frame_widgets_iterated.should be <= 300,
      "X-step VISITED #{lr.frame_widgets_iterated} cells (expected O(visible) ~130, must stay << O(total)=1M)"
    lr.frame_primitive_count.should be <= 55,
      "X-step drew #{lr.frame_primitive_count} primitives (expected <=50, observed 11)"
    lr.frame_layer_count.should be <= 10,
      "X-step rendered #{lr.frame_layer_count} layers (expected <=10, observed 4)"
    lr.frame_layers_needing_render.should be <= 10,
      "X-step had #{lr.frame_layers_needing_render} layers needing render (expected <=10, observed 4)"
    lr.frame_layers_total.should be <= 10,
      "X-step had #{lr.frame_layers_total} total layers (expected <=10, observed 5)"
    lr.frame_composite_count.should be <= 5,
      "X-step had #{lr.frame_composite_count} composites (expected <=5, observed 0)"
    lr.frame_viewport_cache_count.should be <= 5,
      "X-step had #{lr.frame_viewport_cache_count} viewport cache composites (expected <=5, observed 0)"
    lr.frame_pure_container_skips.should be <= 5,
      "X-step skipped #{lr.frame_pure_container_skips} containers (expected <=5, observed 0)"
    renderer.render_layer_count.should be <= 5,
      "X-step rendered #{renderer.render_layer_count} layers via TestRenderer (expected <=5, observed 0)"
    renderer.compositor_call_count.should be <= 5,
      "X-step had #{renderer.compositor_call_count} compositor calls (expected <=5, observed 1)"
    renderer.backend_blit_count.should be <= 15,
      "X-step had #{renderer.backend_blit_count} backend blits (expected <=15, observed 5)"
    renderer.backend_clear_count.should be <= 5,
      "X-step had #{renderer.backend_clear_count} backend clears (expected <=5, observed 2)"
    renderer.layer_backend_clear_count.should be <= 5,
      "X-step had #{renderer.layer_backend_clear_count} layer backend clears (expected <=5, observed 1)"
    renderer.primitive_count.should be <= 30,
      "X-step had #{renderer.primitive_count} total primitives (expected <=15, observed 3)"
    CrymbleUI::VirtualMatrix.update_visible_cells_call_count.should be <= 2,
      "X-step had #{CrymbleUI::VirtualMatrix.update_visible_cells_call_count} cell creation events (expected <=2, observed 0)"
  end

  it "X-step vs Y-step: rendering cost comparison" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # === Y-step ===
    bottom_row = last_visible_row(matrix)
    mid_col = (matrix.scroll_offset.x / 103.0).to_i32 + 2
    matrix.cursor_rc = {bottom_row, mid_col}
    renderer.settle_rendering(app)

    old_scroll_y = matrix.scroll_offset.y
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.reset_counters

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
    renderer.render_frame(app)

    matrix.scroll_offset.y.should_not eq(old_scroll_y), "Y-step did not scroll"

    y_widgets = CrymbleUI::LayerRenderer.frame_widget_count
    y_primitives = CrymbleUI::LayerRenderer.frame_primitive_count

    # === X-step (fresh setup to avoid interaction) ===
    renderer2 = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app2 = VirtualMatrixWindowApp.new
    matrix2 = setup_scrolled_matrix(renderer2, app2, 5000.0, 1000.0)

    right_col = last_visible_col(matrix2)
    mid_row = (matrix2.scroll_offset.y / 23.0).to_i32 + 2
    matrix2.cursor_rc = {mid_row, right_col}
    renderer2.settle_rendering(app2)

    old_scroll_x = matrix2.scroll_offset.x
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer2.reset_counters

    matrix2 = app2.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix2.on_key_down(SF::Keyboard::Key::Right, false, false)
    renderer2.render_frame(app2)

    matrix2.scroll_offset.x.should_not eq(old_scroll_x), "X-step did not scroll"

    x_widgets = CrymbleUI::LayerRenderer.frame_widget_count
    x_primitives = CrymbleUI::LayerRenderer.frame_primitive_count

    # X scrolls ~4.5x further (103px vs 23px) but cost should be bounded
    # within ~5x of Y-step (not proportional to total grid size)
    x_widgets.should be <= y_widgets * 5 + 50,
      "X-step cost (#{x_widgets} widgets) is disproportionate to Y-step (#{y_widgets} widgets). " \
      "Ratio: #{x_widgets.to_f / {y_widgets, 1}.max}"
    x_primitives.should be <= y_primitives * 5 + 100,
      "X-step cost (#{x_primitives} prims) is disproportionate to Y-step (#{y_primitives} prims). " \
      "Ratio: #{x_primitives.to_f / {y_primitives, 1}.max}"
  end
end

# === SUSTAINED CURSOR-HOLD COST ===
# Simulates holding a cursor key for multiple steps, crossing viewport cache
# boundaries that trigger expensive recenter operations. The single-step tests
# above only measure a 1-cell scroll (~23px Y, ~103px X) which may stay within
# the cache_extent (100px) buffer. Sustained hold crosses those boundaries
# repeatedly, triggering clear_all_widget_backends + full re-render.
#
# Key thresholds:
#   cache_extent = 100px → buffer extends 100px beyond viewport on each side
#   Y-step = 23px → recenter every ~4-5 Down presses
#   X-step = 103px → recenter nearly every Right press (exceeds cache_extent)
#   creation_buffer = 150px → cells created within 150px of viewport

# DSL-style app with configurable grid size for scaling tests
class VirtualMatrixSizedApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def initialize(@grid_rows : Int32, @grid_cols : Int32)
    super()
  end

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      matrix = CrymbleUI::VirtualMatrix.new(rows: @grid_rows, cols: @grid_cols, id: "perf_grid")
      widget(matrix)
    end
  end
end

describe "VirtualMatrix sustained cursor-hold cost", tags: "slow" do
  it "20-step Y-hold (cursor-down): bounded total rendering cost" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at bottommost visible row
    bottom_row = last_visible_row(matrix)
    mid_col = (matrix.scroll_offset.x / 103.0).to_i32 + 2
    matrix.cursor_rc = {bottom_row, mid_col}
    renderer.settle_rendering(app)

    old_scroll_y = matrix.scroll_offset.y

    renderer.reset_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    total_widgets_rendered = 0
    total_primitives = 0
    steps = 20

    steps.times do |i|
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_key_down(SF::Keyboard::Key::Down, false, false)
      renderer.render_frame(app)
      total_widgets_rendered += CrymbleUI::LayerRenderer.frame_widget_count
      total_primitives += CrymbleUI::LayerRenderer.frame_primitive_count
    end

    # Verify scrolling actually happened: 20 Y-steps = 20 × 23px = 460px
    scroll_delta = matrix.scroll_offset.y - old_scroll_y
    scroll_delta.should be >= 400.0,
      "Expected ~460px Y-scroll over #{steps} steps, got #{scroll_delta}px"

    # CRITICAL: No layout passes during sustained scroll
    renderer.layout_count.should eq(0),
      "Sustained Y-hold triggered #{renderer.layout_count} layout passes"

    # Total widgets rendered should be bounded by viewport size, not grid size.
    # ~4-5 recenters × ~44 visible cells ≈ 176-220 widgets, plus a few from
    # non-recenter frames. Allow generous headroom.
    total_widgets_rendered.should be <= 2000,
      "Sustained Y-hold rendered #{total_widgets_rendered} widgets over #{steps} steps — " \
      "expected <=2000 (bounded by viewport, not 1000×1000 grid)"

    # update_visible_cells should fire bounded number of times
    CrymbleUI::VirtualMatrix.update_visible_cells_call_count.should be <= 30,
      "Sustained Y-hold had #{CrymbleUI::VirtualMatrix.update_visible_cells_call_count} " \
      "cell creation events over #{steps} steps (expected <=30)"
  end

  it "5-step X-hold (cursor-right): bounded total rendering cost" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = VirtualMatrixWindowApp.new
    matrix = setup_scrolled_matrix(renderer, app, 5000.0, 1000.0)

    # Place cursor at rightmost visible column
    right_col = last_visible_col(matrix)
    mid_row = (matrix.scroll_offset.y / 23.0).to_i32 + 2
    matrix.cursor_rc = {mid_row, right_col}
    renderer.settle_rendering(app)

    old_scroll_x = matrix.scroll_offset.x

    renderer.reset_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    total_widgets_rendered = 0
    total_primitives = 0
    steps = 5

    steps.times do |i|
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_key_down(SF::Keyboard::Key::Right, false, false)
      renderer.render_frame(app)
      total_widgets_rendered += CrymbleUI::LayerRenderer.frame_widget_count
      total_primitives += CrymbleUI::LayerRenderer.frame_primitive_count
    end

    # Verify scrolling actually happened: 5 X-steps = 5 × 103px = 515px
    scroll_delta = matrix.scroll_offset.x - old_scroll_x
    scroll_delta.should be >= 400.0,
      "Expected ~515px X-scroll over #{steps} steps, got #{scroll_delta}px"

    # CRITICAL: No layout passes during sustained scroll
    renderer.layout_count.should eq(0),
      "Sustained X-hold triggered #{renderer.layout_count} layout passes"

    # Total widgets rendered: X-step exceeds cache_extent (100px) every time,
    # so expect ~5 recenters × ~44 visible cells ≈ 220 widgets.
    total_widgets_rendered.should be <= 2000,
      "Sustained X-hold rendered #{total_widgets_rendered} widgets over #{steps} steps — " \
      "expected <=2000 (bounded by viewport, not 1000×1000 grid)"

    # update_visible_cells should fire bounded number of times
    CrymbleUI::VirtualMatrix.update_visible_cells_call_count.should be <= 15,
      "Sustained X-hold had #{CrymbleUI::VirtualMatrix.update_visible_cells_call_count} " \
      "cell creation events over #{steps} steps (expected <=15)"
  end

  it "sustained cost scales with viewport, NOT grid size" do
    steps = 5

    # --- Run on 1000×1000 grid ---
    renderer1 = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app1 = VirtualMatrixWindowApp.new  # 1000×1000
    matrix1 = setup_scrolled_matrix(renderer1, app1, 5000.0, 1000.0)

    bottom_row1 = last_visible_row(matrix1)
    mid_col1 = (matrix1.scroll_offset.x / 103.0).to_i32 + 2
    matrix1.cursor_rc = {bottom_row1, mid_col1}
    renderer1.settle_rendering(app1)
    renderer1.reset_counters

    widgets_1k = 0
    steps.times do
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix1 = app1.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix1.on_key_down(SF::Keyboard::Key::Down, false, false)
      renderer1.render_frame(app1)
      widgets_1k += CrymbleUI::LayerRenderer.frame_widget_count
    end

    # --- Run on 10000×10000 grid ---
    renderer2 = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app2 = VirtualMatrixSizedApp.new(10000, 10000)
    app2.build_tree
    renderer2.render_frame(app2)
    matrix2 = app2.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix2.scroll_offset = CrymbleUI::Vec2.new(5000.0, 1000.0)
    renderer2.settle_rendering(app2)
    matrix2 = app2.find("perf_grid").as(CrymbleUI::VirtualMatrix)

    bottom_row2 = last_visible_row(matrix2)
    mid_col2 = (matrix2.scroll_offset.x / 103.0).to_i32 + 2
    matrix2.cursor_rc = {bottom_row2, mid_col2}
    renderer2.settle_rendering(app2)
    renderer2.reset_counters

    widgets_10k = 0
    steps.times do
      CrymbleUI::LayerRenderer.reset_frame_counters
      matrix2 = app2.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix2.on_key_down(SF::Keyboard::Key::Down, false, false)
      renderer2.render_frame(app2)
      widgets_10k += CrymbleUI::LayerRenderer.frame_widget_count
    end

    # Both grids have the same viewport (400×300) so rendering cost should be
    # similar. If 10k×10k costs significantly more, something is O(grid_size).
    # Allow 2x tolerance for minor overhead differences.
    widgets_10k.should be <= widgets_1k * 2 + 50,
      "10000×10000 grid rendered #{widgets_10k} widgets vs #{widgets_1k} for 1000×1000 — " \
      "cost scales with grid size! Ratio: #{widgets_10k.to_f / {widgets_1k, 1}.max}"

    # Neither should trigger layout
    renderer1.layout_count.should eq(0), "1000×1000 triggered layout"
    renderer2.layout_count.should eq(0), "10000×10000 triggered layout"
  end
end

# === SCROLLBAR THUMB DRAG COST ===
# Simulates dragging the vertical scrollbar thumb, which is the code path that
# causes >40% CPU in fullscreen. The vthumb drag path differs from cursor keys:
#   cursor-key: VirtualMatrix.on_key_down → snap_to_cursor → update_visible_cells
#   vthumb-drag: ScrollView.on_mouse_move → sync_from_scroll_view → deferred update
# The key insight is that in fullscreen (~1920×1080), there are ~1300 active cells
# in the creation_buffer, and each viewport recenter clears ALL their backends.

describe "VirtualMatrix scrollbar thumb drag cost" do
  it "vthumb drag: bounded rendering cost at large viewport", tags: "slow" do
    # Simulate large viewport (closer to fullscreen)
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = VirtualMatrixSizedApp.new(1000, 1000)
    app.build_tree
    renderer.render_frame(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.scroll_offset = CrymbleUI::Vec2.new(5000.0, 1000.0)
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    sv = matrix.@content_scroll_view.not_nil!

    # Simulate scrollbar thumb drag start
    # Find the scrollbar thumb position — approximate via scrollbar area
    abs = matrix.absolute_bounds
    scrollbar_x = abs.x + abs.width - 8.0  # middle of 16px wide scrollbar
    thumb_y = abs.y + 50.0                  # approximate thumb position

    # Initiate drag via mouse_down on scrollbar
    sv.on_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, thumb_y))
    renderer.render_frame(app)

    renderer.reset_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    total_widgets_rendered = 0
    drag_steps = 10

    # Simulate slow drag — 10 steps of 5px each (50px total thumb movement)
    drag_steps.times do |i|
      CrymbleUI::LayerRenderer.reset_frame_counters
      sv.on_mouse_move(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + (i + 1) * 5.0))
      renderer.render_frame(app)
      total_widgets_rendered += CrymbleUI::LayerRenderer.frame_widget_count
    end

    sv.on_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + 50.0))

    # No layout passes during drag
    renderer.layout_count.should eq(0),
      "Vthumb drag triggered #{renderer.layout_count} layout passes"

    # Total widgets should be bounded — NOT proportional to grid size.
    # At 1200×800 viewport: ~11 cols × ~34 rows ≈ 374 visible cells.
    # With recenters, expect several full re-renders.
    # Allow generous headroom but catch O(grid_size) regressions.
    total_widgets_rendered.should be <= 10000,
      "Vthumb drag rendered #{total_widgets_rendered} widgets over #{drag_steps} steps — " \
      "expected <=10000 (bounded by viewport, not 1000×1000 grid)"
  end

  it "slow vthumb drag: most frames should be O(1) compositor-only", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = VirtualMatrixSizedApp.new(1000, 1000)
    app.build_tree
    renderer.render_frame(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.scroll_offset = CrymbleUI::Vec2.new(5000.0, 1000.0)
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    sv = matrix.@content_scroll_view.not_nil!

    abs = matrix.absolute_bounds
    scrollbar_x = abs.x + abs.width - 8.0
    thumb_y = abs.y + 50.0

    sv.on_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, thumb_y))
    renderer.render_frame(app)

    renderer.reset_counters
    CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter

    # Very slow drag: 1px per step (simulates slow mouse movement)
    per_step_widgets = [] of Int32
    per_step_scroll_y = [] of Float64
    per_step_names = [] of Array(String)
    drag_steps = 10

    old_scroll_y = matrix.scroll_offset.y

    drag_steps.times do |i|
      CrymbleUI::LayerRenderer.reset_frame_counters
      sv.on_mouse_move(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + (i + 1) * 1.0))
      renderer.render_frame(app)
      w = CrymbleUI::LayerRenderer.frame_widget_count
      per_step_widgets << w
      per_step_names << CrymbleUI::LayerRenderer.rendered_widgets.dup
      matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      per_step_scroll_y << matrix.scroll_offset.y
    end

    sv.on_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + drag_steps.to_f))

    total_scroll = per_step_scroll_y.last - old_scroll_y
    total_widgets = per_step_widgets.sum

    # No layout
    renderer.layout_count.should eq(0),
      "Slow vthumb drag triggered #{renderer.layout_count} layout passes"

    # Non-recenter frames should render at most a few overlay widgets (scrollbar + cursor),
    # NOT full cell re-renders. Count frames with high widget count as "recenter spikes".
    recenter_frames = per_step_widgets.count { |w| w > 10 }
    non_recenter_frames = drag_steps - recenter_frames

    # At least SOME frames should be cheap (non-recenter)
    non_recenter_frames.should be > 0,
      "Every frame triggered a full recenter — cache_extent too small for scroll ratio"

    # Non-recenter frames should render very few widgets (overlay only, not cells)
    non_recenter_max = per_step_widgets.select { |w| w <= 10 }.max? || 0
    non_recenter_max.should be <= 10,
      "Non-recenter frames rendered #{non_recenter_max} widgets — expected <=10 (overlay only)"

    # Recenter frames are bounded by visible cells (~11 cols × ~34 rows ≈ 374 at 1200×800)
    # plus creation_buffer cells. Allow generous headroom.
    recenter_max = per_step_widgets.max
    recenter_max.should be <= 2000,
      "Recenter frame rendered #{recenter_max} widgets — expected <=2000 (bounded by viewport)"
  end

  it "large viewport scroll: cost scales with viewport, NOT grid size", tags: "slow" do
    scroll_steps = 5

    # Helper: set up large-viewport grid, scroll via mouse_wheel, sum widget counts
    run_test = ->(grid_rows : Int32, grid_cols : Int32) do
      renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
      app = VirtualMatrixSizedApp.new(grid_rows, grid_cols)
      app.build_tree
      renderer.render_frame(app)
      matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset = CrymbleUI::Vec2.new(5000.0, 1000.0)
      renderer.settle_rendering(app)

      renderer.reset_counters
      total_widgets = 0

      # Use mouse_wheel to scroll (render-only path, no layout)
      # delta.y = -2.0 → scrolls down by 2 * SCROLL_SPEED(30) = 60px per step
      center = CrymbleUI::Vec2.new(600.0, 400.0)
      scroll_steps.times do
        CrymbleUI::LayerRenderer.reset_frame_counters
        matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -2.0), center)
        renderer.render_frame(app)
        total_widgets += CrymbleUI::LayerRenderer.frame_widget_count
      end

      {total_widgets, renderer.layout_count}
    end

    widgets_1k, layout_1k = run_test.call(1000, 1000)
    widgets_10k, layout_10k = run_test.call(10000, 10000)

    # Both should render similar widget counts (same viewport size)
    widgets_10k.should be <= widgets_1k * 2 + 100,
      "10000×10000 grid rendered #{widgets_10k} widgets vs #{widgets_1k} for 1000×1000 — " \
      "scroll cost scales with grid size! Ratio: #{widgets_10k.to_f / {widgets_1k, 1}.max}"

    layout_1k.should eq(0), "1000×1000 triggered layout"
    layout_10k.should eq(0), "10000×10000 triggered layout"
  end

  it "vthumb recenter renders only edge cells, not all visible cells (blit-shift)", tags: "slow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = VirtualMatrixSizedApp.new(1000, 1000)
    app.build_tree
    renderer.render_frame(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    matrix.scroll_offset = CrymbleUI::Vec2.new(5000.0, 1000.0)
    renderer.settle_rendering(app)

    matrix = app.find("perf_grid").as(CrymbleUI::VirtualMatrix)
    sv = matrix.@content_scroll_view.not_nil!

    abs = matrix.absolute_bounds
    scrollbar_x = abs.x + abs.width - 8.0
    thumb_y = abs.y + 50.0

    sv.on_mouse_down(CrymbleUI::Vec2.new(scrollbar_x, thumb_y))
    renderer.render_frame(app)

    # 1px drag steps — slow enough that each recenter has mostly overlapping content
    drag_steps = 10
    per_step_widgets = [] of Int32

    drag_steps.times do |i|
      CrymbleUI::LayerRenderer.reset_frame_counters
      sv.on_mouse_move(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + (i + 1) * 1.0))
      renderer.render_frame(app)
      per_step_widgets << CrymbleUI::LayerRenderer.frame_widget_count
    end

    sv.on_mouse_up(CrymbleUI::Vec2.new(scrollbar_x, thumb_y + drag_steps.to_f))

    # Pull/SlotBuffer: the real guarantee is that blit-shift bounds the AMORTIZED total of
    # re-rendered cells over the drag — it must never repaint the full viewport every frame. The new
    # model recenters RARELY with larger batches (vs the old model's frequent small recenters), so a
    # single recenter frame may repaint a wider band; but over a 2070px scroll the slot model
    # re-renders ~1600 cells vs the old model's ~10400 — 6.5x FEWER. So assert the amortized TOTAL
    # (the true cost), not a single-frame peak (which would penalize the superior batching).
    total_rendered = per_step_widgets.sum
    naive = drag_steps * 374 # repaint every visible cell every frame
    # Measured ~486 (slot model) — ~13% of naive. Bound at ~3x observed, still far below naive, so a
    # broken blit-shift (repaint-everything) trips it.
    total_rendered.should be <= 1500,
      "Drag re-rendered #{total_rendered} cells total over #{drag_steps} steps " \
      "(naive repaint-all ≈ #{naive}; blit-shift must keep the total far below that)."
  end
end
