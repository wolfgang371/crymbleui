# Rendering laws

Governs: src/rendering/, src/core/layer.cr, src/core/layer_owner.cr, src/core/widget.cr, src/core/app.cr, src/core/drag_manager.cr, src/widgets/scroll_view.cr, src/widgets/popup, src/widgets/menu.cr, src/layout/

The invariants a change to the render path must hold, each with the symbol that enforces it and
the section of `LAYER_RENDERING_ARCHITECTURE.md` that explains WHY. Read this file before touching
`src/rendering/`, `src/core/layer*.cr`, `src/widgets/scroll_view.cr` or `src/widgets/virtual_matrix/`.
The long doc is reference; this file is the contract.

## Coordinate spaces — three, and they are not interchangeable

| space | what it is | ask for it with |
|---|---|---|
| CONTENT | the laid-out position, summed up the parent chain | `absolute_bounds` |
| WINDOW | where the widget is actually PAINTED | `viewport_bounds`, `to_window(point)` |
| BUFFER | position inside a layer's texture | `slot_axis(abs, layer.bounds, buffer_origin)` |

- **A widget whose parent scrolls keeps its laid-out bounds; the pixels move instead.** A
  ScrollView composites its layer shifted; a VirtualMatrix paints its cells shifted. The parent
  declares how much it shifts each child by overriding `Widget#paint_shift_for(child)` (default
  zero; per CHILD, because a ScrollView's scrollbars and a matrix's sticky rows/columns stay put).
- **Anything that meets the CURSOR or leaves the widget tree uses WINDOW space** — drag ghost,
  drop highlight, drop-target hit test, popup/menu anchors, a layer's own bounds
  (`compute_bounds_for_layer`), Tab order and arrow navigation.
- **Anything a widget is HANDED is already in the widget's own space** — `App` converts once, at
  its four dispatch sites plus `preferred_cursor`, via `Widget#to_content`. So `point -
  absolute_bounds` is correct in a handler without anyone thinking about scrolling. Never convert
  again inside a widget (VirtualMatrix used to, and converted twice).
- **Painting uses BUFFER space and `scroll_offset` does NOT appear in it** — the buffer stores
  content, shifted by `buffer_origin`; the COMPOSITE applies `scroll_offset - buffer_origin`. One
  helper, `LayerRenderer#slot_axis`; do not re-derive it (the foreground pass did, and painted
  every decoration 100px off).
- Enforced by `spec/rendering/window_space_containment_spec.cr` (cursor-facing files must not
  touch `absolute_bounds`) and `spec/rendering/scroll_space_sweep_spec.cr` (the invariant across
  vertical / horizontal / both / unscrolled, for nine consumers).
- Why: LAYER_RENDERING_ARCHITECTURE.md § "Coordinate Systems".

## Capture invariants

- **(f) Rendering precondition** — a widget may render into `widget_backend` only if the backend
  is new or its background was restored. `assert(background_restored, ...)` in
  `LayerRenderer#render_single_widget`.
- **(g) Memorization precondition** — restore a background only if one was rendered AND memorized
  AND its size matches; otherwise re-render rather than compose over garbage.
- **(h) Capture purity** — a background capture must contain only what is BENEATH the widget,
  never the widget itself.
- **(h2) A capture needs something painted beneath it.** Covering the buffer is conditional (an
  ancestor can be culled, dropped or return early) while capturing was not, so a widget could
  memorize an empty band and restore that emptiness over its parent's content forever after. When
  a capture would be blind, render DIRECT-TO-LAYER instead (no texture, nothing memorized).
  `LayerRenderer.pass_covered?` + `mark_covered` (a per-pass counter and a per-widget stamp — NOT
  a map, and NOT inside the overridable `record_widget_disposition`, which `TestRenderer` replaces
  without `super`). Regression: `spec/rendering/scroll_shift_stale_background_spec.cr`.
- **(siblings) No overlap** — sibling widgets must not overlap; a capture beneath an overlap is
  ambiguous by construction.
- **Parent-first render ordering** is necessary but NOT sufficient for (h2): being earlier in the
  list is not the same as having painted.

## Buffers and caches

- **`buffer_origin` has ONE production writer**, `Layer#recenter_origin!`; it is whole by
  construction and every reader may assume that. It is `Vec2.zero` off the viewport_cache path.
- **A viewport_cache layer's buffer is viewport + 2x cache_extent.** A grow that still fits keeps
  its backend; only a viewport too big for the buffer needs a new one.
- **The per-slot skip is the buffer's own claim**: `slot_fresh?(buffer_pos)` means the buffer
  already holds this cell's pixels at that position — which is why a `:skipped` widget still
  counts as COVERED for (h2).
- **`tiled_cells` layers render direct-to-layer after a clear** (no per-cell texture): a cleared
  buffer has nothing to capture.
- What invalidates what: LAYER_RENDERING_ARCHITECTURE.md § "Cache-Coherency Contract".

## Pixels

- **`PixelSnap` owns every float-to-device-pixel conversion.** `origin` = floor and
  DIFFERENCE-FIRST, `span = origin(start+len) - origin(start)`, `cover` = ceil for culling and
  clip extents. Sizes, vector fills and content-space values stay raw BY POLICY. Ad-hoc
  `.round/.to_i/.floor/.ceil` on coordinates fails `spec/rendering/pixel_snap_lint_spec.cr`, whose
  file table a new render-path file must join.
- **Clipping**: the layer pushes its own clip; a widget that needs one pushes and pops within its
  own paint. Never leave a clip on the backend across widgets.

## Layout laws that reach the render path

- **An unbounded constraint must survive the trip down.** Derive a child constraint with
  `{x - padding * 2, 0.0}.max`, never `.clamp(0.0, Float64::MAX)`: `INFINITY.clamp(0, MAX)` is
  MAX, a FINITE number, which defeats every `finite?` guard below it — a nested scroller then took
  all 1.79e308 of it and its parent rendered nothing.
  Regression: `spec/layout/unbounded_constraint_spec.cr`.

## When a rule appears twice

Give it one named owner in the same arc. Every defect in this file's history was a rule written
in two places where one copy was wrong: the placement arithmetic (fixed by `centred_in`), the
compound axis (`StickyMath.compound_axis`), the paint position (`slot_axis`), the screen-to-content
conversion (`to_content`).
