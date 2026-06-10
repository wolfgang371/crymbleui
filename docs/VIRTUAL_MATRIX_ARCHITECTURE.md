# VirtualMatrix Architecture

**Status**: IMPLEMENTED
**Last Updated**: 2026-02-21
**Related**: See `LAYER_RENDERING_ARCHITECTURE.md` for layer rendering pipeline, `RENDERING_PIPELINES.md` for rendering pipelines and cache validation

## Overview

VirtualMatrix is a high-performance virtual grid widget that renders only the cells visible within the viewport, dynamically creating and destroying cell widgets as the user scrolls. It supports sticky rows/columns (header pinning via scroll_order), merged/compound cells spanning multiple rows and columns, interactive column/row resize, cursor navigation with proxy focus delegation to cell widgets, and bi-directional ScrollView integration for scrollbar chrome. The grid operates across five rendering layers and three coordinate systems, with aggressive dimension caching to maintain O(log n) scroll performance on grids of arbitrary size.

## File Structure

```
src/widgets/virtual_matrix.cr              (1910 lines) Core class, layout, cell management
src/widgets/virtual_matrix/adapter.cr      (114 lines)  MatrixAdapter interface for data binding
src/widgets/virtual_matrix/cursor.cr       (312 lines)  Cursor navigation, snap_to_cursor, proxy focus
src/widgets/virtual_matrix/cursor_overlay.cr (106 lines) CursorOverlayWidget (highlight bands)
src/widgets/virtual_matrix/event_handlers.cr (387 lines) Mouse/keyboard/text event dispatch
src/widgets/virtual_matrix/ruler_widget.cr (286 lines)  4 ruler widgets (col/row/corner/corner_row_strip)
src/widgets/virtual_matrix/sticky_reposition.cr (223 lines) Sticky cell screen-space repositioning
src/widgets/virtual_matrix/sticky_math.cr  (109 lines)  Pure geometry: visibility ranges, sticky offsets
src/widgets/virtual_matrix/blit_plan.cr    (154 lines)  Fast-path blit plans for sticky cells
                                           ─────────
                                           3601 lines total
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
z = base+2..6 ScrollView layers      sticky_row, sticky_col, sticky_corner, scrollbars
z = base+8    cursor_overlay_layer   non-scrolling, additive/subtractive blend

ScrollView provides 3 sticky sub-layers:
  sticky_row_layer       scrolls X only, fixed Y   (column headers + ColumnRulerWidget)
  sticky_col_layer       scrolls Y only, fixed X   (row headers + RowRulerWidget)
  sticky_corner_layer    no scroll, fixed both      (corner cells + CornerRulerWidget + CornerRowStripWidget)
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

**content_layer**: Owned directly by VirtualMatrix (via LayerOwner). Uses `viewport_cache = true` with `cache_extent = 100.0` for smooth scrolling. Cell widgets are registered to `layer.widgets` and rendered at fixed content-space positions; the compositor handles the viewport shift via `layer.scroll_offset`.

**Sticky layers**: Owned by the child ScrollView. Cells on sticky layers are repositioned to screen-space coordinates every frame (via `reposition_sticky_cells` or the fast-path `compute_sticky_blit_plans`), because these layers do NOT use viewport_cache.

**cursor_overlay_layer**: Owned directly by VirtualMatrix. Renders cross-hair highlight bands via CursorOverlayWidget using additive blend (dark themes, positive `cursor_highlight_delta`) or subtractive blend (light themes, negative delta). Transparent background color `(0,0,0,0)`.

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
   ├── Early-exit if visible_key unchanged              [O(1) common case]
   │   └── reposition_sticky_cells or compute_sticky_blit_plans
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
   ├── WU3: Compute visible compound sizes (sticky compounds only)
   │
   ├── Re-layout during resize drag (content cells at affected positions)
   │
   ├── Reposition sticky cells (screen-space)
   │
   └── Register cell widgets to appropriate layers
       └── get_cell_layer() routes to content/sticky_row/sticky_col/sticky_corner
```

### Early-Exit Optimization

The `@last_visible_key` tracks `{visible_rows, visible_cols}`. When scrolling within the same set of visible indices (common during smooth scrolling), update_visible_cells returns early after only:
1. Repositioning sticky cells (screen-space update)
2. Ensuring layer.widgets are synced (idempotent flag-based)
3. Computing blit plans if eligible (fast path)

This makes the common scroll case O(sticky_cells) rather than O(visible_cells).

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

### Deferred Scroll Updates

Scrollbar drag fires many events per frame. Processing `update_visible_cells` on each would be expensive. Instead:

```
sync_from_scroll_view(new_offset):
  1. Update @scroll_offset (for correct compositing)
  2. Update layer.scroll_offset (compositor uses immediately)
  3. Set @pending_scroll_update = true (defer cell management)
  4. mark_needs_render

pre_render_flush():     <- Called by layer_renderer before rendering
  1. Process pending adapter invalidations
  2. If @pending_scroll_update -> update_visible_cells() once
```

This batches multiple scroll events into a single update_visible_cells call per frame.

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

This means smooth scrolling within the same column boundaries is O(log n) per frame, with O(n) recomputation only when a column actually enters or leaves the viewport.

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

### WU3: Visible Portion Computation

