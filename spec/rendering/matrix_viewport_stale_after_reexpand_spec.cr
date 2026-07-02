require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/widgets/window_panel"
require "../../src/widgets/tree_node"
require "../../src/widgets/expanded"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# grow-ghost regression: collapse a section → shrink the panel → expand it (auto-grows) →
# resize the panel taller. The matrix's TOP rows used to render BLANK and stay blank until a zoom.
# ROOT: a TreeNode collapse zeros its descendants' bounds; those cells survived in @active_cells at
# 0×0; update_visible_cells' creation loop skipped re-laying-out already-active cells, so the zeroed
# top rows never regained bounds and collect_all_widgets_recursive (correctly) dropped them.
#
# Guarded via the RENDER-DISPOSITION oracle (TestRenderer#widget_disposition), NOT pixels: a dropped
# cell never reaches a paint point, so its disposition is nil (absent). The fix gives the top cells
# a real disposition (:rendered fresh into the grown buffer).

private class CellAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    40
  end

  def col_count : Int32
    5
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

describe "VirtualMatrix grow-ghost: top rows survive collapse → expand → re-grow" do
  it "paints the top rows after a collapse zeros their cell bounds and the panel re-grows" do
    CrymbleUI::Theme.set(:dark)
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 950)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 700, 950)
    panel = CrymbleUI::WindowPanel.new("Shape", 20.0, 20.0, 520.0, 720.0)
    vstack = CrymbleUI::VStack.new(spacing: 4.0)
    vstack.add_child(CrymbleUI::Button.new("Header") { })
    tree = CrymbleUI::TreeNode.new("Perspective", expanded: true)
    matrix = CrymbleUI::VirtualMatrix.new(CellAdapter.new, id: "m")
    inner_exp = CrymbleUI::Expanded.new
    inner_exp.add_child(matrix)
    tree.add_child(inner_exp)
    outer_exp = CrymbleUI::Expanded.new
    outer_exp.add_child(tree)
    vstack.add_child(outer_exp)
    panel.add_child(vstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    # collapse → shrink → expand (auto-grows) → resize taller. One render per action (no settle —
    # settle's extra frames would heal a transient).
    ex = panel.x + panel.width / 2.0
    tree.toggle # collapse — zeros the matrix cells' bounds
    renderer.render_frame(app)
    panel.on_mouse_down(CrymbleUI::Vec2.new(ex, panel.y + panel.height - 3.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(ex, panel.y + 40.0)) # shrink small
    panel.pre_render_flush
    renderer.render_frame(app)
    panel.on_mouse_up(CrymbleUI::Vec2.new(ex, panel.y + 40.0))
    renderer.render_frame(app)
    tree.toggle # expand — auto-grows
    renderer.render_frame(app)
    panel.on_mouse_down(CrymbleUI::Vec2.new(ex, panel.y + panel.height - 3.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(ex, panel.y + 760.0)) # resize taller (the grow frame)
    panel.pre_render_flush
    renderer.render_frame(app)

    # The top rows (0..4) must have been PAINTED in the grow frame, not dropped. A culled cell has no
    # disposition (nil); the fix gives each a real one. Before the fix these were all nil (blank top).
    top_cells = (0..4).flat_map { |r| (0...5).map { |c| matrix.active_cells[{r, c}]? } }.compact
    top_cells.should_not be_empty
    painted = top_cells.count { |cell| !renderer.widget_disposition(cell).nil? }
    painted.should eq(top_cells.size)
  end
end
