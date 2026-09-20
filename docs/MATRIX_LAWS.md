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

## Perf

- The blit-shift path exists so a scroll does not re-render every cell; `slot_fresh?` decides per
  cell. A change that makes cells re-render on scroll is a regression even if it looks correct.
- Price any render-adjacent change in the REAL SFML demo that contains a matrix
  (`virtual_matrix_demo`), never headlessly — see memory `laws_perf_debug`.