For sticky compound cells that are partially scrolled, WU3 computes the visible portion:

```
Sticky-row compound cell spanning cols 2-5:
  Col 2: behind sticky header -> excluded
  Col 3: partially visible (shifting_index) -> clipped
  Col 4-5: fully visible -> included

  compound_visible_size = size(col3_clipped) + size(col4) + size(col5)
  compound_clipped_pos  = position of first visible column (clamped to sticky boundary)
```

Content compound cells use FIXED sizes in content-space (the viewport_cache handles clipping), so WU3 only applies to sticky compounds.

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

```
QuickEntry (default):
  wants_arrow_keys? = false
  Arrow keys -> grid navigation (move between cells)
  Typing -> inserts text at cursor

FullEdit (after pressing Enter):
  wants_arrow_keys? = true
  Arrow keys -> text cursor movement within cell
  Enter/Escape -> exit FullEdit, return to QuickEntry
```

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

Cursor flash uses a repeating timer (`CURSOR_FLASH_MS = 400ms`) toggling `flash_on`. Moving the cursor restarts the flash cycle with `flash_on = true` for immediate visual feedback.

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

`setup_cursor_overlay_layer` defends against this by comparing the new
`overlay_bounds` against `last_rendered_bounds`; if either dimension grew,
it explicitly calls `mark_needs_clear_and_render`.

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
  Mark ruler widgets dirty
  Update corner widget bounds
  Sync sticky layer bounds
  update_visible_cells(...)    <- Re-layouts affected cells
  mark_needs_render            <- Render only, no full layout
```

During resize drag, `update_visible_cells` re-layouts only cells whose position or size is affected by the resized column/row. Cells to the left/above the resized dimension are skipped. Size-changed cells get `invalidate_primitive_cache + needs_fresh_background = true`; moved-only cells keep their cached `widget_backend` for fast-path blit.

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
# Reconciled properties (auto-copied to new instance):
layout_property scroll_offset : Vec2 = Vec2.zero, reconcile: true
reconcile_property cursor_rc : Tuple(Int32, Int32) = {0, 0}
reconcile_property resize_axis : ResizeAxis = ResizeAxis::None
# ... and other resize/drag state

# Content layer is reconciled (preserves layer state):
@[Reconcile]
@content_layer : Layer?

# Active cells are NOT reconciled:
# Cells are recreated fresh on rebuild to avoid bounds corruption
@active_cells : Hash(Tuple(Int32, Int32), Widget) = {} of ...
```

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
  @last_col_sticky_key -> @last_col_sticky_result    Full StickyMath output
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

1. **Layout is expensive, render is cheap**: After initial layout, scrolling and cursor movement NEVER call `mark_needs_layout`. They update `@scroll_offset` directly (bypassing the layout_property setter), sync to layer and ScrollView, and call `mark_needs_render`.

2. **Cells have fixed content-space positions**: Content cells are positioned at `ruler_offset + physical_cumulative[index]` and never move. The viewport_cache compositor handles viewport shifting. Only sticky cells need repositioning per frame.

3. **Single update_visible_cells per frame**: Multiple scroll events are batched via `@pending_scroll_update`, flushed once in `pre_render_flush()`.

4. **Sticky cells use screen-space coordinates**: Sticky layers are non-viewport_cache. Cells on these layers must be manually positioned using true content positions minus scroll_offset (for the non-fixed dimension).

5. **Dynamic handle for content compounds, static for sticky**: Content merged cells shift their widget key as parts scroll out. Sticky merged cells always use top-left to avoid destroy/create visual snapping.

6. **Hysteresis prevents thrashing**: Creation buffer (150px) < destruction buffer (200px). A cell entering the creation zone persists until it passes the larger destruction boundary.

## Performance Characteristics

| Operation | Cost | Notes |
|-----------|------|-------|
| Initial layout | O(n) | Builds all caches, creates initial cells |
| Smooth scroll (same indices) | O(log n) + O(sticky) | bsearch + early-exit + sticky reposition |
| Scroll across boundary | O(log n) + O(visible) | bsearch + StickyMath + cell create/destroy |
| Cursor move | O(1) render-only | mark_cursor_overlay_dirty, no layout |
| snap_to_cursor | O(visible) | May trigger update_visible_cells if scroll changed |
| Resize drag (per move) | O(affected_cells) | Re-layout cells at/after resized dimension |
| Resize end | O(1) | Update ScrollView content_size |
| Adapter cell invalidation | O(1) per cell | Deferred to pre_render_flush |
| Adapter full invalidation | O(n) | Destroy all, rebuild dimension caches |
| Size cache lookup | O(1) | Via cumulative arrays after O(n) build |
| StickyMath.sticky() | O(n) | But cached by boundary key, amortized O(1) |

### Memory Model

```
Per visible cell:   1 Widget instance + 2 RenderTextures (widget_backend + background_backend)
Per sticky cell:    Same, plus screen-space reposition per frame
Per ruler widget:   1 Widget + CachePolicy::Never (regenerated each frame)
Cursor overlay:     1 Widget + CachePolicy::Never, separate layer

Dimension caches:   O(rows + cols) arrays (sizes, cumulative, scroll_order)
Sticky caches:      O(visible) per cache key (positions hash, indices array)
```
