# Caching Strategy Analysis

**Created**: 2025-11-19
**Status**: ANALYSIS - Documenting current state before architectural decision

## The Problem

We have TWO incompatible rendering/caching approaches mixed in the codebase:

### Approach A: Layer-Level Caching (DOCUMENTED)
**Location**: `LAYER_RENDERING_ARCHITECTURE.md`
**Implementation**: Partially in code (render_widget_to_backend - OLD path)

### Approach B: Per-Widget Textures (UNDOCUMENTED)
**Location**: Not documented
**Implementation**: Partially in code (render_single_widget - NEW path)

## Approach A: Layer-Level Caching (Current Docs)

### Architecture

```
Layer owns ONE RenderTexture
    └─ All widgets in layer render directly to this texture
    └─ Layer texture is cached between frames
    └─ Layer texture is composited to window
```

### Rendering Modes

**Full Render** (NeedsLayout or first_render):
1. Clear layer buffer to background_color
2. Render ALL widgets recursively to layer buffer
3. Widgets render primitives at layer-local coordinates
4. NO per-widget caching
5. NO background memorization

**Selective Render** (NeedsRender with dirty_widgets):
1. DON'T clear layer buffer (preserves previous render)
2. Render ONLY dirty widgets to layer buffer
3. Dirty widgets overwrite their previous content
4. Children of dirty widgets re-render (parent overwrites children)

### Code Path

```crystal
def render_layer(layer)
  if full_render
    backend.clear(layer.background_color)
    layer.widgets.each do |widget|
      render_widget_to_backend(widget, ...) # Recursive, direct to layer
    end
  else
    layer.dirty_widgets.each do |dirty_widget|
      # OLD approach: also render_widget_to_backend
      # Problem: parent primitives overwrite children
    end
  end
end
```

### Problems with Approach A

**Problem 1: Parent Overwrites Children**
```
Panel (dirty) renders background FillRect
    └─ Overwrites all 400 button textures!
    └─ Must re-render all children even if not dirty
    └─ Selective rendering becomes O(n) not O(dirty)
```

**Problem 2: Background Color Hack**
```
Solution: Move background to layer.background_color
Problem: Only works for solid colors, not gradients/patterns
Problem: Widgets can't render their own backgrounds during selective
```

**Problem 3: Selective Render is Broken**
```
If parent is dirty:
  - Parent renders primitives
  - Children MUST re-render on top (forced by parent)
  - Not truly selective - cascades to all descendants
```

## Approach B: Per-Widget Textures (Current Code)

### Architecture

```
Each widget owns a tiny RenderTexture (widget_backend)
Each widget owns a background snapshot (background_backend)
    └─ Widget captures layer background at its position (first render)
    └─ Widget restores background before each render
    └─ Widget renders primitives on restored background
    └─ Widget_backend is blitted to layer at widget position
```

### Rendering Modes

**Both Full and Selective use SAME path**:
1. For each widget needing render:
   a. Restore background from background_backend (GPU→GPU blit)
   b. Render primitives to widget_backend (on top of background)
   c. Blit widget_backend to layer (GPU→GPU blit)
2. No parent/child dependencies (each widget independent)
3. True O(dirty) selective rendering

### Code Path

```crystal
def render_layer(layer)
  widgets_to_render = if full_render
    collect_all_widgets_recursive(layer.widgets) # All widgets
  else
    layer.dirty_widgets  # Only dirty widgets
  end

  widgets_to_render.each do |widget|
    render_single_widget(widget, ...) # Per-widget texture path
  end
end

def render_single_widget(widget, backend, ...)
  # Ensure widget has backends
  widget.widget_backend ||= create_widget_backend(width, height)

  if background_backend = widget.background_backend
    # Subsequent render: restore saved background (GPU→GPU)
    widget_backend.blit(background_backend, 0, 0)
  else
    # First render: capture background from layer (GPU→GPU)
    background_backend = create_widget_backend(width, height)
    background_backend.blit_region(layer_backend, x, y, width, height, 0, 0)
    widget.background_backend = background_backend
    widget_backend.blit(background_backend, 0, 0)
  end

  # Render primitives on top of restored background
  primitives.each { |p| execute_on_widget_backend(p, widget_backend) }

  # Blit widget_backend to layer
  layer_backend.blit(widget_backend, layer_local_x, layer_local_y)
end
```

### Problems with Approach B

**Problem 1: Mixed Implementation**
```
Current code has BOTH paths:
  - render_widget_to_backend (OLD - direct to layer)
  - render_single_widget (NEW - per-widget textures)
  - if/else switches between them
  - Incompatible assumptions!
```

**Problem 2: Background Capture Timing**
```
When is background captured?
  - After full render? (background includes widget content!)
  - Before first render? (background is empty/wrong!)
  - During parent render? (order dependencies!)
```

**Problem 3: Upside-Down Rendering (SFML)**
```
SFML RenderTexture uses FBOs (Y-flipped)
  - blit_region uses Y-coordinate inversion (flipped_src_y)
  - Sprite scaling for coordinate correction
  - FIXED in commit 00b0c34 (Nov 27, 2025)
```

