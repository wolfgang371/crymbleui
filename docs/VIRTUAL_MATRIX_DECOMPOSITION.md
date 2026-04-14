# VirtualMatrix Decomposition Plan

## Problem

VirtualMatrix has 147 cached/pending/force state flags. It manages 6 layers, 3 coordinate systems, and handles cells, scrolling, sticky headers, cursor, rulers, and adapter invalidation. 70% of rendering bugs originate here.

## Target Architecture

VirtualMatrix becomes a coordinator delegating to 5 components:

| Component | Responsibility | Key state |
|-----------|---------------|-----------|
| `CellManager` | Create/destroy/position active cells, compound cells | `@active_cells`, `@pending_cell_invalidations`, `@force_cell_update` |
| `ScrollController` | Scroll offset, buffer origin, viewport cache, deferred scroll | `@scroll_offset`, `@pending_scroll_update`, `@content_scroll_view` |
| `StickyController` | Sticky row/col partitioning, positioning, StickyMath | `@cached_sticky_*`, sticky layers |
| `CursorController` | Cursor position, overlay widget, flash, navigation | `@cursor_row/col`, `@cursor_overlay_*`, `@proxy_focused_*` |
| `RulerController` | Row/col rulers, resize handles | `@ruler_*`, ruler widgets |

## Contracts Between Components

- `CellManager` asks `ScrollController` for visible range
- `StickyController` tells `CellManager` which cells are sticky
- `CursorController` tells `CellManager` which cell has focus
- `RulerController` reads sizes from `VirtualMatrix` adapter

## Migration Strategy

1. Extract `CursorController` first (most isolated, owns cursor_overlay_layer)
2. Extract `RulerController` (owns ruler widgets, no cell interaction)
3. Extract `ScrollController` (owns content_layer, deferred scroll)
4. Extract `StickyController` (most intertwined with CellManager)
5. Remaining code IS `CellManager`

Each extraction is independently testable and committable.

## Status

DESIGN ONLY — no code changes yet.
