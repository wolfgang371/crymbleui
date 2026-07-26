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

The frame trigger (`RenderTrigger`) sums every widget's version into one aggregate — along with each layer's
`scroll_rev`, `position_rev`, `clear_rev`, and `render_rev` (the completeness token for a bare layer-level
dirty-mark), so a scroll or a panel drag moves the aggregate without any widget re-rendering — and renders a
frame **iff the aggregate moved**. No change → same number → 0% idle
CPU, no diffing, no dirty-walk. This is the same
idea as Salsa / incremental-computation frameworks: identity by version, not by deep comparison.

## Node lifecycle: registration ↔ **dispose**

Auto-capture is one-directional: a node's `get` adds it to each source's `@dependents`, and a source
clears those only on its own next `set`. That is fine for a source that is set often, but the **global**
sources (`Theme.@@current_source`, `FontSizing.@@zoom_index_source`) are set only on a rare theme/zoom
toggle. Every widget's `@primitives_node` reads them while painting, so without an explicit release a
*discarded* widget generation would stay pinned forever via `Source.@dependents → node → on_dirty → widget`
— an unbounded per-rebuild leak.

So a node has an end-of-life: **`CacheNode#dispose`** unregisters it from every source/node it captured
(`dep.remove_dependent(self)`) and drops its `on_dirty` hook. It runs on the trees that are actually thrown
away:

- **`App#rebuild`** calls `old_root.dispose_subtree` after reconcile — the new tree is built fresh and never
  inherits a `@primitives_node`, so the old and new node sets are disjoint and disposing the old ones is safe.
- **`Window#remove_overlay`** / the orphan branch of `cleanup_orphaned_overlays` dispose a dropped popup/menu
  (overlays live outside `@children`, migrated live across rebuilds, so they're released on their own drop
  path, not by the `old_root` walk).

Disposing is node-only: it never touches `@background_backend` (carried into the new tree by
`copy_state_from`) or focus/parent. It's terminal by construction — a disposed node's widget is unreachable
from `@root`, so it never paints again; and if one somehow did, `get_primitives` lazily mints a fresh node
(self-healing, no corruption).

**`Widget#dispose_pull_nodes` is the override seam.** The base releases `@primitives_node` (the only pull
node today). A widget that owns another pull node (e.g. a future `KeyedCached` buffer that reads zoom) MUST
override it as `super` + dispose its own — the contract is *every pull node a widget owns is released here*,
so the leak fix stays complete as new node-backed widgets are added.

## Two orthogonal axes (the thing to keep straight)

`cached.cr` tracks **what** a node depends on. That is *not* the same question as **where** its cached pixels
live. These are independent:

1. **Dependency freshness** — auto-captured reads + the version fold. "Are my primitives up to date?"
2. **Spatial coherence** — a geometric key (a buffer position) carried in lockstep, e.g. the VirtualMatrix
   viewport-cache slot. "Where do my cached pixels sit, and did the viewport move?" The concrete class is
   `KeyedCached(T, K)` (`cached.cr`): it recomputes on *either* a version change or a key change
   (`@value_stale || @key != key`), where the key is a geometric position that never enters the version sum.

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
since `Theme.current` calls `@@current_source.get` — the `Source(ThemeData)` that holds the active theme — reading it in `to_primitives` auto-captures that edge, so a `Theme.set` re-renders every follower for free. An explicit
`Color` is a sticky override that wins; set `nil` again to follow once more. A `ThemeColorRef`
(built with `Theme.ref(&.ruler_label)`) is a third state: a live reference resolved against a *different*
theme key at read time (via `v.resolve`). The full set is: `nil` (follow this property's own default theme
key), `Color` (frozen override), `ThemeColorRef` (live redirect to another key). (The override's setter is the one `mark_needs_render`
left in the macros — it fires only on an explicit, rare override; the theme-following default needs no push.)

The rule of thumb is **Source-back what renders.** A field never read while painting doesn't earn a `Source`:
a managed object uses `reconcile_property`; core widget *state* (`enabled`/`focus_highlighted`)
keeps an explicit `mark_needs_render` — a structural gate, not paint content; and hot per-frame fields stay
plain ivars for speed (next section).

**The one time you reach for a bare `Source(T)`** is reactive state that *isn't* a widget field — a global or
shared signal with no widget to hang a property on. The framework's two are class-level, with hand-written
accessors: `Theme`'s current data and `FontSizing`'s zoom index (`@@…_source : Source(T)`); a `Theme.set` /
zoom change calls `.set`, and every widget that read the value while painting auto-captures it and re-renders.
Inside a widget, wanting a bare `Source` field is the signal you actually wanted a `reactive_property`.

