# Rendering Pipelines & Automatic Verification

CrymbleUI has two rendering pipelines that produce the same visual output from
the same widget code. The **Crymble pipeline** (default) uses multi-level caching
for performance. The **Immediate-mode pipeline** bypasses all caches to produce a
ground-truth reference. The **cache validation framework** automatically compares
them pixel-by-pixel to catch caching bugs.

## What Widget Authors Need to Know

**Almost nothing about the rendering pipeline.** The entire caching and
verification system is invisible to widget code. A widget only needs to:

### 1. Define Primitives

Override `to_primitives()` to describe what to draw using backend-agnostic
`DrawPrimitive` structs. Coordinates are widget-local (0,0 origin):

```crystal
class MyButton < Widget
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      fill_rect(bounds, @background_color)
      draw_rect(bounds, @border_color, 1.0)
      draw_text(@label, Vec2.new(8.0, 4.0), @text_color, 14)
    end
  end
end
```

The renderer handles everything else: creating GPU textures, caching primitives,
memorizing backgrounds, compositing layers, and validating correctness.

### 2. Use Property Macros for Invalidation

Property macros automatically notify the renderer when state changes:

```crystal
class MyButton < Widget
  render_property color : Color = Color::White          # visual change → re-render this widget
  layout_property padding : Float64 = 0.0               # structural change → re-layout subtree
  reconcile_property selected : Bool = false             # preserved across DSL rebuilds, no invalidation
  render_property hover : Bool = false, reconcile = true # visual change + preserved across rebuilds
end
```

- `render_property` → calls `mark_needs_render` on change (selective re-render, O(1))
- `layout_property` → calls `mark_needs_layout` on change (full layout + render, O(subtree))
- `reconcile_property` → no invalidation, just state preservation

### 3. Choose a Cache Policy (Optional)

Override `cache_policy` if the default (`Dynamic`) isn't right:

```crystal
def cache_policy : CachePolicy
  CachePolicy::Static   # Never changes after first render (icons, labels)
  CachePolicy::Dynamic  # Default — re-render when state changes
  CachePolicy::Never    # Always generate fresh primitives (menus, popups)
end
```

### What You Do NOT Touch

The renderer manages all of this internally — widget code never interacts with:
- `widget_backend` / `background_backend` (per-widget GPU textures)
- Background memorization and restoration
- Layer compositing and viewport caching
- Blit-shift optimization during scroll
- The fast-path cache check
- Coordinate translation (widget-local → layer-local → buffer-relative)

## The Crymble Pipeline (Cached, Default)

Every frame proceeds through three phases:

### Phase 1: Layout (O(dirty path), skipped if unchanged)

Widgets with `needs_layout?` recompute bounds top-down. Template method pattern:
`layout()` checks constraints → `perform_layout()` runs if changed → recurses to
children. Unchanged subtrees are skipped entirely.

### Phase 2: Render (O(dirty widgets) selective, O(visible) full)

Each widget owns two small GPU textures:
- **widget_backend**: the widget's rendered content (background + primitives)
- **background_backend**: memorized parent content at the widget's position

Rendering a widget:
1. **Restore background**: blit `background_backend` → `widget_backend`
2. **Render primitives**: execute `DrawPrimitive` list on `widget_backend`
3. **Blit to layer**: copy `widget_backend` → layer buffer at widget position

**Fast path** (~90% of widgets during scroll): if the widget hasn't changed
(`has_valid_primitive_cache? && !needs_render? && !needs_fresh_background?`),
skip steps 1-2 and just re-blit the cached `widget_backend`. This is O(1) per
widget — no primitive generation, no background restoration.

**Selective rendering**: only widgets in `dirty_widgets` are re-rendered. Clean
widgets keep their cached content in the layer buffer from previous frames.

### Phase 3: Composite (O(layers))

Layer textures are blitted to the window sorted by z-index. For viewport_cache
layers (scrollable content), the compositor samples the correct viewport region
from the larger buffer using `texture_rect`. This makes panel drag O(1) — just
move the layer position, no re-rendering.

### Blit-Shift Optimization (Scroll Recenter)

When scrolling moves the viewport beyond the buffer's cache extent:
1. Compute overlap between old and new buffer regions
2. Copy overlap to temp → clear buffer → restore at new position
3. Invalidate widget_backends at the old buffer boundary (prevents truncated blits)
4. Render only newly-visible edge cells

Cost: O(edge_cells) instead of O(all_visible). For a 1400×900 matrix with 23px
rows, a vertical recenter re-renders ~12 cells instead of ~400.

## The Immediate-Mode Pipeline (Uncached Ground Truth)

The immediate-mode pipeline produces pixel-identical output using a naive
painter's algorithm that bypasses all caching:

1. Create a fresh viewport-sized backend, clear to `layer.background_color`
2. Collect ALL widgets in parent-first order (depth-first traversal)
3. For each widget:
   a. Copy current viewport surface at widget position → serves as background
      (parent content already painted by painter's algorithm)
   b. Call `to_primitives()` directly — NOT `get_primitives()`, which would
      return cached primitives for Static/Dynamic policies
   c. Render primitives on a temp widget-sized backend
   d. Blit temp backend to viewport surface
4. Second pass: render foreground primitives for DecoratedContainers

**Key insight**: `to_primitives()` vs `get_primitives()`. The cached pipeline
calls `get_primitives()` which returns `@cached_primitives` when the cache policy
allows it. The immediate-mode pipeline calls `to_primitives()` which always
generates primitives from scratch. This means cache validation can detect bugs in
primitive caching, not just rendering caching.

### Compile Flags

| Flag | Effect |
|------|--------|
| (none) | Crymble pipeline only, zero validation overhead |
| `-Dcache_validation` | Both pipelines run, pixel comparison after each frame |
| `-Dimmediate_mode_only` | Only immediate-mode pipeline, all caching bypassed |

`-Dimmediate_mode_only` is useful for visual debugging: if a rendering bug
disappears with this flag, the bug is in caching. If it persists, the bug is in
layout or primitive generation.

## Cache Validation Framework

### How It Works

With `-Dcache_validation`, after each frame's Crymble render of a viewport_cache
layer, the validator:

1. Captures the viewport region from the cached buffer (the "cached result")
2. Renders the same layer via immediate-mode painter's algorithm (the "fresh result")
3. Compares pixel-by-pixel

Any mismatch means a caching bug: the optimized path diverges from ground truth.

### Validation Levels

| Level | Cache | Status | What It Catches |
|-------|-------|--------|-----------------|
| 1 | **Immediate mode** (all caches) | Implemented | Any divergence between cached and uncached rendering |
| 2 | **Blit-shift** (overlap copy) | Implemented | Pixel corruption during buffer recenter |
| 3 | Dirty widget tracking | Planned | Selective render missing a dirty widget |
| 4 | Widget fast-path | Planned | Fast-path blit using stale widget_backend |
| 5 | Primitive cache | Planned | `@cached_primitives` diverging from `to_primitives()` |
| 6 | Blit-plan fast-path | Planned | Sticky layer shortcut producing wrong output |
| 7 | Layout cache | Planned | Skipped layout producing wrong bounds |

### Runtime Control

```crystal
CrymbleUI::CacheValidation.enable(:immediate_mode)
CrymbleUI::CacheValidation.enable(:blit_shift)
CrymbleUI::CacheValidation.disable_all

# After running:
CrymbleUI::CacheValidation.assert_no_failures!
# Or inspect:
CrymbleUI::CacheValidation.failures.each { |f| puts f }
```

### Headless vs SFML

| Backend | What It Catches | Limitation |
|---------|----------------|------------|
| TestRenderBackend (headless) | Logic bugs in caching, coordinate math, widget collection | No GPU — can't detect SFML-specific FBO/texture quirks |
| CrSFMLBackend (SFML) | All of the above + GPU-specific issues (Y-flip, texture staleness, scissor state) | Requires display (DISPLAY=:0 or Xvfb) |

Both backends implement the same `RenderBackend` interface, and both support
`capture_region_pixels` for pixel comparison. The immediate-mode pipeline works
identically on both.

Some bugs are SFML-only (e.g., the blit-shift boundary truncation bug where
widget_backends retained stale FBO clipping state). These can only be caught by
SFML autotests with `-Dcache_validation`, not by headless specs.

### Writing Cache Validation Tests

```crystal
# Headless spec (crystal spec -Dcache_validation)
{% if flag?(:cache_validation) %}
describe "Cache Validation" do
  before_each do
    CrymbleUI::CacheValidation.clear_failures!
    CrymbleUI::CacheValidation.enable_all
  end
  after_each { CrymbleUI::CacheValidation.disable_all }

  it "cached rendering matches immediate mode after scroll" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MyTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Scroll to trigger blit-shift
    scroll_widget(app, 7.times)
    renderer.settle_rendering(app)

    CrymbleUI::CacheValidation.assert_no_failures!
  end
end
{% end %}
```

## Performance Model

| Operation | Cost | Example |
|-----------|------|---------|
| Leaf widget change (hover, text edit) | O(1) ~0.2ms | Button hover in 400-button panel |
| Parent widget change (resize, recolor) | O(children) ~154ms | Rare, correct cascade |
| Panel drag | O(1) <0.1ms | Compositor only, no re-render |
| Scroll (within cache) | O(0) | Viewport shifts, no rendering |
| Scroll (blit-shift recenter) | O(edge_cells) ~2ms | ~12 cells re-rendered |
| Scroll (full recenter) | O(visible) ~50ms | No overlap, all cells re-rendered |
| Full layout | O(n) ~76ms | Window resize |
