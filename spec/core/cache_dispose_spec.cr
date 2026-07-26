require "spec"
require "../../src/core/cached"

# CacheNode#dispose severs a node from the reactive graph — the fix for immortal global Sources
# (theme/zoom) that clear @dependents only on their own `set`, so a discarded widget's pull node would
# otherwise pin its whole dead generation forever. dispose unregisters the node from every source/node
# it read (draining those @dependents) and drops its on_dirty enqueue hook.

describe "CacheNode#dispose" do
  it "unregisters the node from a Source it read (Source#remove_dependent drains @dependents)" do
    src = CrymbleUI::Source(Int32).new(0)
    node = CrymbleUI::Cached(Int32).new { src.get }
    node.get # recompute reads src.get → registers node in src.@dependents
    src.dependent_count.should eq(1)

    node.dispose
    src.dependent_count.should eq(0) # drained without a Source#set
  end

  it "unregisters from another node it read (node→node back-edge)" do
    src = CrymbleUI::Source(Int32).new(0)
    inner = CrymbleUI::Cached(Int32).new { src.get }
    outer = CrymbleUI::Cached(Int32).new { inner.get + 1 }
    outer.get # outer's recompute reads inner → inner.@dependents gains outer
    inner.dependent_count.should eq(1)

    outer.dispose
    inner.dependent_count.should eq(0)
  end

  it "is idempotent — a second dispose finds @deps already empty" do
    src = CrymbleUI::Source(Int32).new(0)
    node = CrymbleUI::Cached(Int32).new { src.get }
    node.get
    node.dispose
    node.dispose # must not raise
    src.dependent_count.should eq(0)
  end

  it "leaves a bare Rev unharmed (remove_dependent no-op default is total over VersionSource)" do
    # A Rev is never auto-captured as a dep, but VersionSource must still answer remove_dependent so
    # dispose's `@deps.each(&.remove_dependent(self))` type-checks; the default is a safe no-op.
    CrymbleUI::Rev.new.remove_dependent(CrymbleUI::Cached(Int32).new { 0 })
  end

  it "stays off the dep-probe hot path (dispose uses Set#delete, never note_dep_probe)" do
    src = CrymbleUI::Source(Int32).new(0)
    node = CrymbleUI::Cached(Int32).new { src.get }
    node.get
    CrymbleUI::CacheNode.dep_probe_iterations = 0
    node.dispose
    CrymbleUI::CacheNode.dep_probe_iterations.should eq(0) # the fix adds nothing to Source#get's cost
  end
end
