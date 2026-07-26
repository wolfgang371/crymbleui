# Layer-Based Rendering Architecture

**Status**: IMPLEMENTED ✅
**Related**: See `ARCHITECTURE.md` for DrawPrimitive architecture, and `REACTIVITY.md` for the
canonical reactive-invalidation model (auto-capture, version counting, the pull render trigger).

## Overview

CrymbleUI uses a **layer-based rendering architecture** where widgets can own render targets (layers) that cache their visual content. This enables high-performance dragging, resizing, and animations by avoiding expensive re-rendering of static content.

**Key Insight**: When a panel with 400 buttons is dragged, we don't re-render 400 buttons. We just move the cached layer texture. This is O(1) instead of O(n).

## The Core Architecture

### Widget Tree vs Layer Tree

```
Widget Tree                  Layer Tree
━━━━━━━━━━━                  ━━━━━━━━━━
Window                       RootLayer (z=0)
├─ MenuBar                      └─ (no layer)
│  └─ Menu
│     └─ MenuItem
├─ StatusBar
└─ WindowPanel ─────────►    PanelLayer (z=100)
   ├─ Button                    └─ (no layer - rendered to PanelLayer)
   ├─ Button
   └─ ... (400 buttons)
```

**Key Points:**
- Most widgets DON'T have layers - they render to their parent's layer
- Only specific widgets create layers: Window, WindowPanel, Popup
- Layer tree is SPARSE - much fewer nodes than widget tree
- Layers form a hierarchy for organization, but render by z-index

### What is a Layer?

```crystal
class Layer
  property id : String
  property z_index : Int32           # Rendering order (higher = on top)
  property bounds : Rect             # Position and size in window coordinates
  property opacity : Float64         # 0.0 - 1.0
  property blend_mode : BlendMode
  property background_color : Color  # For clearing buffer

  property backend : RenderBackend?  # Render target (texture)
  property parent : Layer?
  property children : Array(Layer)
  property widgets : Array(Widget)   # Widgets that render to this layer

  property state : WidgetState       # Clean, NeedsRender, NeedsLayout
  getter dirty_widgets : Set(Widget) # For selective rendering
end
```

**Layer Responsibilities:**
1. **Own a render target** (texture/framebuffer) to cache rendering
2. **Track which widgets** render to this layer
3. **Track dirty widgets** for selective rendering
4. **Provide background color** for clearing (instead of rendering FillRect)
5. **Maintain bounds** for positioning during composite

## Three-Phase Rendering Pipeline

Every frame goes through exactly 3 phases:

```
┌─────────────────────────────────────────────────┐
│  PHASE 1: LAYOUT                                │
│  - Calculate widget positions/sizes             │
│  - Update widget.bounds (absolute coordinates)  │
│  - Performance: O(n) - walks entire tree        │
│  - Triggered by: size changes, structure changes│
│  - NOT triggered by: position-only changes      │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  PHASE 2: RENDER                                │
│  - Generate primitives for dirty widgets        │
│  - Render primitives to layer backends          │
│  - Performance: O(dirty) - only changed widgets │
│  - Triggered by: content changes, layout changes│
│  - NOT triggered by: layer position changes     │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  PHASE 3: COMPOSITE                             │
│  - Copy layer textures to window                │
│  - Apply z-index ordering, opacity, blending    │
│  - Performance: O(layers) - very few layers     │
│  - Triggered by: ALWAYS (even if no re-render)  │
│  - Handles layer position changes               │
└─────────────────────────────────────────────────┘
```

### When Each Phase Runs

| Change Type | Layout | Render | Composite | Example |
|------------|--------|--------|-----------|---------|
| **Widget size changed** | ✅ Yes | ✅ Yes | ✅ Yes | Panel resized |
| **Widget structure changed** | ✅ Yes | ✅ Yes | ✅ Yes | Button added to panel |
| **Widget content changed** | ❌ No | ✅ Yes | ✅ Yes | Button text changed |
| **Layer position changed** | ❌ No | ❌ No | ✅ Yes | **Panel dragged** ← KEY! |
| **Nothing changed** | ❌ No | ❌ No | ✅ Yes | Static frame |

**CRITICAL INVARIANT**: Position-only changes (drag) don't need layout or render - only compositor update!

## Performance Model

Understanding the cost of each phase is critical:

```
LAYOUT Phase:     O(n) where n = total widgets
                  - Walks entire widget tree
                  - Recalculates all positions
                  - EXPENSIVE with many widgets
                  - Example: 400 buttons = 76ms

RENDER Phase:     O(dirty) where dirty = changed widgets
                  - Only renders widgets marked dirty
                  - Selective rendering optimization
                  - Example: 1 button = 0.2ms, not 400!

COMPOSITE Phase:  O(layers) where layers = # of layer objects
                  - Copies cached textures to window
                  - Very fast (usually < 1ms)
                  - Example: 2 layers = 0.1ms

DISPLAY:          O(1) - Single call per frame
                  - window.display swaps back buffer
                  - MUST be called exactly once per frame
```

**Rule: Single `window.display` per frame**

Multiple display calls per frame cause:
- Extra vsync waits (16ms each at 60Hz) - kills frame rate
- Potential screen tearing
- Wasted GPU cycles

```crystal
# BAD - Do not call display multiple times!
window.display  # First display
do_more_work()
window.display  # WRONG - wastes 16ms+ waiting for vsync

# GOOD - Single display at end of render loop
render_all_layers(...)
composite_all_layers(...)
window.display  # Once, at the very end
```

### Cost Breakdown Examples

**Scenario 1: Panel Drag (400 buttons)**
```
Without layer caching:
  Layout:    76ms   (re-layout 400 buttons)
  Render:    154ms  (re-render 400 buttons)
  Composite: 0.1ms
  TOTAL:     230ms  ← Freezes for 1/4 second!

With layer caching (current):
  Layout:    0ms    (position-only, no layout!)
  Render:    0ms    (cached layer texture)
  Composite: 0.1ms  (just move layer)
  TOTAL:     0.1ms  ← Smooth 60 FPS!
```

**Scenario 2: Button Hover (1 button changes)**
```
  Layout:    0ms    (no size change)
  Render:    0.2ms  (1 button = 1 dirty widget)
  Composite: 0.1ms
  TOTAL:     0.3ms  ← Smooth!
```

**Scenario 3: Panel Resize**
```
  Layout:    76ms   (must recalculate 400 button positions)
  Render:    154ms  (full render after layout)
  Composite: 0.1ms
  TOTAL:     230ms  ← Acceptable for resize (one-time)
```

## Incremental Layout Optimization

**Status**: IMPLEMENTED ✅ (as of 2025-12)

Layout is expensive O(n), so we optimize by skipping layout for widgets that don't need it.

### The Template Method Pattern

The `Widget` base class uses a template method pattern for layout:

```crystal
abstract class Widget
  # Last constraints used for layout (for incremental optimization)
  @last_constraints : BoxConstraints?

  # Template method: handles skip check, delegates to perform_layout
  def layout(constraints : BoxConstraints, position : Vec2)
    # Skip layout if constraints unchanged and widget is clean
    if can_skip_layout?(constraints)
      @bounds = Rect.new(position, @bounds.size)  # Just update position
      return
    end

    @state = WidgetState::Clean
    perform_layout(constraints, position)  # Delegate to subclass
    @last_constraints = constraints
  end

  # Check if layout can be skipped
  protected def can_skip_layout?(constraints : BoxConstraints) : Bool
    return false if needs_layout?              # Marked dirty
    return false if @last_constraints.nil?     # First layout
    @last_constraints == constraints           # Same constraints
  end

  # Subclasses implement this instead of layout()
  abstract def perform_layout(constraints : BoxConstraints, position : Vec2)
end
```

### Skip Condition

A widget can skip layout if ALL of these are true:
1. `!needs_layout?` - widget not marked dirty via `mark_needs_layout()`
2. `@last_zoom_epoch == FontSizing.zoom_epoch` - zoom unchanged since the last layout
3. `@last_constraints != nil` - not first layout
4. EITHER `@last_constraints == constraints` (same available space from parent), OR the new constraints
   are a **relaxation this widget did not use**: its last size still fits them, and in each axis whose
   max grew it was not already filling the old max. See `docs/ARCHITECTURE.md` "Loose content +
   relaxation-skip" for why a panel hands its content a loose box.
5. `!subtree_layout_depends_on_available_space?` - neither this widget nor any descendant re-arranges
   against the available space. A wrapping `FlowLayout` does, and the check has to be the SUBTREE
   closure: the skip that would strand it happens at an ancestor, which returns before the flow's
   `layout()` is reached. (Condition 5 does not apply to case "identical constraints" in 4 — nothing can
   change when the available space did not.)

**Key insight**: Position is irrelevant for layout. A widget's internal layout depends ONLY on constraints (available space). Position is just a translation applied at the end.

### Performance Model

When a widget calls `mark_needs_layout()`:
1. It propagates UP to root (lazy trigger)
2. It invalidates `@last_constraints` (forces re-layout even if constraints unchanged)
3. During layout pass, only the dirty path re-layouts

```
Window (dirty via propagation)
  ├── Sidebar (Clean, same constraints) ← SKIPPED (just update position)
  │     └── 100 widgets...              ← NOT VISITED (parent skipped)
  └── VStack (dirty via propagation)
        ├── Button1 (dirty) ← the changed one, full layout
        ├── Button2 (Clean) ← skip (check only, no recursion into children)
        └── Button3 (Clean) ← skip
```

| Scenario | Widgets Visited | Full Layout |
|----------|-----------------|-------------|
| One leaf dirty | O(path + siblings) | O(path) |
| No changes | O(1) - root only | O(0) |
| Window resize | O(n) | O(n) |

### Layer-Owning Widgets

Widgets with their own layers (Popup, MenuBar) override `can_skip_layout?` to always return `false`:

```crystal
class Popup < Widget
  protected def can_skip_layout?(constraints : BoxConstraints) : Bool
    return false if @internal_layer  # Never skip - layer.bounds must sync
    super
  end
end
```

**Why**: These widgets update `layer.bounds` in `perform_layout`. If layout is skipped but `@bounds` is updated (position change), `layer.bounds` becomes out of sync, causing rendering at wrong coordinates.

