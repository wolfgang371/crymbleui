require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Adapter for the task board layout: 7 rows × 13 cols with status/priority headers
# and out-of-order scroll_order. Same as in scroll_render_spec.cr.
class RoundtripTaskBoardAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))

  def initialize
    define_merge({0, 1}, {0, 4})
    define_merge({0, 5}, {0, 8})
    define_merge({0, 9}, {0, 12})
    define_merge({1, 0}, {2, 0})
    define_merge({3, 0}, {4, 0})
    define_merge({5, 0}, {6, 0})
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    ColorBox.new(cell_color(row, col))
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {[1, 2, 3, 4, 5, 6, 0], [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end

  private def define_merge(top_left : Tuple(Int32, Int32), bottom_right : Tuple(Int32, Int32))
    @merges << {top_left, bottom_right}
  end
end

# Minimal widget: fill_rect with a configurable color. No text, no FontScalable.
private class ColorBox < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder
  getter bg_color : CrymbleUI::Color

  def initialize(@bg_color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints, position)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @bg_color) }
  end
end

# Unique color per (row, col), avoiding extremes (0/255) to distinguish from
# white background and black.
private def cell_color(row : Int32, col : Int32) : CrymbleUI::Color
  r = ((row * 37 + col * 73 + 50) % 200 + 30).to_u8
  g = ((row * 59 + col * 41 + 80) % 200 + 30).to_u8
  b = ((row * 83 + col * 17 + 110) % 200 + 30).to_u8
  CrymbleUI::Color.new(r.to_i, g.to_i, b.to_i, 255)
end

# DSL-style app with colored box cells — same layout as TaskBoardScrollAdapter
# (7×13, out-of-order scroll_order, merged regions) but using ColorBox instead of text.
class ColorBoxDSLApp < CrymbleUI::App
  # Reuse TaskBoardScrollAdapter from scroll_render_spec.cr
  def build : CrymbleUI::Widget
    adapter = RoundtripTaskBoardAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "task_board")
    matrix.col_width(0, 4.0)
    matrix.row_height(0, 1.5)
    matrix
  end
end

# Capture every 2nd pixel from the composite window backend.
private def snapshot_composite(renderer : CrymbleUI::Testing::TestRenderer) : Array(Tuple(Int32, Int32, CrymbleUI::Color))
  backend = renderer.backend
  result = [] of Tuple(Int32, Int32, CrymbleUI::Color)
  y = 0
  while y < backend.height
    x = 0
    while x < backend.width
      color = backend.get_pixel(x, y)
      result << {x, y, color} if color
      x += 2
    end
    y += 2
  end
  result
end

# Count pixels that differ beyond tolerance between two snapshots.
private def count_mismatches(a : Array(Tuple(Int32, Int32, CrymbleUI::Color)),
                             b : Array(Tuple(Int32, Int32, CrymbleUI::Color)),
                             tolerance : Int32 = 5) : Int32
  count = 0
  min = {a.size, b.size}.min
  min.times do |i|
    _, _, ca = a[i]
    _, _, cb = b[i]
    if (ca.r.to_i - cb.r.to_i).abs > tolerance ||
       (ca.g.to_i - cb.g.to_i).abs > tolerance ||
       (ca.b.to_i - cb.b.to_i).abs > tolerance
      count += 1
    end
  end
  count += (a.size - b.size).abs
  count
end

describe CrymbleUI::VirtualMatrix, tags: "slow" do
  describe "Horizontal scroll round-trip pixel regression (Bug 2)" do
    it "content pixels match after hscroll right→left round-trip" do
      app = ColorBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 150)
      renderer.settle_rendering(app)

      # Snapshot at scroll=0
      initial_pixels = snapshot_composite(renderer)

      point = CrymbleUI::Vec2.new(350.0, 75.0)

      # Scroll right to max (22 steps × 30px = 660px > max ~635px)
      22.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # Scroll back to 0 (22 steps)
      22.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # Snapshot at scroll=0 again
      final_pixels = snapshot_composite(renderer)

      # Compare — any mismatches = lost cells (Bug 2)
      mismatches = count_mismatches(initial_pixels, final_pixels)
      mismatches.should eq(0),
        "Round-trip hscroll lost #{mismatches}/#{initial_pixels.size} pixels. " \
        "Cells missing after scroll right → left."
    end

    it "ColorBox cells render with expected colors at scroll=0" do
      app = ColorBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 150)
      renderer.settle_rendering(app)

      # Spot-check: sample a pixel inside a known content area.
      # Content cells start after the sticky row/col headers.
      # Just verify we have non-white, non-black pixels in the content area,
      # confirming ColorBox rendering works.
      backend = renderer.backend
      non_bg_count = 0
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      black = CrymbleUI::Color.new(0, 0, 0, 255)
      transparent = CrymbleUI::Color.new(0, 0, 0, 0)

      # Sample across the viewport
      (10...backend.width).step(20) do |x|
        (10...backend.height).step(20) do |y|
          color = backend.get_pixel(x, y)
          next unless color
          next if color == white || color == black || color == transparent
          non_bg_count += 1
        end
      end

      non_bg_count.should be > 10,
        "Expected many colored pixels from ColorBox cells, but only found #{non_bg_count}. " \
        "ColorBox rendering may not be working."
    end

    it "no rendering exceptions during round-trip scroll" do
      app = ColorBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 150)
      renderer.settle_rendering(app)

      point = CrymbleUI::Vec2.new(350.0, 75.0)

      # Scroll right to max (no rebuild — matches real SFML demo)
      22.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
        renderer.render_frame(app)
      end

      # Scroll back to 0 (no rebuild — matches real SFML demo)
      22.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), point, shift: true)
        renderer.render_frame(app)
      end

      renderer.exceptions_caught.should eq(0),
        "Rendering exceptions during round-trip scroll: #{renderer.exceptions_caught}. " \
        "last_exception=#{renderer.last_exception_message}"
    end
  end

  describe "Scroll performance: early-exit avoids cell creation" do
    it "small scrolls within same boundary trigger 0 cell creations" do
      # Use the same 7×13 task board — small enough to settle fast,
      # large enough to have meaningful creation/destruction regions
      app = ColorBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 150)
      renderer.settle_rendering(app)

      point = CrymbleUI::Vec2.new(350.0, 75.0)

      # Scroll right by 1 step (30px) to get past initial state
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point, shift: true)
      renderer.render_frame(app)

      # Reset counter AFTER first scroll settles (cells created for initial + first scroll)
      CrymbleUI::VirtualMatrix.reset_update_visible_cells_counter
      renderer.reset_counters

      # Do 5 tiny vertical scrolls (1px each via mouse wheel with small delta)
      # These should NOT cross a cell boundary, so early-exit should fire
      5.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -0.05), point)
        renderer.render_frame(app)
      end

      # Cell creation count should be 0 — early-exit prevented expensive work
      CrymbleUI::VirtualMatrix.update_visible_cells_call_count.should eq(0),
        "Expected 0 cell creations during small scrolls, got " \
        "#{CrymbleUI::VirtualMatrix.update_visible_cells_call_count}. " \
        "Early-exit optimization may not be working."

      # Layout count should also be 0 — no new cells means no layout
      renderer.layout_count.should eq(0),
        "Expected 0 layout calls during small scrolls, got " \
        "#{renderer.layout_count}. Scroll should not trigger layout."
    end
  end
end
