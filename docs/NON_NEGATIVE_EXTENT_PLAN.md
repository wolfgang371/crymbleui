# Non-Negative `Extent` Type — Plan (Deferred)

**Status:** Proposal, deferred. Not scheduled. Written after the 2026-06-13/14
resize + focus bug arc as the "once and for all" option for the
misalignment / scaling / overflow class. Read alongside
[`TYPED_COORDINATES.md`](TYPED_COORDINATES.md) (the *signed-position* counterpart)
and [`GRACEFUL_DEGRADATION.md`](GRACEFUL_DEGRADATION.md) (the existing *runtime*
non-negative-dimension validation this would make unnecessary).

## Problem

A recurring bug class: layout arithmetic computes a **negative width/height**
(`size − padding`, `size − scrollbar`, `baseline + ancestor_delta`, an empty
rect intersection), that negative flows into a texture dimension, and
`SF::RenderTexture.new(w.to_u32, …)` turns it into a huge `UInt32` →
`OverflowError("Arithmetic overflow")` + garbled rendering. Examples from the
arc: maximized panel narrowed below `2·CONTENT_PADDING`; the resize-clip
subtracting the *panel's* delta from a narrow inner layer (mid-drag layer width
hit −434).

The fixes were per-site clamps (`Math.max(0.0, …)`) and a re-architected
clip-to-content-rect. Those work, but each is a place a future contributor can
forget the clamp. A type that makes a negative extent **unrepresentable** would
eliminate the whole class by construction.

## What already nets this class (so a type is the *last 20%*)

- **Strict `TestRenderBackend`** — rejects negative dimensions (was silently
  masked headless; only blew up under SFML).
- **Resize + focus fuzzers** (`spec/fuzz/resize_focus_fuzz_spec.cr`) — invariants:
  no negative layer bounds, matrix height invariant under width-only resize,
  re-expand after a round-trip, focus never escapes the scope.
- **Faithful shared dispatch** (`FocusManager#dispatch_key`, used by both the
  SFML renderer and the headless tester) so input-path bugs are observable.
- **Validation-before-render** (see `GRACEFUL_DEGRADATION.md`): layer/widget
  dims checked `> 0` / finite at render time.
- A full suite run under `-Dverify_bounds` (a `Size.new` non-negativity guard)
  showed **production never constructs a negative `Size`** across 1530+ examples —
  only one test does, on purpose, to exercise `is_empty?`.

So this proposal buys the *by-construction* guarantee, not new coverage of
today's known failures.

## Design

`Extent` = a non-negative scalar (`Float64 >= 0`) for a width/height.

Two decisions define the entire effort:

1. **Separate signed from unsigned.** Positions, offsets and deltas stay signed
   (`Vec2`, scroll offsets, "how much did this shrink"). Extents do not.
   `Size` becomes `Extent × Extent`; `Vec2` stays `Float64 × Float64`. (This is
   orthogonal to the abs-vs-relative *coordinate* confusion — that's
   `TYPED_COORDINATES.md`.)