### Self-Positioning Widgets

Some widgets compute their own position internally rather than using the `position` parameter passed to `layout()`. These also override `can_skip_layout?`:

```crystal
class WindowPanel::Content < Widget
  protected def can_skip_layout?(constraints : BoxConstraints) : Bool
    false  # Always run perform_layout to compute correct position
  end

  def perform_layout(constraints, position)  # position parameter ignored!
    content_y = panel.title_bar_height + CONTENT_PADDING
    @bounds = Rect.new(CONTENT_PADDING, content_y, ...)  # Computes own position
  end
end
```

**Why**: The skip path does `@bounds = Rect.new(position, @bounds.size)`, which uses the `position` parameter. But self-positioning widgets ignore this parameter and compute position from internal state (e.g., `panel.title_bar_height`). If the skip path runs, `@bounds` gets the wrong position.

**Pattern applies to**: `WindowPanel::Content`, `LayerBox` (any widget that ignores the `position` parameter).

### LayerOwner Ancestor Notifications

Layer-owning widgets need to update their layer bounds when an ancestor moves or resizes. The `LayerOwner` mixin provides notification callbacks:

```crystal
# Callbacks (override in layer-owning widgets)
def on_ancestor_position_changed(delta : Vec2)    # Ancestor dragged
def on_ancestor_resize_start                       # Ancestor resize started
def on_ancestor_resize_move(dw, dh)               # Ancestor resizing (delta from start)
def on_ancestor_resize_end                         # Ancestor resize ended
def on_ancestor_z_index_changed(base_z : Int32)   # Ancestor z-index changed

# Broadcasting (call from parent widget)
notify_layer_owners_position_changed(delta)
notify_layer_owners_resize_start
notify_layer_owners_resize_move(dw, dh)
notify_layer_owners_resize_end
notify_layer_owners_z_index_changed(new_z)
```

**Example**: `WindowPanel` broadcasts position changes to `@content`, which propagates to any nested `ScrollView` widgets. Each `ScrollView` updates its own layer bounds without WindowPanel needing to know about ScrollView-specific internals.

**Why notifications instead of direct calls?**
- Decouples parent from child's layer implementation details
- Any `LayerOwner` widget automatically receives notifications
- Adding new layer-owning widgets doesn't require parent changes

## WidgetState Enum

The state machine that controls rendering:

```crystal
enum WidgetState
  Clean         # No changes, skip rendering
  NeedsRender   # Content changed, selective render
  NeedsLayout   # Size/structure changed, full layout + render
end
```

### State Transitions

```
Clean ──content_change──> NeedsRender ──render()──> Clean
  │                                                    ▲
  │                                                    │
  └───size/structure_change──> NeedsLayout ──layout()─┘
```

### State Propagation Rules

**Content invalidation is no longer pushed through `mark_needs_render`.** A reactive value (a
`reactive_property`, see `REACTIVITY.md`) read in `to_primitives` is auto-captured as a dependency of the
widget's cached primitives node; changing it moves a version counter, which marks the node stale and enqueues
the widget for re-render. The author never wires this up, and the edge cannot be forgotten because *reading*
the value is what declares it.

`mark_needs_render` survives only as a **structural** signal — for state that is not paint content expressed
as a `Source`: `visible`/`enabled`/`focus_highlighted`, drag/reflow transitions, and the like. It still does
the layer bookkeeping below (add to `dirty_widgets`), but it is no longer the channel for "the color/text
changed."

```crystal
# Structural re-render request (NOT used for ordinary content changes anymore)
widget.mark_needs_render
  → widget.state = WidgetState::NeedsRender
  → widget.layer.mark_needs_render(widget)  # Add to dirty_widgets
  → widget.layer.state = WidgetState::NeedsRender

widget.mark_needs_layout
  → widget.state = WidgetState::NeedsLayout
  → widget.invalidate_last_constraints  # Force re-layout even if constraints unchanged
  → widget.parent.mark_needs_layout  # Propagate WITHIN layer only (stops at layer boundary)
  → widget.layer.mark_needs_layout
  → widget.layer.dirty_widgets.clear  # Full render needed
  → widget.layer.state = WidgetState::NeedsLayout
  → DOES NOT propagate to parent layers  # Layout is confined to single layer
```

> Layout stays an imperative pass (not a pull node), so a field that affects size/position still pokes
> `mark_needs_layout` explicitly — via the `reactive_property ... layout: true` setter. Only *render*
> invalidation moved to auto-capture.

**Layout Scope and Isolation (as of 2025-11-30)**

Layout changes are **confined to a single layer** and do NOT propagate across layer boundaries:

- `Widget.mark_needs_layout` propagates UP the widget tree within the same layer
- When reaching a widget that owns a layer (Window, MenuBar, Popup, LayerBox), propagation STOPS
- `Layer.mark_needs_layout` does NOT propagate to parent layers
- This isolation prevents expensive O(n) cascades across the entire window tree

**Example: CPUMonitor in Overlay**
```crystal
# Overlay layer structure:
Window (owns root layer)
  └─ LayerBox (owns overlay layer)  ← Layer boundary
       └─ CPUMonitor (flexible size)

# When CPUMonitor size changes:
CPUMonitor.mark_needs_layout
  → LayerBox.mark_needs_layout  # Propagates to parent
  → STOPS (LayerBox owns a layer - boundary reached)
  → Overlay layer marked NeedsLayout
  → Root layer unaffected ✓

# Performance: O(overlay widgets) not O(all widgets)
```

**Why This Matters**

- Small overlay widgets (CPUMonitor, tooltips) don't trigger full window layouts
- Each layer can be laid out independently
- Overlay layers are typically tiny (1-5 widgets) vs root layer (100+ widgets)
- Layout cost scales with layer size, not total widget count

## Rendering Scope and Isolation (as of 2025-11-30)

Rendering changes, like layout changes, are **confined to a single layer** and do NOT propagate across layer boundaries:

- `Widget.mark_needs_render` marks the widget dirty within its layer
- `Layer.mark_needs_render(widget)` adds widget to dirty set - does NOT notify parent
- `Layer.mark_needs_full_render` marks all widgets dirty - does NOT propagate to parent
- This isolation prevents expensive cascading re-renders up the layer tree

**Architecture: Independent Layer Rendering**

Each layer is an independent render target:

1. **Root layer** has opaque background (window background color)
2. **Child layers** can have transparent backgrounds (show parent layers through)
3. **Each layer renders independently** to its own texture/backend
4. **Compositor blits all layers** on top of each other (sorted by z-index)

**Example: Button hover in WindowPanel**
```
Button hover in panel
→ Panel layer marks button dirty (adds to dirty_widgets)
→ Panel re-renders ONLY the button (selective render)
→ NO notification to Window layer (parent)
→ Compositor blits Window layer (unchanged) + Panel layer (updated)
```

**Why parent notification is NOT needed:**

- Each layer maintains its own cached texture
- When a child layer changes, it just re-renders itself
- Parent layer's texture stays unchanged
- Compositor always runs and blits all layers together
- Transparency works at composite time (lower layers show through)

**When layers DO need coordination:**

Layers should coordinate ONLY for structural changes:
- Z-index changes (affects composite ordering)
- Layer added/removed (compositor needs to know)
- Layer opacity changes (affects alpha blending)

These are handled explicitly, not via automatic propagation.

## Drag-and-Drop Overlay Layers

Drag-and-drop uses overlay layers to provide visual feedback without triggering expensive cache invalidation.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Window                                                       │
│  ├─ Root Layer (z=0)         ← Normal widget content        │
│  ├─ Highlight Layer (z=1000) ← Drop zone feedback (40% opacity) │
│  └─ Ghost Layer (z=9999)     ← Drag preview (70% opacity)   │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `DragManager` - Coordinates drag operations, creates/destroys overlay layers
- `Draggable` mixin - Widgets that can be dragged (`get_drag_data`, `on_drag_start/end`)
- `DropTarget` mixin - Widgets that accept drops (`accepts_drop?`, `on_drop`)
- `GhostWidget` - Semi-transparent preview in ghost layer
- `HighlightWidget` - Drop zone highlight in highlight layer

### Performance Model

| Operation | Cost | Why |
|-----------|------|-----|
| Ghost position update | O(1) | Only `layer.bounds` changes, no re-render |
| Drop target enter/leave | O(1) | New highlight layer created, old destroyed |
| Drag start | O(1) | Create ghost layer + one render |

**Key insight:** Ghost movement is O(1) because we only update `layer.bounds`:

```crystal
# In DragManager.update_ghost_position - O(1)
layer.bounds = Rect.new(
  position.x - @ghost_offset.x,
  position.y - @ghost_offset.y,
  layer.bounds.width,
  layer.bounds.height
)
# NO mark_needs_render! Layer content unchanged, just composited elsewhere.
```

### Why Overlay Layers?

**Problem:** If drop zones changed background color on hover:
- Parent color change invalidates children's background cache
- Children would re-capture stale backgrounds from SFML RenderTexture
- Result: visual glitches, O(n) re-render on every hover

**Solution:** Overlay layer with opacity:
- Drop zone background stays static (no cache invalidation)
- `HighlightWidget` renders on separate layer at 40% opacity
- `layer.opacity` applied during compositing (`sfml_renderer.cr` lines 298-300 for standard layers, lines 376-378 for viewport-cache layers)
- Result: O(1) visual feedback, no widget cache touched

### DSL Usage

```crystal
# Draggable item
draggable(data: TextDragData.new("Task A")) do
  hstack(padding: 8.0, background_color: blue) do
    text("Task A")
  end
end

# Drop zone
drop_zone(accept_types: ["text"], on_drop: ->(data, pos) {
  puts "Received: #{data.display_text}"
}) do
  vstack(padding: 8.0) do
    text("Drop here")
  end
end
```

### Customization

Override in `DropTarget` implementations:
- `highlight_color : Color` - Overlay color (default: blue)
- `highlight_opacity : Float64` - Overlay opacity 0.0-1.0 (default: 0.4)

## Selective Rendering

The optimization that makes large UIs fast:

### Full Render vs Selective Render

