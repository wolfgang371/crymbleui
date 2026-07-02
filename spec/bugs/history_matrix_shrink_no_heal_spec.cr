require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/tree_node"
require "../../src/widgets/checkbox"
require "../../src/widgets/combo_box"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/simple_matrix"
require "../../src/dsl/builder"

# Reproduction of the user-reported embrace bug:
#
#   "Beim Verändern der Fenstergrößen der Shapes ... Am krassesten ist, wenn die
#    History Selection geöffnet ist und das Fenster ganz schmal gezogen wird.
#    Dann bekommt man Müll angezeigt. Das heilt sich dann auch nicht mehr aus.
#    Auf der Shell sehe ich dann auch Warnungen zu Arithmetic overflow."
#
# Root cause (CrymbleUI, general flaw): VirtualMatrix#measure with
# shrink_to_content=true DESTRUCTIVELY mutates @col_widths:
#
#   if constraints.max_width.finite? && intrinsic_w > constraints.max_width
#     scale = constraints.max_width / intrinsic_w
#     @col_widths = @col_widths.map { |w| w * scale }   # <-- side effect in a query
#     ...
#   end
#
# Three independent defects flow from this single line:
#   (1) measure() is NON-IDEMPOTENT: each call shrinks columns again, and a
#       layout pass calls measure() multiple times (TreeNode#measure, then
#       VirtualMatrix#perform_layout). Columns shrink far past "fit".
#   (2) The shrink is ONE-DIRECTIONAL and PRESERVED across reconciliation
#       (copy_state_from copies old.@col_widths when grid dims are unchanged),
#       so widening the panel never restores the columns -> "heilt nicht aus".
#   (3) `scale` is unguarded against a non-positive max_width, so a negative
#       available width yields NEGATIVE column widths -> negative content
#       dimensions -> `.to_u32` "Arithmetic overflow" in the SFML backend.
#
# This is "something special about the history section": it is the embedded
# shrink_to_content matrix (the matrix() DSL sugar) inside a width-constraining
# tree_node — the only place that drives the destructive scale path.
#
# These tests assert the CORRECT behaviour and therefore FAIL until the flaw
# is fixed (they reproduce the bug; they are not regression-green yet).

# Test-only window into the (protected) internal column widths.
class CrymbleUI::VirtualMatrix
  def test_col_widths : Array(Float64)
    @col_widths.dup
  end

  def test_col_pixel_widths : Array(Float64)
    (0...@cols).map { |c| col_width_pixels(c) }
  end

  def test_max_scroll_x : Float64
    max_content_scroll_x
  end
end

# Mirrors core/src/gui/embrace.cr build_history_section: a tree_node (expanded —
# per the user's note that the bug shows when History Selection is open)
# containing the Branch hstack and a shrink_to_content matrix(max_height: 200).
class HistoryReproApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Test", 1200, 800) do
      window_panel("Shape", x: 50.0, y: 50.0, width: 1000.0, height: 700.0,
                   resizable: true, id: "panel") do
        vstack(spacing: 5.0, padding: 5.0) do
          tree_node("History selection", expanded: true, id: "history") do
            hstack(spacing: 5.0) do
              text("Branch:")
              combo_box(items: ["Branch 001", "Branch 002", "Branch 003"],
                        selected: 0, width: 120.0, id: "branch")
              button("<", padding: 3.0) { }
              text("1/3 (open)")
              button(">", padding: 3.0) { }
              button("Commit!", padding: 3.0) { }
              button("Show changes", padding: 3.0) { }
            end
            matrix(id: "changes", max_height: 200.0) do |m|
              m.header "", "Table", "Records", "Fields", "Cells", ""
              8.times do |i|
                m.row do |r|
                  r << CrymbleUI::Checkbox.new(text: "", checked: true,
                    id: "chk_#{i}").as(CrymbleUI::Widget)
                  r.text("Table number #{i}")
                  r.text("+#{i}")
                  r.text("+#{i}")
                  r.text("#{i * 3}")
                  r << CrymbleUI::Button.new("→ Shape", padding: 3.0,
                    id: "to_shape_#{i}").as(CrymbleUI::Widget)
                end
              end
            end
          end
        end
      end
    end
  end