**Problem 4: Memory Overhead**
```
Every widget gets 2 RenderTextures:
  - widget_backend (for rendering)
  - background_backend (for background storage)
  - 400 widgets = 800 textures = high memory usage
```

**Problem 5: Parent-Child Rendering Order**
```
If parent changes, children backgrounds are invalid!
  - Parent background changes
  - Child background_backend has old parent background
  - Child restores old background = artifacts
```

## Comparison

| Aspect | Approach A (Layer) | Approach B (Per-Widget) |
|--------|-------------------|------------------------|
| **Documented** | ✅ Yes | ❌ No |
| **Memory** | ✅ O(layers) textures | ❌ O(widgets) textures |
| **Selective Render** | ❌ Broken (parent→child cascade) | ✅ True O(dirty) |
| **Parent Background** | ✅ Works (layer background_color) | ❌ Broken (capture timing) |
| **Gradients/Patterns** | ❌ Limited (layer color only) | ✅ Works (pixel-perfect) |
| **SFML Complexity** | ✅ Simple (direct rendering) | ❌ Complex (FBO flipping) |
| **Implementation** | ⚠️ Partial (render_widget_to_backend) | ⚠️ Partial (render_single_widget) |

## Current State (Mixed)

```crystal
# layer_renderer.cr has BOTH paths:

def render_layer(layer)
  if full_render
    layer.widgets.each do |widget|
      render_widget_to_backend(widget, ...) # Path A (OLD)
    end
  else
    layer.dirty_widgets.each do |dirty_widget|
      render_single_widget(dirty_widget, ...) # Path B (NEW)
    end
  end
end
```

**Why This is Broken:**
1. Full render uses Path A (no widget backends created)
2. Widget becomes dirty
3. Selective render uses Path B (expects widget backends!)
4. Background capture happens DURING selective render
5. Background already contains widget's old content
6. Restore + render = double rendering (BOLD effect)

## Symptoms We're Seeing

- ✅ **Bold rendering**: Content rendered twice (background contains old content)
- ✅ **Upside-down**: SFML FBO Y-flip issues in blit_region
- ✅ **Artifacts**: Background invalidation not working correctly
- ✅ **High CPU**: 307 render cycles (separate event loop issue)
- ✅ **Double rendering**: Mixing two incompatible paths

## Decision Points

### Option 1: Pure Approach A (Layer-Level Only)
**Remove**: All per-widget texture code
**Keep**: Layer-level caching, direct rendering
**Fix**: Selective rendering parent→child issue differently

**Pros:**
- ✅ Documented architecture
- ✅ Lower memory (fewer textures)
- ✅ Simpler (no coordinate flipping issues)

**Cons:**
- ❌ Selective rendering still broken (parent→child cascade)
- ❌ Can't do gradients/patterns as widget backgrounds
- ❌ Need different solution for selective rendering

### Option 2: Pure Approach B (Per-Widget Textures)
**Remove**: Old render_widget_to_backend path
**Keep**: Per-widget textures, background memorization
**Fix**: Background capture timing, SFML flipping

**Pros:**
- ✅ True O(dirty) selective rendering
- ✅ Pixel-perfect background restoration
- ✅ No parent→child dependencies

**Cons:**
- ❌ Higher memory (2x textures per widget)
- ❌ Complex SFML coordinate handling
- ❌ Background invalidation on parent changes
- ❌ Must document new architecture

### Option 3: Hybrid (Smart Selection)
**Full Render**: Use Approach A (layer-level)
**Selective Render**: Use Approach B (per-widget)
**Fix**: Make them compatible

**Pros:**
- ✅ Best of both worlds?

**Cons:**
- ❌ ALREADY BROKEN - this is what we have now!
- ❌ Incompatible assumptions between paths
- ❌ Background capture timing impossible to fix

## Resolution (2025-11-19)

**DECISION: Pure Approach B (Per-Widget Textures)** with correct implementation

### Why Approach B?

**Answers to the discussion questions:**

1. **Memory acceptable?** YES - 10-15MB GPU memory for 400 widgets is acceptable on modern GPUs (2-8GB VRAM typical)

2. **Can we solve background capture timing?** YES - capture BEFORE widget renders, AFTER parent renders (parent-first ordering)

3. **Is Approach A fixable?** Partially - layer.background_color solves parent background, but limited to solid colors (no gradients/patterns)

4. **Do we need per-widget caching?** YES - enables O(1) selective rendering for leaf changes (button hover, text update) which is the common case (90-95%)

### How Approach B Works (Correctly Implemented)

#### Key Insight: Background Capture Timing
The original implementation attempted Approach B but had WRONG timing:
- ❌ **Wrong**: Captured background AFTER widget rendered → double-rendering bug
- ✅ **Correct**: Capture background BEFORE widget renders, AFTER parent renders

#### Critical Components

**1. Two-Level Caching**
```crystal
Layer cache:     One RenderTexture per layer (coarse-grained, O(1) panel drag)
Widget cache:    Two RenderTextures per widget (fine-grained, O(1) selective render)
  - widget_backend: rendering target
  - background_backend: memorized background (captured BEFORE widget renders)
```

