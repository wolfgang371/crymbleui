require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Regression test for the row-merged-cell scroll layout bug.
#
# Symptom (user-reported in embrace trend mode with row-merged headers):
# wheel-scrolling reveals stale content in the merged-header column —
# e.g. cluster B renders cluster A's value, cluster A's value appears
# twice, etc.
#
# Root cause: when a merged cell's top-left scrolls out, VirtualMatrix
# rekeys @active_cells under the *dynamic handle* (first visible row of
# the cluster). The widget's content-space layout position must still be
# anchored to the cluster top-left so the merged cell stays in its
# cluster's box. Using the dynamic-handle key's row/col here slid the
# cell off its cluster and into the next one, where its cached pixels
# remained after the dynamic handle migrated again, producing the
# stale-content artefact.
#
# Compile with -Dcache_validation to also run pixel-level cache
# validation against the immediate-mode pipeline.

private GROUP = 5

private class MergedHeaderAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  ROWS = 50
  COLS = 3

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    LabeledBox.new("r#{row}c#{col}", color_for(row, col))
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...ROWS).to_a, (0...COLS).to_a}
  end

  # Column 0 is row-merged: rows in groups of GROUP share one bounding box.
  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    if col == 0
      group_top = (row // GROUP) * GROUP
      group_bottom = Math.min(group_top + GROUP - 1, ROWS - 1)
      { {group_top, 0}, {group_bottom, 0} }
    else
      { {row, col}, {row, col} }
    end
  end

  private def color_for(row : Int32, col : Int32) : CrymbleUI::Color
    r = ((row * 7 + col * 41) % 200 + 30).to_u8
    g = ((row * 17 + col * 31) % 200 + 30).to_u8
    b = ((row * 23 + col * 13) % 200 + 30).to_u8
    CrymbleUI::Color.new(r.to_i, g.to_i, b.to_i, 255)
  end
end

private class LabeledBox < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder
  getter label : String
  getter color : CrymbleUI::Color

  def initialize(@label : String, @color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 80.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints, position)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color) }
  end
end

private class App < CrymbleUI::App
  @adapter : MergedHeaderAdapter

  def initialize(@adapter)
    super()
  end

  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(@adapter, id: "merged_header_test")
  end
end

describe CrymbleUI::VirtualMatrix, tags: "slow" do
  describe "Merged-header scroll: cell stays in its cluster across handle migration" do
    it "scrolls through many cluster boundaries without cache divergence" do
      {% if flag?(:cache_validation) %}
        CrymbleUI::CacheValidation.enable_all
        CrymbleUI::CacheValidation.clear_failures!
      {% end %}
      adapter = MergedHeaderAdapter.new
      app = App.new(adapter)
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(700, 220)
      renderer.settle_rendering(app)

      vm = app.root.as?(CrymbleUI::VirtualMatrix).not_nil!
      point = CrymbleUI::Vec2.new(350.0, 110.0)

      # Snapshot the canonical bounds.y for each cluster at scroll=0 (when
      # every dynamic handle equals its canonical top-left). Any later
      # widget in @active_cells covering the same cluster MUST land at the
      # same content-space y — otherwise the merged cell has slid off its
      # cluster.
      cluster_top_y = {} of Int32 => Float64
      vm.active_cells.each do |key, w|
        next unless key[1] == 0
        tl_row = (key[0] // GROUP) * GROUP
        cluster_top_y[tl_row] ||= w.bounds.y
      end
      check_layout = ->{
        bad : NamedTuple(key: Tuple(Int32, Int32), bounds_y: Float64, expected_y: Float64)? = nil
        vm.active_cells.each do |key, w|
          next unless key[1] == 0
          tl_row = (key[0] // GROUP) * GROUP
          if (expected = cluster_top_y[tl_row]?) && (w.bounds.y - expected).abs > 0.5
            bad ||= {key: key, bounds_y: w.bounds.y, expected_y: expected}
          end
        end
        bad
      }

      # Varying scroll amplitudes hit lots of dynamic-handle positions,
      # including non-canonical ones (where the cluster's top-left has
      # scrolled out).
      [3, 7, 11, 13, 17, 23, 31, 37, 41, 5].each do |amp|
        amp.times do
          app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), point)
          renderer.render_frame(app)
          if (b = check_layout.call)
            fail "Cluster cell laid out off-cluster at scroll=#{vm.scroll_offset}: key=#{b[:key]} bounds.y=#{b[:bounds_y]} expected=#{b[:expected_y]}"
          end
        end
        amp.times do
          app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), point)
          renderer.render_frame(app)
          if (b = check_layout.call)
            fail "Cluster cell laid out off-cluster at scroll=#{vm.scroll_offset}: key=#{b[:key]} bounds.y=#{b[:bounds_y]} expected=#{b[:expected_y]}"
          end
        end
      end

      {% if flag?(:cache_validation) %}
        CrymbleUI::CacheValidation.assert_no_failures!
      {% end %}
    end
  end
end
