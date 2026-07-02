# Widget Tree Structure

## Overview

The UI has a hierarchical widget tree with **layers** as the rendering abstraction.

## Test Case Structure (panel_click_blank_spec.cr)

### Widget Tree
```
Window (root)
└── WindowPanel
    ├── @chrome (Chrome, title bar)
    └── @content (Content, container)
        └── BlackRectWidget
```

### Layer Structure
```
Layer "panel_<id>" (WindowPanel's internal layer)
├── [widgets list]:
│   ├── Chrome (title bar - added directly to layer.widgets)
│   └── Content (container - added directly to layer.widgets)
│       └── BlackRectWidget (collected recursively from Content.children)
```

### Key Points

**Widget tree (`@children`):**
- Window has WindowPanel as child
- WindowPanel.@children = `[@chrome, @content]`; Chrome is first (renders first), Content is second
- BlackRectWidget (user-added child) lives under `@content`; `add_child` redirects all user additions to `@content`

**Layer structure (`layer.widgets`):**
- WindowPanel creates an internal layer (`@internal_layer`)
- During layout, WindowPanel populates `layer.widgets` with its internal `Chrome` and `Content` widgets (see `WindowPanel#perform_layout` in window_panel.cr)
- User-added children live under `Content`; they are NOT explicitly added to `layer.widgets`
- User children are collected recursively during rendering via `collect_all_widgets_recursive`

**Rendering order:**
1. Renderer calls `collect_all_widgets_recursive(layer.widgets)`
2. Starts with `layer.widgets` = `[Chrome, Content]`
3. Recursively collects: `Chrome`, then `Content` → `BlackRectWidget`
4. Result: `[Chrome, Content, BlackRectWidget]` (parent-first order)
5. Renders in this order, so parent captures background before children render

## General Structure

### Window Class (src/widgets/window.cr)

**Children:**
- MenuBar (optional) - window-level menu
- WindowPanel(s) - floating panels
- Content widgets - buttons, text, etc.

**Layers created:**
- `@root_layer` - for content widgets (z-index 0)
- Each WindowPanel creates its own layer
- Each MenuBar creates its own layer

**Layout logic** (see `Window#perform_layout`, window.cr):
```crystal
# Separate children
menubar = children.find { |c| c.is_a?(MenuBar) }
panels = children.select { |c| c.is_a?(WindowPanel) }
content = children.reject { |c| c.is_a?(MenuBar) || c.is_a?(WindowPanel) }

# Layout menubar at top
# Layout content below menubar → added to root_layer.widgets
# Layout panels (they position themselves absolutely)
```

### WindowPanel Class (src/widgets/window_panel.cr)

**Internal structure:**
- `@internal_layer` - Layer for panel chrome + content
- `@children` - `[@chrome, @content]` (Chrome is a genuine child of WindowPanel, not merely a content wrapper)

**Mixin: `include LayerOwner`** (src/core/layer_owner.cr)

WindowPanel includes `LayerOwner`, the required mixin for any widget that owns a rendering layer. The mixin provides:
- `can_skip_layout?` — returns `false` while the widget has a live layer, preventing stale `layer.widgets`
- `compute_bounds_for_layer` — default implementation; WindowPanel overrides it to return `Rect(x, y, width, height)`
- `on_ancestor_z_index_changed` — default no-op; overridden when the widget needs to propagate z-index updates

Any new layer-owning widget must `include LayerOwner` and create its layer in `initialize`.

**Positional fields are `reactive_property`** (widget.cr)

`x`, `y`, `width`, `height`, `z_index`, `title`, `closed`, `maximized`, and similar fields are declared with the `reactive_property` macro, which wraps each value in a `Source(T)`. The generated setter calls `@field.set(value)`, notifying any pull-node that reads it, rather than issuing a blanket `mark_needs_render`. Behaviour from the caller's perspective is identical to a plain ivar — `panel.width = 300` works as expected — but internal resize hot-paths exploit the `.set(...)` bypass to avoid full repaints when only geometry changes.

**Layout logic** (see `WindowPanel#perform_layout`, window_panel.cr):
```crystal
# Populate layer.widgets with internal chrome and content widgets
layer.widgets.clear
layer.widgets << @chrome   # Chrome (title bar) renders first
layer.widgets << @content  # Content container renders second

# Grow the panel to its content-aware floor (both axes) BEFORE laying out the chrome,
# so the title bar is laid out at the settled width. Laying the chrome out first and
# growing width afterwards left a stale title-bar fill on the right when the panel
# floored wider than its built/zoomed width. Skipped while maximized or resizing.
recompute_content_min
self.height = panel_min_height if height < panel_min_height
self.width  = panel_min_width  if width  < panel_min_width

# Layout chrome (title bar area) at the now-settled width
# Layout content (content widget computes its own position below title bar)
# Track position for drag offset

# DON'T add user children directly to layer.widgets - they are collected
# recursively from @content during rendering (prevents double-rendering)
```