**2. Parent-First Render Ordering**
```crystal
# MUST process widgets in depth-first order (parent before children)
def collect_widgets_parent_first(widgets)
  result = []
  widgets.each { |w| collect_depth_first(w, result) }
  result
end
```

**Why critical**: Children capture backgrounds from layer. If child processes before parent, it captures empty/wrong background!

**3. Parent Invalidation Cascade**
```crystal
def mark_needs_render
  @state = WidgetState::NeedsRender
  invalidate_children_backgrounds  # O(children) cascade
end
```

**Performance implications**:
- Common case (90-95%): Leaf changes → O(1) selective rendering ✓
- Uncommon case (5-10%): Parent changes → O(children) cascade ✓ (correct, rare)
- Rare case (<1%): Layout changes → O(n) full render ✓ (expected)

The O(children) cascade when parent changes is **CORRECT behavior**, not a bug. The architecture optimizes for the common case.

**4. Four Invariants (Enforced with Assertions)**

**Invariant (f): Rendering precondition**
- Widget can only render to widget_backend if first time OR background was restored
- Catches: rendering to stale/dirty buffer (double-rendering)

**Invariant (g): Memorization precondition (graceful handling)**
- Background size must match widget size for direct restore
- Size mismatch → fills with background color instead (handles edge cases)
- NOT asserted (can occur legitimately during reconcile, text changes)

**Invariant (h): Background capture purity**
- Widget can only capture background if it has NEVER rendered to layer at current bounds
- Catches: capturing own old content as background (causes garbage accumulation)

**Invariant (siblings): No overlap constraint**
- Sibling widgets cannot have overlapping bounds (current constraint)
- Future: will relax with explicit z-index
- Catches: layout bugs, background corruption from overlapping siblings

### Why Mixing Approaches Failed

**The mixed implementation** (old code):
- Full render used Approach A: direct rendering to layer
- Selective render used Approach B: per-widget textures
- Background captured DURING selective render (too late!)
- Result: background contained widget's own old content → double-rendering

**The solution**: Always use Approach B (per-widget textures) for ALL rendering.

### Implementation Checklist

- ✅ Document per-widget texture architecture in LAYER_RENDERING_ARCHITECTURE.md
- ✅ Document invariants (f), (g), (h), and (siblings)
- ✅ Implement parent-first render ordering (depth-first traversal)
- ⏳ Implement parent invalidation cascade (invalidate_children_backgrounds)
- ✅ Add invariant assertions for (f), (h), (siblings) - always on
- ✅ Add siblings no-overlap validation
- ✅ Fix failing tests (menubar double-render)
- Note: (g) handled gracefully, not asserted (edge cases are legitimate)

### Performance Model

**Memory** (400-button panel):
```
Layer cache:     ~480KB (1 texture)
Widget caches:   ~9.6MB (800 textures: 2 per widget)
Total:           ~10MB GPU memory ✓ Acceptable
```

**Render performance**:
```
Leaf change:     O(1)      ~0.2ms   (button hover)
Parent change:   O(children) ~154ms   (panel color - rare!)
Layout change:   O(n)      ~154ms   (panel resize - rare!)
Panel drag:      O(1)      <0.1ms   (compositor only)
Scroll:          O(newly-visible) ~1.5ms  (viewport_cache buffer)
```

### Scroll Optimization (Dec 2025)

**Problem**: Scrolling 100-button ScrollView used 100-120% CPU despite widget caching.

**Root causes found**:
1. All visible widgets re-rendered (cache not used during scroll)
2. `validate_sibling_bounds` ran O(n²) every frame

**Solutions**:

1. **Widget cache check**: Skip re-rendering if `has_valid_primitive_cache? && !needs_render?`
   ```crystal
   # In render_single_widget for viewport_cache layers:
   if widget.has_valid_primitive_cache? && !widget.needs_render?
     backend.blit(existing_backend, x, y)  # Fast path: just blit
     return
   end
   ```

2. **Skip validation on scroll**: `validate_sibling_bounds` only runs on `first_render?` or `NeedsLayout`

3. **O(n) for ordered containers**: VStack/HStack use `each_cons(2)` instead of O(n²) all-pairs

**Result**: Scroll CPU dropped from 100-120% to 0-60%, render time from 17ms to 1.5ms

### Alternatives Considered and Rejected

**Pure Approach A (Layer-level only)**:
- ❌ Rejected because:
  - Parent primitives overwrite children during selective render
  - layer.background_color only works for solid colors (no gradients/patterns)
  - Would need complex logic to avoid rendering parent primitives during selective render
  - O(n) selective rendering (must recurse tree to find dirty widgets)

**Hybrid (A for full, B for selective)**:
- ❌ Rejected because:
  - This is what we HAD - proven broken!
  - Incompatible timing: background captured at wrong time
  - Leads to double-rendering bugs

**Pure Approach B with lazy invalidation**:
- ❌ Rejected because:
  - Accepting temporary visual wrongness unacceptable
  - Would require eventual consistency (complex, error-prone)

**Decision**: Pure Approach B with correct implementation (parent-first, parent invalidation cascade, invariants)
