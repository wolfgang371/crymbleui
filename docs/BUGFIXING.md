# Causality sequence

root cause -> possible internal inconsistency -> symptom1 -> symptom2 -> etc.

actually, this is oversimplified - in a complex system (like we have) we might also suffer from _multiple_ root causes for one symptom.
this understanding is important, since single bugfixes will not work in such setups!

# Execution models

- I will typically use the SFML based visual system
- you will typically use the headless test system

both are supposed to behave identically, but every now and then a difference will show up.

## How to deal with differences in execution models

we always need to have a failing test case first.

(a) ideally this is a headless test (which will be commited later)
(b) if not possible w/ a headless test, we temporarily (i.e. not to be commited) use an automated SFML test instead
    - this will be used to also figure out the difference between the two execution models
    - and hence also be used to align the execution models
    - and to create a failing headless test (a) instead later

# Implementation sequence when hunting for a bug

1. we always need to have a failing test case first (see "How to deal with differences in execution models")
1. based on an automated test we can do further investigation
    - reasoning and/or
    - either instrumentation
1. identify (intermediate) hypothesis
1. it is important to construct an FTA (fault tree analysis)
    - observed symptom is root
    - nodes on next layer: either AND or OR
    - nodes on next layer: (intermediate) hypothesis
    - ... continue
1. in the course of investigation we will confirm (intermediate) hypothesis - or falsify
1. it is important to store the continuously developed FTA in such a way that it survives auto-compact, e.g. by continuously writing it to the plan file
1. at the end we have one sub-tree of the FTA as the proper FTA (which we can store in the commit message)
1. when we succeed we
    (a) re-confirm the bug is still detected w/ our headless test w/o the fix(es) being in place
    (b) confirm the bug is gone w/ our fix(es) in place
    (c) we have no regressions
    (d) remove all instrumentation
1. commit

# Lessons learned

## Layer-specific instrumentation early

When a bug manifests visually (e.g. black pixels, rendering gaps), add per-layer PNG dumps or pixel inspection **before** reasoning about code paths. In the Bug 2 investigation, content_layer PNGs immediately showed truncated compound cells — this was the smoking gun. Without them, many phases were spent suspecting compositor/buffer_origin/blit code.

**Rule**: If the symptom is visual, make it visible per-layer first. Reasoning without visual evidence in a multi-layer system wastes time.

## Overlapping root causes hide progress

Bug 2 had two independent root causes (compound cell sizing + buffer origin drift) producing the same symptom (black pixels after hscroll round-trip). Fixing one didn't reduce the symptom because the other still produced it. This led to falsely reverting correct fixes.

**Rule**: When a fix doesn't eliminate the symptom, check whether a second root cause exists before reverting. Use the "hot candidates" combination testing approach documented above.

## Question uniform code paths across architectural boundaries

Bug A happened because the visible-size shrinking of compound cells was applied uniformly to all of them. But content cells and sticky cells have fundamentally different coordinate models (fixed content-space vs viewport-relative). The fix was a two-line guard: `next if row >= sticky_rows && col >= sticky_cols`.

**Rule**: When code applies the same transformation to widgets on different layers or in different coordinate spaces, verify the transformation is correct for each case. Uniform application across architectural boundaries is a common source of subtle bugs.

## Assert invariants at the boundary, not just the output

A test asserting "content compound cell width == calculate_merged_width regardless of scroll position" would have caught Bug A at introduction time. Instead, the only tests verified final pixel output, which required both bugs to be fixed simultaneously.

**Rule**: Write invariant tests for intermediate state (cell sizes, positions, layer contents), not just end-to-end pixel tests. These catch bugs earlier and isolate root causes.

## Stale primitive cache after zoom (VHTree white lines)

**Root cause**: HStack/VStack `perform_layout` set new bounds after zoom (e.g., 196x21 → 306x29) but never called `mark_needs_render`. `get_primitives()` returned cached primitives from the old size — a `fill_rect(0, 0, 196, 21)` rendered on a 306x29 widget_backend. The unfilled bottom region showed stale background content as "white lines" at every row boundary.

**Secondary cause**: Some VHTree rows used `vstack` wrappers which pass loose height constraints, so their HStack children measured to natural height (28.15) instead of the required 29px.

### Why diagnosis was slow

1. **Misleading "healing" signal.** The user reported checkbox clicks "heal" the seams. The healing was actually the checkbox *deselecting* the row (changing its color), not a rendering fix. A pure `request_rebuild` didn't fix anything — but we didn't test that until late.

2. **Layout was correct.** All widget bounds were integer-aligned, no gaps between rows. Every layout diagnostic said "all correct." The bug lived in the *cache invalidation* path between layout and rendering — invisible to bounds inspection.

3. **Symptom color (TEXT_COLOR) suggested text rendering.** The seam pixels (240,240,240) matched text color, and HStack children (28px) were shorter than their parent (29px). Both looked like text-positioning bugs. We spent time on Button centering and row padding before realizing these were symptoms of the stale fill_rect, not the cause.

### Rules

**Rule**: When a "heal" action exists, first test with the *minimal* heal (pure rebuild, no state change). If the bug persists after rebuild, the heal action has side effects that mask the real situation.

**Rule**: Stale primitive caches are invisible to layout diagnostics. When layout is correct but rendering is wrong, check whether `get_primitives()` returns primitives matching the current bounds. A `DEBUG_STALE_PRIMITIVES` flag that asserts fill_rect dimensions match widget_backend size would catch this instantly.

**Rule**: Size-change detection should live in the base `Widget.layout()`, not in individual subclasses. Button already called `mark_needs_render` on size change; HStack/VStack forgot. Moving this to the framework prevents the same class of bug from recurring.