```crystal
def render_layer(layer : Layer)
  full_render = layer.first_render? || layer.state == WidgetState::NeedsLayout

  if full_render
    # O(n): Traverse entire widget tree recursively
    backend.clear(layer.background_color)  # Clear to background
    layer.widgets.each do |widget|
      render_widget_to_backend(widget, layer, backend, full_render)
    end
  else
    # O(dirty): Only render specific dirty widgets
    layer.dirty_widgets.each do |dirty_widget|
      render_single_widget(dirty_widget, backend)
    end
  end

  layer.clear_render_state  # Mark clean, clear dirty list
end
```

### Dirty Widget Tracking

```crystal
class Layer
  getter dirty_widgets : Set(Widget)

  def mark_needs_render(widget : Widget)
    @state = WidgetState::NeedsRender if @state == WidgetState::Clean
    @dirty_widgets << widget
  end

  def mark_needs_layout
    @state = WidgetState::NeedsLayout
    @dirty_widgets.clear  # Layout = all widgets dirty
  end

  def widget_dirty?(widget : Widget) : Bool
    @dirty_widgets.empty? || @dirty_widgets.includes?(widget)
  end
end
```

**Key Insight**: Empty `dirty_widgets` set means "all dirty" (full render). Non-empty means "only these widgets dirty" (selective render).

### The Version-Keyed Fast Path

Before any of the above runs, a per-widget **version gate** decides whether a widget needs to be visited at
all. Each widget exposes a primitives version (the fold of its cached node's `local_rev` plus the versions of
every dependency it auto-captured, plus a `slot_rev` for its cache slot). A widget whose version is unchanged
since it was last rendered is skipped outright — no `to_primitives`, no blit. This is the render-side
counterpart of the frame trigger described in `REACTIVITY.md`: identity by version, never by deep comparison.
`dirty_widgets` is still consulted for non-`viewport_cache` layers, but the version gate is the authority on
*whether the work is actually needed*; an unchanged widget in the dirty set still costs nothing.

### viewport_cache Layers: the Pull / SlotBuffer Model

`viewport_cache` layers (the VirtualMatrix viewport) do **not** use the `dirty_widgets` set. They run a
**pull, visit-all-visible** model: each frame the renderer walks every currently-visible cell, and for each
one compares its version against the version recorded in the slot it occupies in the buffer (`slot_rev`). A
cell whose version matches its slot is **slot-skipped** — its cached pixels are already correct and stay put.
Only cells whose version moved (a value edit) are re-rendered into their slot. Scrolling is mostly *spatial
coherence* (re-blit the buffer at a new offset; slots keep their versions), distinct from a value edit which
is *dependency freshness* — see the "two orthogonal axes" section of `REACTIVITY.md`. This keeps a scrolling
or idle matrix at near-zero render work while still catching a single edited cell.

**Layer-level gate (above the per-slot pull).** The visit-all-visible pass is itself O(visible) — cheap per
cell, but not free when a maximized matrix is dragged and a frame fires per mouse-move. So a `viewport_cache`
layer runs the pass **only when its content could have changed**: `Layer#viewport_body_stale?` gates it on a
per-layer version, `content_rev` (= `scroll_rev + clear_rev + render_rev + Σ visible-widget `primitives_version``) plus the
push flags (`needs_render?`/`needs_clear`), a pending resize `resize_shift`, and `size_changed?`. Crucially it
**excludes `position_rev`**: a WindowPanel *drag* bumps only the layer's composite position, and the
unconditional composite already re-blits the cached buffer at the pulled `bounds` (`compute_bounds_for_layer` →
`absolute_bounds`, live parent chain). So a position-only frame skips the whole pass — the matrix drags as a
pure composite, exactly like a button panel (this was the fix for a ~90%-CPU maximized-drag). `content_rev` is
the same per-layer sum `frame_aggregate_rev` folds for the render trigger (minus `position_rev`), so trigger
and gate cannot drift; the stamp of "what was last rendered" lives in `clear_render_state`.

> **PRECONDITION — change must move a version, not just a per-frame poll.** The gate assumes appearance
> changes move a *version* (as the RULE below already requires). Two concrete traps:
> - A `CachePolicy::Never` widget that repaints on an external clock (its `primitives_version` does **not**
>   move per frame) placed **directly on a `viewport_cache` layer** would freeze between content changes.
>   Today none exist there (the cursor-overlay and rulers live on their own non-`viewport_cache` layers); a
>   future one must force `needs_render?` on its layer each tick, or live on a non-`viewport_cache` layer.
> - A `MatrixAdapter` whose `start_frame`/`cell_read` change-poll is the **only** notice of a value change
>   (a derived / background-recomputed cell with no version bump) is polled only on a content-rendering
>   frame, so its change-flash is deferred across a pure drag until release. Embrace's flashes are
>   reactive-driven (they move a rev → `content_rev` → the layer wakes), so this is latent, not live; bump a
>   version if a poll-detected change must animate mid-drag.

## Cache-Coherency Contract (what invalidates what)

Cache garbling is almost always a **missing invalidation**: a value changed, but the signal that should
have re-rendered the cache depending on it was either never sent or sent on the *wrong channel*. This
section is the single "what invalidates what" reference, so a widget author picks the right channel.

### The caches

| Cache | Holds | Owned by |
|-------|-------|----------|
| **A1 primitives** (`@cached_primitives` / primitives node) | the widget's DrawPrimitives at (0,0) origin | every widget |
| **A2 widget texture** (`widget_backend`) | the rasterized widget | every rendered widget **except** a `tiled_cells` layer's cells (see Direct-to-layer below) |
| **A3 background** (`background_backend`) | the layer pixels behind the widget, memorized | every rendered widget (same exception) |
| **A4 slot buffer** | rasterized visible cells, one per buffer slot | `viewport_cache` layers (VirtualMatrix, ScrollView content) |
| **A5 layer texture** | the composited layer | layer-owning widgets |

### Direct-to-layer render (`tiled_cells` layers)

A `viewport_cache` layer whose top-level widgets form a **grid of tiling cells** — adjacent, gaps filled by
grid lines, over a uniform background — sets `layer.tiled_cells = true` (VirtualMatrix does this on its
content layer). On a full render of such a layer (`buffer_just_cleared`), each cell's primitives are drawn
**directly into the layer buffer** via `execute_primitive_with_offset` — skipping the per-cell `widget_backend`
entirely: no texture allocation, no background capture/restore (invariants f/h), no per-cell blit. The buffer
is the single source of truth, so the pixels are identical to the texture path (any device-pixel edge a cell
leaves uncovered is a tiling neighbour, a grid line, or the just-cleared uniform bg). This is the measured
DnD-reconfigure win (~130 texture allocs+blits → 0). The cell is left in the clean state {no `widget_backend`,
no `background_backend`, `slot` stamped at its buffer position}, so it costs zero GPU texture memory.

**Validity is the slot, not the texture.** Because a direct-rendered cell has no `widget_backend`, the
scroll-skip and blit-shift paths key off the **slot** (`slot_rev` = `primitives_version`, `slot_buffer_pos` =
buffer position) rather than texture existence: a cell is skipped when `slot_fresh?` (content + position
unchanged), and the blit-shift moves each cell's slot in lockstep with the pixels it translates
(`shift_slot`), so a scroll skips the still-valid cells with no re-render. Only a genuinely reflowed or
newly-exposed cell (stale/absent slot) re-renders. Non-tiling `viewport_cache` content (a ScrollView's spaced
list, a ComboBox popup) leaves cell edges exposed over the layer bg, so it stays on the per-cell texture path.

> **Testing note:** a direct-rendered cell has no `widget_backend`, so "did this cell paint?" is the
> renderer's per-frame **disposition** (`widget_disposition(cell)` → `:rendered`/`:blitted`/`:skipped` =
> painted; `nil` = culled), or a `get_pixel` on the **layer buffer** — never `widget_backend` presence.
>
> **LAW — assert viewport-cache RE-RENDER via the disposition oracle, NOT pixels.** For any test of
> whether a viewport-cache body *re-rendered* (collapse→re-expand, grow-ghost, reflow), use
> `widget_disposition` (`nil` = the cell was dropped — the bug), NEVER a pixel assertion. The headless
> `TestRenderBackend` is a plain pixel array that **retains** stale content, whereas a real SFML
> `RenderTexture` **blanks** a culled/un-repainted buffer — so a pixel assertion is a **false green**
> headless (the bug is invisible). The disposition is deterministic and backend-agnostic. (A pixel
> `get_pixel` is fine for a *within-frame* paint check, e.g. border parity above — just not for
> re-render-after-cull correctness.) An "unavailable pixel" fault on the test backend was considered and
> rejected: a collapse drops individual *cells*, not the layer (`valid_layer_dimensions?` stays true),
> so a correct fault would just re-derive the disposition oracle.
>
> **Border pixel-parity:** the direct path draws a cell's primitives at a *buffer offset*, whereas the texture
> path drew them widget-local at (0,0). `draw_rect` (borders) simulates SFML clipping the outline's outer half
> at the scissor edge; that skip is **clip-relative** (`bounds.x <= clip.x`), NOT origin-0, so a border renders
> identically whichever path drew it — matching real SFML, which scissors wherever the clip sits. (Keying the
> skip on `bounds.x == 0` alone made the two paths differ by 1px — the cv oracle caught it.)

### Two kinds of signal — and the trap

There are exactly two ways to mark a cache stale, and they are **not** interchangeable:

- **PERSISTENT — a version bump.** A widget's `primitives_version` is its Cached-node version for a rendered
  Dynamic widget (auto-capturing content/theme/zoom), falling back to the residual
  `primitive_cache_rev = content_rev + layout_rev` otherwise (theme/zoom reach the residual via the node or a
  rebuild; the global `theme_rev` counter was deleted). It is a *value*, so it survives until the widget is
  actually re-rendered. You raise it by **reading a `reactive_property` getter in `to_primitives`**
  (content/theme/zoom auto-capture → content_rev) or by **`mark_needs_layout`** (size/structure → layout_rev).
- **TRANSIENT — a dirty flag.** `mark_needs_render(widget)` adds the widget to its layer's `dirty_widgets`
  set, which is **swept Clean every frame by `clear_render_state`**.

