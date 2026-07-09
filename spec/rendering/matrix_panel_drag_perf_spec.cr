require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/testing/configurable_matrix_adapter"

# Regression: dragging a WindowPanel that CONTAINS a VirtualMatrix must be O(1), exactly like dragging
# a panel of plain buttons. A drag changes only the panel's WINDOW position — the matrix's
# scroll_offset, content, cell sizes and sticky configuration are all unchanged — so the viewport_cache
# layer must NOT re-evaluate or walk its cells on each drag frame; the unconditional composite re-blits
# the cached buffer at the pulled bounds.
#
# Bug (before the fix): the matrix's two viewport_cache layers (VM content + the VM's inner ScrollView)
# re-render EVERY drag frame and walk ~150 visible cells → ~90% CPU on a maximized window, while an
# equivalent button panel drags as a pure composite (0 work) at ~15-20%.
#
# The button panel is the "fast sibling" baseline: the matrix panel's per-drag-frame cost must MATCH it.

private def build_drag_panel(with_matrix : Bool, id : String = "P") : {CrymbleUI::App, CrymbleUI::WindowPanel}
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 1400, 950)
  panel = CrymbleUI::WindowPanel.new(id, 40.0, 120.0, 700.0, 620.0, id: id)

  if with_matrix
    adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 20, 20)
    panel.add_child(CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "matrix_#{id}"))
  else
    # SAME 20x20 grid the stress_panel_demo uses — a known-O(1) drag baseline.
    vs = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |col| hs.add_child(CrymbleUI::Button.new("#{row},#{col}", font_scale: -5, padding: 3.0) { }) }
      vs.add_child(hs)
    end
    panel.add_child(vs)
  end

  window.add_child(panel)
  app.root_widget = window
  {app, panel}
end

# Drag a panel by its title bar through `steps` moves of `dx` px each, running one frame per move.
# Yields (max_layers, max_cells) — the WORST per-frame render cost seen across the drag.
private def drag_panel(renderer, app, panel, dx : Float64 = 40.0, steps : Int32 = 4)
  tx = panel.x + 60.0
  ty = panel.y + 10.0 # title bar
  renderer.mouse_down(tx, ty)
  renderer.render_frame(app)

  max_layers = 0
  max_cells = 0
  steps.times do
    tx += dx
    # Headless render_frame does NOT reset the LayerRenderer frame counters (only the SFML renderer
    # does), so reset per frame for a clean delta.
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.mouse_move(tx, ty)
    renderer.render_frame(app)
    max_layers = Math.max(max_layers, CrymbleUI::LayerRenderer.frame_layers_needing_render)
    max_cells = Math.max(max_cells, CrymbleUI::LayerRenderer.frame_widgets_iterated)
  end
  renderer.mouse_up(tx, ty)
  {max_layers, max_cells}
end

private def worst_drag_frame_cost(with_matrix : Bool) : {Int32, Int32}
  renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
  app, panel = build_drag_panel(with_matrix)
  renderer.render_frame(app)
  renderer.render_frame(app) # settle initial layout + first viewport render
  drag_panel(renderer, app, panel)
end

