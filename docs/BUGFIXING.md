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

(VHTree is an embrace application widget composed of nested HStack/VStack rows — it is not a crymbleui class. The framework bug was in HStack/VStack.)

**Root cause**: HStack/VStack `perform_layout` set new bounds after zoom (e.g., 196x21 → 306x29) but never called `mark_needs_render`. `get_primitives()` returned cached primitives from the old size — a `fill_rect(0, 0, 196, 21)` rendered on a 306x29 widget_backend. The unfilled bottom region showed stale background content as "white lines" at every row boundary.

**Secondary cause**: Some VHTree rows used `vstack` wrappers which pass loose height constraints, so their HStack children measured to natural height (28.15) instead of the required 29px.

### Why diagnosis was slow

1. **Misleading "healing" signal.** The user reported checkbox clicks "heal" the seams. The healing was actually the checkbox *deselecting* the row (changing its color), not a rendering fix. A pure `request_rebuild` didn't fix anything — but we didn't test that until late.

2. **Layout was correct.** All widget bounds were integer-aligned, no gaps between rows. Every layout diagnostic said "all correct." The bug lived in the *cache invalidation* path between layout and rendering — invisible to bounds inspection.

3. **Symptom color (TEXT_COLOR) suggested text rendering.** The seam pixels (240,240,240) matched text color, and HStack children (28px) were shorter than their parent (29px). Both looked like text-positioning bugs. We spent time on Button centering and row padding before realizing these were symptoms of the stale fill_rect, not the cause.

### Rules

**Rule**: When a "heal" action exists, first test with the *minimal* heal (pure rebuild, no state change). If the bug persists after rebuild, the heal action has side effects that mask the real situation.

**Rule**: Stale primitive caches are invisible to layout diagnostics. When layout is correct but rendering is wrong, check whether `get_primitives()` returns primitives matching the current bounds. (A `DEBUG_STALE_PRIMITIVES` flag that asserts fill_rect dimensions match widget_backend size was proposed but never built. The real debug flags are `-Dverify_bounds` for constraint checks and `-DDEBUG_RENDER` for render logging.)

**Rule**: Size-change detection should live in the base `Widget.layout()`, not in individual subclasses. Button had already called `mark_needs_render` on size change; HStack/VStack had not. Moving this to the framework prevents the same class of bug from recurring.

**Why this check remains necessary after the reactive arc**: After the reactive migration, text-rendering widgets auto-capture the zoom source (`FontSizing.zoom_index_source`, a `Source(Int32)`) inside `to_primitives`, so a zoom change automatically invalidates their primitive cache. However, widget bounds are passed as a plain `Rect` to `to_primitives` — they are not reactive, so a size change never triggers pull-node invalidation. For layout containers like `VStack`, whose `to_primitives` only conditionally draws a background fill and does not read zoom at all, there is no reactive zoom-capture either. The base `Widget.layout()` size-change guard is therefore still the sole mechanism that forces a re-render when layout produces new dimensions.

# The instrument fleet (what proves what)

Four durable instruments replace the old ad-hoc SFML autotest pile (which violated the
temporary-instrumentation rule above). When hunting a rendering bug, reach for them in this order:

| Instrument | Command | Proves |
|---|---|---|
| Headless suite | `crystal spec spec/widgets` + the rest | All logic, layout, disposition, and pixel behavior the TestRenderer models — including text inking, compositor snapping, and blit arithmetic parity with SFML (the rounding/flip algebra is spec'd in `spec/rendering/pixel_snap_spec.cr` / `fbo_math_spec.cr`) |
| cv-coherency | `tools/cv-coherency.sh` | Cached-vs-immediate CONTENT-layer coherency headless, under `-Dcache_validation -Dverify_bounds` — the verify_bounds asserts (buffer-origin whole+fitting, sticky position invariants) and the sibling no-overlap RE-LAYOUT check (warn + `Widget.sibling_overlap_warnings`, self-tested by `spec/rendering/sibling_overlap_guard_spec.cr`) are ACTIVE only here, so this run is load-bearing, not optional. Blind spots: sticky layers (excluded by design) and uniform buffer-origin drift (cache and reference share the origin) |
| SFML parity sweep | `tools/sfml-parity.sh` | The axioms headless cannot model: real FBO orientation, GL scissor, glyph atlas, full-stack compositing — 3 configs × scroll patterns with per-phase non-vacuity counters, sticky GAP (black-pixel) + GARBLE (content-color) probes. CAVEAT: the two proven historical fault classes (blit_region recenter, buffer-origin drift) manifest as a DETERMINISTIC GLX crash on the current driver, so exit 2 ("no verdict") must be investigated as a possible regression, never waved through |
| Real-loop smoke | `spec/autotest/timer_rebuild_autotest.cr` | The SFML wait-event idle path (timer-driven rebuilds without input) |
| Clipboard round trip | `tools/clipboard-roundtrip-probe.cr` — `serve` / `read`, commands in its header | That non-ASCII survives the OS clipboard in BOTH directions across a real process boundary. No spec can prove it: `Testing::TestClipboard` stores a Crystal String verbatim, so it round-trips non-ASCII whether or not the real path does. NOTE `serve` must pump a window's events — SFML answers SelectionRequest only from its event loop, so a windowless owner takes the selection and never answers. Blind spots: payloads large enough to trigger INCR, Wayland, and target-atom negotiation (it compares bytes only) |

Perf attribution stays with the dedicated tools (`spec/autotest/grow_perf_autotest.cr`,
`spec/autotest/vmatrix_resize_perf_autotest.cr`) — measurements, not tests.

Reusable capture tooling for NEW hunts lives in `src/testing/layer_capture.cr` (per-layer/region
capture, the sticky-inclusive software window compositor, PNG dumps, black-pixel + tolerance
signatures) — extracted from the retired harnesses; build on it instead of re-copying.

For GPU-memory hunts, `src/testing/surface_leaks.cr` answers "did this interaction leak a surface?"
Scope the question with `TestRenderBackend.census_start` / `census_take`, then ask
`SurfaceLeaks.stranded(root, renderer, created)` for the censused surfaces that are undisposed AND
unreachable from the live tree. Ask it that way rather than bounding the number of live surfaces:
the live generation is legitimately undisposed and scales with how much is on screen, so a
count-based bound is either slack or wrong, while an unreachable surface is unambiguously lost
(under SFML the payload is a driver texture the collector cannot see). `spec/core/unreachable_backend_census_spec.cr`
is both its self-test and the worked example. It is what pinned the leak where `mark_needs_layout`
shed one background per ancestor per layout invalidation.

# Past SFML incidents (symptom → fix → guard)

Grep fodder: each retired debugging harness's institutional memory. "Guard" = what goes red today
if the fix regresses.

| Symptom | Fix | Guard today |
|---|---|---|
| Scroll past cache extent → cells snap to row-0 content (blit_region FBO Y-flip put the recenter overlap at the wrong dest; ~48% corruption) | 7e79842 (recenter copy → full blit) | `spec/rendering/instrument_tripwires_spec.cr` (containment: production must never regain a blit_region caller); `virtual_matrix_blit_shift_spec`; parity sweep (crash-class on current driver) |
| Small scroll down+up leaves garbling (stale background restore through viewport-cache recenter) | 3ee048f | `scroll_view_buffer_recenter_spec`; sweep CONFIG C sub-recenter |
| ScrollView content floats outside panel during resize-expand | 685adef | `window_panel_resize_content_bounds_spec`, `window_panel_scrollview_resize_spec` |
| Ruler row ~39 garbled across sticky+content after deep vscroll (compound/sticky positioning cluster) | b25fe3e, ef5a3de, 027571c | `tutorial22_bugs_spec`, `virtual_matrix_sticky_ghosting_spec`, `virtual_matrix_black_rows_spec`, cv-coherency; sweep deep-scroll GARBLE probe |
| Overlapping panels: drag-reveal ghost / scrollbar bleed-through / thumb frozen during resize | 685adef + 3ee048f | `panel_drag_reveal_ghost_spec` (NEW), `window_panel_scrollview_zindex_spec`, `scroll_view_resize_scrollbar_spec`, `panel_drag_live_rendering_spec` |
| Slow resize stops mid-drag (Content skip-path reset bounds to (0,0)) | 685adef (`Content#can_skip_layout? → false`) | `window_panel_resize_skip_path_spec` (NEW) |
| Horizontal sticky-scroll round-trip leaves black unrendered bands (buffer_origin drift) | 3e5904f (origin whole+fitting by construction) | `-Dverify_bounds` asserts via cv-coherency; sweep CONFIG B hops + black-pixel probe |
| Vertical compound+sticky scroll: wrong data snaps in / blank rows on return | 3e5904f, 7e79842, b25fe3e, 899046d | cv-coherency; `virtual_matrix_fractional_bounds_spec`; sweep pure-V multi-recenter |
| "Watery"/greyish button text after zoom (text-position rounding + headless truncation hid it) | 20a683b; structurally d2c1bcc; instrument parity 2de7f7e | `button_zoom_pixel_spec`, `composite_snap_spec`, `headless_text_snap_spec` |
| Garbled text on 2nd zoom cycle (stale SF::Font glyph atlas in a zoom-keyed cache) | 4a7b4a5 (cache deleted) | `instrument_tripwires_spec` guard (d) — cause-level; the atlas class is headless-invisible by nature |
| VirtualMatrix corruption after 2 zoom cycles (reconciled layer kept stale owner; zoom baseline lost on rebuild) | 4a7b4a5 | `reconcile_layer_registry_spec`, `virtual_matrix_zoom_spec`, `virtual_matrix_zoom_reconcile_spec` (NEW) |
