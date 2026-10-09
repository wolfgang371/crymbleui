# VirtualMatrix laws

Governs: src/widgets/virtual_matrix

What a change to `src/widgets/virtual_matrix/` must hold. `VIRTUAL_MATRIX_ARCHITECTURE.md` is the
reference that explains why; this file is the contract. See also `RENDERING_LAWS.md` — the matrix
is a scroller, so every coordinate law there applies to it.

## The matrix is a scroller that is not a ScrollView

- **Cells keep CONTENT positions; the matrix paints them shifted.** A cell's `absolute_bounds`
  does not change when the matrix scrolls (measured: a cell stays at x=143 while the scroll goes
  46 -> 60). The compositor applies `-scroll_offset` for the content layer.
- **Sticky layers are non-viewport_cache and hold one axis still**: a sticky ROW scrolls X and is
  fixed in Y; a sticky COLUMN is fixed in X and scrolls Y; the corner is fixed in both.
- **Sticky cells are MOVED, not shifted.** The sticky pass (`reposition_sticky_cells`, and the blit
  plan's mirror - both apply `sticky_cell_rect`) rewrites a sticky cell's bounds screen-relative on
  every scroll, and the sticky layers composite unshifted - so a sticky cell (and a ruler, a fixed
  band that draws its numbers shifted inside) is painted AT its bounds.
- **The framework asks via `paint_shift_for(child)`** (see RENDERING_LAWS § Coordinate spaces), so
  anything anchored to a cell — a cell editor's dropdown, a drop highlight, a delivered click — lands
  where the cell is PAINTED. Answer it from `child.render_layer`, which `sync_cells_to_layers`
  already set: the content layer -> `scroll_offset`; every sticky layer, and anything else ->
  nothing (their bounds already hold the scroll - subtracting it again put every header's dropdown
  and click a scroll away). **O(1); never scan `active_cells`** — `viewport_bounds` is called per
  drop-target candidate on every mouse-move of a drag.
- **One quantization, one line rule, one region answer.** `painted_scroll` is the whole scroll the
  grid paints with (the floor - what the content layer composites at; the sticky pass moves headers
  by it too). Sizes are the PLACED ones (`placed_col_sizes`: whole pixels), and the sticky extents
  are their sums, so a band edge and the cells beside it agree however fractional a width is. A line
  is placed by `painted_col` / `painted_row` (laid out at `placed_col_start` / `placed_row_start`);
  anything on CELLS - the drag ghost and decal, the change glow, the cursor-cell flash, the Driver's
  aim, `cell_screen_position` - asks `painted_rect(region)`: the placed cells' painted rects (pitch,
  or the cell rect), clipped to the region their layer shows (a content cell: the viewport minus the
  bands), unioned - the VISIBLE part of the region; nil when nothing of it is painted. Only the
  active cells are asked (they cover the viewport and more). `spec/widgets/virtual_matrix/
  placement_quantization_lint_spec.cr` keeps a hand-quantized scroll or a hand-placed line out.
- **Its clip is declared the same way, `clip_for(child)`**: a cell is clipped to the layer painting
  it (`child.painting_layer.bounds` - the content viewport, or the sticky band or corner it sits in);
  its chrome ScrollView to nothing of the matrix's, so its scrollbars are never cut by its content
  layer (which excludes the gutter). Its layers answer `compute_bounds_for_layer` in CONTENT space
  (`absolute_bounds`), like every owner; the sticky blit plans read `Layer#content_rect`.
- **Do NOT convert a received point.** `App` hands every widget coordinates in its own space (and
  `DragManager` a drop target, in `on_drop` / `on_drag_over`); the
  matrix's old `ancestor_scroll_offset` converted a second time and put the cursor on the wrong
  cell. `drag_ghost_bounds` places a drag box that spans several cells: `painted_rect(drag box)` -
  where the box is painted in the matrix - moved to where the matrix itself is painted
  (`viewport_bounds`).

## Stickiness is derived, not declared

- `sticky_row_count` / `sticky_col_count` come from `derive_sticky_count(scroll_order)`, which
  reads the order BACKWARDS and counts the trailing indices that form `{0..n-1}`. So a fixture
  must contain EVERY index, with the sticky ones LAST (`(1...n).to_a + [0]` ⇒ index 0 sticky).
  An order that merely omits an index is malformed and raises deep in `update_visible_cells`.