**THE TRAP.** A `viewport_cache` layer does **not consult `dirty_widgets` at all** — it re-evaluates every
visible cell each frame and **slot-skips** any whose `primitives_version` still matches its slot's `slot_rev`
(`slot_rev_matches?`). So a transient `mark_needs_render` on a viewport_cache *child* is **silently dropped**:
the flag is swept Clean before the visit-all-visible pass runs, and the pass never looks at it anyway. The
cell keeps its stale slot pixels.

> **RULE:** an *appearance* change for anything inside a `viewport_cache` layer must move a **version**
> (`primitive_cache_rev`) — express it as a `reactive_property` read in `to_primitives`, or as
> `mark_needs_layout` for size. Never rely on `mark_needs_render` alone there.
>
> *Worked example:* a grid cell's selection highlight toggled via `mark_needs_render` repainted fine in a
> normal panel but never updated in the matrix viewport — the version-gated pull path ignored the dirty flag.
> Routing the highlight through a versioned (reactive) field fixed it.

### What invalidates what

| You changed… | Send… | Channel | Cost |
|--------------|-------|---------|------|
| paint content (color, text, …) | read a `reactive_property` getter in `to_primitives` | content_rev — **persistent** | O(1) re-render |
| theme / zoom | *(automatic)* `Theme.theme_rev` / `FontSizing.zoom_*` | theme_rev / zoom_rev — **persistent** | O(visible) |
| structural state not backed by a `Source` (focus highlight, drag/reflow) | `mark_needs_render` | `dirty_widgets` — **transient, non-`viewport_cache` only** | O(1) |
| size / structure | `mark_needs_layout` (or a `reactive_property … layout: true`) | layout_rev — **persistent** | O(n) layout |
| position only (drag) | set `layer.bounds` | composite | O(layers) |
| widget hidden / collapsed | `zero_bounds!` | releases the cache | O(subtree) |
| DSL rebuild (`app.rebuild`) | — | per-layer **content-staleness**: after layout repopulates `layer.widgets`, the renderer's `assess_rebuild_staleness` marks `mark_needs_clear_and_render` ONLY on a non-overlay / non-`viewport_cache` layer whose `{path_id, absolute_bounds, primitives}` signature changed vs. what it last full-rendered (carried on the reconciled `Layer`); an **unchanged** layer is left Clean → its carried buffer re-blits (0 re-render). Overlays (`skip_rebuild_clear`) refresh in `app.rebuild`; `viewport_cache` layers self-gate via `viewport_body_stale?`. | O(chrome widgets) assess per rebuild; **0** re-render for unchanged layers, O(n) full clear for changed |

### Footprint vacate: release the whole subtree

When a widget leaves the visible area (TreeNode collapse, hide), `zero_bounds!` zeroes its bounds **and
recurses into the whole subtree**, releasing every descendant's `widget_backend`/`background_backend`. This
is load-bearing for `viewport_cache` layers: their visit-all-visible pass discovers cells by their *bounds*
and never traverses *through* a zeroed parent to learn a descendant is gone. If `zero_bounds!` cleared only
the top node, a grandchild would keep stale bounds + a cached texture, and the pass would re-blit it next
frame as a ghost.

> *Worked example:* collapsing a TreeNode inside a ScrollView left its children for one frame, then a stale
> copy re-appeared — the collapse had released only the top node's pixels, not the subtree's.

### Note on off-buffer paints

An earlier hypothesis held that a widget partly outside its layer buffer could paint-skip and leave a stale
strip. It was tested and **refuted** — the renderer *clips*, it does not skip — so there is no off-buffer
special case to guard. The coherency hazards that remain are the two above: the wrong signal *channel*
(transient vs persistent) and an *incomplete footprint release*.

## `buffer_origin` Reader/Writer Invariant

`viewport_cache` layers carry a `buffer_origin : Vec2` that records which content coordinate sits at the
buffer's top-left corner. Render and composite both subtract this offset — if they ever observe different
values the entire viewport appears shifted. The invariant is enforced by a single-reader /
single-production-writer seam in `src/core/layer.cr`:

- **One reader**: `Layer#viewport_sample_origin` (`layer.cr:218`) — pure method that computes the
  integer sample position `(scroll - buffer_origin).to_i` for the live compositor and the cv instrument.
  Every composite pass calls this; no other site reads `buffer_origin` directly.
- **Private writer**: `Layer#write_buffer_origin` (`layer.cr:175`) — the only assignment to
  `@buffer_origin`. Under `-Dverify_bounds` it asserts the value is whole-valued (a fractional origin
  produces a 1px render/composite seam).
- **One production writer**: `Layer#recenter_origin!` (`layer.cr:270`) — the sole external entry point
  for recenter operations. All `viewport_cache` recenter and first-render sites funnel through this; it
  calls `write_buffer_origin` and asserts the resulting origin fits the buffer under `-Dverify_bounds`.
- **Pure computation**: `Layer#compute_buffer_origin` (`layer.cr:235`) computes a candidate whole+fitting
  origin given scroll and buffer dimensions but **never writes** `@buffer_origin`. The blit-shift path
  pre-computes the origin (to reuse it for overlap math) and then passes it into `recenter_origin!`.
- **Test seam**: `Layer#set_buffer_origin_for_test` (`layer.cr:186`) — the only non-production writer,
  used to position the buffer at an arbitrary offset in isolation without triggering a full recenter.
- **Deleted**: `quantized_buffer_origin` no longer exists; its quantization logic was absorbed into
  `compute_buffer_origin_axis`.

`Layer#assert_composite_fits!` (`layer.cr:195`) guards the invariant at composite time: both the SFML
renderer and the TestRenderer call it after computing the sample position, and it raises under
`-Dverify_bounds` if the sample differs from `(scroll - buffer_origin).to_i` — catching any divergence
between what the renderer wrote and what the compositor reads.

## Coordinate Systems

Two coordinate systems that must be kept distinct:

### Absolute Coordinates (widget.bounds)

```crystal
window = Window.new(800, 600)
  panel = WindowPanel.new(100, 100, 200, 150)  # x=100, y=100
    button = Button.new("Click")

# After layout:
window.bounds  = Rect(0, 0, 800, 600)
panel.bounds   = Rect(100, 100, 200, 150)     # Absolute position
button.bounds  = Rect(110, 130, 50, 24)       # Absolute position
```

**Used for:**
- Layout calculations (parent → child positioning)
- Hit testing (mouse clicks)
- Layer positioning (where to draw cached texture)

### Widget-Local Coordinates (primitives)

```crystal
# Button.get_primitives() returns primitives at (0,0) origin
button.get_primitives(button.bounds)
  → [
      FillRect(bounds: Rect(0, 0, 50, 24), color: bg_color),
      DrawText("Click", Vec2(5, 5), color: text_color)
    ]
```

**Why widget-local?**
- Primitives can be cached and reused when widget moves
- Just update layer.bounds, primitives don't change!
- This is how drag works without re-rendering

### Coordinate Translation (Rendering)

```crystal
# Layer renderer translates widget-local → layer-local
def execute_primitive_on_backend(
  primitive, backend,
  widget_x, widget_y,    # Widget absolute position
  layer_x, layer_y       # Layer absolute position
)
  case primitive
  when FillRect
    # Primitive coords are widget-local (0,0 origin)
    # Translate to layer-local coords
    bounds = Rect.new(
      primitive.bounds.x + widget_x - layer_x,  # To layer-local
      primitive.bounds.y + widget_y - layer_y,
      primitive.bounds.width,
      primitive.bounds.height
    )
    backend.fill_rect(bounds, primitive.color)
  end
end
```

**Example:**
```
Widget at absolute (110, 130)
Layer at absolute (100, 100)
Primitive at widget-local (0, 0)

Layer-local position = 0 + 110 - 100 = 10
                       0 + 130 - 100 = 30

So primitive renders at (10, 30) within layer texture
```

### Float-to-Integer Coordinate Rounding — the PixelSnap policy

Widget bounds use `Float64` for layout precision (sub-pixel positioning, DPI scaling, layout division).
GPU operations require `Int32` pixel coordinates. Every float→device-pixel conversion follows ONE
policy, keyed by the coordinate's ROLE — ad-hoc rounding is the defect class behind a long line of
shipped 1px/blur/ghost/seam bugs (scissor-vs-compositor edge seams, glyph-atlas blur, ghosted
sprites, cache-validator false seams, the cursor-cell text jitter from parity-dependent
ties-to-even rounding). The policy is ENFORCED by `spec/rendering/pixel_snap_lint_spec.cr`, which
fails on any raw conversion in render-path files outside its reviewed per-file baseline — covering
the rendering core (`src/rendering/`), the headless instruments, the matrix blit/park internals
(`src/widgets/virtual_matrix/`), and the layer sampling seam (`src/core/layer.cr`).

**Why floats for layout:**
- Smooth scrolling (scroll_offset accumulates sub-pixel deltas)
- Layout division: `300px / 7 children = 42.857...` per child
- Zoom/DPI scaling produces fractional sizes
- Drag offset for smooth panel movement

**The role table:**