**to_primitives:**
- WindowPanel itself is a pure container: returns `[] of DrawPrimitive`
- Chrome rendering (title bar, close button, etc.) is handled by `Chrome#to_primitives` (window_panel.cr)
- Content rendering (background, user children) is handled by `Content#to_primitives` (window_panel.cr — returns empty, pure container)

## Rendering Process (src/rendering/layer_renderer.cr)

### Full Render
```crystal
# Collect ALL widgets recursively from layer.widgets
all_widgets = []
layer.widgets.each do |widget|
  collect_all_widgets_recursive(widget, all_widgets, layer)  # Parent-first traversal
end
# Render all_widgets in order
```

### Selective Render (Dirty Widgets Only)
```crystal
# Collect all widgets recursively
all_widgets = []
layer.widgets.each do |widget|
  collect_all_widgets_recursive(widget, all_widgets, layer)
end
# Filter to dirty widgets ONLY (preserves parent-first order)
dirty_set = layer.dirty_widgets
widgets_to_render = all_widgets.select { |w| dirty_set.includes?(w) }
```

**Critical:** Selective render filters to dirty widgets but **preserves parent-first order** from recursive collection.

> **Note:** This dirty-widget path applies to ordinary (push-style) layers only. `viewport_cache`
> layers (the matrix/VirtualMatrix content) bypass `dirty_widgets` entirely — they re-evaluate
> per-slot every frame (Pull / SlotBuffer), so don't over-generalize the dirty-set filtering above to them.

### collect_all_widgets_recursive (see `LayerRenderer#collect_all_widgets_recursive`, layer_renderer.cr)
```crystal
private def collect_all_widgets_recursive(widget : Widget, result : Array(Widget), target_layer : Layer)
  # Zero-size early return: skip widget AND all its descendants.
  # Collapsed TreeNode children retain stale bounds; this prevents ghost rendering.
  return if widget.bounds.width <= 0.0 || widget.bounds.height <= 0.0

  result << widget        # Add parent first

  # If this widget itself owns a different layer, its children belong there — stop.
  if widget.responds_to?(:layer)
    return if (wl = widget.layer) && wl != target_layer
  end

  widget.children.each do |child|
    # Layer-owning children are ENTIRELY EXCLUDED: neither added to result nor recursed.
    # Their own layer handles them in a separate collection pass.
    if child.responds_to?(:layer) && child.layer
      next  # skip entirely
    else
      collect_all_widgets_recursive(child, result, target_layer)
    end
  end
end
```

**Result:** Parent always appears before children in `widgets_to_render` list.

## Rendering Order Invariant

**For panel with children:**
```
layer.widgets = [Chrome, Content]

collect_all_widgets_recursive:
1. Add Chrome
2. Recurse to Chrome.children (none)
3. Add Content
4. Recurse to Content.children
5. Add BlackRectWidget

Result: [Chrome, Content, BlackRectWidget]
```

**During selective render (without invalidate_children_backgrounds):**
```
dirty_set = {Chrome}  # Only chrome is dirty (e.g., title bar color change)

widgets_to_render = [Chrome, Content, BlackRectWidget].select { |w| dirty_set.includes?(w) }
                  = [Chrome]  # Content and BlackRectWidget filtered out!
```

**This *was* the bug** (historical — now FIXED): Chrome rendered alone and blitted its background over where BlackRectWidget should be. The fix (parent-first ordering + `invalidate_children_backgrounds`, below) is in place; this section is kept as the worked example of *why* the ordering invariant exists, not a description of current behaviour.

## Why Parent-First Order Exists

Comment in `LayerRenderer` (layer_renderer.cr), in the selective-render branch of the
widget-collection method:
```crystal
# Selective render: only dirty widgets, but MUST preserve parent-first order!
# CRITICAL: If child renders before parent, it captures wrong (old) background
```

**Reason:** Background capture happens from layer buffer. If child renders first:
1. Child captures layer background
2. Child renders and blits to layer
3. Parent captures layer background (now includes child's content!)
4. Parent blits over child → child disappears

**Solution:** Parent always renders first, so child captures parent's background (correct).

**Problem:** This means parent's background_backend contains layer-bg pixels where children will later render.

## Implications for Blank Panel Bug

1. **Chrome renders first** (correct for background capture)
2. **Chrome captures layer background** including areas where children will render
3. **Children render after Chrome** and overwrite Chrome's areas
4. **On selective re-render:**
   - Chrome re-renders (restores background with layer-bg pixels in children's areas)
   - Children DON'T re-render (not in dirty set without invalidate_children_backgrounds)
   - Chrome's widget_backend (with layer-bg pixels) blits over children's screen positions
   - **Result:** Children disappear (replaced with layer background color)

## Summary

**Your assumption was partially correct but not quite:**

- Window is the root
- WindowPanel is a child of Window (not separate chrome/content)
- WindowPanel internally has a `Chrome` widget (title bar) and a `Content` widget (container for user children)
- WindowPanel populates `layer.widgets` with `[Chrome, Content]` during layout (not itself)
- User children live under `Content` and are collected recursively during rendering
- **Critical:** Parent renders before children (parent-first order) for correct background capture
- **Bug:** This means parent's background contains "blank" pixels where children will later render
