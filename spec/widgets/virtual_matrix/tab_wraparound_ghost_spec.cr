require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/text_input"
require "../../../src/widgets/button"
require "../../../src/testing/test_renderer"

# Tab/Shift+Tab wrapping around a VirtualMatrix in a SCROLLING (partial)
# viewport must not leave a ghost QuickEntry select-all highlight + caret on the
# cells the cursor swept through but no longer occupies. Only the cursor cell may
# show that edit decoration.
#
# Root cause: a proxy-focused QuickEntry cell bakes the highlight+caret into its
# per-widget cache; deactivate_proxy_focus only mark_needs_render's, and that
# transient flag is cleared by a later layout pass before the now-off-buffer cell
# re-renders during the wraparound scroll → the stale cached texture is fast-path
# blitted when the cell scrolls back into view. Fix: deactivate_proxy_focus clears
# @pending_replace and invalidate_primitive_cache (a persistent signal).
#
# These are GUI-behaviour tests: they drive Tab through the REAL dispatch
# (press_tab -> FocusManager), render each step, then assert on the cells' rendered
# textures (widget_backend pixels) — what the user actually sees — not internal flags.

private class GhostMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    20
  end

  def col_count : Int32
    5
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

# True if the cell's cached texture contains the QuickEntry select-all highlight
# color. Reads the widget's OWN backend (where input_selection is stored verbatim,
# unblended) and matches it exactly — never the composited window (which blends).
private def cell_shows_highlight?(widget : CrymbleUI::Widget) : Bool
  backend = widget.widget_backend
  return false unless backend.is_a?(CrymbleUI::Testing::TestRenderBackend)
  return false if backend.width <= 0 || backend.height <= 0
  sel = CrymbleUI::Theme.current.input_selection
  backend.get_pixels(0, 0, backend.width, backend.height).any? do |c|
    c.r == sel.r && c.g == sel.g && c.b == sel.b
  end
end

# VISIBLE (in-viewport) non-cursor cells whose cached texture shows the highlight.
private def visible_ghosts(matrix : CrymbleUI::VirtualMatrix) : Array(Tuple(Int32, Int32))
  vis = matrix.visible_cell_indices
  ghosts = [] of Tuple(Int32, Int32)
  vis[:rows].each do |r|
    vis[:cols].each do |c|
      next if {r, c} == matrix.cursor_rc
      w = matrix.active_cells[{r, c}]?
      ghosts << {r, c} if w && cell_shows_highlight?(w)
    end
  end
  ghosts
end

private def build_scrolling_matrix
  matrix = CrymbleUI::VirtualMatrix.new(GhostMatrixAdapter.new, id: "m")
  sibling = CrymbleUI::Button.new("Sibling", id: "sibling") { }
  root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
  root.add_child(matrix)
  root.add_child(sibling)

  renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
  app = TestApp.new
  app.root_widget = root
  app.build_tree
  root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)

  CrymbleUI::Widget.focus_manager.focus(matrix)
  matrix.cursor_rc = {0, 0}
  renderer.render_frame(app)

  {app, matrix, renderer}
end

describe "VirtualMatrix Tab-wraparound ghost highlight" do
  it "leaves no ghost highlight on swept cells after forward Tab then scroll-back" do
    app, matrix, renderer = build_scrolling_matrix

    # Sweep forward (scrolls the partial view down), then retreat (scrolls swept
    # cells back into view) — the gesture that strands stale cached textures.
    60.times { press_tab(app); renderer.render_frame(app) }
    20.times { press_tab(app, shift: true); renderer.render_frame(app) }
    renderer.settle_rendering(app)

    # Preconditions: the view genuinely scrolled (partial view) and there are
    # visible non-cursor cells to inspect (guards against a vacuous pass).
    matrix.scroll_offset.y.should be > 0.0
    vis = matrix.visible_cell_indices
    (vis[:rows].size * vis[:cols].size).should be > 1

    visible_ghosts(matrix).should eq([] of Tuple(Int32, Int32))
  end

  it "still shows the highlight on the cursor cell (positive control)" do
    app, matrix, renderer = build_scrolling_matrix
    60.times { press_tab(app); renderer.render_frame(app) }
    20.times { press_tab(app, shift: true); renderer.render_frame(app) }
    renderer.settle_rendering(app)

    cursor_cell = matrix.active_cells[matrix.cursor_rc]?
    cursor_cell.should_not be_nil
    cell_shows_highlight?(cursor_cell.not_nil!).should be_true
  end

  it "leaves no ghost highlight after Shift+Tab backward wrap" do
    app, matrix, renderer = build_scrolling_matrix

    # Shift+Tab from {0,0} wraps to the last cell, sweeping backward through scroll;
    # then Tab forward brings swept cells back into view.
    40.times { press_tab(app, shift: true); renderer.render_frame(app) }
    20.times { press_tab(app); renderer.render_frame(app) }
    renderer.settle_rendering(app)

    matrix.scroll_offset.y.should be > 0.0
    visible_ghosts(matrix).should eq([] of Tuple(Int32, Int32))
  end

  it "deactivate_proxy_focus tears down the QuickEntry edit state and cache" do
    cell = CrymbleUI::TextInput.new(value: "value", mode: CrymbleUI::TextInputMode::QuickEntry)
    cell.activate_proxy_focus
    cell.pending_replace.should be_true
    cell.get_primitives(CrymbleUI::Rect.new(0.0, 0.0, 60.0, 20.0)) # populate primitive cache
    cell.has_valid_primitive_cache?.should be_true

    cell.deactivate_proxy_focus
    cell.pending_replace.should be_false           # no leaked pending-replace
    cell.has_valid_primitive_cache?.should be_false # cache dropped → repaints clean
  end

  it "carries the cleared pending_replace across reconciliation" do
    # pending_replace is a reconcile_property; a deactivated cell must hand the
    # new instance false (not the old leaked true) on rebuild.
    old = CrymbleUI::TextInput.new(value: "value", mode: CrymbleUI::TextInputMode::QuickEntry)
    old.activate_proxy_focus
    old.deactivate_proxy_focus

    fresh = CrymbleUI::TextInput.new(value: "value", mode: CrymbleUI::TextInputMode::QuickEntry)
    fresh.copy_state_from(old)
    fresh.pending_replace.should be_false
  end

  it "does not invalidate untouched cells on a cursor move (perf)" do
    app, matrix, renderer = build_scrolling_matrix
    renderer.settle_rendering(app)

    # One in-viewport cursor move repaints only the leaving + arriving cells (plus
    # the cursor overlay), NOT the whole viewport. A viewport-wide invalidation
    # (~15 cells) would blow this primitive bound.
    renderer.reset_counters
    press_tab(app)
    renderer.render_frame(app)
    {% unless flag?(:cache_validation) %}
      # Under -Dcache_validation the validator does a 2nd ground-truth render per frame,
      # inflating primitive_count — perf-counter assertions are meaningless in that mode.
      renderer.primitive_count.should be < 100
    {% end %}
  end
end
