# Graceful Degradation

This document describes CrymbleUI's two-layer defense strategy for handling render-time failures.

## Problem

In a retained-mode UI framework, rendering exceptions can leave the system in an inconsistent state:
- Cached primitives may be stale or partially computed
- Layer backends may have incomplete content
- Interaction state (hover, mouse_down) may reference invalid widgets
- Next frame may crash due to corrupted state

## Solution: Two-Layer Defense

CrymbleUI uses two complementary strategies:

### Layer 1: Validation-Before-Render (Option C)

**Prevent invalid operations** by validating widget/layer state before rendering.

**What gets validated**:
- Layer dimensions (width/height > 0, finite)
- Widget absolute_bounds (width/height > 0, finite)
- Backend type compatibility (graceful skip instead of crash)

**Location**: `layer_renderer.cr`

```crystal
private def valid_layer_dimensions?(layer : Layer) : Bool
  layer.bounds.width > 0 && layer.bounds.height > 0 &&
  layer.bounds.width.finite? && layer.bounds.height.finite?
end

private def valid_widget_dimensions?(widget : Widget) : Bool
  abs = widget.absolute_bounds
  abs.width > 0 && abs.height > 0 &&
  abs.width.finite? && abs.height.finite?
end
```

**Behavior**: Invalid widgets/layers are silently skipped (logged with `-Ddebug_render`).

### Layer 2: Frame-Boundary Exception Handling (Option A)

**Catch and recover** from exceptions that slip past validation.

**Location**: `sfml_renderer.cr` and `test_renderer.cr`

```crystal
def render_frame(app : App)
  begin
    # ... layout and render ...
  rescue exception
    handle_frame_exception(exception, app)
  end
end

private def handle_frame_exception(exception : Exception, app : App)
  STDERR.puts "[GRACEFUL_DEGRADATION] Frame exception: #{exception.message}"
  STDERR.puts "  #{exception.backtrace?.try(&.first(3).join("\n  "))}"
  app.reset_all_caches
  app.root.try(&.mark_needs_layout)
end
```

**Recovery actions**:
1. Log exception to STDERR (visible but doesn't pollute stdout)
2. Reset all caches (can't know what's corrupted)
3. Force re-layout (safest recovery path)
4. Next frame renders from clean state

## Cache Reset Methods

### Widget.reset_render_caches_recursive
Clears all render caches on widget tree:
- `@cached_primitives`
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
- Clears interaction state (`@hovered_widget`, `@mouse_down_widget`)
- Cancels any in-progress drag operation

## What Still Asserts vs. What Validates

| Scenario | Handling | Rationale |
|----------|----------|-----------|
| Zero-size widget | Validate, skip | Edge case, not a bug |
| NaN/Infinity bounds | Validate, skip | Edge case, not a bug |
| Backend type mismatch | Validate, skip | Graceful degradation |
| Sibling overlap | Assert | Invariant violation = bug |
| Missing background before render | Assert | Invariant violation = bug |
| Rendering before layout | Assert | Invariant violation = bug |

**Philosophy**: Assertions catch bugs during development. Validation handles edge cases in production.

## Debug Output

Enable with `-Ddebug_render` flag:

```
crystal build -Ddebug_render src/main.cr
```

This enables verbose logging of render operations, including skipped widgets.

## Testing

See `spec/rendering/graceful_degradation_spec.cr` for tests covering:
- Exception recovery (widget throws during render)
- Cache reset verification
- Zero-size/NaN/Infinity widget validation

## Design Decisions

1. **Keep assertions for invariants** - bugs should crash, not degrade silently
2. **Validation for edge cases** - zero sizes, NaN, type mismatches
3. **Reset ALL caches on exception** - can't know what's corrupted
4. **Force re-layout** - safest recovery path
5. **Log to STDERR** - visible but doesn't pollute stdout
6. **No retry limit** - infinite loop protection via layout/render guards
