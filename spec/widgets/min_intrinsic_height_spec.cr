require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/drop_zone_box"
require "../../src/widgets/expanded"
require "../../src/widgets/tree_node"
require "../../src/layout/vstack"

# a fill VirtualMatrix's content floor must flow through the REAL Shape matrix nesting
# (Expanded → TreeNode → VStack → Expanded → DropZoneBox → VirtualMatrix), flooring to header+1row
# instead of its greedy fill. A synthetic Expanded[VM] would miss the DropZoneBox/Expanded
# pass-throughs (the round-1/2 gate lesson), so this uses the real nesting.
describe "min_intrinsic_height through the matrix nesting" do
  it "floors a fill VirtualMatrix to ~1 row, and the floor reaches the top through the pass-throughs" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 3, id: "vm") # fill mode (non-shrink)
    dz = CrymbleUI::DropZoneBox.new(accept_types: [] of String)
    dz.add_child(vm)
    inner_exp = CrymbleUI::Expanded.new
    inner_exp.add_child(dz)
    inner = CrymbleUI::VStack.new
    inner.add_child(inner_exp)
    tree = CrymbleUI::TreeNode.new("Perspective", expanded: true)
    tree.add_child(inner)
    outer_exp = CrymbleUI::Expanded.new
    outer_exp.add_child(tree)
    root = CrymbleUI::VStack.new
    root.add_child(outer_exp)

    w = 400.0
    vm_floor = vm.min_intrinsic_height(w)
    floor = root.min_intrinsic_height(w)

    # The VM floors to roughly one row — NOT its ~300px greedy fill (RED until the VM override lands).
    vm_floor.should be < 150.0
    # That floor reaches the top: the DropZoneBox/Expanded pass-throughs don't revert to greedy.
    floor.should be_close(vm_floor, 60.0)
  end
end