2. **Subtraction semantics — the crux.** You'd want `Extent − x` to *saturate at
   0* (so `width − padding` can't go negative). But the same expression shape is
   sometimes a legitimate **signed delta** (`new_w − old_w`, the resize-clip
   delta). A single `Extent` type cannot auto-resolve this; blanket saturation
   would silently destroy real deltas (a *new* bug class). Therefore:
   - clamped extents use an **explicit** `saturating_sub` / `inset(total, by)`;
   - signed deltas are computed in `Float64`.
   This makes the migration **non-mechanical**: every subtraction site needs a
   "clamped extent or signed delta?" decision. That review *is* the cost.

Resolved sub-points (not blockers):
- **Empty:** `Extent(0)`; `is_empty?` collapses from `<= 0` to `== 0`;
  `Size.zero == Extent(0) × Extent(0)`. The only casualty is the test that
  constructs a negative on purpose.
- **Infinity:** `Extent` must represent `+∞` (`BoxConstraints` unconstrained).
- **Conversions:** safe `to_i` / `to_u32` / `ceil` / `round`; the texture
  boundary takes `Extent`, so its runtime guards become unnecessary.

## Two levels — and only the expensive one pays off

- **Level 1 — storage typing only** (`Size.width : Extent`, guard at `Size.new`).
  Prototyped via `-Dverify_bounds`; caught nothing new (production is clean), and
  intermediate `Float64` arithmetic still flows unprotected. **Low value.**
- **Level 2 — arithmetic typing** (geometry computations flow through saturating
  `Extent`). The only level that prevents the class. **The real churn.**

"Add an `Extent` type" therefore means Level 2 or it isn't worth doing.

## Invasiveness (concrete, measured 2026-06-14)

- `Size.new` ×136 (47 files), `Rect.new` ×195 (45 files) — mostly survive *if*
  `Extent` accepts `Float64`/`Int` implicitly at construction. Low risk.
- **773 `.width` / `.height` reads — the churn epicentre.** If `.width` returns
  `Extent`, every read used in arithmetic (`x + width`, `width / 2`,
  `width.to_i`, `Math.min(width, …)`, comparisons with `Float64`, string
  interpolation) needs either full `Float64` interop on `Extent` (which *loses*
  the saturating benefit on mixed ops → back to Level 1) or an explicit `.to_f`
  per site (safe but hundreds of edits). No free lunch.
- `BoxConstraints` (`min/max_width/height`, `+∞`) — dozens more sites.
- Conversions + the texture boundary (`CrSFMLBackend`, `TestRenderBackend`) —
  the payoff: they become safe by type.
- **Cross-lib ripple**: `core`/embrace reads crymbleui geometry; `.width`
  returning `Extent` can leak across the boundary.

Rough effort: **a few hundred edited sites across ~50 files, plus a per-
subtraction-site semantic review** (the non-mechanical part). Cannot be done
half-way safely — a partial migration creates a confusing two-world API.

## Risks

- **Silent delta destruction** if a subtraction is mis-classified as saturating —
  a new bug class introduced by the fix.
- **Performance**: fine if `Extent` stays a `struct` wrapping `Float64` and
  inlines; verify.
- **Broad regression risk** across ~50 files → the fuzz/invariant suite is a
  hard prerequisite, run green after every step.

## Phased migration (only if approved)

1. Introduce `Extent` (struct; `>= 0` ctor; explicit `saturating_sub`/`inset`;
   `Float64` interop for *reads*; safe `to_u32`; `+∞`). Additive, nothing uses it.
2. Migrate **VirtualMatrix sizing** end-to-end first (the bug-richest subsystem),
   arithmetic included; fuzzers green. This calibrates the real per-site cost on
   the worst case before committing to the rest.
3. Roll outward `Size` → `Rect` → `BoxConstraints`, each behind the green
   fuzz/invariant suite.
4. Make the texture boundary take `Extent`; delete the runtime clamps/guards
   (now impossible by type).

## Recommendation

**Defer.** The boundary nets + fuzzers catch this class where it actually causes
damage, and production is already clean. Pursue the full type only for the
by-construction guarantee, as a dedicated multi-day effort with the fuzz suite as
the safety net.

If we want *more than the nets* before then, two cheaper options rank higher:

- **Middle path (surgical):** a tiny saturating-geometry vocabulary —
  `inset(total, by)` / `Extent.sub` — applied only at the ~dozen
  "size − padding/scrollbar/title-bar" sites that are the actual bug origins.
  Named, greppable, "can't write the bug without trying"; no type-system
  upheaval.
- **Higher value, likely:** the coordinate-space phantom types in
  `TYPED_COORDINATES.md`. The abs-vs-relative confusion caused real bugs;
  negative extents are already well-netted, so coordinate typing is the better
  next type-safety investment.
