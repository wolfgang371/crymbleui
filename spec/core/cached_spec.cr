require "spec"
require "../../src/core/cached"

# The Cached(T) / VersionSource / Source / KeyedCached core with AUTO-CAPTURE.
#
# Make-or-break: does fully-auto-capture work cleanly in Crystal? A dependency is created by READING
# its source during recompute (read-interception), so:
#   - it cannot be FORGOTTEN (positive: reading X means X invalidates me), and
#   - an unread source does NOT invalidate me (NEGATIVE: the load-bearing proof this is real
#     auto-capture, not @deps-by-hand — and that there is no over-capture either).
# Performance (Coder gate, load-bearing): an unchanged node does ZERO dep-walk on read — the version
# fold is memoized via dirty-propagation, not re-summed every frame.

describe "Cached / Source (auto-capture core)" do
  it "memoizes: recomputes only when a read dependency moves" do
    x = CrymbleUI::Source(Int32).new(1)
    runs = 0
    n = CrymbleUI::Cached(Int32).new { runs += 1; x.get * 10 }

    n.get.should eq 10
    runs.should eq 1
    n.get.should eq 10 # memo — no recompute
    runs.should eq 1

    x.set(2)
    n.get.should eq 20 # x moved → recompute
    runs.should eq 2

    x.set(2) # same value → no version move
    n.get.should eq 20
    runs.should eq 2
  end

  it "auto-captures the POSITIVE edge: reading a source registers the dependency (no hand-declared @deps)" do
    theme = CrymbleUI::Source(Int32).new(0)
    runs = 0
    n = CrymbleUI::Cached(Int32).new { runs += 1; theme.get }

    n.get
    runs.should eq 1
    theme.set(1)
    n.get.should eq 1
    runs.should eq 2 # invalidated purely because recompute READ theme
  end

  it "auto-capture NEGATIVE: a source NOT read does not invalidate (forgetting impossible, over-capture impossible)" do
    x = CrymbleUI::Source(Int32).new(1)
    y = CrymbleUI::Source(Int32).new(1)
    runs = 0
    n = CrymbleUI::Cached(Int32).new { runs += 1; x.get } # reads x, never y

    n.get
    runs.should eq 1
    y.set(99) # y is unrelated — n never read it
    n.get
    runs.should eq 1 # NOT invalidated by y
  end

  it "re-captures CONDITIONAL deps each recompute" do
    flag = CrymbleUI::Source(Bool).new(false)
    y = CrymbleUI::Source(Int32).new(0)
    runs = 0
    n = CrymbleUI::Cached(Int32).new { runs += 1; flag.get ? y.get : -1 }

    n.get.should eq -1
    runs.should eq 1
    y.set(5) # flag false → y was NOT read → not a dependency
    n.get.should eq -1
    runs.should eq 1
    flag.set(true) # flip → recompute now READS y, capturing it
    n.get.should eq 5
    runs.should eq 2
    y.set(6) # y is now a dependency
    n.get.should eq 6
    runs.should eq 3
  end

  it "folds NESTED Cached nodes (a node reading a node)" do
    x = CrymbleUI::Source(Int32).new(1)
    inner_runs = 0
    outer_runs = 0
    inner = CrymbleUI::Cached(Int32).new { inner_runs += 1; x.get * 2 }
    outer = CrymbleUI::Cached(Int32).new { outer_runs += 1; inner.get + 1 }

    outer.get.should eq 3
    inner_runs.should eq 1
    outer_runs.should eq 1
    outer.get.should eq 3 # both memoized
    inner_runs.should eq 1
    outer_runs.should eq 1

    x.set(10) # x → inner (20) → outer (21), propagated up
    outer.get.should eq 21
    inner_runs.should eq 2
    outer_runs.should eq 2
  end

  it "version() reflects a dep change WITHOUT recomputing the value (cheap aggregate fold)" do
    # The render-trigger aggregate folds node versions every frame; reading a version must NOT run the
    # compute (e.g. to_primitives). Value recompute is deferred to get().
    x = CrymbleUI::Source(Int32).new(1)
    runs = 0
    node = CrymbleUI::Cached(Int32).new { runs += 1; x.get }
    node.get
    runs.should eq 1
    v0 = node.version

    x.set(2)
    node.version.should_not eq v0 # version reflects the change...
    runs.should eq 1              # ...WITHOUT recomputing the value
    node.get.should eq 2          # value recomputed only on get
    runs.should eq 2
  end

  it "does ZERO dep-walk on an unchanged read (memoized version fold)" do
    x = CrymbleUI::Source(Int32).new(1)
    n = CrymbleUI::Cached(Int32).new { x.get }
    n.get # prime

    CrymbleUI::CacheNode.fold_iterations = 0
    5.times do
      n.get
      n.version
    end
    CrymbleUI::CacheNode.fold_iterations.should eq 0 # clean → no dep iteration at all

    x.set(2)
    n.get # now it must fold (one recompute)
    CrymbleUI::CacheNode.fold_iterations.should be > 0
  end

  it "registers a dependency in O(1) per read — a globally-read Source stays linear, not quadratic" do
    # The garbling-proofing win makes globals (theme/zoom) Sources that EVERY widget-node reads. With an
    # Array @dependents, each read's `includes?` dedup scans the whole list → O(N²) across N distinct
    # reader nodes (N = widget count, thousands in a matrix). A Set keeps each registration O(1). The
    # dep-probe instrument counts membership scan steps; this asserts the total stays O(N).
    source = CrymbleUI::Source(Int32).new(0)
    n = 150
    CrymbleUI::CacheNode.dep_probe_iterations = 0
    n.times do
      node = CrymbleUI::Cached(Int32).new { source.get } # each fresh node reads the one global Source
      node.get                                           # recompute registers node as a dependent
    end
    # Linear: ~O(N). The Array path is N(N-1)/2 ≈ 11_175 for N=150 — far past this non-brittle bound.
    CrymbleUI::CacheNode.dep_probe_iterations.should be <= 4 * n
  end

  it "touch() bumps the node's OWN version and forces recompute, independent of deps" do
    # A widget's content/layout change isn't a Source it reads — it's an intrinsic change the widget
    # signals. touch() must move the node's version (so consumers/aggregates see it) AND recompute.
    x = CrymbleUI::Source(Int32).new(1)
    runs = 0
    node = CrymbleUI::Cached(Int32).new { runs += 1; x.get }

    node.get
    runs.should eq 1
    v0 = node.version
    node.touch # intrinsic change, no dep moved
    node.get
    runs.should eq 2 # recomputed
    node.version.should_not eq v0 # version moved → consumers observe it
  end

  it "touch propagates to dependents (a touched child invalidates its parent)" do
    child = CrymbleUI::Cached(Int32).new { 1 }
    parent_runs = 0
    parent = CrymbleUI::Cached(Int32).new { parent_runs += 1; child.get + 1 }

    parent.get
    parent_runs.should eq 1
    child.touch
    parent.get
    parent_runs.should eq 2 # child's intrinsic change propagated up
  end

  it "fires on_dirty exactly once per clean→stale transition (the node-driven layer-enqueue hook)" do
    # A node going value-stale must enqueue its owning widget into the layer dirty index. The
    # generic hook is on_dirty, fired once on the clean→stale edge (re-enqueueing an already-dirty node
    # is wasted — it's already in the set).
    x = CrymbleUI::Source(Int32).new(1)
    node = CrymbleUI::Cached(Int32).new { x.get }
    fires = 0
    node.on_dirty = -> { fires += 1; nil }

    node.get # prime → clean
    fires.should eq 0
    x.set(2) # clean → stale: fires
    fires.should eq 1
    x.set(3) # already stale (not yet recomputed) → no new transition
    fires.should eq 1
    node.get # recompute → clean again
    x.set(4) # clean → stale: fires again
    fires.should eq 2
  end

  it "fires on_dirty on an intrinsic touch() too (content/layout change, not a dep)" do
    node = CrymbleUI::Cached(Int32).new { 1 }
    fires = 0
    node.on_dirty = -> { fires += 1; nil }
    node.get
    node.touch
    fires.should eq 1
  end

  it "DEFERS an on_dirty fired mid-recompute until the recompute completes (no re-entrant enqueue)" do
    # Safety rail: if a Source is set DURING another node's recompute (the forbidden 'mutate while
    # rendering' anti-pattern), the enqueue must not re-enter mid-compute — it fires after.
    sink = CrymbleUI::Source(Int32).new(0)
    log = [] of String
    watcher = CrymbleUI::Cached(Int32).new { sink.get }
    watcher.on_dirty = -> { log << "enqueue"; nil }
    watcher.get # prime → clean

    driver = CrymbleUI::Cached(Int32).new do
      log << "compute-start"
      sink.set(1) # marks watcher dirty mid-recompute → must DEFER
      log << "compute-end"
      42
    end
    driver.get
    log.should eq ["compute-start", "compute-end", "enqueue"] # fired AFTER the compute, not between
  end

  it "supports a Rev leaf source (bare monotonic counter)" do
    r = CrymbleUI::Rev.new
    v0 = r.version
    r.bump
    r.version.should_not eq v0
  end
end

describe "KeyedCached (version axis + geometric key)" do
  it "invalidates on key-change OR version-change; memoizes on same key + clean" do
    x = CrymbleUI::Source(Int32).new(1)
    runs = 0
    kc = CrymbleUI::KeyedCached(Int32, Tuple(Int32, Int32)).new { |key| runs += 1; x.get + key[0] }

    kc.get({0, 0}).should eq 1
    runs.should eq 1
    kc.get({0, 0}).should eq 1 # same key + clean → memo
    runs.should eq 1
    kc.get({5, 0}).should eq 6 # key changed → recompute
    runs.should eq 2
    kc.get({5, 0}).should eq 6 # memo
    runs.should eq 2
    x.set(10) # version moved → recompute (same key)
    kc.get({5, 0}).should eq 15
    runs.should eq 3
  end
end
