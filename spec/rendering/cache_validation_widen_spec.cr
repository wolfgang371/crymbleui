require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/rendering/cache_validation"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"

# Cache-validation repro for the COLUMN-WIDEN desync (Wolfgang, 2026-05-30): widening a column
# in the perspective leaves a STALE cache (cached render ≠ immediate-mode/fresh render) until a
# forced refresh (Ctrl). All existing cache-validation tests only SCROLL; the interactive
# column-resize path (set_col_width_for_drag — updates @col_widths WITHOUT mark_needs_layout) is
# never validated. This drives that path and runs the dual-pipeline comparison.
#
# Run: crystal spec spec/rendering/cache_validation_widen_spec.cr -Dcache_validation

{% if flag?(:cache_validation) %}

class WidenCVAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32 = 20, @cols : Int32 = 30)
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

class WidenCVApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 800, 600) do
      widget(CrymbleUI::VirtualMatrix.new(adapter: WidenCVAdapter.new, id: "cv_widen"))
    end
  end
end

describe "Cache Validation — column widen" do
  before_each do
    CrymbleUI::CacheValidation.suite_gate = false # self-tests assert on failures themselves
    CrymbleUI::CacheValidation.clear_failures!
    CrymbleUI::CacheValidation.enable(:immediate_mode)
  end
  after_each { CrymbleUI::CacheValidation.disable_all }

  it "cached render matches immediate-mode while/after widening a column (drag path)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = WidenCVApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("cv_widen").as(CrymbleUI::VirtualMatrix)

    # Reset validation state AFTER the initial settle (don't validate the build).
    CrymbleUI::CacheValidation.disable_all
    CrymbleUI::CacheValidation.enable(:immediate_mode)
    CrymbleUI::CacheValidation.clear_failures!

    # Start an interactive widen of column 2: press on its right border in the ruler strip.
    abs = matrix.absolute_bounds
    ruler_y = abs.y + matrix.ruler_row_height_pixels / 2.0
    border_x = abs.x + matrix.ruler_col_width_pixels +
               (0..2).sum { |c| 3.0 + matrix.get_col_width(c) * 20.0 } # cum width through col 2
    press = CrymbleUI::Vec2.new(border_x, ruler_y)
    matrix.on_mouse_down(press)
    matrix.resize_axis.to_s.should eq("Col") # sanity: we actually grabbed a column border

    # Drag wider, rendering each step — validation runs per frame on the matrix_content layer.
    8.times do |i|
      matrix.on_mouse_move(CrymbleUI::Vec2.new(press.x + (i + 1) * 16.0, press.y))
      renderer.render_frame(app)
    end
    matrix.on_mouse_up(CrymbleUI::Vec2.new(press.x + 128.0, press.y))
    renderer.render_frame(app)

    # The widen made the content overflow; now scroll horizontally with the NEW widths.
    # This is the user's sequence (widen → content auto-scrolls). The cached cell buffers
    # were rendered at the pre-widen layout; scrolling blits them → potential stale cache.
    center = CrymbleUI::Vec2.new(400.0, 300.0)
    10.times do
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center, shift: true)
      renderer.render_frame(app)
    end

    # The cached (Crymble) pipeline must match the uncached immediate-mode ground truth.
    # If the widen+scroll left a stale cache, this raises with the pixel diff (the desync).
    CrymbleUI::CacheValidation.assert_no_failures!
  end
end
{% end %}
