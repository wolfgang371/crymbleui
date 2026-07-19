# VirtualMatrix Architecture

**Status**: IMPLEMENTED
**Last Updated**: 2026-06-19
**Related**: See `REACTIVITY.md` for the reactive model (property macros, Source-backed `scroll_offset`, the matrix viewport-cache slot as the canonical "spatial coherence" axis), `LAYER_RENDERING_ARCHITECTURE.md` for the layer rendering pipeline, `RENDERING_PIPELINES.md` for rendering pipelines and cache validation

## Overview

VirtualMatrix is a high-performance virtual grid widget that renders only the cells visible within the viewport, dynamically creating and destroying cell widgets as the user scrolls. It supports sticky rows/columns (header pinning via scroll_order), merged/compound cells spanning multiple rows and columns, interactive column/row resize, cursor navigation with proxy focus delegation to cell widgets, and bi-directional ScrollView integration for scrollbar chrome. The grid operates across five rendering layers and three coordinate systems, with aggressive dimension caching to maintain O(log n) scroll performance on grids of arbitrary size.

## File Structure

```
src/widgets/virtual_matrix.cr              (2184 lines) Core class, layout, cell management
src/widgets/virtual_matrix/adapter.cr      (199 lines)  MatrixAdapter interface for data binding
src/widgets/virtual_matrix/cursor.cr       (327 lines)  Cursor navigation, snap_to_cursor, proxy focus
src/widgets/virtual_matrix/cursor_overlay.cr (152 lines) CursorOverlayWidget (highlight bands)
src/widgets/virtual_matrix/event_handlers.cr (639 lines) Mouse/keyboard/text event dispatch
src/widgets/virtual_matrix/ruler_widget.cr (188 lines)  4 ruler widgets (col/row/corner/corner_row_strip)
src/widgets/virtual_matrix/sticky_reposition.cr (240 lines) Sticky cell screen-space repositioning
src/widgets/virtual_matrix/sticky_math.cr  (275 lines)  Pure geometry: visibility ranges, sticky offsets
src/widgets/virtual_matrix/blit_plan.cr    (426 lines)  Fast-path blit plans for sticky cells
                                           ─────────
                                           4630 lines total
```

## Class Structure

```
VirtualMatrix < Widget
  includes: LayerOwner, PrimitiveBuilder
  focus: focusable? = true, is_focus_scope? = true

  Inner Classes:
    DefaultAdapter          (fallback adapter for (rows, cols) constructor)
    ColumnRulerWidget       (column labels on sticky_row_layer)
    RowRulerWidget          (row labels on sticky_col_layer)
    CornerRulerWidget       (corner + sticky col labels on sticky_corner_layer)
    CornerRowStripWidget    (sticky row labels on sticky_corner_layer)
    CursorOverlayWidget     (row/col highlight bands on overlay layer)
```

## Data Model

### Sparse Cell Storage

```
@active_cells : Hash(Tuple(Int32, Int32), Widget)
```

Only cells within the creation buffer exist as widget instances. The key is `{row, col}` -- for merged cells, the key is the **handle cell** (see Merged Cells section). This keeps memory proportional to visible cells, not total grid size.

### Cell Sizing

Sizes are stored in **frame_height multiples** (like ImGui), converted to pixels via `@frame_height` (default 20.0):

```
@row_heights : Hash(Int32, Float64)    # Sparse: missing = DEFAULT_ROW_HEIGHT (1.0)
@col_widths  : Hash(Int32, Float64)    # Sparse: missing = DEFAULT_COLUMN_WIDTH (5.0)

pixel_size = GRID_SPACING + size_in_multiples * @frame_height
```

Constants:
- `GRID_SPACING = 3` pixels between cells
- `DEFAULT_COLUMN_WIDTH = 5.0` (100px at default frame_height)
- `DEFAULT_ROW_HEIGHT = 1.0` (20px + 3px spacing = 23px)
- `MIN_COL_WIDTH = 0.5`, `MIN_ROW_HEIGHT = 0.5`
- `RESIZE_TOLERANCE = 4.0` pixels from border to trigger resize

## Five-Layer Architecture

VirtualMatrix uses five rendering layers, each with different scroll behavior:

```
Layer Stack (z-index ascending)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
z = base+1    content_layer          viewport_cache, scrolls X+Y
z = base+3..7 ScrollView layers      internal, sticky_row, sticky_col, sticky_corner, scrollbars
z = base+8    cursor_overlay_layer   non-scrolling, additive/subtractive blend

ScrollView provides 3 sticky sub-layers (VM passes base_z+2 as parent_z; SV adds +1..+5):
  sticky_row_layer       scrolls X only, fixed Y   (column headers + ColumnRulerWidget)  z = base+4
  sticky_col_layer       scrolls Y only, fixed X   (row headers + RowRulerWidget)        z = base+5
  sticky_corner_layer    no scroll, fixed both      (corner cells + CornerRulerWidget + CornerRowStripWidget) z = base+6
```

### Layer Ownership and Scroll Behavior

