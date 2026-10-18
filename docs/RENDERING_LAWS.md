# Rendering laws

Governs: src/rendering/, src/core/layer.cr, src/core/layer_owner.cr, src/core/widget.cr, src/core/app.cr, src/core/drag_manager.cr, src/widgets/scroll_view.cr, src/widgets/fitted.cr, src/widgets/popup, src/widgets/menu.cr, src/layout/

The invariants a change to the render path must hold, each with the symbol that enforces it and
the section of `LAYER_RENDERING_ARCHITECTURE.md` that explains WHY. Read this file before touching
`src/rendering/`, `src/core/layer*.cr`, `src/widgets/scroll_view.cr` or `src/widgets/virtual_matrix/`.
The long doc is reference; this file is the contract.

## Coordinate spaces — three, and they are not interchangeable

| space | what it is | ask for it with |
|---|---|---|
| CONTENT | the laid-out position, summed up the parent chain | `absolute_bounds` |
| WINDOW | where the widget is actually PAINTED | `viewport_bounds`, `to_window(point)` |
| BUFFER | position inside a layer's texture | `LayerRenderer#paint_span(layer, c, start, len)` per axis; a viewport-cache slot key `slot_axis(abs, layer.content_rect, buffer_origin)` |
| below a SCALE | a fitted's subtree: content space drawn at a factor about the scaled child's origin - an `absolute_bounds` there means nothing to any ancestor | `viewport_bounds`, `to_window`, `to_content` - nothing else crosses |

- **A widget whose parent scrolls keeps its laid-out bounds; the pixels move instead.** A
  ScrollView composites its layer shifted; a VirtualMatrix paints its cells shifted. The parent
  declares how much it shifts each child by overriding `Widget#paint_shift_for(child)` (default
  zero; per CHILD, because a ScrollView's scrollbars stay put and a matrix's sticky cells are moved
  by the matrix itself - their bounds already hold the scroll).
- **Anything that meets the CURSOR or leaves the widget tree uses WINDOW space** — drag ghost,
  drop highlight, drop-target hit test, popup/menu anchors, a layer's composite position
  (`Layer#bounds`), Tab order and arrow navigation.
- **A layer is painted in its owner's CONTENT space, at its owner's factor, about its content-rect
  origin, and composited in WINDOW space.** The owner states the content rect
  (`compute_bounds_for_layer` → `absolute_bounds`, never `viewport_bounds`: `Layer#content_rect`, its
  position `C` the render origin) and the factor (`compute_scale_for_layer` → `Layer#render_scale`
  `f`: 1.0 for every owner but a fitted, PULLED like the rect - a fitted answers a carried property,
  so a reconciled layer and a fresh instance agree before the next layout). A content edge `e` lies at
  buffer coordinate `(e - C) * f` and at window coordinate `(C - owner.enclosing_scroll) + (e - C) * f`.
  The layer derives both: `Layer#size`, its extent in BUFFER and WINDOW pixels, is
  `content_rect.size * f`; `Layer#bounds` is `(C - owner.enclosing_scroll, size)`. So an ancestor's
  scroll moves the composite and leaves the buffer alone, and a repaint paints the content where it
  is laid out. Render sites read `content_rect`, composite sites `bounds`, readers of the layer's
  pixel extent `Layer#size` - never `content_rect.size`, which is unscaled. Enforced by
  `spec/rendering/layer_content_space_lint_spec.cr` (textual: no `viewport_bounds` in a
  `compute_bounds_for_layer`), `spec/rendering/scrolled_layer_space_spec.cr` and
  `spec/widgets/fitted_spec.cr`.
- **Below a scale, only `viewport_bounds` / `to_window` / `to_content` cross the boundary.** A parent
  that draws a child scaled declares it per child (`Widget#scale_for`, default 1.0 - a fitted), like
  the shift and the clip, and those three walks apply it (`Widget.scale_about` / `unscale_about`; at
  f == 0 every point maps to the origin, so no NaN reaches a handler). `enclosing_scroll` is only the
  ADDITIVE part of the crossing, and asserts it is never asked below a scale: the backstop behind a
  fitted's refusal of any layer owner inside it, whose `Layer#bounds` would ask and must fail loud,
  never composite silently in the wrong place. At most one factor on a chain: no layer owner inside a
  fitted (a fitted is one), so no fitted in a fitted. A factor change clears the fitted's layer and
  releases every surface of its subtree, so each widget re-captures over the cleared, parent-first
  buffer - never the flat fill a mere size change gives (a transparent child's parent showed through
  as a hole). Known limits, stated: popups and dropdowns opened from inside open at natural size; a
  DrawCircle outline stays 1px; text bearing offsets are computed at natural size.
- **A layer composites clipped by every scroller around it**: `owner.ancestor_clip`, the
  intersection of each ancestor's `Widget#clip_for(child)` - declared per child, like the shift (a
  ScrollView clips its content, not its scrollbars; a VirtualMatrix a cell to the layer painting
  it, not its chrome; a WindowPanel to its interior). All four sides, every depth; one rule for
  every composite (`LayerRenderer#composite_region`). The shift and clip walks stop after an
  overlay: a popup is placed and clipped in window space. Occlusion counts what a layer SHOWS; a
  layer showing nothing is skipped at its own turn in the render loop, after the flushes before
  it, so what a flush reveals is painted in that frame (`-Dverify_bounds`: `LayerSpaceError` if a
  later flush moves it).
