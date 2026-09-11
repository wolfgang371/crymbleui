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
  # The floor is "one DEFAULT line", not "whatever line 0 currently measures".
  #
  # It exists so a grid cannot collapse to nothing. Reading row 0's ACTUAL height made it follow
  # content instead: a 60-line value in row 0 drove the floor to 888px and WindowPanel grew the
  # Shape to fit — the panel got taller instead of scrolling, and the matrix's own scrollbar went
  # off-screen with it. The width dual did the same for column 0 (measured 3414px in a 1400px
  # window, where hit_test at the visible bottom edge returned nothing at all).
  it "does not follow row 0's actual height — the floor is one DEFAULT row" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 3, id: "vm_tall")
    vm.sticky_row_count.should eq(0) # instrument: row 0 is a DATA row here, so the skip rule
    #                                  (sticky lines are not content-sized) cannot explain the result
    before = vm.min_intrinsic_height(400.0)

    vm.row_height(0, 43.0) # ~860px: a 60-line value's worth

    vm.get_row_height(0).should be > 40.0            # control: the row really is that tall now
    vm.min_intrinsic_height(400.0).should eq(before) # ...and the panel floor did not follow it
  end

  it "the width dual: the floor does not follow column 0's actual width" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 3, id: "vm_wide")
    before = vm.min_intrinsic_width(400.0)

    vm.col_width(0, 168.0) # ~3400px, the measured sticky-column case

    vm.get_col_width(0).should be > 100.0
    vm.min_intrinsic_width(400.0).should eq(before)
  end
end