```
                          ┌─────────────────────────────────────────┐
                          │  VirtualMatrix.bounds                   │
                          │                                         │
  ┌──────────┬────────────┤                                         │
  │  Corner   │  Col Ruler │  <- sticky_corner_layer (no scroll)   │
  │  Ruler    │  (sticky   │                                        │
  │  +Labels  │   col hdr) │  <- sticky_row_layer (scrolls X)      │
  ├──────────┼────────────┤                                         │
  │  Row      │            │                                        │
  │  Ruler    │  Content   │  <- content_layer (viewport_cache,     │
  │  (sticky  │  Cells     │    scrolls X+Y)                        │
  │   labels) │            │                                        │
  │           │            │  <- cursor_overlay_layer (non-scroll,  │
  │           │            │    additive/subtractive blend)         │
  │           │            │                                        │
  │           │            ├──┐                                     │
  │           │            │SB│ <- ScrollView scrollbar chrome       │
  ├──────────┴────────────┴──┤                                     │
  │         HScrollbar        │                                     │
  └───────────────────────────┘                                     │
                          └─────────────────────────────────────────┘
```

**content_layer**: Owned directly by VirtualMatrix (via LayerOwner). Uses `viewport_cache = true` with `cache_extent = 100.0` for smooth scrolling. Cell widgets are registered to `layer.widgets` and rendered at fixed content-space positions; the compositor handles the viewport shift via `layer.scroll_offset`. The layer is rendered with a **Pull/SlotBuffer** model (see "Content-Layer Render Model" below): each frame it visits every visible cell and slot-skips the ones whose buffer already holds their current pixels.

**Sticky layers**: Owned by the child ScrollView. Cells on sticky layers are repositioned to screen-space coordinates every frame (via `reposition_sticky_cells` or the fast-path `compute_sticky_blit_plans`), because these layers do NOT use viewport_cache.

**cursor_overlay_layer**: Owned directly by VirtualMatrix. Renders cross-hair highlight bands via CursorOverlayWidget using additive blend (dark themes, positive `cursor_highlight_delta`) or subtractive blend (light themes, negative delta). Transparent background color `(0,0,0,0)`.

### Buffer-origin contract — one reader, one writer

A `viewport_cache` layer's `buffer_origin` (the content coordinate at buffer pixel `(0,0)`) obeys one
invariant: it is **always whole-valued** and positioned so the viewport **fits** the buffer at it — per
axis `(scroll − origin).to_i ∈ [0, buffer − ceil(viewport)]`, degenerating to `floor(scroll)` only at zero
margin. Whole-valued is load-bearing: the render path subtracts `buffer_origin.to_i` (truncate-first) while
the composite truncates `(scroll − buffer_origin)` (subtract-first) — they agree only for an integer origin,
else a 1px seam.

The invariant is kept correct-by-construction by collapsing the math to **one reader and one writer**:

- **One reader** — `Layer#viewport_sample_origin(bw, bh, vw, vh)`: THE composite authority for "where in the
  buffer does the viewport start". Every composite path routes through it — `SFMLRenderer`, the
  `TestRenderer`, the `immediate_mode_only` ground-truth blit, and the `-Dcache_validation` instrument
  (`validate_immediate_mode`) — so no hand-mirrored copy can drift (the 2026-06-05 "content offset" hunt
  ended with a correct compositor and a drifted capture mirror; that class is now structurally impossible).
  The `.clamp` inside it is a **defensive memory-safety bound** on the texture read (prevents an OOB
  `blit_region`), **provably identity** under the invariant — not a behavioral fallback.
- **One writer** — `Layer#compute_buffer_origin(bw, bh)` computes the always-whole, always-fitting origin
  (preserving the `cache_extent` quantization grid away from capacity); `recenter_origin!` is the only
  public mutator and all first-render / needs_clear / recenter sites funnel through it.
- **Derived predicate** — the recenter gate `Layer#viewport_fits_buffer?` is *derived from the reader*
  (clamped == unclamped), so "gate says fits" ⟺ "composite won't clamp"; they cannot diverge.

Enforcement: under `-Dverify_bounds` the writer asserts the fit at the source and both composite seams
`raise` if a `viewport_cache` composite ever clamps (the invariant broke). CI runs the ScrollView/VMatrix
cache-validation job with this flag on.

## Three Coordinate Systems

```
1. CONTENT-SPACE                    2. SCROLL-SPACE                   3. SCREEN-SPACE
(Linear sum of cell sizes)          (Content - scroll_offset)         (For sticky layers)

  Cell positions are computed        viewport_cache layers use         Sticky layers are non-
  as cumulative sums:                this automatically via            viewport_cache. Cells
                                     layer.scroll_offset during        must be manually placed
  x = ruler_offset +                 compositing. Cell widgets         at screen positions:
      col_physical_cum[col]          stay at content-space
                                     positions.                        sticky_row: x = content_x - scroll.x
  y = ruler_offset +                                                              y = content_y (fixed)
      row_physical_cum[row]          No widget repositioning           sticky_col: x = content_x (fixed)
                                     needed for scrolling!                         y = content_y - scroll.y
                                                                       corner:     x = content_x (fixed)
                                                                                   y = content_y (fixed)
```

### Coordinate Translation During Scroll

