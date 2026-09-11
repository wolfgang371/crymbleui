require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Symptom-2 repro: widening a column past the viewport must make the horizontal scrollbar
# appear. Today it doesn't until a full layout (Ctrl+0): the matrix updates sv.content_size on
# resize, but content_size is a reconcile_property (no invalidation) so the ScrollView never
# re-lays-out → no scrollbar.

class WSAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32 = 10, @cols : Int32 = 4)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

# The TYPING path needs cells that can report a content size — WSAdapter's `Text` cannot, so
# content sizing has nothing to measure and the path is unreachable through it.
class WSTypeAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32 = 10, @cols : Int32 = 4)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "#{row},#{col}")
  end
end

class WSTypeApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(adapter: WSTypeAdapter.new, id: "wst")
  end
end

private def typing_matrix(renderer)
  app = WSTypeApp.new
  app.build_tree
  renderer.settle_rendering(app)
  m = app.find("wst").as(CrymbleUI::VirtualMatrix)
  m.auto_size = true # fit_cell_to_content returns early unless the mode is on
  renderer.settle_rendering(app)
  {app, m}
end

# Matrix directly as root (like ResizeDSLApp) — a window wrapper would add chrome margin that
# re-lays-out non-deterministically and confounds the pixel diff. This isolates the scrollbar.
class WSApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(adapter: WSAdapter.new, id: "ws")
  end
end

private def widen_first_col(renderer, app, m : CrymbleUI::VirtualMatrix, dx : Float64)
  abs = m.absolute_bounds
  ry = abs.y + m.ruler_row_height_pixels / 2.0
  bx = abs.x + m.ruler_col_width_pixels + (0..1).sum { |c| 3.0 + m.get_col_width(c) * 20.0 }
  press = CrymbleUI::Vec2.new(bx, ry)
  m.on_mouse_down(press)
  6.times { |i| m.on_mouse_move(CrymbleUI::Vec2.new(press.x + dx * (i + 1) / 6, press.y)); renderer.render_frame(app) }
  m.on_mouse_up(CrymbleUI::Vec2.new(press.x + dx, press.y))
  renderer.render_frame(app)
end

private def window_pixels(renderer) : Array(UInt32)
  b = renderer.backend
  b.capture_region_pixels(0, 0, b.width, b.height)
end