end

# Mimic the SFML event loop: a mouse event that dirties the tree triggers a
# rebuild (new widget instances + reconciliation), exactly like the real app.
private def pump(app, renderer)
  if (root = app.root) && (root.needs_layout? || root.needs_render?)
    app.rebuild
  end
  renderer.render_frame(app)
end

# Drag the panel's right edge to `target_w` in small steps (like a real drag).
private def drag_panel_width(app, renderer, target_w : Float64, steps = 30)
  panel = app.find("panel").as(CrymbleUI::WindowPanel)
  ry = panel.y + panel.height / 2.0
  app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ry))
  pump(app, renderer)
  start_w = panel.width
  steps.times do |i|
    w = start_w + (target_w - start_w) * (i + 1) / steps
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + w, ry))
    pump(app, renderer)
  end
  app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x + target_w, ry))
  pump(app, renderer)
end

describe "History Selection matrix: shrink_to_content destructive measure" do
  it "measure() is idempotent at a fixed width (does not keep shrinking columns)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    constraints = CrymbleUI::BoxConstraints.new(
      min_width: 0.0, max_width: 120.0,
      min_height: 0.0, max_height: 200.0)

    vm.measure(constraints)
    after_first = vm.test_col_widths
    vm.measure(constraints)
    after_second = vm.test_col_widths

    # measure() is a query: measuring the same constraints twice must be stable.
    after_second.should eq(after_first)
  end

  it "the embedded history table re-expands after the Shape panel is widened again" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    baseline_width = vm.bounds.width
    baseline_width.should be > 300.0 # sanity: table is wide to start

    # Drag the panel narrow (down to the 100px clamp), then wide again.
    drag_panel_width(app, renderer, 100.0)
    drag_panel_width(app, renderer, 1000.0)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    # With the panel wide again, the table should once more use the available
    # width. The bug leaves it stuck at a collapsed sliver ("Müll, heilt nicht").
    vm.bounds.width.should be > 300.0
  end

  it "a maximized Shape never produces a negative content area when the window is narrowed" do
    app = HistoryReproApp.new
    app.build_tree
    r0 = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    r0.settle_rendering(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    panel.toggle_maximize
    app.root.try &.mark_needs_layout
    r0.settle_rendering(app)

    # OS window dragged very narrow (SFML Resized has no min clamp; a maximized
    # panel re-fits with no clamp either). content_width = width - 2*PADDING.
    narrow = CrymbleUI::Testing::TestRenderer.new(5, 800)
    app.root.try &.mark_needs_layout
    narrow.render_frame(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    content_padding = 8.0 # WindowPanel::CONTENT_PADDING
    content_width = panel.width - content_padding * 2

    # A negative content width is what feeds `.to_u32` in the SFML backend and
    # produces the "Arithmetic overflow" warnings on the shell.
    content_width.should be >= 0.0
  end

  it "clips (keeps columns at readable natural width) instead of scaling them to slivers when narrow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    wide_cols = vm.test_col_pixel_widths
    wide_cols.sum.should be > 100.0 # sanity

    # X: a free-floating panel now FLOORS at its content width, so the matrix can be forced
    # narrower than its content only at the WINDOW boundary — maximize into a window narrower than the
    # content (constrain_to_window_bounds is below the floor by design). The clip-not-scale behaviour is
    # what we verify there.
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    panel.toggle_maximize
    app.root.try &.mark_needs_layout
    narrow = CrymbleUI::Testing::TestRenderer.new(300, 800) # window narrower than the ~471px content
    app.root.try &.mark_needs_layout
    narrow.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    narrow_cols = vm.test_col_pixel_widths

    # Columns keep their natural, readable width — they are NOT scaled down
    # into unreadable slivers ("Müll"). The matrix simply clips.
    narrow_cols.each_with_index do |w, i|
      w.should be_close(wide_cols[i], 0.5)
    end

    # Clipping really happens: the matrix is narrower than its column content.
    vm.bounds.width.should be < narrow_cols.sum

    # Clip — NOT a horizontal scrollbar (no horizontal scroll region).
    vm.test_max_scroll_x.should eq(0.0)
    sv = vm.content_scroll_view.not_nil!
    sv.content_size.width.should be <= vm.bounds.width + 1.0
  end

  it "matrix content layer never gets a negative size mid-resize-drag (Arithmetic overflow source)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    ry = panel.y + panel.height / 2.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ry))
    app.rebuild if app.root.try(&.needs_layout?)
    renderer.render_frame(app)

    # Drag the right edge inward in steps; sample the content layer mid-drag
    # (before mouse-up). The ancestor-resize clamp must never hand the backend
    # a negative dimension (→ .to_u32 "Arithmetic overflow" in SFML).
    min_layer_w = Float64::MAX
    [800.0, 500.0, 250.0, 120.0].each do |target|
      app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + target, ry))
      app.rebuild if app.root.try { |rt| rt.needs_layout? || rt.needs_render? }
      renderer.render_frame(app)
      vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
      lw = vm.content_layer.try(&.bounds.width) || 0.0
      min_layer_w = Math.min(min_layer_w, lw)
    end
    app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x + 120.0, ry))

    min_layer_w.should be >= 0.0
  end

  it "does not shrink the History matrix while the panel is still wider than it (mid-drag)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    natural_w = vm.content_layer.not_nil!.bounds.width
    natural_w.should be > 200.0 # sanity: matrix is comfortably wide

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    ry = panel.y + panel.height / 2.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ry))
    app.rebuild if app.root.try(&.needs_layout?)
    renderer.render_frame(app)

    # Drag the right edge inward to a width that is STILL much wider than the
    # matrix's content. The matrix must NOT shrink yet — it should only clip
    # once the panel's content edge actually reaches the table ("vanishing
    # line"), not the moment the drag starts.
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + 700.0, ry))
    app.rebuild if app.root.try { |rt| rt.needs_layout? || rt.needs_render? }
    renderer.render_frame(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    mid_w = vm.content_layer.not_nil!.bounds.width
    mid_w.should be_close(natural_w, 5.0)

    app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x + 700.0, ry))
  end

  it "keeps the sticky header as wide as the data while the panel is still wide (mid-drag)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    ry = panel.y + panel.height / 2.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ry))
    app.rebuild if app.root.try(&.needs_layout?)
    renderer.render_frame(app)

    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + 700.0, ry))
    app.rebuild if app.root.try { |rt| rt.needs_layout? || rt.needs_render? }
    renderer.render_frame(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    content_w = vm.content_layer.not_nil!.bounds.width
    sticky = vm.content_scroll_view.not_nil!.sticky_row_layer.not_nil!
    # The header row spans the same columns as the data; it must not over-shrink
    # (clip to "Ta…") while the data rows stay full width.
    sticky.bounds.width.should be_close(content_w, 5.0)

    app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x + 700.0, ry))
  end

  it "matrix height does not change with panel width (no phantom horizontal scrollbar)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
    app = HistoryReproApp.new
    app.build_tree
    renderer.settle_rendering(app)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    wide_h = vm.content_layer.not_nil!.bounds.height

    # Narrow the panel WIDTH only (height unchanged), then release (re-layout).
    drag_panel_width(app, renderer, 200.0)

    vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
    narrow_h = vm.content_layer.not_nil!.bounds.height

    # A horizontally clipped matrix has no horizontal scrollbar, so narrowing
    # the width must NOT steal 16px of height for a phantom scrollbar (which
    # made rows appear/disappear when the panel was merely widened/narrowed).
    narrow_h.should be_close(wide_h, 1.0)
  end
end