| Coordinate role | Conversion | Owner | Why |
|-----------------|-----------|-------|-----|
| DRAW position: glyph-atlas text, texture-blit sprite/layer-composite destinations | `PixelSnap.snap` (half-up, `floor(v+0.5)`) | `src/rendering/pixel_snap.cr` | Whole pixels avoid GPU bilinear blur on the glyph atlas; half-up is TRANSLATION-INVARIANT (`snap(v+n) == snap(v)+n` for integer n), so widget-local (texture) and layer-local (direct) rasterization land on the same device pixel, and the headless and SFML compositors place layers identically. `Float#round`'s ties-to-even is parity-dependent at exact .5 fractions and violated this — text visibly jumped 1px whenever a cell flipped between render paths. |
| Value WHOLE BY CONSTRUCTION (viewport-cache `buffer_origin`) | `PixelSnap.whole` (asserting cast, exact tolerance) | `pixel_snap.cr` + the single writer (`recenter_origin!`) | Not a rounding: a fractional value is a broken invariant. The buffer-origin quantization itself is a separate, deliberately bespoke owner. |
| Widget/layer-local ORIGIN | `PixelSnap.origin` (floor) | `round_to_layer_pixels` → PixelSnap | Floor of the DIFFERENCE (never floor terms separately — `floor(a-b) != floor(a)-floor(b)`). Floor equals the old truncation for non-negative coords and, unlike it, stays translation-invariant at negative fractions (top/left-clipped content at fractional zoom). |
| Backend/texture EXTENT | `PixelSnap.span` (via `device_pixel_span`) | `pixel_snap.cr` | Defined AS `origin(start+len) - origin(start)`, so both edges share origin's floor direction BY CONSTRUCTION — exact sibling tiling, and a 1px widget at a negative fractional start keeps its pixel (truncate-both-edges dropped it). |
| Slot keys (viewport-cache stamp + blit-shift bookkeeping) | `slot_axis` | `layer_renderer.cr` | ONE arithmetic for both sides: `origin(abs - layer_bound) - buffer_origin`. The blit-shift previously re-derived keys with term-wise ties-even rounds, diverging from the stamp whenever widget coords were fractional → mis-classified boundary cells moved slot stamps onto stale pixels. |
| Culling/visibility BOUND | `PixelSnap.cover` (ceil) | culling sites | Conservative: may over-include, never under-include (`cover(len) >= span(start, len)` for every placement), so edge widgets are not prematurely culled. |
| Blit destinations — SPLIT BY TARGET | compositor layer→window: `snap` · cell-texture→layer: `origin` | per the target's frame | A cell blitted INTO a layer must land on the render path's slot origin (same `origin` arithmetic) or it jumps 1px between blit-frames and render-frames; the whole-layer composite to the window snaps (half-up) like every draw position. |
| Vector shapes: fills, lines, borders, circles | RAW (no snapping) | — | Sub-pixel BY DESIGN: the GPU rasterizes them by center coverage (the headless backend models the same rule). Snapping them would cause fill seams. Only glyph-atlas text and texture-blit destinations snap. |
| Sizes (font size, zoom-scaled metrics like grid spacing) | RAW | their single owner | One producer, all consumers see the same value — no cross-frame invariant at stake. Migrating them would CHANGE layout at tie values (e.g. a zoom-scaled spacing hitting exactly .5). |
| CONTENT-SPACE values (scroll grids, scroll-into-view targets, visible cell ranges) | RAW, or content-quantized via the `x.to_i.to_f64` round-trip | matrix scroll sites | Content pixels, not device pixels: the round-trip RETURNS to `Float64`, so it is never a device conversion (the lint recognizes the idiom and leaves it in scope-exempt content space). LAW: every consumer of the same content-space predicate must use the SAME quantized value — the sticky park predicates in `sticky_reposition` and `blit_plan` both compare against `scroll.to_i` per axis, so the reposition pass and the blit plan can never disagree about whether a header is parked. |

**FBO surface orientation (the Y-flip convention):** owned by `src/rendering/fbo_math.cr` —
its header carries the full convention table (RenderTexture.texture is bottom-up; the window and
copy_to_image are top-down; full-sprite blits need NO flip) and the pure flip algebra
(`blit_region_flip`, `scissor_gl_y`), property-spec'd in `spec/rendering/fbo_math_spec.cr`. Those
specs prove self-consistency with the convention; the real FBO orientation axiom is witnessed only
by the SFML parity sweep (`tools/sfml-parity.sh`).

**Historical seam note:**
Scissor clipping once truncated (giving 298 for bounds 298.666) while the compositor ceiled (giving 299):
pixel 298 was never rendered but was sampled — white/garbage pixels at the right edge. The lesson
generalizes: two code paths converting the SAME coordinate MUST share one conversion — which is what
PixelSnap and the lint tripwire enforce structurally.

**Cache-validation instrument (`render_layer_immediate`):**
The `render_layer_immediate` method (the ground-truth pass used by the cache-validation harness,
`-Dcache_validation`) also sizes widget backends via `device_pixel_span`, matching production
`render_single_widget` exactly (`layer_renderer.cr:840-841`). Using `.ceil.to_i` in the instrument while
production uses `device_pixel_span` caused false ~1px "stale cache" seam failures at every
fractional-width widget edge — the instrument painted one extra column the cache had never written.
Aligning the instrument to `device_pixel_span` was the fix; production code was unchanged. This
alignment is a correctness invariant of the validator: the ground-truth path and the production path
must agree on widget extent, or the seam the instrument reports is its own error, not a cache bug.

## Layer Background Color

Critical optimization for drag performance:

### The Problem

Panel has a background color and 400 child buttons. Two approaches:

**Approach A (BAD):** Render background as FillRect primitive
```crystal
class WindowPanel
  def get_primitives(bounds)
    primitives do
      fill_rect(bounds, background_color)  # Panel background
      # ... panel chrome primitives ...
    end
  end
end

# Problem during selective rendering:
# - Button changes, marks panel layer dirty
# - Selective render: only re-render changed button
# - Button renders on top of OLD background FillRect
# - Background FillRect overwrites button!
# - Content appears blank/corrupt during drag
```

**Approach B (GOOD):** Background is layer property
```crystal
class Layer
  property background_color : Color
end

def render_layer(layer)
  if full_render
    backend.clear(layer.background_color)  # Clear once
  end
  # Selective render: don't clear, just render dirty widgets
end

# During selective rendering:
# - Layer buffer already has correct background (from previous full render)
# - Dirty widget renders on top of cached content
# - Background doesn't overwrite anything
```

### Implementation

```crystal
class WindowPanel < Widget
  def initialize(title, x, y, width, height)
    # ...
    @internal_layer = Layer.new(
      "panel_#{id}",
      bounds,
      z_index: 100,
      background_color: @background_color  # ← Set layer background
    )
  end

  def get_primitives(bounds)
    primitives do
      # DON'T render background here!
      # fill_rect(bounds, @background_color)  ← NO!

      # Only render panel chrome (border, title bar, etc.)
      draw_rect(bounds, border_color)
      fill_rect(title_bar_bounds, title_bg_color)
      draw_text(@title, title_pos, title_color)
    end
  end
end
```

## Per-Widget Texture Architecture

Beyond layer-level caching, each widget can own small GPU textures for ultra-fine-grained selective rendering. This enables O(1) updates when a single button changes in a panel with 400 buttons.

### Two-Level Caching Strategy

```
┌─────────────────────────────────────────────┐
│  Layer Cache (Coarse-Grained)               │
│  - One RenderTexture per layer              │
│  - Size: full layer bounds (e.g., 300×400)  │
│  - Purpose: O(1) panel drag/position        │
│  - Composite to window                      │
│                                              │
│  ┌──────────────────────────────────────┐  │
│  │  Widget Cache (Fine-Grained)         │  │
│  │  - Two RenderTextures per widget:    │  │
│  │    • widget_backend (render target)  │  │
│  │    • background_backend (memorized)  │  │
│  │  - Size: widget bounds (e.g., 100×30)│  │
│  │  - Purpose: O(1) selective rendering │  │
│  │  - Blit to layer backend             │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

**How they work together:**
- **Layer cache**: Panel drag updates `layer.bounds`, compositor blits cached layer → O(1)
- **Widget cache**: Button hover renders only that button to layer → O(1)

### What is Per-Widget Texture?

Each widget (button, text, panel chrome, etc.) can own two small GPU textures:

```crystal
class Widget
  # Widget's rendering target (widget-local coordinates)
  property widget_backend : RenderBackend?

  # Memorized background (captured BEFORE widget first renders)
  property background_backend : RenderBackend?
end
```

**Example sizes** (for 400-button panel):
```
Button: 100×30 pixels × 4 bytes (RGBA) = 12KB
  × 2 textures = 24KB per button
  × 400 buttons = 9.6MB total

Panel chrome: 300×400 pixels × 2 textures = ~1MB
Total: ~10-15MB GPU memory (acceptable on modern GPUs)
```

### Background Memorization - The Key Insight

**Critical timing**: Background must be captured BEFORE widget renders, AFTER parent renders.

#### Wrong Timing (Causes Double-Rendering Bug)
```crystal
# DON'T: Capture after widget renders
parent.render()  # Panel renders background
child.render()   # Button renders
child.capture_background()  # ✗ Captures button's own content!
# Result: Next render shows old button + new button = BOLD TEXT
```

#### Correct Timing
```crystal
# DO: Capture before widget renders
parent.render()              # Panel renders background to layer
child.capture_background()   # ✓ Captures parent's background only
child.render()               # Button renders on top
# Result: background_backend contains only parent, no double-rendering
```

### The Rendering Flow

#### Full Render (First Time or After Layout)
```crystal
def render_layer(layer : Layer)
  # Clear layer to background_color
  backend.clear(layer.background_color)

  # Collect widgets in parent-first order (CRITICAL!)
  widgets = collect_widgets_parent_first(layer.widgets)

  widgets.each do |widget|
    render_single_widget(widget, backend, layer)
  end
end

def render_single_widget(widget, layer_backend, layer)
  # Ensure widget has rendering target
  widget.widget_backend ||= create_widget_backend(width, height)

  # CAPTURE BACKGROUND (before widget renders!)
  if widget.background_backend.nil?
    widget.background_backend = create_widget_backend(width, height)
    # Capture parent's content from layer (parent already rendered)
    widget.background_backend.blit_region(
      layer_backend,                    # Source: layer texture
      widget.layer_local_x,             # Position within layer
      widget.layer_local_y,
      widget.width,
      widget.height,
      0, 0                              # Destination: (0,0) in background
    )
  end

  # RESTORE BACKGROUND (to widget's render target)
  widget.widget_backend.blit(widget.background_backend, 0, 0)

  # RENDER WIDGET (primitives on top of restored background)
  primitives = widget.get_primitives(widget.bounds)
  primitives.each do |prim|
    execute_primitive_on_widget_backend(prim, widget.widget_backend)
  end

  widget.widget_backend.display

  # BLIT TO LAYER (composite widget + background to layer)
  layer_backend.blit(widget.widget_backend, widget.layer_local_x, widget.layer_local_y)