describe "WindowPanel drag with VirtualMatrix content" do
  it "is O(1) — a position-only drag re-renders no layers and walks no cells, same as a button panel" do
    button_layers, button_cells = worst_drag_frame_cost(false)
    matrix_layers, matrix_cells = worst_drag_frame_cost(true)

    # Baseline: a button panel drag is a pure composite (fast sibling).
    button_layers.should eq 0
    button_cells.should eq 0

    # The matrix panel must match the fast sibling: a drag moves only window
    # position, so the viewport_cache must not re-evaluate or walk cells.
    matrix_cells.should eq button_cells   # was: 150 vs 0
    matrix_layers.should eq button_layers # was: 2 vs 0
  end

  it "still re-composites the matrix at the new position — the layer bounds follow the panel even though the body is skipped" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
    app, panel = build_drag_panel(true)
    renderer.render_frame(app)
    renderer.render_frame(app)

    matrix = app.find("matrix_P").not_nil!.as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    x0 = content_layer.bounds.x

    max_layers, _ = drag_panel(renderer, app, panel, dx: 40.0, steps: 5) # total +200px

    # Body was skipped every frame ...
    max_layers.should eq 0
    # ... yet the layer's COMPOSITE position tracked the panel move (pull-based bounds → composite).
    (content_layer.bounds.x - x0).should be_close(200.0, 1.0)
  end

  it "re-arms after a drag: a subsequent scroll still re-renders and recenters the matrix" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
    app, panel = build_drag_panel(true)
    renderer.settle_rendering(app)

    matrix = app.find("matrix_P").not_nil!.as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!

    # Drag first (drives many skipped frames) ...
    drag_panel(renderer, app, panel)
    origin_after_drag = content_layer.buffer_origin

    # ... then scroll far enough to force a buffer recenter. The skip MUST re-arm (scroll_rev ∈ content_rev).
    center = CrymbleUI::Vec2.new(panel.x + 300.0, panel.y + 300.0)
    CrymbleUI::LayerRenderer.reset_frame_counters
    10.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end

    # The content layer re-rendered on scroll (would be 0 if the skip had wedged) ...
    CrymbleUI::LayerRenderer.rendered_layer_ids.should contain(content_layer.id)
    # ... and the recenter inside render_layer actually fired.
    content_layer.buffer_origin.should_not eq(origin_after_drag)
  end

  it "dragging one matrix panel wakes neither matrix, and only the dragged panel's layer moves" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1400, 950)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 1400, 950)

    pa = CrymbleUI::WindowPanel.new("A", 40.0, 120.0, 500.0, 400.0, id: "A")
    pa.add_child(CrymbleUI::VirtualMatrix.new(adapter: ConfigurableMatrixAdapter.new(2, 2, 3, 3, 20, 20), id: "matrix_A"))
    pb = CrymbleUI::WindowPanel.new("B", 700.0, 120.0, 500.0, 400.0, id: "B")
    pb.add_child(CrymbleUI::VirtualMatrix.new(adapter: ConfigurableMatrixAdapter.new(2, 2, 3, 3, 20, 20), id: "matrix_B"))
    window.add_child(pa)
    window.add_child(pb)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.render_frame(app)

    la = app.find("matrix_A").not_nil!.as(CrymbleUI::VirtualMatrix).content_layer.not_nil!
    lb = app.find("matrix_B").not_nil!.as(CrymbleUI::VirtualMatrix).content_layer.not_nil!
    ax0, bx0 = la.bounds.x, lb.bounds.x

    max_layers, _ = drag_panel(renderer, app, pa, dx: 40.0, steps: 4) # move A by +160px

    max_layers.should eq 0                             # neither matrix re-rendered during the drag
    (la.bounds.x - ax0).should be_close(160.0, 1.0)    # dragged panel's matrix followed
    (lb.bounds.x - bx0).should be_close(0.0, 1.0)      # the other stayed put
  end
end

# --- Pixel-level reposition guard (known per-row colors) ---
# The count-based tests prove the body is skipped; this proves the user-visible property the skip
# promises: after a drag, the matrix's actual PIXELS appear at the new panel position (composited from
# the cached buffer), and the vacated origin no longer shows them. Guards against a future change that
# freezes the matrix (e.g. gating the composite on rendered_count) while counts still read 0.
private class DragReposCell < CrymbleUI::Widget
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
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill_color) }
  end
end

private class DragReposAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter
  CELL = CrymbleUI::Color.new(200, 40, 40, 255) # distinct from any panel/background color

  def initialize(@rows : Int32 = 40, @cols : Int32 = 6)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    DragReposCell.new(CELL)
  end
end

describe "WindowPanel drag with VirtualMatrix content (pixel reposition)" do
  it "the matrix's pixels move with the panel and the vacated origin is not left stale" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1000, 800)
    app = TestApp.new
    window = CrymbleUI::Window.new("W", 1000, 800)
    panel = CrymbleUI::WindowPanel.new("PixP", 60.0, 100.0, 500.0, 500.0, id: "PixP")
    m = CrymbleUI::VirtualMatrix.new(adapter: DragReposAdapter.new, id: "pix_matrix")
    m.show_rulers = false
    panel.add_child(m)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    win_buf = renderer.backend
    cell = DragReposAdapter::CELL

    # Find a window pixel showing a matrix cell, inside the panel's content area (below the title bar,
    # left half so a +right drag keeps it on-screen).
    sx = sy = -1
    (140..320).step(4) do |y|
      (80..300).step(4) do |x|
        px = win_buf.get_pixel(x, y)
        if px && px == cell
          sx, sy = x, y
          break
        end
      end
      break if sx >= 0
    end
    sx.should_not eq(-1), "setup: no matrix pixel found in the panel content area"

    # Drag the panel right by +200px.
    drag_panel(renderer, app, panel, dx: 40.0, steps: 5)
    renderer.render_frame(app)

    # The cell color now appears 200px to the right (content followed the panel) ...
    win_buf.get_pixel(sx + 200, sy).should eq(cell),
      "matrix pixel did not follow the panel to x=#{sx + 200}"
    # ... and the original location no longer shows the matrix (vacated, not stale).
    win_buf.get_pixel(sx, sy).should_not eq(cell),
      "vacated origin at x=#{sx} still shows a stale matrix pixel"
  end
end
