require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/testing/configurable_matrix_adapter"

# HOT-PATH TREE-WALK PERF AUDIT (measurement, not a pass/fail contract).
#
# After the viewport_cache per-frame re-render bug was fixed, an audit flagged OTHER
# "O(total-widget) walk on a hot frame" suspects. This spec PROVES + SIZES each one by
# scaling the CONTENT (widget/row count) between a "small" and a "big" setup and reading
# a deterministic visit counter added at each walk site. If visits ~double when content
# doubles → the walk is O(content); if visits stay flat → O(1).
#
# It PRINTS a table (does not assert), so it always "passes"; read the printed rows.

# ---------- generic leaf/root widgets for the DnD (A5) tree ----------
private class PerfFiller < CrymbleUI::Widget
  def initialize(id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(10.0, 10.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(10.0, 10.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class PerfDraggable < CrymbleUI::Widget
  include CrymbleUI::Draggable

  def initialize(id : String? = nil)
    super(id: id)
  end

  def get_drag_data : CrymbleUI::DragData?
    CrymbleUI::TextDragData.new("x")
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(20.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(20.0, 20.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class PerfDropTarget < CrymbleUI::Widget
  include CrymbleUI::DropTarget

  def initialize(id : String? = nil)
    super(id: id)
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    data.data_type == "text"
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(20.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(20.0, 20.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class PerfRoot < CrymbleUI::Widget
  def initialize
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(2000.0, 2000.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(2000.0, 2000.0))
    x = 0.0
    @children.each do |ch|
      ch.perform_layout(constraints, CrymbleUI::Vec2.new(x, 0.0))
      x += 12.0
    end
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# ---------- setup helpers ----------

# A Window with `n_panels` WindowPanels, each holding a VirtualMatrix (real, virtualized cells).
private def matrix_panel_app(n_panels : Int32) : {CrymbleUI::App, Array(CrymbleUI::WindowPanel)}
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 1400, 950)
  panels = [] of CrymbleUI::WindowPanel
  n_panels.times do |i|
    p = CrymbleUI::WindowPanel.new("P#{i}", 30.0 + i * 360.0, 120.0, 340.0, 700.0, id: "P#{i}")
    p.add_child(CrymbleUI::VirtualMatrix.new(
      adapter: ConfigurableMatrixAdapter.new(1, 1, 2, 2, 10, 5), id: "m#{i}"))
    window.add_child(p)
    panels << p
  end
  app.root_widget = window
  {app, panels}
end

# A plain ScrollView with `n` Buttons in a VStack.
private def scrollview_app(n : Int32) : {CrymbleUI::App, CrymbleUI::ScrollView}
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 600, 400)
  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv")
  vstack = CrymbleUI::VStack.new(spacing: 2.0)
  n.times { vstack.add_child(CrymbleUI::Button.new("B") { }) }
  sv.set_content(vstack)
  window.add_child(sv)
  app.root_widget = window
  {app, sv}
end

# A single WindowPanel (CONSTANT panel count) holding `n_buttons` Buttons in a VStack — for
# the A1/A2 registry-lookup assertions below. Scales NON-PANEL content only: a WindowPanel/Popup
# registry lookup is O(#panels × depth), so this must stay flat as n_buttons grows, whereas the
# old collect_panels_recursive/collect_popups_recursive walk visited every Button too (O(content)).
private def panel_buttons_app(n_buttons : Int32) : {CrymbleUI::App, CrymbleUI::WindowPanel}
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 1400, 950)
  panel = CrymbleUI::WindowPanel.new("P", 30.0, 120.0, 340.0, 700.0, id: "P")
  vstack = CrymbleUI::VStack.new(spacing: 2.0)
  n_buttons.times { |i| vstack.add_child(CrymbleUI::Button.new("B#{i}") { }) }
  panel.add_child(vstack)
  window.add_child(panel)
  app.root_widget = window
  {app, panel}
end

# A single WindowPanel + VirtualMatrix with `lrs` leaf rows (total rows = 1 + lrs) but a
# small, fixed viewport — so visible cells stay constant while TOTAL rows scale.
private def resize_matrix_app(lrs : Int32) : {CrymbleUI::App, CrymbleUI::VirtualMatrix}
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 800, 600)
  panel = CrymbleUI::WindowPanel.new("P", 40.0, 40.0, 500.0, 400.0, id: "P")
  m = CrymbleUI::VirtualMatrix.new(
    adapter: ConfigurableMatrixAdapter.new(0, 0, 1, 1, lrs, 3), id: "m")
  panel.add_child(m)
  window.add_child(panel)
  app.root_widget = window
  {app, m}
end

# ---------- table formatting ----------
private def audit_row(interaction : String, counter : String, small : Int32, big : Int32)
  if small == 0 && big == 0
    ratio_s = "n/a"
    verdict = "NOT TRIGGERED (0/0)"
  elsif small == 0
    ratio_s = "inf"
    verdict = "big-only (small=0)"
  else
    ratio = big.to_f / small.to_f
    ratio_s = ratio.round(2).to_s
    verdict = if ratio >= 1.6
                "O(n) content"
              elsif ratio <= 1.3
                "O(1)"
              else
                "~#{ratio.round(2)}x (partial?)"
              end
  end
  puts "%-16s | %-24s | %10d | %10d | %7s | %s" % [interaction, counter, small, big, ratio_s, verdict]
end

# Content-independence ratio for an ASSERTION (not just the printed table): big/small, with
# 0/0 treated as perfectly flat (1.0) — a registry lookup over zero registered panels/popups
# is still O(1), it just has nothing to report. Only small==0 < big>0 is the genuinely
# pathological "appeared from nowhere" case, which should not occur here.
private def content_independence_ratio(small : Int32, big : Int32) : Float64
  return 1.0 if small.zero? && big.zero?
  return Float64::INFINITY if small.zero?
  big.to_f / small.to_f
end

describe "hot-path tree-walk perf audit" do
  it "measures per-frame walk visit counts at two content sizes" do
    puts ""
    puts "=" * 108
    puts "HOT-PATH TREE-WALK PERF AUDIT  (visits per measured frame/op; O(n) => scales with content)"
    puts "=" * 108
    puts "%-16s | %-24s | %10s | %10s | %7s | %s" % ["interaction", "counter", "small", "big", "ratio", "O(1)? / O(n)?"]
    puts "-" * 108

    # ============================ A1 — idle & drag (panel walk) ============================
    # CONSTANT panel count (exactly 1 WindowPanel) — small=50 vs big=100 Buttons in a VStack
    # INSIDE that one panel scales the NON-PANEL content only. A panel-registry lookup is
    # O(#panels × depth): with #panels pinned at 1, panel_walk_visits must stay flat as the
    # button count doubles. Pre-fix (collect_panels_recursive walks the whole tree every frame,
    # idle or dragging) this scales with content instead (ratio ~2.0) — RED. NOT scaling panel
    # count (that would leave the post-fix registry cost at ratio 2.0 = #panels, the wrong
    # axis) and NOT VirtualMatrix rows (VirtualMatrix virtualizes: more rows add 0 nodes).
    {"A1 idle" => :idle, "A1 drag" => :drag}.each do |label, mode|
      results = [] of Int32
      [50, 100].each do |n|
        # Clear leaked orphans from earlier builds in this same example (registry lifetime
        # is process-wide; a stale orphan from a previous iteration must not inflate counts).
        CrymbleUI::WindowPanel.clear_registry
        CrymbleUI::Popup.clear_registry
        renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
        app, panel = panel_buttons_app(n)
        renderer.settle_rendering(app)

        if mode == :idle
          CrymbleUI::Widget.reset_panel_walk_visits
          renderer.render_frame(app)
          results << CrymbleUI::Widget.panel_walk_visits
        else # drag the (only) panel by its title bar
          renderer.mouse_down(panel.x + 60.0, panel.y + 10.0)
          renderer.render_frame(app)
          CrymbleUI::Widget.reset_panel_walk_visits
          renderer.mouse_move(panel.x + 100.0, panel.y + 10.0)
          renderer.render_frame(app)
          results << CrymbleUI::Widget.panel_walk_visits
          renderer.mouse_up(panel.x + 100.0, panel.y + 10.0)
        end
      end
      audit_row(label, "panel_walk_visits", results[0], results[1])
      ratio = content_independence_ratio(results[0], results[1])
      ratio.should be <= 1.3,
        "#{label}: panel_walk_visits scaled with NON-PANEL content (#{results[0]} -> #{results[1]}, " \
        "ratio #{ratio.round(2)}) at a CONSTANT 1 panel — expected O(#panels), not O(content)"
    end

    # ===================== A7 — absolute_bounds recomputation (in-frame double-calc) =====================
    # absolute_bounds is UNCACHED and re-walks the parent chain on EVERY call (~85 call sites). Measures
    # Widget.absolute_bounds_count per frame at a CONSTANT 1 panel, 50 vs 100 Buttons. If it scales with
    # content it is an O(visible×depth) IN-FRAME recomputation — a frame-scoped-cache target. PRINT-ONLY
    # (not fixed): no assertion, just the magnitude/scaling for prioritisation.
    {"A7 idle" => :idle, "A7 drag" => :drag}.each do |label, mode|
      results = [] of Int32
      [50, 100].each do |n|
        CrymbleUI::WindowPanel.clear_registry
        CrymbleUI::Popup.clear_registry
        renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
        app, panel = panel_buttons_app(n)
        renderer.settle_rendering(app)
        if mode == :idle
          CrymbleUI::Widget.reset_absolute_bounds_count
          renderer.render_frame(app)
          results << CrymbleUI::Widget.absolute_bounds_count
        else
          renderer.mouse_down(panel.x + 60.0, panel.y + 10.0)
          renderer.render_frame(app)
          CrymbleUI::Widget.reset_absolute_bounds_count
          renderer.mouse_move(panel.x + 100.0, panel.y + 10.0)
          renderer.render_frame(app)
          results << CrymbleUI::Widget.absolute_bounds_count
          renderer.mouse_up(panel.x + 100.0, panel.y + 10.0)
        end
      end
      audit_row(label, "absolute_bounds_count", results[0], results[1])
    end

    # ============================ A2 — hover (panel + popup walk) ============================
    # update_hover(pt) + get_cursor_for_point(pt). get_cursor_for_point walks find_all_popups
    # AND find_all_panels. Same CONSTANT-panel-count / scaling-buttons setup as A1.
    panel_res = [] of Int32
    popup_res = [] of Int32
    [50, 100].each do |n|
      CrymbleUI::WindowPanel.clear_registry
      CrymbleUI::Popup.clear_registry
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
      app, panel = panel_buttons_app(n)
      renderer.settle_rendering(app)
      pt = CrymbleUI::Vec2.new(panel.x + 20.0, panel.y + 30.0)

      CrymbleUI::Widget.reset_panel_walk_visits
      CrymbleUI::Widget.reset_popup_walk_visits
      app.update_hover(pt)
      app.get_cursor_for_point(pt)
      panel_res << CrymbleUI::Widget.panel_walk_visits
      popup_res << CrymbleUI::Widget.popup_walk_visits
    end
    audit_row("A2 hover", "panel_walk_visits", panel_res[0], panel_res[1])
    audit_row("A2 hover", "popup_walk_visits", popup_res[0], popup_res[1])

    panel_ratio = content_independence_ratio(panel_res[0], panel_res[1])
    panel_ratio.should be <= 1.3,
      "A2 hover: panel_walk_visits scaled with content (#{panel_res[0]} -> #{panel_res[1]}, " \
      "ratio #{panel_ratio.round(2)}) at a CONSTANT 1 panel"

    popup_ratio = content_independence_ratio(popup_res[0], popup_res[1])
    popup_ratio.should be <= 1.3,
      "A2 hover: popup_walk_visits scaled with content (#{popup_res[0]} -> #{popup_res[1]}, " \
      "ratio #{popup_ratio.round(2)}) though 0 popups are registered — the walk must be O(#popups)"

    # ============================ A3 — scroll plain ScrollView ============================
    # collect_all_widgets_recursive walks all N child widgets when the scroll content layer
    # re-renders. Scale = N buttons.
    a3 = [] of Int32
    [50, 100].each do |n|
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      app, sv = scrollview_app(n)
      renderer.settle_rendering(app)

      CrymbleUI::LayerRenderer.collect_widgets_visits = 0
      sv.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(300.0, 200.0))
      renderer.render_frame(app)
      a3 << CrymbleUI::LayerRenderer.collect_widgets_visits
    end
    audit_row("A3 scroll", "collect_widgets_visits", a3[0], a3[1])

    # ============================ A4 — render-state sweep ============================
    # clear_render_state_recursive runs on every NON-layout frame, whole-tree.
    a4 = [] of Int32
    [1, 2].each do |n|
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
      app, _ = matrix_panel_app(n)
      renderer.settle_rendering(app)
      renderer.render_frame(app) # ensure a clean, non-layout frame follows
      CrymbleUI::Widget.reset_state_sweep_visits
      renderer.render_frame(app)
      a4 << CrymbleUI::Widget.state_sweep_visits
    end
    audit_row("A4 state sweep", "state_sweep_visits", a4[0], a4[1])

    # ============================ A5 — DnD drop-target hit walk ============================
    # find_drop_target recurses the whole tree per drag-move. Position over empty space so it
    # visits every node (returns nil). Scale = N filler widgets.
    a5 = [] of Int32
    [50, 100].each do |n|
      root = PerfRoot.new
      draggable = PerfDraggable.new
      target = PerfDropTarget.new
      root.add_child(draggable)
      root.add_child(target)
      n.times { root.add_child(PerfFiller.new) }
      root.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(2000.0, 2000.0)), CrymbleUI::Vec2.zero)

      manager = CrymbleUI::DragManager.new
      manager.begin_drag_tracking(draggable, CrymbleUI::Vec2.new(5.0, 5.0))
      manager.update_drag(CrymbleUI::Vec2.new(20.0, 20.0), root) # pass threshold -> Active
      CrymbleUI::DragManager.drop_target_visits = 0
      manager.update_drag(CrymbleUI::Vec2.new(5000.0, 5000.0), root) # measured move (over empty space)
      a5 << CrymbleUI::DragManager.drop_target_visits
    end
    audit_row("A5 DnD move", "drop_target_visits", a5[0], a5[1])

    # ============================ A6 — column resize row-cache rebuild ============================
    # A COLUMN resize invalidates ALL dimension caches, so update_visible_cells rebuilds the
    # O(total rows) @cached_row_sizes array — even though the visible viewport is unchanged.
    # small = 1+100 rows, big = 1+200 rows, SAME small viewport.
    a6 = [] of Int32
    [100, 200].each do |lrs|
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app, m = resize_matrix_app(lrs)
      renderer.settle_rendering(app)

      m.resize_axis = CrymbleUI::VirtualMatrix::ResizeAxis::Col
      m.resize_index = 0
      m.resize_start_mouse = 0.0
      m.resize_start_size = m.get_col_width(0)

      CrymbleUI::VirtualMatrix.reset_row_cache_rebuild_rows
      m.on_mouse_move(CrymbleUI::Vec2.new(m.absolute_bounds.x + 120.0, m.absolute_bounds.y + 20.0))
      renderer.render_frame(app) # pre_render_flush -> flush_resize_update -> update_visible_cells
      a6 << CrymbleUI::VirtualMatrix.row_cache_rebuild_rows
    end
    audit_row("A6 col resize", "row_cache_rebuild_rows", a6[0], a6[1])

    puts "=" * 108
    puts "NOTE: small/big content sizes: A1/A2/A4 = 1 vs 2 matrix panels (tree size); A3/A5 = 50 vs 100"
    puts "      child/filler widgets; A6 = 101 vs 201 TOTAL rows at a CONSTANT viewport."
    puts "=" * 108
    puts ""

    # A3-A6 are KNOWN O(n) content-dependent walks (each mechanism documented per-row above; A4 is the
    # per-frame render-state sweep tracked as its own optimization ticket) — UNLIKE A1/A2's O(1) (asserted
    # <= 1.3). Content roughly DOUBLES between the small/big runs, so a linear path lands near 2.0 and an
    # O(n^2) REGRESSION would land near 4.0. Guard "not worse than linear" (<= 3.0 — headroom on both
    # sides): this catches a quadratic regression in scroll / state-sweep / DnD / col-resize WITHOUT
    # pinning the current linear value.
    content_independence_ratio(a3[0], a3[1]).should be <= 3.0, "A3 scroll: collect_widgets_visits went super-linear (#{a3[0]} -> #{a3[1]})"
    content_independence_ratio(a4[0], a4[1]).should be <= 3.0, "A4 state sweep: state_sweep_visits went super-linear (#{a4[0]} -> #{a4[1]})"
    content_independence_ratio(a5[0], a5[1]).should be <= 3.0, "A5 DnD move: drop_target_visits went super-linear (#{a5[0]} -> #{a5[1]})"
    content_independence_ratio(a6[0], a6[1]).should be <= 3.0, "A6 col resize: row_cache_rebuild_rows went super-linear (#{a6[0]} -> #{a6[1]})"
  end
end
