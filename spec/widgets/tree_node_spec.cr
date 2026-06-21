require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/tree_node"
require "../../src/widgets/window"

# T-031: TreeNodeHeader used to read a raw @expanded ivar in to_primitives, kept in
# sync only by the parent pushing it every perform_layout + an unconditional
# mark_needs_render -- so the triangle updated ONLY because toggling forced a layout
# (a latent freeze if expanded ever changed without one). The header now PULLS the
# TreeNode's single `expanded` Source, auto-capturing it, so any change re-renders it.

private def header_of(node) : CrymbleUI::TreeNodeHeader
  node.children.first.as(CrymbleUI::TreeNodeHeader)
end

describe "TreeNode / TreeNodeHeader reactivity" do
  it "the header re-renders when the TreeNode's expanded changes, with NO layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(300, 200)
    app = TestApp.new
    node = CrymbleUI::TreeNode.new("Root", expanded: true)
    window = CrymbleUI::Window.new("Test", 300, 200)
    window.add_child(node)
    app.root_widget = window
    renderer.render_frame(app) # the header renders and captures the parent's expanded

    header = header_of(node)
    # Flip the PARENT's expanded WITHOUT a relayout. The header pulls it, so its
    # cached primitives must go stale (the old wrong-read left it frozen).
    node.expanded = false
    header.needs_render?.should be_true
  end

  it "the header reflects the TreeNode's expanded live (pull, not a stored copy)" do
    node = CrymbleUI::TreeNode.new("X", expanded: true)
    header = header_of(node)
    header.expanded?.should be_true

    node.expanded = false
    header.expanded?.should be_false # follows the parent, no stale duplicate
  end

  it "the header renders exactly one triangle (the expand/collapse indicator)" do
    node = CrymbleUI::TreeNode.new("X", expanded: true)
    header = header_of(node)
    prims = header.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, 120.0, 24.0))
    prims.count(&.is_a?(CrymbleUI::FillTriangle)).should eq(1)
  end
end
