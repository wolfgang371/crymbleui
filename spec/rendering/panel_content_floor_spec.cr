require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/drop_zone_box"
require "../../src/widgets/expanded"
require "../../src/widgets/tree_node"
require "../../src/layout/vstack"

# a WindowPanel won't shrink below its content's intrinsic floor (a fill grid keeps ≥1 row),
# grows when a section expands, never shrinks back on collapse, and never recomputes the floor on a
# resize frame. Built with the REAL Shape matrix nesting so the DropZoneBox/Expanded pass-throughs
# are exercised.
private def build_floor_panel(tree_expanded = true)
  renderer = CrymbleUI::Testing::TestRenderer.new(1000, 1000)
  app = TestApp.new
  window = CrymbleUI::Window.new("T", 1000, 1000)
  panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 400.0, 800.0)
  vstack = CrymbleUI::VStack.new(spacing: 4.0)
  vstack.add_child(CrymbleUI::Button.new("Header") { }) # a rigid section
  tree = CrymbleUI::TreeNode.new("Perspective", expanded: tree_expanded)
  inner = CrymbleUI::VStack.new
  inner_exp = CrymbleUI::Expanded.new
  dz = CrymbleUI::DropZoneBox.new(accept_types: [] of String)
  vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 3, id: "vm")
  dz.add_child(vm)
  inner_exp.add_child(dz)
  inner.add_child(inner_exp)
  tree.add_child(inner)
  outer_exp = CrymbleUI::Expanded.new
  outer_exp.add_child(tree)
  vstack.add_child(outer_exp)
  panel.add_child(vstack)
  window.add_child(panel)
  app.root_widget = window
  renderer.settle_rendering(app)
  {renderer, app, panel, tree, vm}
end

describe "WindowPanel content floor" do
  it "refuses to shrink below the content floor — the grid keeps a row, not 0" do
    renderer, app, panel, tree, vm = build_floor_panel
    ex = panel.x + panel.width / 2.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(ex, panel.y + panel.height - 3.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(ex, panel.y + 10.0)) # ask for a ~10px-tall panel
    renderer.render_frame(app)
    # Stopped at the content floor — strictly above MIN_PANEL_SIZE (100), and the grid kept a row.
    panel.height.should be > 110.0
    vm.absolute_bounds.height.should be > 8.0
  end

  it "grows the panel when a collapsed section is expanded" do
    renderer, app, panel, tree, vm = build_floor_panel(tree_expanded: false)
    ex = panel.x + panel.width / 2.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(ex, panel.y + panel.height - 3.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(ex, panel.y + 10.0))
    panel.on_mouse_up(CrymbleUI::Vec2.new(ex, panel.y + 10.0))
    renderer.render_frame(app)
    small = panel.height
    tree.toggle # expand → grid needs a row → panel grows
    renderer.settle_rendering(app)
    panel.height.should be > small
  end

  it "does not shrink back when a section is collapsed (grow-only)" do
    renderer, app, panel, tree, vm = build_floor_panel(tree_expanded: true)
    tall = panel.height
    tree.toggle # collapse
    renderer.settle_rendering(app)
    panel.height.should eq(tall)
  end

  it "does not recompute the floor on resize frames (reads the cache)" do
    renderer, app, panel, tree, vm = build_floor_panel
    CrymbleUI::WindowPanel.reset_min_floor_recompute_count
    ex = panel.x + panel.width / 2.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(ex, panel.y + panel.height - 3.0))
    5.times do |i|
      panel.on_mouse_move(CrymbleUI::Vec2.new(ex, panel.y + 500.0 - i * 30.0))
      renderer.render_frame(app)
    end
    CrymbleUI::WindowPanel.min_floor_recompute_count.should eq(0)
    tree.toggle # a structural change DOES recompute
    renderer.settle_rendering(app)
    CrymbleUI::WindowPanel.min_floor_recompute_count.should be > 0
  end
end