**Two-way binding — the third bare-`Source` case (app-owned).** The exception to "a widget field should be a
`reactive_property`, not a bare `Source`" is when the *app* owns the cell and hands it *in*. `text_input(bind: src)`
(`TextInput.new(bind:)`) ADOPTS the caller's `Source(String)` as its value cell instead of allocating a fresh one:
the widget reads it in `to_primitives` (auto-capture → re-render on `.set`) *and* its edits call `src.set` — so an
edit writes straight back to app state with no callback and no `request_rebuild`, and any other widget reading the
same `src` updates for free. The app holds `@name = Source(String).new(...)` (a bare `Source` — legitimate here, it
is app state, not a widget field) and passes it each build; because the *caller* owns it, the binding survives
reconcile with **no** widget-side carry — the freshly-built widget re-adopts the same object. `checkbox(bind: src)`
adopts a `Source(Bool)` the same way (a click writes it two-way); across widgets, **`bind:` always means "adopt this
`Source`"**. (The old plain-state checkbox auto-toggle sugar now lives on a separate keyword, `checkbox(toggle: state_var)`,
so `bind:` is never overloaded to mean two different things.) `combo_box(bind: src)` adopts a `Source(Int32)` — the
selected **INDEX**, not the value (derive the value via `items[idx]`); it is index-only, so `bind:` with an editable
combo (whose free-typed text can't round-trip an `Int32`) raises. `selected_index` is itself `reconcile: true`, but
that's a no-op for a bound combo — the reconcile carry is an identity *assignment* of the (shared) Source, never a
`.set`, so it can't clobber the caller's cell. **Invariant (all bind: widgets): pass a STABLE `Source` (an app ivar),
not a fresh one per build** — the same discipline as a stable `id:`. **Enforced:** a bound widget whose `Source`
changes identity on two consecutive rebuilds logs a one-time `WARNING` (gated on `Widget.enable_warnings`; test
counter `Widget.bind_stability_warnings`), catching the fresh-`Source.new(...)`-in-`build()` footgun. A *legitimate*
one-time rebind (identity changes once, then settles) does not trip it — the guard needs two consecutive swaps.
(Still open: binding a multi-select `combo_box` to a `Source(Set(Int32))`, and binding an editable combo's text —
both future work.)

**Caller contract:** `bind:` is safe only for a cell consumed *reactively* — read by widgets that paint it. A `.set`
on a bound `Source` fires a re-render, **not** a `request_rebuild`, so a value that gates a *structural* `build()`
branch (e.g. `if src.get.empty?` deciding whether a section exists) will not re-run `build()` and will silently
desync. Structure-gating state still uses `request_rebuild`.

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

### Timer-driven rebuilds

The SFML render loop checks `app.needs_rebuild?` on every iteration, not only after input events; the test
renderer's `render_frame_if_needed` does the same. A timer callback that mutates app state and calls
`request_rebuild` therefore fires a frame without waiting for the next mouse move or keypress — making the
pull model equally reliable for clock displays, polled data, and state-based animations.

## Using widgets: the two-mechanism model (the imgui-ease path)

Everything above is how the framework decides what to re-render. As a *consumer* of crymbleui (an app author
who mostly *uses* widgets rather than writing them) you almost never touch it. The design goal is that updating
the UI is as thoughtless as immediate-mode — change state, it shows — and two mechanisms cover nearly everything:

- **Structure or a display value changed → `request_rebuild`.** Re-run `build()`. This is the retained-mode
  analogue of imgui re-running every frame, and a full rebuild is cheap enough (~12–22 ms even for a large,
  matrix-heavy tree) that "just rebuild on any change" is a valid default — you do *not* have to reason about
  rebuild cost per interaction. This is also the *only* correct choice when a value's dependents are structural
  (rows/sections/chips that appear or disappear): a paint-only channel can't add or remove widgets.
- **A user EDITS a value → `bind: Source(T)`.** `text_input(bind: src)` / `checkbox(bind: src)` /
  `combo_box(bind: src)` (the selected index). The edit writes straight back to `src` with **no callback and no
  rebuild**, and every widget reading `src` updates for free. This is the one place the reactive model earns its
  keep — an edit that would otherwise cost a full rebuild per keystroke (a filter box, a form field).

`find(id)` + a reactive setter (`w.text = v`) is a **third, rare** tool: a targeted push into a *named* widget,
worth it only for a high-frequency *display* update where even a cheap rebuild is wasteful (e.g. a statusbar on
every mouse-move). If a plain `request_rebuild` would do, prefer it — it needs no id and no reasoning. Reaching
for `find+setter` on ordinary state is a premature optimization.

### The two footguns (the sweet spots to stay clear of)

1. **A fresh `Source.new(...)` created inside `build()` and passed to `bind:`.** Every rebuild re-adopts a *new*
   cell, so edits don't persist and cross-widget sharing breaks. Pass a STABLE `Source` — an app ivar re-passed
   each build; for keyed state a *storing* default gives stable per-key identity
   (`Hash(K, Source(String)).new { |h, k| h[k] = Source(String).new("") }`). **This footgun is now caught at
   runtime** — the widget logs a `WARNING` after two consecutive fresh Sources (see the bind: invariant above).
2. **Reading a `Source` in `build()` expecting it to be reactive.** `src.get` inside `build()` returns a *frozen
   snapshot* — `build()` is not a render node, so the read does not subscribe (see "Where you read decides the
   channel"). To make a value reactive you PASS the Source into the widget (`bind:`); you do not read it in
   `build()` and hope. **This one cannot be caught** — a build-time snapshot read is correct and common (the
   bind ctors themselves do it), so there is no false-positive-free runtime check; it is documentation only.
   The rule of thumb: **in `build()`, Sources are *passed*, not *read-for-reactivity*.**