```
Content cell (row=5, col=3):
  content_x = ruler_col_w + col_physical_cum[3]   = 40 + 309 = 349
  content_y = ruler_row_h + row_physical_cum[5]    = 20 + 115 = 135

  Scroll offset = (100, 50)

  In viewport_cache layer:
    Widget stays at (349, 135) in content-space
    Compositor shifts by -scroll_offset -> appears at (249, 85) on screen

  Sticky row cell (row=0, col=3):
    screen_x = 349 - 100 = 249   (scrolls with content horizontally)
    screen_y = 20                 (fixed vertically - ruler offset only)
```

## Cell Lifecycle and Virtualization

### Creation and Destruction Buffers

```
                    destruction buffer (200px)
                ┌───────────────────────────────────┐
                │   creation buffer (150px)          │
                │ ┌─────────────────────────────┐   │
                │ │   viewport_cache (100px)     │   │
                │ │ ┌─────────────────────────┐ │   │
                │ │ │                         │ │   │
                │ │ │   VIEWPORT              │ │   │
                │ │ │   (visible to user)     │ │   │
                │ │ │                         │ │   │
                │ │ └─────────────────────────┘ │   │
                │ └─────────────────────────────┘   │
                └───────────────────────────────────┘

  creation_buffer  = 150px  (cache_extent 100 + safety 50)
  destruction_buffer = 200px (creation 150 + hysteresis 50)
```

**Hysteresis**: Cells are created at 150px but destroyed at 200px. This prevents rapid create/destroy cycles when scrolling near the edge. A cell entering the creation zone is kept alive until it passes the destruction boundary.

### Cell Lifecycle Flow

```
1. update_visible_cells(viewport_w, viewport_h)
   │
   ├── Compute visible indices via StickyMath.sticky()  [O(log n) bsearch + cached O(n)]
   │
   ├── Early-exit if visible_key unchanged              [O(1) cell-set gate]
   │   └── reposition_sticky_cells or compute_sticky_blit_plans
   │       (only gates cell create/destroy — content re-render is
   │        decided per-slot at render time, see below)
   │
   ├── Compute creation/destruction regions (with buffers)
   │
   ├── For merged cells: resolve handle cells
   │   ├── Sticky compounds: permanent key = top-left
   │   └── Content compounds: dynamic_handle = first visible cell
   │
   ├── DESTROY cells outside destruction buffer
   │   └── Clears proxy_focus, removes from children/active_cells
   │
   ├── CREATE new cells via adapter.cell_paint()
   │   └── Layout at content-space position, mark needs_fresh_background
   │
   ├── Compute visible compound sizes (sticky compounds only)
   │
   ├── Re-layout during resize drag (content cells at affected positions)
   │
   ├── Reposition sticky cells (screen-space)
   │
   └── Register cell widgets to appropriate layers
       └── get_cell_layer() routes to content/sticky_row/sticky_col/sticky_corner
```

### Content-Layer Render Model (Pull / SlotBuffer)

The content layer is rendered with a **Pull/SlotBuffer** model, not a
dirty-widgets / early-exit model. Every frame, the layer renderer **visits every
visible cell** and decides re-render vs. skip per cell against a
`{rev, buffer_pos}` slot key (see `REACTIVITY.md`, axis 2 "spatial coherence",
for which the matrix viewport-cache slot is the canonical example; and
`LAYER_RENDERING_ARCHITECTURE.md` for the generic render mechanics):

- The slot key is `{content version, BUFFER position}` where the content version
  is the cell's `primitives_version` (auto-captures theme/zoom/layout) and the
  buffer position is `content_pos − buffer_origin`. The methods are
  `slot_fresh?` / `slot_rev_matches?` / `stamp_slot` on `Widget`.
- `slot_fresh?(buffer_pos)` → the buffer already holds this cell's current pixels
  at this buffer position (rev *and* buffer_pos unchanged since the last blit) →
  the renderer returns without touching it. This is the common smooth-scroll case.
- The soundness invariant is that `buffer_pos` moves **in lockstep** with the
  pixels: on a scroll recenter the buffer's pixels are **blit-shifted**, and
  `shift_slot(dx, dy)` shifts each cell's stamp by the same amount; a reflow/clear
  disposes the backend so the slot is forced stale. A re-entering or moved cell has
  a stale `buffer_pos` (or no backend) and falls through to re-render. Only the
  newly-exposed edge strip is actually re-rendered.

This visit-all-then-slot-skip model re-renders roughly **6.5× fewer cells per
scroll** than the previous dirty-widgets/early-exit approach, and it is
correct-by-construction: visiting every visible cell means a change to any cell
can never be missed.

**`@last_visible_key` is no longer the scroll optimization.** It tracks
`{visible_rows, visible_cols}` and now serves only as a **cell create/destroy
gate** in `update_visible_cells`: when the visible index *set* is unchanged
(common during smooth scroll), `update_visible_cells` skips the create/destroy
work and only repositions sticky cells / computes blit plans. Whether content
cells re-render is decided entirely by the per-slot check at render time, not by
this key.

## Scroll and Viewport Integration

### Bi-directional ScrollView Sync

VirtualMatrix owns `@scroll_offset` but delegates scrollbar UI to a child ScrollView:

```
VirtualMatrix <-------> ScrollView
  @scroll_offset         scroll_offset

  Push (VM -> SV):
    on_mouse_wheel, snap_to_cursor, perform_layout
    -> sv.set_scroll_offset_for_sync(@scroll_offset)

  Pull (SV -> VM):
    ScrollView scrollbar drag -> on_scroll_changed callback
    -> sync_from_scroll_view(new_offset)

  Sync detection:
    @last_synced_scroll_offset tracks which side changed
    If VM.offset != last_synced -> push to SV
    If SV.offset != last_synced -> pull from SV
```

### Scroll Updates (coalesced to once-per-frame)

Scrollbar thumb drag fires `on_scroll_changed` → `sync_from_scroll_view` on **every** mouse
event (~125Hz). Running `update_visible_cells` (cell create/destroy) on each one backs the event
loop up into a multi-second freeze at large grids. So the thumb path is **deferred**:
`sync_from_scroll_view` applies only the cheap compositing offset and flags
`@pending_scroll_update`; `pre_render_flush` runs the expensive cell management **once per
frame**, for the only scroll position the user actually sees. (`on_mouse_wheel` is discrete and
stays synchronous via `apply_scroll`.)

> This deferral was once removed as "unnecessary complexity" and the freeze came straight back —
> coalescing is the architecture, not an optimization. Each coalesced update is itself O(visible)
> (see StickyMath above), so the result is cheap *and* once-per-frame.

```
sync_from_scroll_view(new_offset):   <- scrollbar thumb/track, potentially every mouse event
  1. @scroll_offset.set(new_offset)              (Source.set — notify)
  2. layer.scroll_offset = new_offset            (compositor shifts cached content immediately)
  3. @pending_scroll_update = true               (DEFER cell create/destroy to the frame)
  4. mark_needs_render + mark_cursor_overlay_dirty
       (rulers self-enqueue via auto-captured scroll_offset)

pre_render_flush():                  <- called by layer_renderer once per frame, before render
  1. if @pending_scroll_update -> update_visible_cells ONCE   (the coalesced update)
  2. process pending adapter invalidations + change-animation
```

**Why the deferral lives in VirtualMatrix, not the event loop.** Render-coalescing is already
general: the SFML loop drains *all* queued events and renders once per batch (`sfml_renderer.cr`
— *"poll all pending events, don't render per event"*). But it still *dispatches* every mouse
event to widgets — deliberately, since dropping events would break anything that needs each one
(drag precision, gestures). `pre_render_flush` is likewise a general hook (`widget.cr`, invoked
on every layer owner). So the only VirtualMatrix-specific part is the *decision* to defer its
scroll work into that hook — and it's the only widget that needs to, because it's the only one
whose per-mouse-move work (cell create/destroy, sticky math, blit plans) is heavy enough to back
the event loop up. Cheap per-event widgets (hover, labels) ride the existing render-coalescing.

### effective_content_size Two-Pass Algorithm

When scrollbars appear, they reduce viewport space, which may trigger the other scrollbar:

```
Pass 1: Check if vertical scrollbar needed -> reduce width by SCROLLBAR_WIDTH (16px)
Pass 2: Check if horizontal scrollbar now needed -> reduce height
         Check if vertical scrollbar now needed (in case pass 1 didn't trigger it)
```

## StickyMath Algorithm

The `StickyMath.sticky()` function is the core visibility algorithm, ported from an ImGui implementation.

### Inputs and Outputs

```
Input:
  sizes_pixel    : Array(Int32)   Size per element in pixels (includes spacing)
  scroll_order   : Array(Int32)   Indices in order they scroll out (first = first to leave)
  min_pos_pixel  : Int32          Left/top viewport boundary
  max_pos_pixel  : Int32          Right/bottom viewport boundary

Output tuple:
  offset         : Int32                Total pixel offset of shifted-out elements
  positions      : Hash(Int32, Int32)   Visible index -> accumulated pixel position
  shifting_index : Int32                Currently-shifting element (partially visible)
  indices        : Array(Int32)         Visible row/col indices (paint order)
  indices_with_beyond : Set(Int32)      Visible + just-beyond indices (for culling buffer)
```

### Sticky Derivation from scroll_order

Sticky elements are **derived** from the scroll_order tail, not declared separately:

```
scroll_order = [2, 3, 4, 5, 6, 7, 0, 1]
                |-- scroll out first --| |- tail -|

Tail {0, 1} forms contiguous set {0, 1, ..., N-1} -> 2 sticky elements
Rows 0 and 1 are sticky (scroll out last, rendered at fixed positions)
```

The `derive_sticky_count` method walks the tail backwards, checking if the accumulated set equals `{0, 1, ..., size-1}`.

### Incremental Caching Strategy

Full `sticky()` recomputation is O(n). To avoid this per-scroll:

```
Per-resize (O(n) once):
  @cached_col_sizes        Array of pixel sizes
  @cached_col_cumulative   Running sums in scroll_order
  @cached_col_physical_cum Running sums in natural order

Per-scroll (O(log n)):
  bsearch on cumulative array -> {num_shifted, index_beyond}
  This is the "sticky cache key"

Full sticky() only when cache key changes:
  @last_col_sticky_key -> @last_col_sticky_result
  A boundary crossing (column shifts in/out) invalidates the cache
```

