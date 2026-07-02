require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/drop_zone_box"
require "../../src/widgets/expanded"
require "../../src/widgets/tree_node"
require "../../src/layout/vstack"
require "../../src/layout/hstack"
require "../../src/layout/flow"

# min_intrinsic_width is the WIDTH dual of min_intrinsic_height — the floor on the other axis.
# Stacking axis = Σ children; cross axis = MAX child. Self-scrolling bodies (a fill VirtualMatrix) report a
# small sliver (header-col + 1 col), NOT their greedy fill width — and that sliver must flow up through the
# passthroughs (VStack=MAX cross-axis, Expanded/DropZoneBox=passthrough). HStack (the width STACKING axis)
# needs Σ AND its missing min_intrinsic_height cross-axis twin. FlowLayout wraps, so its width-min is the
# WIDEST single child, not the packed-into-one-row sum the greedy default computes.

# Deterministic fixed-size leaf (no font dependency); min_intrinsic_* == its measured size.
class FixedLeaf < CrymbleUI::Widget
  def initialize(@fw : Float64, @fh : Float64)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@fw, @fh)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end
end

describe "min_intrinsic_width (the width half of the floor protocol)" do
  it "a leaf reports its measured width" do
    FixedLeaf.new(120.0, 30.0).min_intrinsic_width(500.0).should be_close(120.0, 0.5)
  end

  it "a fill VirtualMatrix floors to a sliver (header-col + 1 col), not its greedy fill width" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 8, id: "vm") # fill mode
    # RED until the VM width override lands (the greedy measure fills to a large width).
    vm.min_intrinsic_width(400.0).should be < 150.0
  end

  it "the width floor flows up through VStack(MAX cross-axis) / Expanded / DropZoneBox passthroughs" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 8, id: "vm")
    dz = CrymbleUI::DropZoneBox.new(accept_types: [] of String)
    dz.add_child(vm)
    exp = CrymbleUI::Expanded.new
    exp.add_child(dz)
    root = CrymbleUI::VStack.new
    root.add_child(exp)
    # The sliver reaches the top — the passthroughs don't revert to the greedy fill width.
    root.min_intrinsic_width(400.0).should be_close(vm.min_intrinsic_width(400.0), 30.0)
  end

  it "an HStack floors WIDTH to Σ children (stacking axis) and HEIGHT to MAX child (cross-axis twin)" do
    vm = CrymbleUI::VirtualMatrix.new(rows: 60, cols: 8, id: "vm")
    hs = CrymbleUI::HStack.new(spacing: 4.0)
    hs.add_child(FixedLeaf.new(80.0, 40.0))
    hs.add_child(vm)
    # WIDTH = leaf(80) + spacing(4) + vm-sliver(<150) → well under the greedy fill the default would give.
    hs.min_intrinsic_width(400.0).should be < 250.0
    # HEIGHT (the NEW twin) = MAX(leaf 40, vm sliver) → small, NOT the greedy fill height of the default.
    hs.min_intrinsic_height(400.0).should be < 150.0
  end

  it "a FlowLayout floors WIDTH to its widest single child (it wraps to one-per-row), not the packed sum" do
    flow = CrymbleUI::FlowLayout.new(hspacing: 4.0)
    flow.add_child(FixedLeaf.new(100.0, 20.0))
    flow.add_child(FixedLeaf.new(60.0, 20.0))
    # RED until the override: the default packs both onto one row (Σ ≈ 164); the wrap-floor is the widest (100).
    flow.min_intrinsic_width(500.0).should be_close(100.0, 4.0)
  end
end