end
```

**Why this works:**
1. Parent renders its background to layer first (parent-first order)
2. Child captures that background (parent's content, not child's)
3. Child restores background, renders on top, blits to layer
4. Layer now contains: parent background + child content (no double-rendering!)

#### Selective Render (Only Dirty Widgets)
```crystal
def render_layer(layer : Layer)
  # Only render dirty widgets (O(dirty), not O(n)!)
  layer.dirty_widgets.each do |widget|
    render_single_widget(widget, backend, layer)  # Same as above
  end
end
```

**Performance:**
- Button hover: only that button re-renders (O(1))
- 1 widget out of 400 → 0.2ms instead of 154ms

### Parent Invalidation Cascade

**The Challenge**: When parent changes appearance, children's memorized backgrounds become stale.

**Example Scenario**:
```
Panel background color changes: gray → blue
├─ Panel marked dirty, re-renders blue background to layer ✓
└─ Button (not dirty) restores OLD gray background ✗
Result: Button shows gray background, rest of panel shows blue
```

**Solution: Chrome/content split makes cascade unnecessary**

```crystal
class Widget
  def mark_needs_render
    # Don't downgrade from NeedsLayout to NeedsRender
    @state = WidgetState::NeedsRender if @state == WidgetState::Clean

    # Chrome/content split eliminates need for invalidate_children_backgrounds!
    # Chrome and content have non-overlapping bounds, so chrome re-render
    # cannot overwrite content. Content uses selective rendering (dirty widgets only).
    # This achieves O(1) performance instead of O(children) cascade.

    # Propagate to containing layer (replaces parent propagation for rendering)
    propagate_to_layer
  end
end
```

**Performance implications:**
```
Common case (90-95%): Leaf widget changes (button hover, text update)
  → Only that widget marked dirty
  → O(1) selective rendering ✓

Uncommon case (5-10%): Parent changes (panel background color)
  → Parent marked dirty; chrome/content split means children are NOT
     invalidated (their non-overlapping bounds are unaffected)
  → O(1) — no cascade needed ✓

Rare case (<1%): Layout changes (panel resize)
  → Full re-layout + re-render
  → O(n) - expected and acceptable ✓
```

**Key insight**: The chrome/content split architecture means `mark_needs_render` never needs to cascade to children. Each widget's `background_backend` captures only the layer region behind it (not the widget itself), and because siblings/chrome cannot overlap content, a parent re-render does not corrupt children's cached backgrounds. This keeps all selective-render paths at O(1).

### Rendering Invariants (Enforced with Assertions)

These invariants catch bugs and ensure correctness:

#### Invariant (f): Rendering Precondition
**Rule**: Widget can only render to `widget_backend` if:
- First time (backend newly created), OR
- Background was restored (backend cleared to memorized state)

**Enforcement**:
```crystal
def render_single_widget(widget, ...)
  # Assert: backend is either new or background was restored
  # Uses always-on assert() macro (see src/core/assert.cr)
  assert(background_restored, "(f - rendering precondition): Widget ... rendering without cleared buffer")

  # ... render widget ...
end
```

**Catches**: Rendering to stale/dirty buffer (causes double-rendering)

#### Invariant (g): Memorization Precondition (Graceful Handling)
**Rule**: Can only copy memorization (restore background) if:
- Background was rendered before (layer has parent's content), AND
- Background was memorized before (background_backend exists), AND
- Background size matches widget size

**Handling** (graceful, not assertion):
```crystal
def render_single_widget(widget, ...)
  if background_backend = widget.background_backend
    if background_backend.width == widget_width &&
       background_backend.height == widget_height
      # Size matches - restore background
      widget_backend.blit(background_backend, 0, 0)
    else
      # Size mismatch! Fill with layer background instead
      # (handles reconcile edge cases, text width changes, etc.)
      widget_backend.clear(layer.background_color)
      widget.background_backend = create_new_at_correct_size()
    end
  else
    # First render: capture background (parent must have rendered first!)
    # ...
  end
end
```

**Note**: Size mismatch is handled gracefully (not asserted) because it can occur
legitimately during reconciliation, text content changes, and other edge cases.
The graceful handling prevents transparent pixel artifacts.

**Catches**: Size mismatches → fills with background color instead of crashing

#### Invariant (h): Background Capture Purity
**Rule**: Widget can only capture background if it has NEVER rendered to layer at current bounds.

**Why critical**:
- If widget already rendered to layer at this position, the layer contains its own old content
- Capturing this as "background" would memorize own content → garbage accumulation
- Must only capture from layer when widget hasn't rendered there yet

**Enforcement** (always on, not just DEBUG):
```crystal
assert(!widget.rendered_to_layer_at_current_bounds?,
  "(h - background capture purity): Widget cannot capture background - " +
  "already rendered to layer at current position!")
```

**Catches**: Capturing widget's own old content as "background" (causes double-rendering artifacts)

#### Invariant (siblings): No Overlap Constraint
**Rule**: Sibling widgets cannot have overlapping bounds.

**Why critical**:
- If siblings overlap, they can overwrite each other's content
- Background memorization becomes ambiguous (which sibling's content?)
- Rendering order between siblings would matter (breaks declarative model)

**Future relaxation**: Will allow explicit z-index for overlapping siblings, but requires careful ordering logic.

**Enforcement**:
```crystal
# During rendering, validate sibling bounds (uses always-on assert):
def validate_sibling_bounds(widgets)
  widgets_by_parent.each do |parent, siblings|
    if parent.is_a?(VStack) || parent.is_a?(HStack)
      # O(n): Ordered containers - only adjacent siblings can overlap
      siblings.each_cons(2) { |(a, b)| check_overlap(a, b) }
    else
      # O(n²): General case - check all pairs
      siblings.each_combination(2) { |pair| check_overlap(pair[0], pair[1]) }
    end
  end
end
```

**Performance optimization**: in a release build the raising validation runs only on `first_render?`, not during scroll frames (scroll doesn't change widget structure, so re-validating would be wasted O(n²) work). An overlap introduced by a LATER layout change used to escape entirely — that is how a stale-skip overlap reached a beta tester — so under `-Dverify_bounds` every re-**LAYOUT** re-checks it as a **warn + `Widget.sibling_overlap_warnings`** rather than a raise (self-tested by `spec/rendering/sibling_overlap_guard_spec.cr`, run by `tools/cv-coherency.sh`). Deliberately keyed on `NeedsLayout`, not on the `full_render` flag: `mark_needs_clear_and_render` sets `NeedsRender`, and several call sites choose it *because* it does not imply sibling validation.

**Known limit**: this checks siblings against each other, never a child against its parent. Stacks size themselves from `measure` but advance their cursor by each child's post-layout `bounds`, so a child whose laid-out extent exceeds its measured one escapes the PARENT instead of overlapping a sibling. That case is covered by the containment warning in `Widget#layout`'s own `-Dverify_bounds` block.

**Catches**: Layout bugs where children overlap, background corruption

### Parent-First Render Ordering

**Critical requirement**: During full render, widgets MUST be processed in parent-before-children order.

**Why**: Children capture backgrounds from layer. If child processes before parent, it captures empty/wrong background!

```crystal
# Collect widgets in depth-first order (parent before children)
private def collect_widgets_parent_first(root_widgets : Array(Widget)) : Array(Widget)
  result = [] of Widget
  root_widgets.each do |widget|
    collect_widget_tree_depth_first(widget, result)
  end
  result
end

private def collect_widget_tree_depth_first(widget : Widget, result : Array(Widget))
  result << widget              # Parent first
  widget.children.each do |child|
    collect_widget_tree_depth_first(child, result)  # Then children
  end
end
```

**Example order for panel with buttons**:
```
1. Panel (renders background to layer)
2. Button 1 (captures panel background, renders on top)
3. Button 2 (captures panel background, renders on top)
...
400. Button 400
```

**NOT**:
```
✗ Button 1 (captures empty background - WRONG!)
✗ Button 2 (captures empty background - WRONG!)
✗ Panel (renders background - too late!)
```

### Performance Characteristics

**Memory** (for 400-button panel):
```
Layer cache:     300×400×4 = ~480KB (1 texture)
Widget caches:   100×30×4×2×400 = ~9.6MB (800 textures)
Total:           ~10MB GPU memory
```

**Render performance**:
```
Full render:              O(n) widgets (first time or layout change)
  - Panel + 400 buttons:  ~154ms (acceptable, rare)

Selective render (leaf):  O(1) - only dirty widget
  - Button hover:         ~0.2ms (smooth 60fps)

Selective render (parent): O(children) - parent + descendants
  - Panel color change:   ~154ms (acceptable, rare)

Panel drag:              O(1) - only compositor
  - Update layer.bounds:  <0.1ms (smooth 60fps)
```

**Composite performance**:
```
Compositor: O(layers)
  - 2-5 layers:  ~0.1ms (always fast)
```

### When Per-Widget Textures Are Used

**Always**: Current implementation uses per-widget textures for ALL widgets within a layer.

**Benefits**:
- True O(1) selective rendering for leaf changes
- Handles transparent overlays correctly (background memorization)
- No parent→child overwrites during selective render

**Trade-offs**:
- Higher memory (2 textures per widget)
- Parent invalidation cascade (O(children), but rare and correct)
- More complex implementation (invariants needed)

**Alternative** (not currently implemented):
- Layer-level only: widgets render directly to layer
- Lower memory, simpler
- But: parent primitives can overwrite children during selective render
- Solution: layer.background_color for solid backgrounds only (no gradients/patterns)

### Summary: Per-Widget Texture Architecture

**Key points:**
1. **Two-level caching**: Layer cache (coarse) + widget cache (fine)
2. **Background memorization**: Captured BEFORE widget renders, AFTER parent renders
3. **Parent-first ordering**: Critical for correct background capture
4. **Parent invalidation**: O(children) cascade when parent changes (correct, rare)
5. **Invariants enforce correctness**: (f) rendering, (g) memorization, (h) capture purity, (siblings) no-overlap
6. **Performance**: Optimized for common case (leaf changes = O(1)), accepts rare case (parent changes = O(children))

## The Drag Performance Bug (Case Study)

### What We Discovered (Nov 2025)

**Symptom**: Panel drag with 400 buttons caused multi-second freezes