This means smooth scrolling within the same column boundaries is O(log n) per frame. When a column actually enters or leaves the viewport, the recompute (`sticky_fast`) is **O(visible), not O(n)**: shifted-out membership is answered in O(1) via a per-resize cached inverse permutation (`scroll_rank` → `StickyMath::ShiftedSet`), and positions are computed by walking only the visible window. This rests on the weak **seam invariant** — nothing scrolled out lives physically past the viewport bottom (top-down scroll cannot have passed a cell below it), asserted under `-Dverify_bounds`. No assumption is made that shifted cells form a contiguous physical prefix, so grouped / pivot layouts (a header pinned while its data scrolls out from under it) are handled directly.

## Merged/Compound Cells

### Bounding Box Model

```
cell_get_bounding_box(row, col) returns:
  { {min_row, min_col}, {max_row, max_col} }

Non-merged: { {row, col}, {row, col} }     (self)
Merged:     { {0, 0}, {0, 2} }             (3-column header spanning cols 0-2)
```

### Handle Cell Strategies

**Static handle (top-left)**: Used for sticky compound cells. The widget key is always `{min_row, min_col}`. Sticky cells don't need handle shifting because they are always visible (not subject to viewport_cache buffer limits).

**Dynamic handle (first visible cell)**: Used for content compound cells. When the top-left scrolls out, the first visible cell of the merged region takes over as the widget key. This uses `calc_visibles()` output to find the first visible row/col within the bounding box. Prevents destroy+create cycles as the merged region scrolls.

```
Example: Merged region (rows 3-5, cols 2-4)

Fully visible:    handle = {3, 2}   (top-left)
Row 3 scrolled:   handle = {4, 2}   (first visible row)
Row 3+4 scrolled: handle = {5, 2}   (last row)
All scrolled:     handle = nil       (entirely invisible, destroyed)
```

### Visible Portion Computation (Sticky Compounds)

For sticky compound cells that are partially scrolled, the visible portion is computed:

```
Sticky-row compound cell spanning cols 2-5:
  Col 2: behind sticky header -> excluded
  Col 3: partially visible (shifting_index) -> clipped
  Col 4-5: fully visible -> included

  compound_visible_size = size(col3_clipped) + size(col4) + size(col5)
  compound_clipped_pos  = position of first visible column (clamped to sticky boundary)
```

Content compound cells use FIXED sizes in content-space (the viewport_cache handles clipping), so this visible-portion computation only applies to sticky compounds.

## Cursor and Proxy Focus

### Cursor Navigation

The cursor is stored as `@cursor_rc : Tuple(Int32, Int32)` and supports:
- Arrow keys (with Ctrl for jump-to-edge)
- Home/End (with Ctrl for top-left / bottom-right)
- Tab/Shift+Tab (wrapping navigation across rows)

### snap_to_cursor

Auto-scrolls to keep the cursor cell visible. Follows the render-only pattern (no layout):

```
1. Compute cursor cell position in data-space (sum of sizes)
2. Account for sticky header dimensions
3. If for_edit=true, use full bounding box of merged region
4. Compare cell screen position against viewport boundaries
5. Adjust scroll_offset if cell is behind sticky header or off-screen
6. Clamp scroll values
7. If scroll changed: update layer.scroll_offset, sync to ScrollView,
   update_visible_cells, mark_needs_render
```

Key detail: `viewport_width/height` comes from `@content_layer.bounds.width/height`, which already accounts for scrollbar space via `effective_content_size()`.

### Proxy Focus Model

VirtualMatrix is a `focus_scope` -- it retains real FocusManager focus while delegating keyboard events to child cells:

```
VirtualMatrix (real focus, is_focus_scope?)
  └── @proxy_focused_widget -> TextInput cell
        @proxy_focused = true
        effectively_focused? = true -> renders cursor, handles text

Event dispatch (on_key_down):
  1. For non-nav keys: snap_to_cursor(for_edit: true) first
  2. If proxy exists:
     - Arrow keys -> forward only if proxy.wants_arrow_keys? (FullEdit mode)
     - Tab -> don't forward; fall through to grid nav below
     - Everything else -> forward to proxy
  3. Grid navigation (if proxy didn't consume):
     - Arrow keys -> move_cursor + snap_to_cursor
     - Tab/Shift+Tab -> move_cursor(:tab) round-robin + snap_to_cursor;
       matrix consumes Tab and stays focused (never cycles focus out)

Text input (on_text_input):
  1. snap_to_cursor(for_edit: true)
  2. Forward to proxy if exists
```

### QuickEntry vs FullEdit Modes (TextInput)

A grid text cell has two edit states. Enter TOGGLES between them (F2-style) and
never moves the cursor; the arrow keys are what accept-and-move in QuickEntry.

```
QuickEntry (cell-nav, default):
  wants_arrow_keys? = false
  Arrow keys -> grid navigation (move between cells; commits the current edit)
  Typing     -> replaces the cell's value (pending_replace on a fresh cell); the caret
                appears, but the mode STAYS QuickEntry so arrows still accept-and-move
  Enter      -> ENTER full-edit
  Escape     -> cancel any typed-but-uncommitted edit; back to the fresh type-to-replace
                state (value restored, NO caret)
  A fresh cell (not yet typed) shows the cursor cell-flash and NO caret.

FullEdit (character editing):
  wants_arrow_keys? = true
  Arrow keys -> move the text caret within the cell
  Typing     -> inserts at the caret
  Enter      -> commit + LEAVE full-edit (back to QuickEntry, SAME cell)
  Escape     -> cancel (restore value) + back to QuickEntry (clean, no caret)
```