- **A layer composites within the layer it is painted into** (`Layer.composite_order`): directly above it,
  below that layer's later siblings, at any depth - what covers a widget covers the layers inside it. The layer a
  widget is painted into is `Widget#painting_layer` (its own render_layer first). z orders only an owner's own
  layers; owners painted into one layer order by the rank that layer's owner declares, then boundaries by z,
  then tree order; boundaries are local; overlays come after the tree. Never order by a flat or inherited z: a
  scroll view's scrollbar once passed its grid's sticky header that way.
- **A click lands where it is drawn**: hit testing walks the composite order backwards
  (`Widget#children_in_hit_order`). The two agree because siblings do not overlap; a container whose children
  overlap would need an "owns a layer" tier in the key.
- **A drop highlight shows what the user sees of its target.** Its bounds are `visible_bounds` (the part
  no scroll view, popup or panel clips away), and it composites directly after the last layer painting
  the target, so a panel, sticky band or popup in front covers it as it covers the target. Never give an
  overlay that stands for a widget a fixed z: z 1000 put it over every panel's content and every sticky band.
- **A drop lands where a click would.** `DragManager#find_drop_target` starts from the hit test
  and walks up to the first DropTarget that takes the payload, so z order, popups, scrollbars and
  click-through hold for a drop exactly as for a click. Never search the tree for drop targets on
  its own: a second walk kept "in step" is how a drop once passed through the panel in front.
- **Culling skips painting, never the state the next input reads.** The frame that lowers the input
  barrier applies, before the next input, the structural work of every widget that announced it -
  painted or not (`App#finish_frame`; a VirtualMatrix's rebuilt cells and its proxy editor). A
  covered grid used to keep an announced rebuild pending while the barrier came down, and the next
  keystroke found no cell editor. Both renderers end `render_frame` with the render-trigger stamp,
  then `finish_frame`, and do not idle when it applied work.
- **Anything a widget is HANDED is already in the widget's own space** — `App` converts once, at
  its four dispatch sites plus `preferred_cursor`, and `DragManager` at the two drop-target hooks
  (`on_drop`, `on_drag_over`), via `Widget#to_content`. So `point -
  absolute_bounds` is correct in a handler without anyone thinking about scrolling. Never convert
  again inside a widget (VirtualMatrix used to, and converted twice).
- **Painting uses BUFFER space and `scroll_offset` does NOT appear in it** — the buffer stores
  content, shifted by `buffer_origin`; the COMPOSITE applies `scroll_offset - buffer_origin`. One
  geometry owner per axis, `LayerRenderer#paint_span` (origin and device span of a content range,
  for every paint path: the widget texture, both immediate passes, the foreground), and one slot-key
  helper, `LayerRenderer#slot_axis`; do not re-derive either (the foreground pass did, and painted
  every decoration 100px off).
- Enforced by `spec/rendering/window_space_containment_spec.cr` (cursor-facing files must not
  touch `absolute_bounds`) and `spec/rendering/scroll_space_sweep_spec.cr` (the invariant across
  vertical / horizontal / both / unscrolled, for nine consumers).
- Why: LAYER_RENDERING_ARCHITECTURE.md § "Coordinate Systems".

## The wheel

- **A scroller takes what it can and passes the rest on.** `App#handle_mouse_wheel` hands the delta to
  the widget under the point and then up the ancestors that handle the wheel (`on_mouse_wheel`), each
  returning what it did NOT take, until nothing is left. Per axis: an axis a scroller moved on is
  taken whole - a partial move too (the rest is dropped, as in a browser) - and an axis it cannot move
  on (no overflow there, or already at its end) goes on. No latching: each event is judged on its
  own, so a fling that empties an inner list goes on to its container (SFML reports no gesture
  phases to latch by).
- **The leftover travels in the INPUT frame.** A handler applies shift to what it READS and swaps the
  leftover back, so the next handler swaps it once (a VirtualMatrix under shift reads only delta.y,
  as x, and hands on delta.x untouched).
- **A grid's chrome ScrollView takes nothing** (`hands_wheel_on?`): the wheel over a grid's
  scrollbar does what it does over the grid - one scroll, the grid's clamp.

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
- **A viewport_cache layer is never scaled** (asserted at `render_layer`'s entry): its origin,
  recenter, slot keys and sampling have no scaled form. Only reachable if a fitted's refusal failed.
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
- **A scaled layer snaps EDGES.** `paint_span` keeps two formulas on purpose: unscaled it delegates
  to the contract-pinned `round_to_layer_pixels` / `device_pixel_span` (bit-identical); scaled it
  floors both scaled edges, so siblings sharing an edge share its pixel (the start + length form
  leaves a background column at a fractional factor). A covering fill (`FillRect#covers`, set by
  `fill_background`) becomes the device span itself (`DrawPrimitive.scaled_primitives`), covering by
  construction, and `-Ddebug_fill_coverage` checks covering fills and hand-written fills from the widget
  origin on every paint path. A text scaled
  below one pixel is dropped (`DrawText#scaled`).
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
compound axis (`StickyMath.compound_axis`), the paint position (`paint_span`, with `slot_axis` for the slot key), the screen-to-content
conversion (`to_content`).
