require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# A layer buffer clear (mark_needs_clear_and_render: reflow / sticky reposition / zoom)
# bumps no widget/scroll/position rev, so it was invisible to frame_aggregate_rev — only the
# `|| any_needs_render?` backstop caught it. Folding a per-layer clear_rev into the aggregate makes the
# clear visible to the render trigger, which is the prerequisite for deleting that backstop.

private class A42Adapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    30
  end

  def col_count : Int32
    4
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

describe "buffer clear moves the aggregate" do
  it "mark_needs_clear_and_render moves frame_aggregate_rev" do
    matrix = CrymbleUI::VirtualMatrix.new(A42Adapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    matrix.content_layer.not_nil!.mark_needs_clear_and_render
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg # the clear is now visible to the trigger
  end
end