The caret appears the moment you start typing or enter full-edit; a fresh cell
shows no caret (just the cell-flash), and the two never run at once (see Cursor
Overlay below).

## Cursor Overlay

The CursorOverlayWidget renders on a separate layer with additive or subtractive blending:

```
cursor_highlight_delta > 0:  Additive blend (brighten, for dark themes)
cursor_highlight_delta < 0:  Subtractive blend (darken, for light themes)

Primitives (when flash_on):
  1. Horizontal band  (row highlight, full width minus sticky col area)
  2. Vertical band    (col highlight, full height minus sticky row area)
  3. Cell flash rect  (intersection, brighter/darker intensity)

Bands extend into sticky areas to highlight headers, but NOT when
the cursor itself is on a sticky row/col (avoids header-highlighting-header).
```

Cursor flash uses a repeating timer (`CURSOR_FLASH_MS = 400ms`) toggling `flash_on`. Moving the cursor restarts the flash cycle with `flash_on = true` for immediate visual feedback. The whole-cell flash (primitive 3) is suppressed for the cursor cell while it draws its own caret (an actively-edited TextInput — see `cursor_cell_draws_edit_caret?`), so the flash and the caret never compete; a fresh (not-yet-typed) cursor cell shows the flash.

### Bounds-grow pixel-clear invariant

The cursor overlay layer is configured with `skip_rebuild_clear = true` because
the widget has `CachePolicy::Never` and regenerates primitives every frame —
so in normal operation a per-frame clear is wasteful. But `CachePolicy::Never`
only promises "fresh primitives", not "fresh pixels over the entire layer": the
widget only draws its current highlight region.

When the overlay layer's bounds *grow* (e.g. a sibling panel collapses and the
matrix gains height) while its pre-allocated backend still fits the new
bounds, `size_changed?` returns false and no automatic re-clear happens.
The newly-exposed area then retains whatever was there before (old highlight
pixels, or uninitialized memory for a fresh texture) — producing a cursor
band that stops one row short, or a ghost row below the data.

`setup_cursor_overlay_layer` defends against this declaratively: it sets
`@cursor_overlay_layer.not_nil!.clear_on_grow = true`. The renderer's
size-change handler checks `Layer#grew?` (compares `@last_rendered_bounds`
against current bounds) and clears the whole layer on a grow before the
partial painter runs. This is a generic Layer property, not a per-widget
guard — any partial-painter layer can opt in the same way.

## Interactive Resize

### Detection and Drag

```
detect_resize_edge(point):
  - Column borders: in top ruler strip (sy < ruler_h), within RESIZE_TOLERANCE (4px)
  - Row borders: in left ruler strip (sx < ruler_w), within RESIZE_TOLERANCE

On mouse_down:
  Store: resize_axis, resize_index, resize_start_mouse, resize_start_size

On mouse_move (during drag):
  delta_pixels = current_mouse - resize_start_mouse
  new_size = resize_start_size + delta_pixels / @frame_height
  set_col_width_for_drag(index, new_size.clamp(MIN, MAX))

On mouse_up:
  Update ScrollView content_size
  Clear resize_axis -> ResizeAxis::None
```

### O(1) Resize Drag

The `set_col_width_for_drag` / `set_row_height_for_drag` methods update the size hash and invalidate dimension caches but **do not call mark_needs_layout**. Instead:

```
set_col_width_for_drag:
  @col_widths[col] = width
  invalidate_dimension_caches
  @force_cell_update = true
  (No mark_needs_layout!)

on_mouse_move (resize):
  set_col_width_for_drag(...)
  mark_ruler_widgets_dirty     <- RESIZE-only; rulers don't depend on the resized geometry reactively
  Update corner widget bounds
  Sync sticky layer bounds
  update_visible_cells(...)    <- Re-layouts affected cells
  mark_needs_render            <- Render only, no full layout
```

During resize drag, `update_visible_cells` re-layouts only cells whose position or size is affected by the resized column/row. Cells to the left/above the resized dimension are skipped. Size-changed cells get `invalidate_primitive_cache + needs_fresh_background = true`; moved-only cells keep their cached `widget_backend` for fast-path blit.

**Rulers on scroll vs. resize.** The four ruler widgets are `CachePolicy::Dynamic`,
so their primitives nodes **auto-capture `scroll_offset`** (a Source). On a scroll,
the `scroll_offset` setter notifies and the ruler nodes self-enqueue for re-render
— `apply_scroll` does **not** call `mark_ruler_widgets_dirty`. `mark_ruler_widgets_dirty`
is **RESIZE-only**: a column/row size change alters geometry the rulers depend on
but which is not a reactive Source, so it must be marked explicitly (the cursor
overlay is `CachePolicy::Never` with no node, so it is still marked explicitly on
scroll via `mark_cursor_overlay_dirty`).

## Sticky Cell Rendering: Two Paths

### Full Path: reposition_sticky_cells

