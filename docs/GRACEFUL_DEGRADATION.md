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

**Location**: `sfml_renderer.cr` and `test_renderer.cr`

```crystal
def render_frame(app : App)
  begin
    # ... layout and render ...
  rescue exception
    handle_frame_exception(exception, app, window)
  end
end

private def handle_frame_exception(exception : Exception, app : App, window : SF::RenderWindow)
  STDERR.puts "[GRACEFUL_DEGRADATION] Frame exception: #{exception.message}"
  STDERR.puts "  #{exception.backtrace?.try(&.first(3).join("\n  "))}"
  app.reset_all_caches
  app.root.try(&.mark_needs_layout)
  window.display  # a stale frame is better than a black hole
end
```

**Recovery actions**:
1. Log exception to STDERR (visible but doesn't pollute stdout)
2. Reset all caches (can't know what's corrupted)
3. Force re-layout (safest recovery path)
4. Always call `window.display` — a stale frame is better than a blank/black display
5. Next frame renders from clean state

### Layer 3: Input-Path Exception Handling

**Catch exceptions during event processing** to prevent a bad input handler from breaking the event loop.

**Location**: `sfml_renderer.cr`

`handle_event` wraps `handle_event_impl` in a rescue. If `app.on_event_exception` is set (a `Proc(String, Nil)?`), the error message is forwarded there (e.g. for a status-bar warning); otherwise the full backtrace goes to STDERR. The method returns `false` (no redraw) and the frame loop continues normally. This path resets no caches — a bad event handler does not leave the render state partially modified.

## Cache Reset Methods

### Widget.reset_render_caches_recursive
Clears all render caches on widget tree:
- `@cached_primitives`
- `@primitives_node.try(&.touch)` (touches the reactive signal to force primitive recomputation next frame)
- `@widget_backend`
- `@background_backend`
- `@rendered_to_layer_at_current_bounds`

### Layer.reset_for_recovery
Resets layer to clean state:
- `@backend = nil`
- `@dirty_widgets.clear`
- `@last_rendered_bounds = nil`
- `@state = WidgetState::NeedsLayout`

### App.reset_all_caches
Full app reset for recovery:
- Calls `reset_render_caches_recursive` on root
- Calls `reset_for_recovery` on all layers
- Clears interaction state (`@hovered_widget`, `@mouse_down_widget`, `@topmost_panel`)
- Cancels any in-progress drag operation

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

## Design Decisions

1. **Keep assertions for invariants** - bugs should crash, not degrade silently
2. **Validation for edge cases** - zero sizes, NaN (a backend *type mismatch* is NOT an edge case — it raises)
3. **Reset ALL caches on exception** - can't know what's corrupted
4. **Force re-layout** - safest recovery path
5. **Log to STDERR** - visible but doesn't pollute stdout
6. **No retry limit** - infinite loop protection via layout/render guards
