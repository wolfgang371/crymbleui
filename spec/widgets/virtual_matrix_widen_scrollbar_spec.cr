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