- **A whole-axis order means every line is sticky, and that is legal** — nothing scrolls, which
  is inert, not broken (embrace's [Commits] view is one pinned row over an empty content layer,
  and a one-row grid's `[0]` derives the same way). Note that `(1...n).to_a + [0]` pins ONE index
  only for n > 2; at n = 2 the whole order qualifies and both lines are sticky.

## Ink bands

- **A region gives the band no more than it exceeds one line** (`hold` = `line_extent`, one default
  line's placed box; `column_extent` on X). A one-line row is cut where it sits by either edge, text
  and ruler number alike, and carries no ink region at all (a compound always keeps one); a taller
  row or a span gives the band its excess and no more. Continuous: no "is this row ordinary?" test (one jumps a label at one line).
- **The band a cell places ink in is the one it LIVES in.** `update_ink_regions` hands every cell
  the band its ink must stay inside and `place_ink` holds the ink at that band's edge, which is
  how a half-scrolled cell taller than one line keeps its value readable. A pinned row is held in the strip ABOVE the
  scrolling area, so measuring it against the scrolling band declared it entirely invisible and
  the hold pinned its ink to the cell's far edge: short values sat on the bottom edge of a row
  made tall by a multi-line neighbour (2026-09-21). Any new cell class needs its own band, not
  the content one.
- **A ruler's band is in the RULER's space.** `draw_labels` takes the viewport's extent and must
  subtract the widget's own origin: every ruler sits at the matrix's origin except the corner row
  strip, which sits at `(0, ruler_h)` and drew a pinned row's number a ruler-height too low.
- **Whatever a placement READS, the cache must depend on.** A ruler places its labels against the
  viewport extent, which it reads straight off the matrix — not through a Source — so its
  primitive cache has no dependency on it. Marking the sticky LAYERS on resize does not help: a
  layer re-renders from the widgets' cached primitives. Shrinking the panel therefore left a
  pinned row's number where it sat when the panel was tall while the cells beside it re-placed
  (measured in the field: the strip's last recompute used band 0..366 while the cells had moved
  on to 0..46). `perform_layout` now invalidates the ruler caches on a size change — and the
  general rule stands: a new non-reactive input to a placement needs its own invalidation, or it
  needs to be read through a Source.

## Cells

- `active_cells : Hash({row, col}, Widget)` is the live set; cells come and go with virtualization.
- **A cell that leaves is DETACHED, never destroyed** (`detach_cell`, the one body every teardown
  uses - the scroll sweep, the auto-size re-measure, a zoom change, a cell invalidation, an
  invalidate-all): an adapter may hand the SAME widget back (one that keeps its cell widgets), and
  it must come back whole. Its proxy focus is dropped (an edit in progress committed); it has
  `render_layer = nil` and no parent. Once the update is done, what did not come straight back (a
  merged cell's migrating handle does, with a reusing adapter) is released (`release_detached`):
  every layer of its subtree retired (`Layer#retire`), every widget letting go of what it held
  (`release_own`: its pull node - its subscription to the global zoom and theme Sources, which
  otherwise kept every cell ever shown reachable - its own surfaces, its slot stamp; a widget shown
  again re-creates its node). The App holds nothing inside a cell to let go of: the grid takes the
  hover, the press, a drag and the focus (below). A cell attached again rejoins the registry
  (`Layer#register`). What a user sees: a reused cell comes back with its inner scroll position and
  edit state, a fresh adapter's comes back reset; a popup opened from a cell stays open after the
  cell leaves (nothing links a popup to the widget that opened it).
- **A cell that owns layers is composited the frame it appears**: attaching or detaching one bumps
  `Layer.order_version` (only then - a plain grid never does), and the renderer re-collects the
  frame's layers at the start of a frame and after any owner's flush that moved it.
- **One input model: the grid takes every press.** `hit_test` returns the grid (its scrollbar area,
  the chrome ScrollView): a cell widget is never hit, hovered, pressed, a drag source or a drop target, and the
  grid takes the wheel - a widget nested in a cell gets none of it (a cell's ScrollView is not
  wheel-scrolled; the grid is). `point_to_cell` maps the point; the grid's release clicks the
  cursor cell (`trigger_click` forwarded to the proxy), a double-click hands the cell
  `on_mouse_up` (a ComboBox opens) unless `on_cell_activate` takes it, and proxy focus forwards keys to the cell that owns the cursor.
  A grid that cannot move the way the wheel goes passes it on to the scroller around it
  (RENDERING_LAWS § The wheel).
- **A host never focuses a cell widget.** The focus stays on the grid; a cell is reached through the
  cursor (`set_cursor_from_cell`, the Driver's `focus_cell`). A cell widget holding the focus would
  take keys past the grid and keep the focus after its cell left.
- A cell's `bounds` are relative to the matrix, and its `absolute_bounds` is content space.

## Two paths for sticky placement — one owner

`reposition_sticky_cells` (layout) and `compute_sticky_blit_plans` (fast path) run
EITHER/OR per frame; both place a sticky cell with `sticky_cell_rect`. They were born divergent and produced a compound header that jumped a column
pitch whenever the frame TYPE flipped. Both now call ONE pure
`StickyMath.compound_axis(view, bb_lo, bb_hi, true_pos)`. **Any new geometry either path needs
goes into StickyMath, not into one of them.**

## Compound (merged) cells

- A compound is held only by as much as its span EXCEEDS the visible band; a group you can see all
  of is not held at all. Identify a compound by a FACT about the model (its span), never by an
  implementation signal the rule may withdraw (e.g. `ink_region.compound`).

## Content sizing (`auto_size`)

- **A line shrinks only against a recorded runner-up.** One cell's measurement can prove a column
  must be wider, never that it may be narrower; `@as_col_best`/`@as_col_second` (pass 1 of
  `flush_auto_size`) are what make the narrowing safe and O(1). Without them the only honest move
  is to grow — which is what the `@as_extents_valid == false` branch of `fit_cell_to_content` does.
- **Carry the measurement with the sizes, or don't cancel the re-measure.** Reconciliation adopts
  the old matrix's `@col_widths`/`@row_heights` and cancels `@auto_size_pending` on the strength of
  it. Any state the incremental path needs to keep working must travel with them
  (`carry_line_extents_from`) — a widget that holds sizes it cannot explain is permanently
  grow-only, and it looks perfectly correct until someone shortens a value. And cancel it only
  when the old matrix HAD measured: one rebuilt before its first frame carries default sizes, so
  its pending re-measure travels too (else a matrix born with the mode on never applies it).

## Perf

- The blit-shift path exists so a scroll does not re-render every cell; `slot_fresh?` decides per
  cell. A change that makes cells re-render on scroll is a regression even if it looks correct.
- Price any render-adjacent change in the REAL SFML demo that contains a matrix
  (`virtual_matrix_demo`), never headlessly — see memory `laws_perf_debug`.
