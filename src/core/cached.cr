module CrymbleUI
  # Pull-cache core. Two orthogonal axes (see docs/REACTIVITY.md):
  #   1. dependency freshness — AUTO-CAPTURED reads (this file): a dependency is created by READING its
  #      source during a recompute, so an edge cannot be forgotten and an unread source cannot invalidate.
  #   2. spatial coherence — a geometric key carried in lockstep (KeyedCached), about WHERE cached pixels
  #      live, not WHAT they depend on.
  #
  # The model is pull-on-read with dirty-propagation (SolidJS/Salsa-style): a Source bump marks its
  # dependents dirty (push the bit up); a clean node's read returns its memo with ZERO dep-walk; a dirty
  # node recomputes, RE-capturing its dependency set (so conditional deps are always current).

  # Anything exposing a monotonic version. A raw counter (Rev / Source) OR a derived node (CacheNode).
  module VersionSource
    abstract def version : UInt64
  end

  # A bare monotonic counter — a leaf input rev not carrying a value (e.g. a layer's position_rev).
  class Rev
    include VersionSource
    @version : UInt64 = 0

    def version : UInt64
      @version
    end

    def bump : Nil
      @version &+= 1
    end
  end

  # A tracked input value. Reading it during a recompute auto-registers it as a dependency of the
  # currently-computing node; setting a *different* value bumps its version and marks dependents dirty.
  class Source(T)
    include VersionSource
    @version : UInt64 = 0
    # A Set, not an Array: dependent registration must be O(1) per read — a globally-read Source
    # (theme/zoom) accumulates one dependent per widget, and an Array `includes?` dedup would make every
    # read O(dependents) (quadratic across the widget tree). Dedup is by object identity either way.
    @dependents = Set(CacheNode).new

    def initialize(@value : T)
    end

    def get : T
      if cur = CacheNode.current
        cur.register_dep(self)
        CacheNode.note_dep_probe # one O(1) Set probe per registration
        @dependents.add(cur)
      end
      @value
    end

    def set(value : T) : Nil
      return if value == @value
      @value = value
      @version &+= 1
      # Mark dependents dirty and clear them — they re-register on their next recompute.
      stale = @dependents
      @dependents = Set(CacheNode).new
      stale.each(&.mark_dirty)
    end

    def version : UInt64
      @version
    end
  end

  # Base for memoized derived nodes. Holds the shared dependency/dirty/version machinery so the only
  # difference between Cached and KeyedCached is how their value is computed. Non-generic so the capture
  # stack and back-edges can hold heterogeneous nodes.
  abstract class CacheNode
    include VersionSource

    # The node currently recomputing (the auto-capture target). The render loop is single-threaded, so a
    # class variable is the capture context; recompute pushes/pops it.
    @@current : CacheNode? = nil

    def self.current : CacheNode?
      @@current
    end

    # Write through an explicit CacheNode class method (not a bare `@@current = …` in an inherited
    # method) — a bare assignment from a Cached(T)/KeyedCached subclass method targets the SUBCLASS's
    # copy of the class var, which Source would never read.
    def self.current=(node : CacheNode?) : CacheNode?
      @@current = node
    end

    # Perf instrument: counts dep-fold iterations so a spec can assert zero dep-walk on an unchanged read.
    @@fold_iterations = 0

    def self.fold_iterations : Int32
      @@fold_iterations
    end

    def self.fold_iterations=(value : Int32) : Int32
      @@fold_iterations = value
    end

    # Explicit class-method increment — a bare `@@fold_iterations += 1` from a subclass method would hit
    # the subclass's copy, not the one the instrument reads.
    def self.note_fold : Nil
      @@fold_iterations += 1
    end

    # Perf instrument: counts dependent/dep membership-probe steps so a spec can witness
    # that registering a dependency is O(1) per read (a `Set`), not O(n) (the old `Array#includes?` scan
    # — quadratic for a globally-read Source like theme/zoom that one widget-node per widget reads).
    @@dep_probe_iterations = 0

    def self.dep_probe_iterations : Int32
      @@dep_probe_iterations
    end

    def self.dep_probe_iterations=(value : Int32) : Int32
      @@dep_probe_iterations = value
    end

    def self.note_dep_probe : Nil
      @@dep_probe_iterations += 1
    end

    # Deferred enqueue list: an on_dirty fired while a recompute is in flight
    # (CacheNode.current != nil — the forbidden mutate-during-render anti-pattern) is queued here and
    # fired when the OUTERMOST recompute completes, so an enqueue never re-enters a compute.
    @@pending = [] of -> Nil

    def self.defer(callback : -> Nil) : Nil
      @@pending << callback
    end

    def self.drain_pending : Nil
      return if @@pending.empty?
      batch = @@pending
      @@pending = [] of -> Nil
      batch.each(&.call)
    end

    @deps = Set(VersionSource).new
    @dependents = Set(CacheNode).new
    @cached_version : UInt64 = 0
    @local_rev : UInt64 = 0
    # Two independent staleness bits so the render-trigger aggregate can fold node versions CHEAPLY:
    # reading version() only re-FOLDS (sum of cheap dep revs) — it never recomputes the value. The
    # expensive value recompute is deferred to get(). Both start true (never computed).
    @version_stale : Bool = true
    @value_stale : Bool = true

    # The node-driven enqueue hook: fired ONCE on the clean→stale edge, set by the
    # owning widget to enqueue itself into its layer's selective-render index. Generic `-> Nil` so
    # cached.cr stays Widget-free.
    @on_dirty : (-> Nil)? = nil

    def on_dirty=(callback : (-> Nil)?) : Nil
      @on_dirty = callback
    end

    # Called by a dependency's getter while this node is recomputing (forward edge, for the fold).
    def register_dep(dep : VersionSource) : Nil
      CacheNode.note_dep_probe # one O(1) Set probe per registration
      @deps.add(dep)
    end

    # Signal an INTRINSIC change — one not expressed as a tracked Source the node reads (e.g. a widget's
    # content/layout change). Bumps the node's own rev (so its version moves for consumers/aggregates)
    # and marks it dirty (recompute on next read), propagating to dependents.
    def touch : Nil
      @local_rev &+= 1
      mark_dirty
    end

    # Mark stale and propagate up to my own dependents. The version bit is always re-set (so a later
    # version() re-folds); the value bit + propagation fire once per clean→stale transition.
    def mark_dirty : Nil
      @version_stale = true
      return if @value_stale
      @value_stale = true
      fire_on_dirty
      stale = @dependents
      @dependents = Set(CacheNode).new
      stale.each(&.mark_dirty)
    end

    # Fire the enqueue hook — but DEFER if a recompute is in flight (current != nil), so an on_dirty
    # triggered mid-compute fires after the outermost recompute, never re-entrantly.
    private def fire_on_dirty : Nil
      cb = @on_dirty
      return unless cb
      if CacheNode.current
        CacheNode.defer(cb)
      else
        cb.call
      end
    end

    # My version = local_rev + fold of captured deps' versions. CHEAP: a clean node returns the cached
    # fold (O(1), zero dep-walk); a stale node only RE-FOLDS (no value recompute).
    def version : UInt64
      if @version_stale
        @cached_version = fold_version
        @version_stale = false
      end
      @cached_version
    end

    # Has a fresh memoized value (computed and not since invalidated)? False before the first get and
    # after any touch / dep change, until the next get recomputes.
    def valid? : Bool
      !@value_stale
    end

    # Register me with the node reading me (nested fold), if any.
    protected def track : Nil
      if cur = CacheNode.current
        cur.register_dep(self)
        CacheNode.note_dep_probe # one O(1) Set probe per registration
        @dependents.add(cur)
      end
    end

    # Recompute the value under the capture context (re-capturing deps), then re-fold the version.
    protected def recompute : Nil
      @deps.clear
      prev = CacheNode.current
      CacheNode.current = self
      begin
        compute_value
      ensure
        CacheNode.current = prev
      end
      @cached_version = fold_version
      @version_stale = false
      @value_stale = false
      CacheNode.drain_pending if prev.nil? # outermost recompute done → fire any deferred enqueues
    end

    private def fold_version : UInt64
      v = @local_rev
      @deps.each do |dep|
        CacheNode.note_fold
        v &+= dep.version
      end
      v
    end

    # Subclass hook: recompute and store the value (reads its sources, which auto-register).
    protected abstract def compute_value : Nil
  end

  # A memoized derived value, pulled on read. `version = Σ captured-deps.version`, recomputed iff a dep
  # moved. The dependency set is discovered by READING sources inside the compute block.
  class Cached(T) < CacheNode
    @value : T?

    def initialize(&@compute : -> T)
    end

    def get : T
      track
      recompute if @value_stale
      @value.as(T)
    end

    protected def compute_value : Nil
      @value = @compute.call
    end
  end

  # The spatial specialization: a memoized value keyed by BOTH its version fold AND a geometric key K
  # (e.g. a buffer position). Recomputes on key-change OR version-change. K is structural — it is NOT a
  # VersionSource and never enters the version sum; it is "where the cached pixels live".
  class KeyedCached(T, K) < CacheNode
    @value : T?
    @key : K?
    @next_key : K?

    def initialize(&@compute : K -> T)
    end

    def get(key : K) : T
      track
      if @value_stale || @key != key
        @next_key = key
        recompute
        @key = key
      end
      @value.as(T)
    end

    protected def compute_value : Nil
      @value = @compute.call(@next_key.as(K))
    end
  end
end