Computes screen-space positions for each sticky cell and calls `widget.layout()`:

```
For each sticky cell:
  1. Compute true content-space position (ruler_offset + cumulative[index])
  2. For non-sticky dimension:
     - Non-compound: Use StickyMath positions with pinning for shifting index
     - Compound: Compute screen-space bounding box from visible constituent cols/rows
       Pin at sticky boundary, collapse if fully behind header
  3. If position/size changed:
     widget.layout(constraints, new_position)
     widget.invalidate_primitive_cache
     widget.needs_fresh_background = true
```

### Fast Path: compute_sticky_blit_plans

The blit plan fast path skips layout+render for cells whose cached texture is still valid, but must NOT silently skip cells whose cache is absent:

```
Eligibility (sticky_cells_can_use_blit_plan?):
  - At least one sticky cell with widget_backend (so we have SOMETHING to blit)
  - No cached widget_backend is stale (has widget_backend AND needs_render)
  - No compound cells in non-sticky dimension (they resize on scroll)

  NOTE: cells WITHOUT widget_backend do NOT disqualify the fast path.
  They are freshly-created cells (e.g. a sibling section collapsed and new
  sticky rows became visible) and fall through to the render_list below.

Fast path:
  1. Compute new position (same logic as reposition)
  2. Update widget.bounds (for hit-testing)
  3a. If widget_backend present: create BlitEntry(source_backend, dest_x, dest_y)
  3b. If widget_backend absent: append widget to blit_plan_render_widgets
  4. Set layer.blit_plan = entries, layer.blit_plan_render_widgets = render_list
  5. mark_needs_full_render (triggers layer_renderer blit plan path)
```

Cost: O(sticky_cells) position math + O(sticky_cells) GPU blits + normal render for
any uncached cells (usually 0; a handful when bounds grow).

**Cache-validity invariant**: a cell participates in a blit plan only if its
`widget_backend` accurately reflects its current visual state. The builder MUST
check both "do I have a cached texture?" AND "is that cache stale?". Silently
skipping a cell that lacks a cache (instead of rendering it) leaves its layer
region untouched — blank pixels for the user.

## Push-Based Adapter Invalidation

The MatrixAdapter supports push-based change notification:

```
Adapter -> VirtualMatrix:
  invalidate_cell!(row, col)   -> @pending_cell_invalidations << {row, col}
  invalidate_all!              -> @pending_invalidate_all = true

pre_render_flush() (called before rendering):
  If invalidate_all:
    Re-read dimensions, destroy all cells, clear EVERY VM layer's pixels,
    trigger_update_visible_cells
  If cell invalidations:
    Destroy specific cells, trigger_update_visible_cells
```

Cell-level invalidation destroys only the affected cell from `@active_cells`. The next `update_visible_cells` call will recreate it via `adapter.cell_paint()`, picking up the new data.

**Full-invalidate pixel-clear invariant**: `flush_invalidate_all` MUST call
`mark_needs_clear_and_render` on every VM-owned layer — content, sticky_row,
sticky_col, AND cursor_overlay. The cursor overlay is easy to overlook because
its widget has `CachePolicy::Never` ("it always paints fresh"), but the widget
only paints its CURRENT highlight region; pixels outside that region are not
touched. If the previous highlight covered a wider area than the post-invalidate
one, those old pixels remain visible — the cursor band appears to extend past
the last data row.

## Reconciliation

VirtualMatrix supports DSL-style apps where `build()` creates new widget instances on every rebuild:

```crystal
# Reconciled properties (auto-copied to new instance).
# reactive_property is Source-backed (see REACTIVITY.md); reconcile: true adds
# the @[Reconcile] annotation so the value carries to the new instance.
reactive_property scroll_offset : Vec2 = Vec2.zero, reconcile: true
reactive_property cursor_rc : Tuple(Int32, Int32) = {0, 0}, reconcile: true
reactive_property resize_axis : ResizeAxis = ResizeAxis::None, reconcile: true
# ... and other resize/drag state

# Object refs are carried over via reconcile_property (non-reactive: no
# Source backing, no read-sweep — just the @[Reconcile] carry-over):
reconcile_property content_layer : Layer?

# Active cells are NOT reconciled:
# Cells are recreated fresh on rebuild to avoid bounds corruption
@active_cells : Hash(Tuple(Int32, Int32), Widget) = {} of ...
```

> The property macros are `reactive_property` (Source-backed; takes `layout:` and
> `reconcile:` flags), `reconcile_property` (non-reactive object-ref carry-over),
> and `theme_property`. The former `render_property` / `layout_property` macros are
> gone — see `REACTIVITY.md` for the reactive model.

The `copy_state_from` override handles:
1. `auto_copy_reconcile_properties(old_widget)` -- copies all `@[Reconcile]` annotated properties
2. Preserves user-resized col/row widths (`.dup` to avoid aliasing)
3. Clamps cursor to new matrix dimensions
4. Rebinds adapter invalidation callbacks to the new widget instance
5. Invalidates dimension caches and forces cell update

`@last_synced_scroll_offset` is deliberately NOT reconciled: after rebuild, the ScrollView is fresh (offset=0), so the push branch must fire to seed it with the reconciled scroll_offset.

## Dimension Caching