**Root Cause**: `layout_children()` called on EVERY mouse move

```crystal
# BEFORE (BROKEN):
def on_mouse_move(point : Vec2)
  if @interaction_mode == InteractionMode::Dragging
    # Update position
    @x = new_x
    @y = new_y
    @bounds = Rect.new(@x, @y, @width, @height)

    # Update layer bounds
    if layer = @internal_layer
      layer.bounds = Rect.new(@x, @y, @width, @height)
    end

    layout_children  # ← THE BUG! Re-layouts 400 buttons = 76ms
  end
end
```

**Why it was called**: Comment said "Re-layout children to update absolute positions for hit testing"

**Why comment was WRONG**:
- Don't need hit testing during drag (mouse is held down)
- Children absolute positions updated once in on_mouse_up
- Primitives are widget-local, don't need absolute positions

**Profiling Evidence**:
```
Slow Frame:
  layout: 76.84ms        ← layout_children(400 buttons)
  render_layers: 154ms   ← Triggered by layout
  render_frame: 233ms    ← Multi-second freeze during fast drag!
```

**The Fix**:
```crystal
# AFTER (FIXED):
def on_mouse_move(point : Vec2)
  if @interaction_mode == InteractionMode::Dragging
    @x = new_x
    @y = new_y
    @bounds = Rect.new(@x, @y, @width, @height)

    # Update layer bounds to match new panel position
    if layer = @internal_layer
      layer.bounds = Rect.new(@x, @y, @width, @height)
    end

    # NOTE: No layout_children needed during drag!
    # Children absolute positions will be updated in on_mouse_up
    # During drag, hit testing is not needed (mouse is held down)
  end
end

def on_mouse_up(point : Vec2)
  if @interaction_mode == InteractionMode::Dragging
    layout_children  # Update children bounds ONCE after drag
    mark_needs_layout  # Trigger full layout if needed
  end
end
```

**Result**:
- Before: 78 frames in 3s, frequent 200+ms freezes
- After: 417 frames in 3s (4x improvement!), 0 primitives during drag
- Drag now truly O(1) - just updates layer.bounds, no layout/render

### The Critical Invariant

**RULE**: Position-only changes DON'T need layout

```crystal
# Position change (drag):
panel.x = new_x
panel.y = new_y
panel.bounds = Rect.new(new_x, new_y, @width, @height)
layer.bounds = panel.bounds  # ← Only this!
# NO mark_needs_layout!
# NO layout_children!

# Size change (resize):
panel.width = new_width
panel.height = new_height
panel.bounds = Rect.new(@x, @y, new_width, new_height)
mark_needs_layout  # ← Full layout needed!
```

**Why?**
- Layout calculates positions relative to parent
- When parent moves, relative positions don't change
- Only absolute positions change, but those aren't used during rendering
- Primitives are widget-local (0,0 origin), so they don't change
- Compositor uses layer.bounds to position cached texture

## Instrumentation Gaps (Lessons Learned)

### What We Had

```crystal
class TestRenderer
  getter primitive_count : Int32         # ✅ Counts rendering
  getter compositor_call_count : Int32   # ✅ Counts composites
  getter backend_clear_count : Int32     # ✅ Counts buffer clears
  getter render_layer_count : Int32      # ✅ Counts layer render calls
  getter backend_blit_count : Int32      # ✅ Counts widget-backend blits to layer
  def layout_count : Int32               # ✅ Delegates to Widget.layout_count
end
```

### Viewport-Cache Recenter Counters

Three module-level class properties on `LayerRenderer` (reset by `LayerRenderer.reset_frame_counters`,
`layer_renderer.cr:41-43`) track how each `viewport_cache` recenter was resolved. Use these in
perf-budget specs to measure the delta across a scroll session, not an absolute duration:

| Counter | What it counts |
|---------|----------------|
| `LayerRenderer.frame_full_recenter_count` | Recenters with no usable overlap — buffer cleared and fully re-rendered |
| `LayerRenderer.frame_blit_shift_count` | Recenters via blit-shift — existing buffer content shifted, only newly exposed edges re-rendered |
| `LayerRenderer.frame_realloc_count` | Backend buffer reallocations (a grow event; the "allocation storm" these counters guard against) |

A healthy scroll session shows `frame_blit_shift_count >> frame_full_recenter_count` and
`frame_realloc_count == 0`, confirming the sliding-window cache is working correctly.

### What We Didn't Have (Gap Now Resolved)

At the time of the drag bug discovery, layout was not instrumented:

**Why it mattered then**:
- Tests showed `primitive_count = 0` (perfect caching!) ✅
- Tests showed `compositor_call_count = 10` (one per frame) ✅
- Tests DIDN'T show `layout_count = 10` (layout on every frame!) ❌

**Lesson**: Instrument what's expensive (layout!), not just what's visible (primitives)

**Current state**: `layout_count` is implemented. `TestRenderer#layout_count` (`test_renderer.cr:39`)
delegates to `Widget.layout_count` (a class-variable counter incremented inside `Widget#layout`).
`render_layer_count` (`test_renderer.cr:25`) and `backend_blit_count` (`test_renderer.cr:28`) are also
present. Do not re-add hand-rolled versions of these counters.

### Using the Instrumentation in Tests

```crystal
it "drag doesn't trigger layout" do
  renderer.reset_counters

  drag_panel(100px)

  renderer.layout_count.should eq 0
  renderer.primitive_count.should eq 0
  renderer.compositor_call_count.should eq 10  # One per frame
end
```

## Widget-with-Chrome Pattern

**Use Case**: Widgets that need to render decorations (chrome) around their content, with their own layer for clipping, z-index control, or caching.

**Examples**: MenuBar (background/border), WindowPanel (title bar/border via separate widgets), ScrollView (scrollbar around viewport), Popup (border/shadow)

### Two Implementation Patterns

#### Pattern A: Self-Registration (MenuBar, ScrollView)

**When to use**: Widget has simple chrome (background, border, scrollbar) that's part of the widget itself.

**Implementation**:
```crystal
class MenuBar < Widget  # or ScrollView
  include PrimitiveBuilder

  @internal_layer : Layer?

  def layer : Layer?
    @internal_layer
  end

  def perform_layout(constraints : BoxConstraints, position : Vec2)
    # ... layout logic ...

    if layer = @internal_layer
      layer.bounds = absolute_bounds

      # Register SELF to layer.widgets (for chrome rendering)
      layer.widgets.clear
      layer.widgets << self  # This widget renders chrome (background, scrollbar, etc.)

      # Children are rendered RECURSIVELY when self is rendered
      # DO NOT add children to layer.widgets (causes double-rendering)
    end

    # Layout children at appropriate positions
    children.each { |child| child.layout(...) }
  end

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      # Render chrome: background, border, scrollbar, etc.
      fill_rect(background_rect, background_color)
      fill_rect(scrollbar_rect, scrollbar_color)
    end
  end
end
```

**How it works**:
1. Widget registers itself to `layer.widgets`
2. Widget's `to_primitives` renders chrome (background, scrollbar, etc.)
3. Widget's children are rendered **recursively** by the rendering system
4. Children render at positions set by `child.layout()` calls

**Critical**: Don't add children to `layer.widgets` - they're already rendered when the parent is rendered. Adding them causes double-rendering (visible as bold text).

#### Pattern B: Separate Chrome Widget (WindowPanel)

**When to use**: Chrome is complex enough to warrant its own widget class, or chrome and content need different update frequencies.

**Implementation**:
```crystal
class WindowPanel < Widget
  class Chrome < Widget
    def to_primitives(bounds)
      # Render title bar, close button, etc.
    end
  end

  class Content < Widget
    def to_primitives(bounds)
      [] of DrawPrimitive  # Pure container
    end
  end

  @internal_layer : Layer?
  @chrome : Chrome
  @content : Content

  def layer : Layer?
    @internal_layer
  end

  def perform_layout(constraints, position)
    # ... layout logic ...

    if layer = @internal_layer
      layer.bounds = absolute_bounds

      # Register Chrome and Content widgets (NOT panel itself)
      layer.widgets.clear
      layer.widgets << @chrome    # Chrome first (renders first)
      layer.widgets << @content   # Content second
    end

    # Layout chrome and content
    @chrome.layout(...)
    @content.layout(...)
  end

  def to_primitives(bounds)
    [] of DrawPrimitive  # Panel itself renders nothing
  end
end
```

**When to choose Pattern B**:
- Chrome is complex (title bar with buttons, menus, drag handles)
- Chrome and content update independently (title bar static, content changes)
- Need separate cache invalidation for chrome vs content

### Common Mistakes

❌ **Don't add children to layer.widgets when using Pattern A**:
```crystal
# WRONG - causes double-rendering
layer.widgets << self
children.each { |child| layer.widgets << child }  # ← Don't do this!
```

✅ **Children are rendered recursively**:
```crystal
# CORRECT - children rendered automatically
layer.widgets << self
# Children are rendered when self is rendered
```

❌ **Don't forget to register self when widget has chrome**:
```crystal
# WRONG - chrome won't render
layer.widgets.clear
layer.widgets << content  # Only content, scrollbar won't show!
```

✅ **Register self for chrome rendering**:
```crystal
# CORRECT - both chrome and content render
layer.widgets.clear
layer.widgets << self     # Renders scrollbar via to_primitives
# Content renders recursively as child
```

## Best Practices

### When to Call What

```crystal
# Content changed (button text, color, etc.)
# DON'T call mark_needs_render — declare a reactive_property and READ ITS GETTER in to_primitives.
reactive_property color : Color = Color::White
def to_primitives(bounds)
  primitives { fill_rect(bounds, color) }   # reading `color` auto-captures it as a dependency
end
# Setting `self.color = ...` bumps the version → node stale → widget re-renders.
  → Triggers: Render (selective) + Composite
  → Cost: O(1) - one widget
  → Example: Button hover

# Structural state changed (visible/enabled/focus highlight, drag/reflow)
widget.mark_needs_render
  → For state that ISN'T paint content backed by a Source. The escape hatch, not the default.
  → Triggers: Render (selective) + Composite
  → Cost: O(1) - one widget

# Size changed (widget resized)
widget.mark_needs_layout         # or a reactive_property declared `layout: true`
  → Triggers: Layout (full) + Render (full) + Composite
  → Cost: O(n) - entire tree
  → Example: Panel resize

# Position changed (widget moved)
widget.bounds = new_bounds
layer.bounds = new_bounds  # If widget has layer
# NO mark_needs_layout!
# NO mark_needs_render!
  → Triggers: Composite only
  → Cost: O(layers) - very few
  → Example: Panel drag
```

