# Graceful Degradation

This document describes CrymbleUI's three-layer defense strategy for handling render-time failures.

## Problem

In a retained-mode UI framework, rendering exceptions can leave the system in an inconsistent state:
- Cached primitives may be stale or partially computed
- Layer backends may have incomplete content
- Interaction state (hover, mouse_down) may reference invalid widgets
- Next frame may crash due to corrupted state

## Solution: Three-Layer Defense

CrymbleUI uses three complementary strategies:

### Layer 1: Validation-Before-Render (Option C)

**Prevent invalid operations** by validating widget/layer state before rendering.

**What gets validated**:
- Layer dimensions (width/height > 0, finite)
- Widget absolute_bounds (width/height > 0, finite)
- Backend type compatibility (a mismatch **raises** — see "What Still Asserts", below — it is a broken invariant, not a degradable edge case; the raise lives in the backends' `blit`/`blit_region`, `crsfml_backend.cr` / `test_render_backend.cr`)

**Location**: `layer_renderer.cr` (dimension/bounds validation)

```crystal
private def valid_layer_dimensions?(layer : Layer) : Bool
  return false unless layer.bounds.width > 0 && layer.bounds.height > 0 &&
    layer.bounds.width.finite? && layer.bounds.height.finite?
  if owner = layer.owner_widget
    return owner.ancestry_bounds_valid?
  end
  true
end

private def valid_widget_dimensions?(widget : Widget) : Bool
  abs = widget.absolute_bounds
  abs.width > 0 && abs.height > 0 &&
    abs.width.finite? && abs.height.finite?
end
```

The ancestry branch in `valid_layer_dimensions?` handles overlay and popup layers whose owner widget's parent chain contains a zero-bounds ancestor (e.g. a closed `WindowPanel`). The layer's own stored bounds may be stale after a parent collapses; walking up via `ancestry_bounds_valid?` catches it and suppresses compositing.

**Behavior**: Invalid widgets/layers are silently skipped. The dimension-check call sites carry no debug-logging wrapper; `-DDEBUG_RENDER` covers geometric culling, not these NaN/zero-size validation guards.

### Layer 2: Frame-Boundary Exception Handling (Option A)

**Catch and recover** from exceptions that slip past validation.

**Location**: `window_renderer.cr` (WindowRenderer#render_frame, which SFMLRenderer runs) and `test_renderer.cr`

```crystal
def render_frame(app : App)
  begin
    # ... layout and render ...
  rescue exception
    raise exception if exception.is_a?(RenderDefect)
    handle_frame_exception(exception, app) # counts the failure run, recovers, presents (present_after_failure)
  else
    note_frame_completed                           # a frame that completes ends the run
  end
  end_frame(app)                                   # stamps the render trigger
  report_frame_failure(app)                        # AFTER the stamp: the handler's marks paint next
  apply_title(app)
end
```

**Recovery actions**:
1. Log exception to STDERR (visible but doesn't pollute stdout)
2. Reset all caches (can't know what's corrupted)
3. Force re-layout (safest recovery path)
4. Always call `window.display` — a stale frame is better than a blank/black display; after a display that
   succeeded, drain the texture reaper (what the reset released is freed now, in the success path's GL state)
5. Next frame renders from clean state

**What the user sees** (LayerRenderer, the same rule in both renderers): consecutive failing frames form a RUN.
Its first frame and its 10th are reported to the app - `App#report_display_error`: "Display error: <message>",
then "Display error keeps recurring: <message> - please save your work" (embrace: the status bar) - never every
frame; while the run lasts the window title ends in " - display error" (the title is drawn outside the frame, so
it shows even when the failing frame is the one that would paint the status bar). A frame that completes ends the
run and clears the title. A failing frame does not trigger the next one by itself (a frame that reports triggers
one more, through the app's handler) - it recurs only at input or timer rate - so nothing throttles it.
(TestRenderer applies a pending rebuild inside its frame, so a rebuild that raises counts there; under SFML the
loop rebuilds outside the frame. And a TestRenderer frame with no root completes, ending a run; under SFML it
neither counts nor ends one.)

### Layer 3: Input-Path Exception Handling

**Catch exceptions during event processing** to prevent a bad input handler from breaking the event loop.

**Location**: `window_renderer.cr` (WindowRenderer#handle_event, the window loop's dispatch)

`handle_event` wraps `handle_event_impl` in a rescue. If `app.on_event_exception` is set (a `Proc(String, Nil)?`), the error message is forwarded there (e.g. for a status-bar warning); otherwise the full backtrace goes to STDERR. The method returns `false` (no redraw) and the frame loop continues normally. This path resets no caches — a bad event handler does not leave the render state partially modified.

## Cache Reset Methods

### Widget.reset_render_caches_recursive
Clears all render caches on widget tree:
- `@cached_primitives`
- `@primitives_node.try(&.touch)` (touches the reactive signal to force primitive recomputation next frame)
- `widget_backend` / `background_backend` - RELEASED (through the setters), with the
  rendered-at-bounds flag

### Layer.reset_for_recovery
Resets layer to clean state:
- its surface released (`self.backend = nil`)
- the one-shot requests a raising frame may have left: `blit_plan`, `blit_plan_render_widgets`, `resize_shift`
- `@dirty_widgets.clear`
- `@last_rendered_bounds = nil`
- `@state = WidgetState::NeedsLayout`

### App.reset_all_caches
Full app reset for recovery, over the root AND the window's overlays:
- `reset_render_caches_recursive` on each
- `reset_for_recovery` on every layer of each (`each_layer_in_subtree`: owned layers too - a ScrollView's
  bands, a grid's cursor and drag overlays), and `reset_render_caches_recursive` on the widgets each layer
  hosts (grid cells)
- Clears interaction state (`@hovered_widget`, `@mouse_down_widget`, `@topmost_panel`)
- Cancels any in-progress drag operation

**Under SFML, released means queued.** `CrSFMLBackend#dispose` only enqueues; the reaper drains after a
frame's `window.display` - a successful frame's, and a recovered frame's too (unless its display raised). One
exception is never recovered from: `DisposedBackendError` (use after release) is re-raised by both renderers. See
LAYER_RENDERING_ARCHITECTURE.md, "Backend Lifecycle".

## What Still Asserts vs. What Validates

| Scenario | Handling | Rationale |
|----------|----------|-----------|
| Zero-size widget | Validate, skip | Edge case, not a bug |
| NaN/Infinity bounds | Validate, skip | Edge case, not a bug |
| Backend type mismatch | **Assert (raise)** | Broken invariant, not a degradable condition (No-Fallbacks) |
| Sibling overlap | Assert | Invariant violation = bug |
| Missing background before render | Assert | Invariant violation = bug |
| Rendering before layout | Assert | Invariant violation = bug |

**Philosophy**: Assertions catch bugs during development. Validation handles edge cases in production.

## Debug Output

Enable with `-DDEBUG_RENDER` flag:

```
crystal build -DDEBUG_RENDER src/main.cr
```

This enables verbose logging of render operations, including skipped widgets.

## Testing

See `spec/rendering/graceful_degradation_spec.cr` for tests covering:
- Exception recovery (widget throws during render)
- Cache reset verification
- Zero-size/NaN/Infinity widget validation
- The process-wide count of swallowed frame exceptions

**A swallowed exception passes a spec unless something asks.** The TestRenderer recovers
from a frame exception exactly as the app does, so an invariant that raises inside a frame
(an assertion, a `-Dverify_bounds` check) fails nothing by itself. Besides each renderer's
own `exceptions_caught` / `last_exception_message`, `TestRenderer.frame_exceptions_swallowed`
and `TestRenderer.last_frame_exception_message` count across every renderer in the process, so a
suite built from many renderers can fail an example whose frames swallowed one (embrace's
`spec/spec_helper.cr` does).

## Design Decisions

1. **Keep assertions for invariants** - bugs should crash, not degrade silently
2. **Validation for edge cases** - zero sizes, NaN (a backend *type mismatch* is NOT an edge case — it raises)
3. **Reset ALL caches on exception** - can't know what's corrupted
4. **Force re-layout** - safest recovery path
5. **Log to STDERR** - visible but doesn't pollute stdout
6. **No retry limit, no back-off** - a frame that keeps raising is recovered from every time it recurs, which is
   only at input or timer rate (a failing frame does not trigger the next one by itself: measured); the user is told at
   the run's first and 10th frame and by the window title (see Layer 2)