### Cache Hierarchy

```
Per-resize (invalidated by invalidate_dimension_caches):
  @cached_total_width/height         Float64  Total content size
  @cached_col_sizes/row_sizes        Array(Int32)  Pixel sizes per element
  @cached_col_cumulative/row_cum     Array(Int32)  Running sums in scroll_order
  @cached_col_physical_cum/row_phys  Array(Int32)  Running sums in natural order
  @cached_col_scroll_order/row_so    Array(Int32)  Scroll order from adapter
  @cached_sticky_row_count/col_count Int32  Derived sticky counts

Per-scroll (keyed on bsearch boundary):
  @last_col_sticky_key -> @last_col_sticky_result    sticky_fast() output (5th element: ShiftedSet, not Set(Int32))
  @last_row_sticky_key -> @last_row_sticky_result
  @cached_first_visible_cols/rows                    calc_visibles output

Per-scroll (creation/destruction regions):
  @last_creation_col_key -> @last_creation_col_result
  @last_destruction_col_key -> @last_destruction_col_result
  (and corresponding row versions)
```

### Invalidation

`invalidate_dimension_caches()` clears ALL caches. Called when:
- Column/row size changes (col_width, row_height setters)
- Interactive resize drag (set_col_width_for_drag)
- Full adapter invalidation (flush_invalidate_all)
- Reconciliation (copy_state_from)

## Key Invariants

1. **Layout is expensive, render is cheap**: After initial layout, scrolling and cursor movement NEVER call `mark_needs_layout`. `scroll_offset` is a Source-backed `reactive_property`; scroll-changing paths write it via `@scroll_offset.set` (or the `scroll_offset=` setter) and route through `apply_scroll`, which composites (updates `layer.scroll_offset`), optionally syncs the ScrollView, recenters (`update_visible_cells`), and marks render. The setter does NOT call `mark_needs_layout` — scroll never re-layouts.

2. **Cells have fixed content-space positions**: Content cells are positioned at `ruler_offset + physical_cumulative[index]` and never move. The viewport_cache compositor handles viewport shifting. Only sticky cells need repositioning per frame.

3. **Scroll cell-management is coalesced to once-per-frame**: The scrollbar thumb path (`sync_from_scroll_view`) is deferred — it applies the compositing offset immediately but only sets `@pending_scroll_update`; `pre_render_flush` drains it once per frame, calling `update_visible_cells` exactly once for the scroll position the user actually sees. The wheel/snap path (`apply_scroll`) calls `update_visible_cells` synchronously because wheel events are discrete. Within `update_visible_cells` the `@last_visible_key` cell-set gate skips create/destroy work entirely when the visible index set is unchanged. Per-cell content re-render is decided separately at render time by the Pull/SlotBuffer per-slot check.

4. **Sticky cells use screen-space coordinates**: Sticky layers are non-viewport_cache. Cells on these layers must be manually positioned using true content positions minus scroll_offset (for the non-fixed dimension).

5. **Dynamic handle for content compounds, static for sticky**: Content merged cells shift their widget key as parts scroll out. Sticky merged cells always use top-left to avoid destroy/create visual snapping.

6. **Hysteresis prevents thrashing**: Creation buffer (150px) < destruction buffer (200px). A cell entering the creation zone persists until it passes the larger destruction boundary.

## Performance Characteristics

| Operation | Cost | Notes |
|-----------|------|-------|
| Initial layout | O(n) | Builds all caches, creates initial cells |
| Smooth scroll (same indices) | O(log n) + O(sticky) + O(edge strip) | bsearch + cell-set gate + sticky reposition; only the newly-exposed edge re-renders (Pull/SlotBuffer) |
| Scroll across boundary | O(log n) + O(visible) | bsearch + StickyMath + cell create/destroy |
| Scrollbar thumb drag | O(visible) per **frame** | N queued mouse events coalesce to one `update_visible_cells` at `pre_render_flush` — not per event (else multi-second freeze) |
| Cursor move | O(1) render-only | mark_cursor_overlay_dirty, no layout |
| snap_to_cursor | O(visible) | May trigger update_visible_cells if scroll changed |
| Resize drag (per move) | O(affected_cells) | Re-layout cells at/after resized dimension |
| Resize end | O(1) | Update ScrollView content_size |
| Adapter cell invalidation | O(1) per cell | Deferred to pre_render_flush |
| Adapter full invalidation | O(n) | Destroy all, rebuild dimension caches |
| Size cache lookup | O(1) | Via cumulative arrays after O(n) build |
| StickyMath.sticky_fast() | O(visible) | Per-boundary-key recompute; O(1) shifted-membership via cached inverse permutation (`scroll_rank`). `sticky()` (O(n)) is the reference impl / spec ground truth |

### Memory Model

```
Per visible cell:   1 Widget instance + 2 RenderTextures (widget_backend + background_backend)
Per sticky cell:    Same, plus screen-space reposition per frame
Per ruler widget:   1 Widget + CachePolicy::Never (regenerated each frame)
Cursor overlay:     1 Widget + CachePolicy::Never, separate layer

Dimension caches:   O(rows + cols) arrays (sizes, cumulative, scroll_order)
Sticky caches:      O(visible) per cache key (positions hash, indices array)
```