describe "VirtualMatrix content sizing → scrollbars, without a layout" do
  # The drag path below already owns this oracle. The TYPING path — a cell grown by
  # fit_cell_to_content, which is what every keystroke does while the mode is on — has no layout at
  # all, and today nothing tells the ScrollView its content grew. Measured before the fix: 8320
  # pixels differ, rows 384..399, i.e. exactly the 16px strip where the horizontal bar belongs.
  it "a column grown by content sizing renders the scrollbar immediately (no Ctrl+0)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app, m = typing_matrix(renderer)
    sv = m.content_scroll_view.not_nil!
    (sv.content_size.width > sv.viewport_size.width).should be_false # instrument: it fits to begin with

    m.fit_cell_to_content(0, 1, 900.0, 20.0, 1) # what a keystroke does
    m.pre_render_flush
    renderer.render_frame(app)
    m.get_col_width(1).should be > 40.0 # instrument: the column really grew

    after_typing = window_pixels(renderer)
    app.root.try(&.mark_needs_layout) # Ctrl+0 == a full layout
    renderer.settle_rendering(app)
    after_ctrl0 = window_pixels(renderer)

    diff = (0...{after_typing.size, after_ctrl0.size}.min).count { |i| after_typing[i] != after_ctrl0[i] }
    diff.should eq(0),
      "Ctrl+0 changed #{diff} pixels after a content-sized column grew — the horizontal scrollbar " \
      "was left unpainted (its chrome geometry is established in a LAYOUT, so no amount of " \
      "render-invalidation brings it back)."
  end

  it "the VERTICAL twin, in a row the intrinsic floor cannot explain" do
    # Row 3, not row 0: min_intrinsic_height reads index 0 only, so a tall row 3 leaves the panel
    # floor untouched (measured 43.0, unchanged) and the only thing that can produce a scrollbar is
    # the extents update this task adds.
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app, m = typing_matrix(renderer)
    sv = m.content_scroll_view.not_nil!
    (sv.content_size.height > sv.viewport_size.height).should be_false # instrument

    m.fit_cell_to_content(3, 1, 60.0, 900.0, 40)
    m.pre_render_flush
    renderer.render_frame(app)
    m.get_row_height(3).should be > 10.0 # instrument: the row really grew

    after_typing = window_pixels(renderer)
    app.root.try(&.mark_needs_layout)
    renderer.settle_rendering(app)
    after_ctrl0 = window_pixels(renderer)

    diff = (0...{after_typing.size, after_ctrl0.size}.min).count { |i| after_typing[i] != after_ctrl0[i] }
    diff.should eq(0), "Ctrl+0 changed #{diff} pixels after a content-sized ROW grew."
  end
  it "an announced structural change refreshes the extents with content sizing OFF" do
    # The path v2 of the plan missed entirely: flush_invalidate_all reinstalls the adapter's sizes
    # and, with the mode off, nothing recomputed the extents afterwards — an announced change to a
    # grid with a different row count left them describing the old one until some later layout.
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app = WSTypeApp.new
    app.build_tree
    renderer.settle_rendering(app)
    m = app.find("wst").as(CrymbleUI::VirtualMatrix)
    m.auto_size.should be_false # instrument: content sizing is OFF for this example
    sv = m.content_scroll_view.not_nil!

    m.col_width(1, 60.0) # a wide grid the adapter will report on the next invalidate
    renderer.settle_rendering(app) # the setter schedules a layout; that is what publishes extents
    before = sv.content_size.width
    before.should be > sv.viewport_size.width # instrument: it really does overflow now

    m.adapter.not_nil!.invalidate_all! # the announcement a consumer makes on a structural change
    m.pre_render_flush
    # The adapter's own sizes are back, so the extents must have shrunk with them — no layout ran.
    sv.content_size.width.should be < before
  end

  it "two size changes in one frame leave the extents describing the SECOND" do
    # The order invariant, made observable: the totals memoise, so a refresh that read them before
    # clearing the caches would publish the first change's numbers and never correct itself.
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app, m = typing_matrix(renderer)
    sv = m.content_scroll_view.not_nil!

    m.fit_cell_to_content(0, 1, 400.0, 20.0, 1)
    first = sv.content_size.width
    m.fit_cell_to_content(0, 2, 900.0, 20.0, 1)
    second = sv.content_size.width
    m.pre_render_flush

    second.should be > first # the second change is in, not just the first

    # And the no-layout value is already the settled one: a refresh that had published stale totals
    # would be corrected here, and the two would differ.
    without_layout = sv.content_size.width
    app.root.try(&.mark_needs_layout)
    renderer.settle_rendering(app)
    sv.content_size.width.should eq(without_layout)
  end

  it "the toggle-off handover leaves the extents describing the sizes it handed over" do
    # Switching the mode off hands the fitted sizes to the adapter as the user's own and
    # reads them straight back. The extents must follow that read, with no layout — otherwise the
    # bar describes a grid the user is no longer looking at.
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app, m = typing_matrix(renderer)
    sv = m.content_scroll_view.not_nil!

    m.fit_cell_to_content(0, 1, 900.0, 20.0, 1)
    m.pre_render_flush
    fitted = sv.content_size.width
    fitted.should be > sv.viewport_size.width # instrument: the fit really did overflow the view

    m.auto_size = false
    m.pre_render_flush

    sv.content_size.width.should eq(fitted) # the handed-over sizes, not the adapter's defaults
  end

  it "costs no matrix layout per keystroke, and the control leg proves the counter can move" do
    # "Zero layouts" is already true today, so on its own it would stay green on a mis-wired
    # counter. The Ctrl+0 leg is what makes the zero mean something.
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app, m = typing_matrix(renderer)

    CrymbleUI::Widget.reset_layout_count
    5.times { |i| m.fit_cell_to_content(0, 1, 200.0 + i * 100.0, 20.0, 1); m.pre_render_flush }
    renderer.render_frame(app)
    typing_layouts = renderer.layout_count

    CrymbleUI::Widget.reset_layout_count
    app.root.try(&.mark_needs_layout)
    renderer.settle_rendering(app)
    control_layouts = renderer.layout_count

    control_layouts.should be > 0    # the instrument can move...
    typing_layouts.should eq(0)      # ...and typing does not move it
  end
end

describe "VirtualMatrix widen → horizontal scrollbar" do
  it "widening a column past the viewport renders the scrollbar immediately (no Ctrl+0)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(520, 400)
    app = WSApp.new
    app.build_tree
    renderer.settle_rendering(app)
    m = app.find("ws").as(CrymbleUI::VirtualMatrix)
    sv = m.content_scroll_view.not_nil!

    # Initially the content fits — no horizontal scrollbar.
    (sv.content_size.width > sv.viewport_size.width).should be_false

    # Widen the first column far enough that the content overflows the viewport.
    widen_first_col(renderer, app, m, 220.0)
    (sv.content_size.width > sv.viewport_size.width).should be_true # content now overflows

    # What the user sees right after the widen.
    after_widen = window_pixels(renderer)

    # Ctrl+0 == a full layout. It must NOT change anything: the widen should already have
    # made the scrollbar appear (and laid the content out for it). Before the fix it did change
    # (symptom 2 — no scrollbar until Ctrl+0).
    app.root.try(&.mark_needs_layout)
    renderer.settle_rendering(app)
    after_ctrl0 = window_pixels(renderer)

    diff = (0...{after_widen.size, after_ctrl0.size}.min).count { |i| after_widen[i] != after_ctrl0[i] }
    diff.should eq(0),
      "Ctrl+0 (full layout) changed #{diff} pixels after a column widen — the widen left the " \
      "horizontal scrollbar unrendered / the layout stale (you had to press Ctrl+0 to get a scrollbar)."
  end
end
