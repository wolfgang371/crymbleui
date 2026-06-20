require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/widgets/button"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# TIGHT `frame_widget_count` baselines that lock in the current
# O(1) selective-repaint behaviour, so an `&&`-combinator over-invalidation during the cache-keying
# migration FAILS here instead of slipping under the loose `<= 10` bounds.
# `frame_widget_count` counts only ACTUALLY re-rendered widgets (fast-path cache hits = 0).

private class BaselineMatrixAdapter
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

private def lr
  CrymbleUI::LayerRenderer
end

describe "perf baselines (frame_widget_count regression detectors)" do
  it "a single dirtied leaf re-renders exactly that leaf (selective-repaint isolation)" do
    # An appearance change to one leaf (hover/color/text) must re-render ONLY that leaf, not the
    # tree. A keying-migration cascade (level X invalidation re-rendering siblings) blows this.
    window = CrymbleUI::Window.new("Test", 300, 200)
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    btn = CrymbleUI::Button.new("A", id: "btn") { }
    vstack.add_child(btn)
    vstack.add_child(CrymbleUI::Button.new("B", id: "other") { })
    window.add_child(vstack)
    renderer = CrymbleUI::Testing::TestRenderer.new(300, 200)
    app = TestApp.new
    app.root_widget = window
    app.build_tree
    window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    renderer.reset_counters
    lr.reset_frame_counters
    btn.mark_needs_render # one leaf changes appearance
    renderer.render_frame(app)
    puts "\n[baseline] one dirty leaf → frame_widget_count = #{lr.frame_widget_count}"
    lr.frame_widget_count.should eq 1 # ONLY btn — not `other`, not the VStack
  end

  it "single QuickEntry cell edit re-renders a bounded set" do
    matrix = CrymbleUI::VirtualMatrix.new(BaselineMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)
    CrymbleUI::Widget.focus_manager.focus(matrix)
    matrix.cursor_rc = {0, 0}
    renderer.settle_rendering(app)

    renderer.reset_counters
    lr.reset_frame_counters
    CrymbleUI::Widget.focus_manager.handle_text_input('X')
    renderer.render_frame(app)
    puts "[baseline] cell edit → frame_widget_count = #{lr.frame_widget_count}"
    lr.frame_widget_count.should be <= 2 # the edited cell (+ at most overlay); NOT the viewport (~15)
  end

  it "scroll one line re-renders a bounded set" do
    matrix = CrymbleUI::VirtualMatrix.new(BaselineMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    renderer.reset_counters
    lr.reset_frame_counters
    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), matrix.absolute_bounds.center)
    renderer.render_frame(app)
    puts "[baseline] scroll one line → frame_widget_count = #{lr.frame_widget_count}"
    lr.frame_widget_count.should be <= 6 # the newly-exposed row of cells; NOT the whole viewport
  end
end
