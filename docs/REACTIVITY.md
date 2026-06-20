# Reactivity: auto-capture, version counting, and the pull render model

How CrymbleUI decides *what to re-render* — and why a widget author almost never has to think about it.
(Porting an older widget to this model? See `MIGRATION.md`.)

---

## The problem it solves

A retained-mode GUI caches what it drew. The hard question is *cache invalidation*: when a value changes,
which cached pixels are now stale? The brittle answer is **push** — a setter calls `mark_needs_render`, wired
up by hand; miss one (read a value in `to_primitives` but forget to invalidate when it changes) and you get
**garbling**: stale cached pixels that never refresh. CrymbleUI makes that impossible to get wrong by
**pulling** instead — reading a value while painting is itself what registers the dependency.

## Auto-capture: reading a value declares the dependency

Every reactive value lives in a `Source(T)` (`src/core/cached.cr`). A widget's primitives are a memoized
`Cached` node whose recompute function is `to_primitives`. The trick is **read-interception**:

```crystal
# Source#get, simplified
def get : T
  if node = CacheNode.current      # are we inside a node's recompute?
    node.register_dep(self)        # then this read IS a dependency edge
  end
  @value
end
```

While `to_primitives` runs, `CacheNode.current` is that widget's node. So **every `Source` you read while
painting becomes a dependency automatically.** Change the source → its version moves → the node is stale →
the widget re-renders. You cannot forget an edge, because *reading the value is what declares it*. And a
source you *don't* read can't invalidate you — no over-rendering either.

This is the SolidJS / SwiftUI `@State` / Jetpack-Compose `mutableStateOf` model; React and Flutter are the
explicit-push camp (`setState` / `mark_needs_render`). Auto-capture is only possible for reads that go through
a tracked cell — a bare local or constant is never tracked, in *any* of these systems. The craft is making the
*changing* inputs cells; the rest takes care of itself.

## Version counting: how "stale?" is answered cheaply

A node never diffs values. It compares **versions** (monotonic `UInt64` counters):

```
node.version = node.local_rev  +  Σ (dep.version for each captured dep)
```

- A `Source.set` to a new value bumps that source's version and flags its dependents dirty.
- `local_rev` is the node's *own* intrinsic change (content/layout `touch`) — for things that aren't
  expressed as a captured source.
- Reading `node.version` re-folds the (cheap) dep sum; a clean node returns a memoized fold with **zero**
  dep-walk. The expensive `to_primitives` recompute is deferred until something actually reads the value.

The frame trigger (`RenderTrigger`) sums every widget's version into one aggregate and renders a frame **iff
the aggregate moved**. No change → same number → 0% idle CPU, no diffing, no dirty-walk. This is the same
idea as Salsa / incremental-computation frameworks: identity by version, not by deep comparison.

## Two orthogonal axes (the thing to keep straight)

`cached.cr` tracks **what** a node depends on. That is *not* the same question as **where** its cached pixels
live. These are independent:

1. **Dependency freshness** — auto-captured reads + the version fold. "Are my primitives up to date?"
2. **Spatial coherence** — a geometric key (a buffer position) carried in lockstep, e.g. the VirtualMatrix
   viewport-cache slot. "Where do my cached pixels sit, and did the viewport move?"

Conflating them is what makes scroll/cache code confusing. Scroll is *mostly* axis 2 (re-blit the buffer at a
new offset — no widget re-renders); a value edit is axis 1. Keep them apart and each is simple.

## The means: `Source(T)` and the property macros

One primitive, three macros built on it. You almost always write a macro, not `Source(T)` by hand.

**`Source(T)`** (`src/core/cached.cr`) is the reactive cell: `.get` returns the value *and* registers a
dependency when read inside a node's recompute (auto-capture); `.set` stores a new value, bumps its version,
and dirties dependents (equality-gated — a no-op write costs nothing).

To declare a widget field you pick **one macro**:

| macro | gives you | use it for |
|---|---|---|
| **`reactive_property name : T`** | a `Source(T)` field + getter (`.get`, auto-captures) + setter (`.set`, notifies) | any reactive value — **the default** |
| **`reconcile_property name : T`** | a *plain* ivar (no `Source`) carried across a rebuild | a managed `Layer`/`Widget` ref — infrastructure, never painted |
| **`theme_property name, key`** | a getter that resolves the global `Theme` `Source` live | a color that should follow the theme |

So `reactive_property color : Color` *is* "a `Source(Color)` field, plus `color`/`color=` that auto-capture
and notify." Read the getter (`color`, **never `@color`** — that's the raw `Source` object) in
`to_primitives`, and a change re-renders. That's the whole contract. Two optional flags refine
`reactive_property`:

- **`layout: true`** — the setter *also* calls `mark_needs_layout`. Use when the field changes the widget's
  size/position. (Layout is an imperative pass, not a pull node, so it must be poked explicitly —
  auto-capturing it would mean rebuilding layout as a node tree, a Flutter-scale rewrite we declined.)
- **`reconcile: true`** — the value survives a DSL rebuild: `@[Reconcile]` + a build-shadow carry it from the
  old widget instance (the app's build value wins if *it* changed).

`theme_property name, key` is `reactive_property`'s cousin for theme colors, and the one real difference is
**the default**. A `reactive_property` freezes a *constant* default (`= Color::White`); `theme_property`
defaults to `nil` meaning *follow the theme* — its getter resolves `Theme.current.key` live at read time, and
since `Theme.current` is itself a `Source`, a `Theme.set` re-renders every follower for free. An explicit
`Color` is a sticky override that wins; set `nil` again to follow once more. So `nil`/unset is the whole
distinction: a frozen value vs the live theme color. (The override's setter is the one `mark_needs_render`
left in the macros — it fires only on an explicit, rare override; the theme-following default needs no push.)

The rule of thumb is **Source-back what renders.** A field never read while painting doesn't earn a `Source`:
a managed object uses `reconcile_property`; core widget *state* (`visible`/`enabled`/`focus_highlighted`)
keeps an explicit `mark_needs_render` — a structural gate, not paint content; and hot per-frame fields stay
plain ivars for speed (next section).

**The one time you reach for a bare `Source(T)`** is reactive state that *isn't* a widget field — a global or
shared signal with no widget to hang a property on. The framework's two are class-level, with hand-written
accessors: `Theme`'s current data and `FontSizing`'s zoom index (`@@…_source : Source(T)`); a `Theme.set` /
zoom change calls `.set`, and every widget that read the value while painting auto-captures it and re-renders.
Inside a widget, wanting a bare `Source` field is the signal you actually wanted a `reactive_property`.

## Where you read decides the channel

`reactive_property` defaults to *correct*. The one lever you have is **where you read the field** — that, not
an annotation, chooses what a change invalidates:

- **Read it in `to_primitives`** → render-reactive. A change re-renders. (Auto-capture.)
- **Read it in `measure`/`perform_layout`** → it feeds layout. That pass isn't a pull node, so the edge isn't
  auto-captured; the `layout: true` setter pokes `mark_needs_layout` instead.
- **Leave it a plain ivar** → inert and free. Fields read thousands of times per frame in a hot loop (a
  matrix cell's `bounds`, `buffer_pos`) stay plain on purpose — a `.get` probe is wasteful per-cell, fine for
  an on-change value.

There is deliberately **no "untracked read / silent write" escape hatch** — a write whose follow-up you can
forget is the exact garbling we removed, wearing a new hat. If a write must not trigger a channel, that's a
channel *choice* (read it elsewhere), not a silent poke.

### The cross-layer boundary

Auto-capture reaches a value only through a node. A `CachePolicy::Never` widget (one that re-renders every
frame, e.g. an animating cursor overlay) has *no* node, so it cannot auto-capture a value it reads from
another widget. Those rare cross-layer reads need an explicit signal (or the reader made node-backed). This
is a real boundary, not a wart — it's the seam between the per-node pull model and genuinely
render-every-frame widgets.
