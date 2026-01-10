# Widget Tree Structure

## Overview

The UI has a hierarchical widget tree with **layers** as the rendering abstraction.

## Test Case Structure (panel_click_blank_spec.cr)

### Widget Tree
```
Window (root)
└── WindowPanel
    └── BlackRectWidget
```

### Layer Structure
```
Layer "panel_<id>" (WindowPanel's internal layer)
├── [widgets list]:
│   ├── WindowPanel (chrome only - title bar)
│   └── BlackRectWidget (collected recursively)
```

### Key Points

**Widget tree (`@children`):**
- Window has WindowPanel as child
- WindowPanel has BlackRectWidget as child
- Standard parent-child hierarchy

**Layer structure (`layer.widgets`):**
- WindowPanel creates an internal layer (`@internal_layer`)
- During layout, WindowPanel adds itself to `layer.widgets` (line 144 in window_panel.cr)
- Children are NOT explicitly added to `layer.widgets`
- Children are collected recursively during rendering via `collect_all_widgets_recursive`

**Rendering order:**
1. Renderer calls `collect_all_widgets_recursive(layer.widgets)`
2. Starts with `layer.widgets` = `[WindowPanel]`
3. Recursively collects: `WindowPanel` → `BlackRectWidget`
4. Result: `[WindowPanel, BlackRectWidget]` (parent-first order)
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

**Layout logic (lines 43-81):**
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
- `@children` - child widgets (content)

**Layout logic (lines 142-178):**
```crystal
# Populate layer.widgets
layer.widgets.clear
layer.widgets << self  # Panel chrome renders first

# Separate children into menubar and content
# Layout children with relative coordinates
# Track position for drag offset

# DON'T add children to layer.widgets - they're rendered recursively
# (prevents double-rendering)
```

**to_primitives (lines 245-302):**
- Only renders chrome: title bar, border, title text, close button
- Does NOT render full panel background (intentional - see line 264 comment)
- Comment: "No full-panel background fill needed here - prevents overwriting cached children!"

## Rendering Process (src/rendering/layer_renderer.cr)

### Full Render
```crystal
# Collect ALL widgets recursively from layer.widgets
all_widgets = []
layer.widgets.each do |widget|
  collect_all_widgets_recursive(widget, all_widgets)  # Parent-first traversal
end
# Render all_widgets in order
```

### Selective Render (Dirty Widgets Only)
```crystal
# Collect all widgets recursively
all_widgets = []
layer.widgets.each do |widget|
  collect_all_widgets_recursive(widget, all_widgets)
end
# Filter to dirty widgets ONLY (preserves parent-first order)
dirty_set = layer.dirty_widgets
widgets_to_render = all_widgets.select { |w| dirty_set.includes?(w) }
```

**Critical:** Selective render filters to dirty widgets but **preserves parent-first order** from recursive collection.

### collect_all_widgets_recursive (lines 474-479)
```crystal
private def collect_all_widgets_recursive(widget : Widget, result : Array(Widget))
  result << widget        # Add parent first
  widget.children.each do |child|
    collect_all_widgets_recursive(child, result)  # Then recurse to children
  end
end
```

**Result:** Parent always appears before children in `widgets_to_render` list.

## Rendering Order Invariant

**For panel with children:**
```
layer.widgets = [WindowPanel]

collect_all_widgets_recursive:
1. Add WindowPanel
2. Recurse to WindowPanel.children
3. Add BlackRectWidget

Result: [WindowPanel, BlackRectWidget]
```

**During selective render (without invalidate_children_backgrounds):**
```
dirty_set = {WindowPanel}  # Only panel is dirty

widgets_to_render = [WindowPanel, BlackRectWidget].select { |w| dirty_set.includes?(w) }
                  = [WindowPanel]  # BlackRectWidget filtered out!
```

**This is the bug:** WindowPanel renders alone, blits its background over where BlackRectWidget should be.

## Why Parent-First Order Exists

Comment in layer_renderer.cr:173-174:
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

1. **Parent renders first** (correct for background capture)
2. **Parent captures layer background** including areas where children will render
3. **Children render after parent** and overwrite parent's areas
4. **On selective re-render:**
   - Parent re-renders (restores background with layer-bg pixels in children's areas)
   - Children DON'T re-render (not in dirty set without invalidate_children_backgrounds)
   - Parent's widget_backend (with layer-bg pixels) blits over children's screen positions
   - **Result:** Children disappear (replaced with layer background color)

## Summary

**Your assumption was partially correct but not quite:**

- Window is the root
- WindowPanel is a child of Window (not separate chrome/content)
- WindowPanel internally has chrome (title bar) AND children (content)
- WindowPanel adds itself to its layer.widgets
- Children are collected recursively during rendering
- **Critical:** Parent renders before children (parent-first order) for correct background capture
- **Bug:** This means parent's background contains "blank" pixels where children will later render
