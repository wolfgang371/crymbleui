require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Alignment guards: with a STICKY adapter (2 sticky rows + 2 sticky
# cols), the content block must start directly after the sticky band on
# the very first render — and stay there across reconciliation cycles.
#
# History (2026-06-05): an apparent "content offset" during the embrace
# commit-graph spike was hunted through three headless mirror variants
# (all green) while SFML captures kept showing a ~100px shift. The
# resolution: buffers and the live compositor were CORRECT all along —
# capture_composited_frame plain-blitted viewport-cache layers from
# (0,0), shifting their content by the cache margin in every captured
# PNG. The instrument was the bug (fixed via the shared
# Layer#viewport_sample_origin; see spec/core/layer_viewport_sample_spec).
# These examples stay as the headless alignment net that made the
# elimination possible.

# Single-color visible cell (TestVisibleCell with a parameterised color).
class OffsetColorCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@color : CrymbleUI::Color)
    super()
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
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color)
    end
  end
end

class StickyOffsetAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  TOTAL_ROWS = 12
  TOTAL_COLS =  5
  STICKY     = CrymbleUI::Color.new(0_u8, 200_u8, 0_u8, 255_u8)  # green
  CONTENT    = CrymbleUI::Color.new(220_u8, 0_u8, 0_u8, 255_u8)  # red

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...TOTAL_ROWS).to_a + [1, 0], (2...TOTAL_COLS).to_a + [1, 0]}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    {Array.new(TOTAL_ROWS, 1.0), Array.new(TOTAL_COLS, 4.0)}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    sticky = row < 2 || col < 2
    OffsetColorCell.new(sticky ? STICKY : CONTENT)
  end
end

# DSL-style app: builds a FRESH window + matrix on every build() call,
# so rebuilds go through reconciliation like real apps.
class RebuildOffsetApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("offset rebuild", 700, 360) do
      widget(CrymbleUI::VirtualMatrix.new(adapter: StickyOffsetAdapter.new, id: "offset_rebuild"))
    end
  end
end

describe "VirtualMatrix content/sticky alignment on first render" do
  it "content block starts directly after the sticky band (no initial offset)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 360)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter: StickyOffsetAdapter.new, id: "offset_test")
    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(700.0, 360.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    g_max_y = g_max_x = -1
    g_min_y = g_min_x = r_min_y = r_min_x = Int32::MAX
    (0...360).each do |y|
      (0...700).each do |x|
        pixel = backend.get_pixel(x, y)
        next unless pixel
        if pixel.g > 150 && pixel.r < 100
          g_min_y = y if y < g_min_y
          g_max_y = y if y > g_max_y
          g_min_x = x if x < g_min_x
          g_max_x = x if x > g_max_x
        elsif pixel.r > 150 && pixel.g < 100
          r_min_y = y if y < r_min_y
          r_min_x = x if x < r_min_x
        end
      end
    end

    diagnosis = "sticky(green) y #{g_min_y}..#{g_max_y} x #{g_min_x}..#{g_max_x}; " \
                "content(red) starts y #{r_min_y} x #{r_min_x}; " \
                "content_layer.bounds=#{matrix.content_layer.try(&.bounds)}"

    r_min_y.should_not eq(Int32::MAX), "no content cells rendered at all — #{diagnosis}"
    g_max_y.should be > 0, "no sticky cells rendered at all — #{diagnosis}"

    # The content block must begin within grid spacing (3px, + slack)
    # of the sticky band's bottom edge — not ~100px below it.
    offset_y = r_min_y - g_max_y - 1
    offset_y.should be <= 8, "content starts #{offset_y}px below the sticky band — #{diagnosis}"
    # And horizontally right after the sticky columns.
    offset_x = r_min_x - g_min_x
    sticky_cols_width = (g_max_x - g_min_x + 1) # full matrix width is green (sticky rows span all cols)
    offset_x.should be <= sticky_cols_width, "content starts at x #{r_min_x} — #{diagnosis}"
  end

  # Same assertion, with the matrix inside a Window widget root and
  # layout driven by the renderer settle (no manual matrix.layout).
  it "content block aligns with the matrix inside a Window root" do
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 360)
    app = TestApp.new
    win = CrymbleUI::Window.new("offset test", 700, 360)
    matrix = CrymbleUI::VirtualMatrix.new(adapter: StickyOffsetAdapter.new, id: "offset_test_w")
    win.add_child(matrix)
    app.root_widget = win
    app.build_tree
    renderer.settle_rendering(app)

    backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    g_max_y = -1
    r_min_y = Int32::MAX
    (0...360).each do |y|
      (0...700).each do |x|
        pixel = backend.get_pixel(x, y)
        next unless pixel
        if pixel.g > 150 && pixel.r < 100
          g_max_y = y if y > g_max_y
        elsif pixel.r > 150 && pixel.g < 100
          r_min_y = y if y < r_min_y
        end
      end
    end

    diagnosis = "sticky(green) max y #{g_max_y}; content(red) first y #{r_min_y}; " \
                "matrix.absolute_bounds=#{matrix.absolute_bounds}; " \
                "content_layer.bounds=#{matrix.content_layer.try(&.bounds)}"
    r_min_y.should_not eq(Int32::MAX), "no content cells rendered at all — #{diagnosis}"
    offset_y = r_min_y - g_max_y - 1
    offset_y.should be <= 8, "content starts #{offset_y}px below the sticky band — #{diagnosis}"
  end

  # Third mirror step: DSL-style app that builds a FRESH tree on every
  # build() — rebuilds reconcile the new matrix against the old one
  # (copy_state_from), which the SFML repro exercised and the variants
  # above never did.
  it "content stays aligned across rebuild/reconciliation cycles" do
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 360)
    app = RebuildOffsetApp.new
    app.build_tree
    renderer.settle_rendering(app)
    3.times do
      app.request_rebuild
      renderer.settle_rendering(app)
    end

    backend = renderer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    g_max_y = -1
    r_min_y = Int32::MAX
    (0...360).each do |y|
      (0...700).each do |x|
        pixel = backend.get_pixel(x, y)
        next unless pixel
        if pixel.g > 150 && pixel.r < 100
          g_max_y = y if y > g_max_y
        elsif pixel.r > 150 && pixel.g < 100
          r_min_y = y if y < r_min_y
        end
      end
    end

    matrix = app.find("offset_rebuild")
    diagnosis = "sticky(green) max y #{g_max_y}; content(red) first y #{r_min_y}; " \
                "matrix=#{matrix.try(&.absolute_bounds)}"
    r_min_y.should_not eq(Int32::MAX), "no content cells rendered at all — #{diagnosis}"
    offset_y = r_min_y - g_max_y - 1
    offset_y.should be <= 8, "content starts #{offset_y}px below the sticky band after rebuilds — #{diagnosis}"
  end
end
