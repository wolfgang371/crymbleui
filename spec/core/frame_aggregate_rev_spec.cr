require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# App-level pull render-trigger: Layer.frame_aggregate_rev(root) is the version-keyed
# replacement for any_layer_needs_render? (the app-level dirty walk). The SFML loop renders a frame
# iff this aggregate moved since the last render — correct-by-construction (it can't miss a change
# that's under versioning), preserving the event-driven 0%-idle behaviour. Every input that requires
# a render must move it: content/theme/zoom/layout (Σ widget primitive_cache_rev), structure
# (Σ layer widget counts), scroll (Σ layer scroll_rev).

private class FARMatrixAdapter
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

describe "Layer.frame_aggregate_rev (app-level pull render-trigger)" do
  it "is stable with no change and moves on content / scroll" do
    matrix = CrymbleUI::VirtualMatrix.new(FARMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    agg1 = CrymbleUI::Layer.frame_aggregate_rev(root)

    # No change → identical aggregate (so the loop would idle, no render).
    CrymbleUI::Layer.frame_aggregate_rev(root).should eq agg1

    # A content change → the aggregate moves (so the loop would render).
    cell = matrix.active_cells.values.first
    cell.mark_needs_render
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg1

    # A theme swap → moves (global theme_rev is inside every cell's primitive_cache_rev).
    agg2 = CrymbleUI::Layer.frame_aggregate_rev(root)
    begin
      CrymbleUI::Theme.set(:dark)
      CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg2
    ensure
      CrymbleUI::Theme.set(:light)
    end

    # A scroll → moves (scroll_rev), so the compositor re-runs at the new offset.
    agg3 = CrymbleUI::Layer.frame_aggregate_rev(root)
    matrix.content_layer.not_nil!.scroll_offset = CrymbleUI::Vec2.new(0.0, 40.0)
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg3
  end
end
