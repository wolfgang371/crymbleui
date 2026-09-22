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
- **The framework asks via `paint_shift_for(child)`** (see RENDERING_LAWS § Coordinate spaces), so
  anything anchored to a cell — a cell editor's dropdown, a drag ghost, a drop highlight — lands
  where the cell is PAINTED. Answer it from `child.render_layer`, which `sync_cells_to_layers`
  already set: content layer -> both axes, sticky row -> X only, sticky column -> Y only, corner
  and anything else -> nothing. **O(1); never scan `active_cells`** — `viewport_bounds` is called
  per drop-target candidate on every mouse-move of a drag.
- **Do NOT convert a received point.** `App` hands every widget coordinates in its own space; the
  matrix's old `ancestor_scroll_offset` converted a second time and put the cursor on the wrong
  cell. `drag_ghost_bounds` is the one place that still converts by hand — it spans several cells,
  so it starts from `viewport_bounds` (the painted matrix) and subtracts the matrix's own scroll.

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

- **The band a cell places ink in is the one it LIVES in.** `update_ink_regions` hands every cell
  the band its ink must stay inside and `place_ink` holds the ink at that band's edge, which is
  how a half-scrolled cell keeps its value readable. A pinned row is held in the strip ABOVE the
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

- `active_cells : Hash({row, col}, Widget)` is the live set; cells are created and destroyed by
  virtualization, and a destroyed cell has `render_layer = nil` and no parent.
- **`hit_test` returns SELF** — cell widgets never receive direct clicks; `point_to_cell` maps the
  point, and proxy focus forwards keyboard to the cell that owns the cursor.
- A cell's `bounds` are relative to the matrix, and its `absolute_bounds` is content space.

## Two paths for sticky placement — one owner

`reposition_sticky_cells` (layout) and `reposition_compound_in_blit_plan` (fast path) run
EITHER/OR per frame. They were born divergent and produced a compound header that jumped a column
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
  grow-only, and it looks perfectly correct until someone shortens a value.

## Perf

- The blit-shift path exists so a scroll does not re-render every cell; `slot_fresh?` decides per
  cell. A change that makes cells re-render on scroll is a regression even if it looks correct.
- Price any render-adjacent change in the REAL SFML demo that contains a matrix
  (`virtual_matrix_demo`), never headlessly — see memory `laws_perf_debug`.