**Author contract**: the default for content is *not* a method call — declare a `reactive_property` and read
its getter in `to_primitives`; the change invalidates automatically (see `REACTIVITY.md`). Reserve
`mark_needs_render` for structural state that isn't expressed as a `Source`.

### Testing Performance

```crystal
it "operation has O(1) performance" do
  renderer.settle_rendering  # Render until stable
  renderer.reset_counters    # Zero everything

  # Test operation
  perform_operation()

  # Assert on absolute counter values
  renderer.layout_count.should eq 0        # No layouts
  renderer.primitive_count.should eq 0     # No re-renders (cached)
  renderer.compositor_call_count.should eq 1  # Just compositor
end
```

### Common Mistakes

❌ **DON'T: Call layout during drag**
```crystal
def on_mouse_move(point)
  # Update position
  layout_children  # ← EXPENSIVE! O(n)
end
```

✅ **DO: Only update layer bounds**
```crystal
def on_mouse_move(point)
  # Update position
  layer.bounds = new_bounds  # ← CHEAP! O(1)
end
```

❌ **DON'T: Mark layout for position change**
```crystal
@x = new_x
mark_needs_layout  # ← Unnecessary full layout!
```

✅ **DO: Only update bounds**
```crystal
@x = new_x
@bounds = Rect.new(@x, @y, @width, @height)
layer.bounds = @bounds
```

❌ **DON'T: Render background as primitive in selective rendering**
```crystal
def get_primitives(bounds)
  primitives do
    fill_rect(bounds, background_color)  # ← Overwrites children!
    # children rendered after this
  end
end
```

✅ **DO: Use layer background_color**
```crystal
def initialize
  @layer = Layer.new(id, bounds, background_color: @bg_color)
end

def get_primitives(bounds)
  primitives do
    # NO background fill here!
    # Just panel chrome (border, title, etc.)
  end
end
```

## Architecture Diagrams

### Rendering Pipeline Flow

```
User drags panel
        │
        ▼
WindowPanel.on_mouse_move(point)
        │
        ├─► Update @x, @y, @bounds
        ├─► Update layer.bounds
        └─► NO layout_children!  ← Critical optimization

Next frame (60 FPS)
        │
        ▼
SFMLRenderer.render_frame(app)
        │
        ├─► Layout phase
        │   ├─► app.prepare_layout(window_size)
        │   └─► if root.needs_layout? → layout()
        │       └─► NO! Position change doesn't need layout
        │
        ├─► Render phase
        │   ├─► render_all_layers(root)
        │   ├─► For each layer:
        │   │   └─► if layer.needs_render? → render_layer()
        │   └─► NO! Position change doesn't need render
        │
        └─► Composite phase
            ├─► clear_window_background()
            └─► For each layer (sorted by z_index):
                └─► composite_layer_to_window(layer)
                    └─► Draw cached texture at NEW position ← Only this!
```

### State Machine

```
Widget State Machine:
┌──────────┐  content_change   ┌─────────────┐
│  Clean   │──────────────────►│ NeedsRender │
└──────────┘                    └──────┬──────┘
     ▲                                 │
     │                                 │ render()
     │                                 │
     │                          ┌──────▼──────┐
     │          layout()        │   Clean     │
     └──────────────────────────┤             │
                                └─────────────┘
     ┌──────────┐  size_change
     │  Clean   │──────────────────┐
     └──────────┘                  │
                                   ▼
                            ┌──────────────┐
                            │ NeedsLayout  │
                            └──────┬───────┘
                                   │ layout() + render()
                                   ▼
                            ┌─────────────┐
                            │   Clean     │
                            └─────────────┘
```

## Summary

**Key Architectural Points:**

1. **Two Trees**: Widget tree (UI structure) and Layer tree (render caching)
2. **Three Phases**: Layout (O(n)) → Render (O(dirty)) → Composite (O(layers))
3. **Critical Invariant**: Position changes don't need layout - only compositor update
4. **Selective Rendering**: Only re-render dirty widgets, not entire tree
5. **Widget-Local Coords**: Primitives at (0,0) origin enable caching across moves
6. **Layer Background**: Background is layer property, not primitive (prevents overwrites)
7. **Incremental Layout**: Template method pattern skips layout for clean widgets with unchanged constraints

**Performance Model:**
- Layout: O(path) for dirty widget, O(n) only for window resize
- Render: O(dirty) - selective rendering
- Composite: O(layers) - always runs, very fast

**Layout Optimization (Template Method):**
- `layout()` is template method in Widget base class
- Subclasses implement `perform_layout()` instead
- Skip check: `!needs_layout? && constraints == @last_constraints`
- When skipping: just update `@bounds.position`, no recursion
- Layer-owning widgets (Popup, MenuBar) override `can_skip_layout?` to never skip

**Instrumentation:**
- MUST track layout calls (would have caught the bug!)
- MUST track primitive counts
- MUST track compositor calls

**Critical for Understanding:**
- Position change ≠ layout needed
- Layer caching = O(1) drag performance
- Background color architecture prevents selective render bugs
- Constraint caching = O(path) layout for single dirty widget

## Proxy Focus

Proxy focus is the mechanism by which a container widget (currently VirtualMatrix) delegates keyboard events and focus visuals to a child widget without transferring real FocusManager focus. The container retains focus ownership for grid-level navigation while child widgets (TextInput, Button, etc.) behave as if focused.

### Pattern

```
VirtualMatrix (real focus, owns grid nav)
  └── @proxy_focused_widget → TextInput cell
        @proxy_focused = true
        effectively_focused? = true → renders cursor, handles text
```

VirtualMatrix manages `@proxy_focused_widget`. When the cursor moves to a new cell, it calls `deactivate_proxy_focus` on the old cell and `activate_proxy_focus` on the new one (if the cell is `focusable?`).

### Widget Contract

| Method | Purpose |
|--------|---------|
| `focusable?` | Container checks this to decide if a cell can receive proxy focus |
| `activate_proxy_focus` | Called on cell when it gains proxy focus (setup: start cursor blink, etc.) |
| `deactivate_proxy_focus` | Called on cell when it loses proxy focus (teardown) |
| `effectively_focused?` | Returns true if real-focused OR proxy-focused — use for render decisions |
| `wants_arrow_keys?` | If true, container forwards arrow keys to cell instead of grid-navigating |
| `is_focus_scope?` | Container returns true so FocusCycler won't Tab into individual cells |

### Event Forwarding

VirtualMatrix's `on_key_down` dispatches events in two phases:

1. **Proxy forwarding** (if `@proxy_focused_widget` exists):
   - Arrow keys → forwarded only if `wants_arrow_keys?` (TextInput FullEdit mode)
   - Tab → not forwarded; falls through to grid navigation below
   - Everything else (Enter, Escape, Backspace, Delete, etc.) → forwarded to cell

2. **Grid navigation** (runs if proxy didn't consume the event):
   - Arrow keys → `move_cursor` + `snap_to_cursor`
   - Tab/Shift+Tab → `move_cursor(:tab)` round-robin + `snap_to_cursor`; the
     matrix consumes Tab and stays focused (spreadsheet semantics). Tab dispatch
     is owned by `FocusManager#handle_tab_key`: the focused widget gets first
     dibs, and only widgets that decline cause focus to cycle.

Text input (`on_text_input`) is always forwarded to the proxy widget if one exists.

### Example: TextInput in VirtualMatrix

TextInput overrides the proxy focus methods:
- `activate_proxy_focus`: sets `@proxy_focused = true`, starts cursor blink timer
- `deactivate_proxy_focus`: sets `@proxy_focused = false`, stops cursor blink
- `wants_arrow_keys?`: returns true in FullEdit mode (after Enter), false in QuickEntry mode

In QuickEntry mode (default), arrow keys move the VirtualMatrix cursor between cells. In FullEdit mode (after pressing Enter), arrows move the text cursor within the TextInput.

## Window.overlays System

Overlays are widgets (typically `Popup` instances) managed by `Window` separately from
the DSL child tree. They are used for popup menus, tooltips, and modals that must
persist across DSL rebuilds.

### Why a Separate List?

DSL-style apps recreate the entire widget tree on every `build()` call. A popup opened
in response to a click would be destroyed on the next rebuild. Overlays solve this:
they live outside the DSL tree, so reconciliation cannot touch them.

### API

```crystal
# Add a popup or modal that persists across rebuilds
window.add_overlay(popup)   # Sets popup.parent = window, calls mark_needs_layout

# Remove it when dismissed
window.remove_overlay(popup)  # Clears popup.parent, calls mark_needs_layout
```

Both methods are defined in `src/widgets/window.cr`.

### Auto-Migration During Reconciliation

`Window.copy_state_from` migrates overlays from the old Window instance to the new one:

```crystal
def copy_state_from(old : Widget)
  super
  return unless old.is_a?(Window)
  old_window = old.as(Window)
  return if old_window.same?(self)

  old_window.overlays.each do |overlay|
    overlay.parent = self
    @overlays << overlay
  end
  old_window.overlays.clear
end
```

This ensures that an open popup is not lost when the DSL app rebuilds.

### Hit Testing and Click-Outside Behavior

`Window.hit_test` checks overlays first (before DSL children), sorted by `z_index`
descending, so the topmost overlay always receives clicks first.

`Window.notify_overlays_of_click(point)` is called by `App` on every `mouse_down`
event. Any `Popup` overlay whose bounds do not contain the click receives
`on_click_outside`, which is the standard mechanism for closing popups on
outside-click.

### Layout

Overlays are laid out by `Window.perform_layout` after all DSL children. They
position themselves (their `bounds.position` is used as the layout origin), so the
caller is responsible for placing the overlay at the correct screen position before
adding it.

