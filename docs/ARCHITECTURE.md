# CrymbleUI Architecture

## The Core Problem

**Current state**: Business logic, state management, and rendering are entangled. This causes:
- Behavior bugs that can't be unit tested (must run visual app to verify)
- Cache invalidation bugs (ghost dropdowns, stale rendering)
- No clear contracts for when things need re-rendering
- Render-related issues that take days to debug

**Key insight**: If we can't unit test behavior, the architecture is wrong.

## Architectural Principles

### 1. Complete Separation of Concerns

```
┌─────────────────────────────────────────────────┐
│  UI BUILDING DSL (Structure)                    │
│  - Declarative widget tree construction         │
│  - Knows NOTHING about rendering                │
│  - Pure parent-child relationships              │
│                                                  │
│  window("App") do                               │
│    vstack { button("Click") { ... } }           │
│  end                                             │
└─────────────────┬───────────────────────────────┘
                  │ Builds Widget Tree
┌─────────────────▼───────────────────────────────┐
│  STATE LAYER (Pure Logic)                       │
│  - Business logic & behavior                    │
│  - 100% unit testable                           │
│  - No rendering knowledge                       │
│  - Emits state changes                          │
└─────────────────┬───────────────────────────────┘
                  │ State Changes
┌─────────────────▼───────────────────────────────┐
│  WIDGET LAYER (Coordination)                    │
│  - Owns state objects                           │
│  - Handles events → state changes               │
│  - Produces DrawPrimitives (via DSL)            │
│  - Manages cache policies                       │
└─────────────────┬───────────────────────────────┘
                  │ Array(DrawPrimitive)
┌─────────────────▼───────────────────────────────┐
│  PRIMITIVE DSL (Rendering Description)          │
│  - Describes "what to draw"                     │
│  - Backend-agnostic data structures             │
│  - Knows NOTHING about SFML/OpenGL              │
│                                                  │
│  primitives do                                   │
│    fill_rect(bounds, color)                     │
│    draw_text("Hello", pos, color)               │
│  end                                             │
└─────────────────┬───────────────────────────────┘
                  │ DrawPrimitive Structs
┌─────────────────▼───────────────────────────────┐
│  RENDERER (Backend Execution)                   │
│  - Executes primitives on backend               │
│  - Knows NOTHING about widgets/DSL              │
│  - Swappable: SFML/OpenGL/Canvas/Terminal       │
│  - Respects cache policies                      │
└─────────────────────────────────────────────────┘
```

### 2. Reactive Change Tracking

A widget's visual output is a memoized **pull node**: reactive fields (declared with `reactive_property`) are `Source` cells, and *reading one in `to_primitives` auto-captures it as a dependency*. Changing the value moves its version, the node goes stale, and the widget re-renders — no setter has to remember to call `mark_needs_render`. Layout is an imperative pass (not a pull node), so layout-affecting changes still poke `mark_needs_layout` explicitly. Parent changes cascade to children; the renderer skips widgets whose primitives are still fresh.

See `docs/REACTIVITY.md` for the full model (auto-capture, version counting, the pull render trigger).

### 3. The Rebuild Cycle (DSL Apps)

In DSL-style apps, `build()` creates the **entire widget tree from scratch** on every call. The framework reconciles old and new trees, preserving widget state via `copy_state_from`.

**`request_rebuild`** tells the framework: "my app state changed — call `build()` again on the next frame."

**When to call `request_rebuild`:**
- App state changed that affects which widgets exist or their structure
  (opening/closing dialogs, adding/removing shapes, changing data that adds/removes rows)
- Example: `@dialogs << dialog; request_rebuild`

**When NOT to call `request_rebuild`:**
- Widget-internal state changes (typing, scrolling, cursor movement, hover)
  — these use `mark_needs_render` or `mark_needs_layout` internally
- Data changes that only affect cell VALUES, not tree structure
  — use `invalidate_all!` on the adapter instead

**Key rule:** If `build()` would produce a **different widget tree** (different widgets, different structure), call `request_rebuild`. If the same widgets just need to repaint with new data, use `mark_needs_render` or `invalidate_all!`.

**Avoid `mark_needs_layout` from app code** — in DSL apps, `mark_needs_layout` propagating to root triggers a full rebuild. Use `mark_needs_render` for visual-only changes, or `request_rebuild` for structural changes.

### 3. Testability First

All business logic must be testable without rendering:

```crystal
# GOOD: Test observable widget state directly
it "button callback fires on click" do
  fired = false
  button = Button.new("OK") { fired = true }
  button.on_click
  fired.should be_true
end

# BAD: Requires visual inspection
it "menu stays open when clicking checkable item" do
  # Can't test without running app and looking at screen
end
```

## The Caching Challenge

Performance requires aggressive caching, but caching is the source of bugs. How do we cache safely?

### Cache Architecture

```
┌────────────────────────────────────────────────┐
│  CACHE LAYER SYSTEM                            │
├────────────────────────────────────────────────┤
│  Static Cache (rarely changes)                 │
│  - Window chrome, static panels                │
│  - Invalidate on: layout changes only          │
├────────────────────────────────────────────────┤
│  Dynamic Cache (changes on interaction)        │
│  - Panel content, buttons, text                │
│  - Invalidate on: state changes                │
├────────────────────────────────────────────────┤
│  Never Cache (always render fresh)             │
│  - Menus, popups, tooltips                     │
│  - Animations, live updates                    │
└────────────────────────────────────────────────┘
```

### Explicit Cache Contracts

Widgets declare their caching behavior:

```crystal
abstract class Widget
  # Override to declare caching behavior
  def cache_policy : CachePolicy
    CachePolicy::Dynamic  # Default: cache but invalidate on state change
  end
end

enum CachePolicy
  Static   # Cache aggressively, rarely invalidate
  Dynamic  # Cache but invalidate on state changes
  Never    # Always render fresh
end
```

In practice, `Dynamic` is the default for all widgets. `Static` is currently unused by any widget. `Never` is declared by the two widgets that must regenerate every frame: `CursorOverlayWidget` (the cursor highlight band in `VirtualMatrix`) and `SimpleGhostWidget` (the drag-ghost preview). All other widgets inherit `Dynamic`.

### Cache Invalidation Rules

Invalidation is **pull-based and mostly automatic**. A widget's primitives live in a memoized cache node; the reactive values it reads while painting (`reactive_property` fields, theme, zoom) are auto-captured as dependencies. When one of those values changes its version moves, the node is stale, and the widget re-renders on the next frame — nothing pushes `mark_needs_render`.

The remaining explicit signals are for things that aren't expressed as captured reactive reads:

- **`mark_needs_layout`** — a layout-affecting change (size/padding). Layout is an imperative pass, not a pull node, so it must be poked. Propagates to parent and children.
- **`mark_needs_render`** — kept only for structural widget *state* (`visible`/`enabled`/`focus_highlighted`) and a few method-level marks (drag/reflow), which are gates rather than paint content.

See `docs/REACTIVITY.md` for how auto-capture and version counting answer "is this stale?" cheaply.

## DrawPrimitive: Backend-Agnostic Rendering

### Primitives are Pure Data Structures

**Critical**: DrawPrimitives are data, not code. They describe "what to draw", not "how to draw it".

```crystal
# Pure data - no rendering logic, no backend dependencies
abstract struct DrawPrimitive
end

struct FillRect < DrawPrimitive
  property bounds : Rect
  property color : Color
end

struct DrawText < DrawPrimitive
  property text : String
  property position : Vec2
  property color : Color
  property size : Float64
end

struct DrawLine < DrawPrimitive
  property from : Vec2
  property to : Vec2
  property color : Color
  property width : Float64
end

struct DrawCircle < DrawPrimitive
  property center : Vec2
  property radius : Float64
  property color : Color
  property fill : Bool
end

struct FillTriangle < DrawPrimitive
  property p1 : Vec2
  property p2 : Vec2
  property p3 : Vec2
  property color : Color
end

struct DrawRect < DrawPrimitive  # rectangle outline
  property bounds : Rect
  property color : Color
  property width : Float64
end

# Clipping — see "Clipping" subsection below
struct PushClip < DrawPrimitive
  property rect : Rect
end

struct PopClip < DrawPrimitive
end

struct DrawImage < DrawPrimitive
  getter source : ImageSource
  property bounds : Rect
  property color : Color  # tint/alpha; Color.white = no tint
end
```

### Benefits of Primitive-Based Rendering

1. **Backend Independence**: Primitives know nothing about SFML, OpenGL, or any renderer
2. **Testability**: Assert on primitive list without any rendering
3. **Serializability**: Save/load/replay rendering commands
4. **Debuggability**: Inspect exactly what was drawn
5. **Swappable Backends**: Same primitives → different renderers

```crystal
# Test rendering without any backend
it "checked menu item produces checkmark primitive" do
  item = MenuItem.new("Dark Mode", checked: true)
  primitives = item.to_primitives(bounds)

  checkmark = primitives.find { |p| p.is_a?(DrawText) && p.text == "✓" }
  checkmark.should_not be_nil
end
```

### Primitive DSL (No Boilerplate)

Widgets use a DSL to build primitives declaratively:

```crystal
module PrimitiveBuilder
  @primitives : Array(DrawPrimitive)?

  # DSL entry point
  def primitives(&block) : Array(DrawPrimitive)
    @primitives = [] of DrawPrimitive
    yield
    @primitives.not_nil!
  end

  # DSL methods - append to @primitives
  def fill_rect(bounds : Rect, color : Color) ...
  # fill_background: like fill_rect but uses ceil(width/height) to cover the
  # pixel-snapped widget backend when the widget sits on a fractional position
  # (avoids a 1px transparent strip at the right/bottom edge on some window widths).
  def fill_background(bounds : Rect, color : Color) ...
  def draw_text(text : String, pos : Vec2, color : Color, font_scale : Int32 = 0)
    size = FontSizing.calculate_size(font_scale)
    if font = Widget.font
      left_offset, top_offset = font.get_text_offsets(text, size)
      adjusted_pos = Vec2.new(pos.x - left_offset, pos.y - top_offset)
      @primitives.not_nil! << DrawText.new(text, adjusted_pos, color, size)
    else
      @primitives.not_nil! << DrawText.new(text, pos, color, size)  # fallback: no font loaded
    end
  end
  # vcentered_text_y: returns the local Y that vertically centres one text line
  # in a band by the real ink height (reference_height), not the em size.
  def vcentered_text_y(band_height : Float64, font_scale : Int32 = 0, band_top : Float64 = 0.0) : Float64 ...
  def draw_line(from : Vec2, to : Vec2, color : Color, width : Float64 = 1.0) ...
  def draw_circle(center : Vec2, radius : Float64, color : Color, fill : Bool = true) ...
  def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color) ...
  def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0) ...  # outline
  # Clipping — push/pop a scissor rect; consumed by the renderer (see "Clipping" below)
  def push_clip(rect : Rect) ...
  def pop_clip ...
  # draw_check_glyph: shared checkbox/checkmark glyph (outline box + state mark).
  def draw_check_glyph(state : CheckState, rect : Rect, box_color : Color, check_color : Color, ...) ...
end
```

**Usage**:
```crystal
class MenuItem < Widget
  include PrimitiveBuilder

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      # Declarative, no array boilerplate!
      fill_rect(bounds, @hover_color) if @hovered
      draw_text("✓", checkmark_pos, text_color) if @checked
      draw_text(@label, label_pos, text_color)
      draw_text(@shortcut, shortcut_pos, @shortcut_color) if @shortcut
    end
  end
end
```

## Widget Property Macros

Widget fields are declared with macros that wire up reactivity and reconciliation. The reactive model behind them — auto-capture, version counting, the pull render trigger — is documented in `docs/REACTIVITY.md`; this section only catalogs the macros and when to reach for each. (The old `render_property` / `layout_property` macros, which pushed `mark_needs_render`/`mark_needs_layout` from the setter, have been **removed**; see `docs/MIGRATION.md` for the before/after.)

### The three macros

The `Widget` base class (`src/core/widget.cr`) provides:

| macro | what it gives you | use it for |
|---|---|---|
| **`reactive_property name : T`** | a `Source(T)` field + a getter that **auto-captures** when read in `to_primitives`, and a setter that notifies dependents | any reactive value — **the default** |
| **`reconcile_property name : T`** | a *plain* ivar (no `Source`) carried across a DSL rebuild via `@[Reconcile]` | a managed `Layer`/`Widget` ref — infrastructure, never painted |
| **`theme_property name, key`** | a getter that resolves the global `Theme` color live (an explicit override wins) | a color that should follow the theme |

```crystal
class Button < Widget
  include PrimitiveBuilder

  reactive_property text_color : Color           # read in to_primitives → change re-renders
  reactive_property background_color : Color
  reactive_property padding : Float64, layout: true  # also re-layouts on change
end
```

**Two flags refine `reactive_property`:**

- **`layout: true`** — the setter *also* calls `mark_needs_layout`. Use when the field changes the widget's size/position. Layout is an imperative pass (not a pull node), so a layout-affecting change must poke it explicitly; auto-capture alone won't.
- **`reconcile: true`** — the value survives a DSL rebuild (`@[Reconcile]` plus a plain build-shadow that the reconciler compares by `==`). Use for state that must persist across rebuilds (e.g. `scroll_offset`, a selected color).

**Rule of thumb: Source-back what renders.** Read the field's *getter* (`text_color`, never the `@text_color` ivar — that's the raw `Source` object) inside `to_primitives`, and a change re-renders automatically. A field never read while painting doesn't earn a `Source`: a managed object uses `reconcile_property`, and a handful of structural state fields (`visible`/`enabled`/`focus_highlighted`) keep an explicit `mark_needs_render` because they're gates, not paint content.

See `docs/REACTIVITY.md` for *why* this works (reading a value is what declares the dependency, so an edge can never be forgotten) and for the one case where you reach for a bare `Source(T)` (a global signal with no widget to hang a property on).

### Layout Template Method Pattern

The Widget base class uses a template method pattern for incremental layout optimization:

```crystal
# Base class handles skip check
def layout(constraints : BoxConstraints, position : Vec2)
  if can_skip_layout?(constraints)
    @bounds = Rect.new(position, @bounds.size)  # Just update position
    return
  end
  @state = WidgetState::Clean
  perform_layout(constraints, position)  # Delegate to subclass
  @last_constraints = constraints
end

# Subclasses implement this instead of layout()
abstract def perform_layout(constraints : BoxConstraints, position : Vec2)
```

**Benefits:**
- Clean widgets with unchanged constraints skip layout entirely
- Only the dirty path from leaf to root re-layouts (O(path) instead of O(n))
- Position-only changes still work (just update bounds, no recursion)

See `LAYER_RENDERING_ARCHITECTURE.md` for full details on incremental layout.

See `GRACEFUL_DEGRADATION.md` for render-time exception handling and recovery.

### When NOT to Use Property Macros

`reactive_property` is the default. Reach for a hand-written setter only when a write needs *extra* logic — clamping, re-deriving a sibling field, restarting a timer. Even then, prefer to keep the value in a `Source` (declared via `reactive_property`) so the dependency is still auto-captured; do the extra work in an overriding setter that delegates to it. A plain ivar with a manual `mark_needs_render` is reserved for the few structural-state fields that are gates rather than paint content.

## Layered Widget Composition

Widgets form layers, from primitive to complex. All share the same interface: `to_primitives()`.

### Layer 1: Primitive Widgets

Directly produce DrawPrimitives:

```crystal
class Text < Widget
  include PrimitiveBuilder

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      draw_text(@text, bounds.position, @color, @font_scale)
    end
  end
end

```

### Layer 2: Composite Widgets

Aggregate primitives from children OR produce directly:

```crystal
class Button < Widget
  include PrimitiveBuilder

  # Option A: Produce primitives directly
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      fill_rect(bounds, @bg_color)
      draw_text(@label, center_pos(bounds), @text_color)
    end
  end

  # Option B: Use child widgets (if built with DSL)
  # def to_primitives(bounds : Rect) : Array(DrawPrimitive)
  #   children.flat_map { |child| child.to_primitives(child.bounds) }
  # end
end
```

### Layer 3: Container Widgets

Lay out children; the renderer visits each child's layer independently — the parent does **not** aggregate child primitives into its own return. `VStack` and `HStack` emit only an optional background fill (or an empty array):

```crystal
class VStack < Widget
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    if color = background_color
      primitives { fill_background(bounds, color) }
    else
      [] of DrawPrimitive
    end
  end
end
# HStack is identical in structure
```

### Layer 4: Pure Containers

Some complex widgets delegate all painting to specialised child widgets on their own layers and return nothing themselves:

```crystal
class WindowPanel < Widget
  # Chrome and Content are separate child widgets on separate layers;
  # WindowPanel itself has nothing to paint.
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    [] of DrawPrimitive
  end
end
```

**Key**: Every widget has a `to_primitives()` method; containers that delegate entirely to children simply return an empty array.

## Cache Implementation Strategy

### Two-Level Caching: Primitives + Textures

**Important**: Cache primitives (lightweight), then optionally cache rendered textures (expensive).

#### Primitive Cache (Level 1) - ESSENTIAL

**Purpose**: Architectural separation + minor performance benefit
- Enables unit testing (assert on primitives without rendering)
- Backend independence (primitives work with any renderer)
- Cheap to store (~200 bytes per widget)
- Avoids re-running `to_primitives()` logic

**Always used**: Yes, for Dynamic and Static policies

#### Texture Cache (Level 2) - OPTIMIZATION

**Purpose**: Performance optimization for expensive rendering
- Stores rendered pixels in GPU memory (2MB per 800x600 texture)
- Only beneficial for complex static content (1000s of primitives)
- NOT helpful if content changes frequently (animations, live updates)

**Selectively used**: Only for Static policy widgets (window chrome, large static panels)

### Base Widget Class Manages ALL Caching

**Critical Design**: Widget subclasses NEVER touch cache code. Base class handles everything.
`cache_policy` selects how the primitives are cached:

- **`Never`** — always regenerate (menus, popups, animations). No node.
- **`Dynamic`** (the default) — primitives live in a **memoized pull node** (`Cached(Array(DrawPrimitive))`, `src/core/cached.cr`) whose recompute is `to_primitives`. The node auto-captures the reactive values it reads while painting and is validated by **version**, not by a dirty flag: a clean node returns its memoized result with no `to_primitives` call; a change to a captured `Source` (or a `touch` from `mark_needs_layout`/content) moves the version, and the next read re-derives. Correct by construction — a value the widget reads can't be forgotten.
- **`Static`** — cache the primitives once, forever (window chrome).

```crystal
# Widget base class (widget.cr) — sketch; see src/core/widget.cr for the real thing
abstract class Widget
  @primitives_node : Cached(Array(DrawPrimitive))?   # Dynamic policy
  @cached_primitives : Array(DrawPrimitive)?         # Static policy

  def get_primitives(bounds : Rect) : Array(DrawPrimitive)
    case cache_policy
    when CachePolicy::Never   then to_primitives(bounds)
    when CachePolicy::Dynamic then (@primitives_node ||= make_node).get  # version-keyed, auto-capturing
    when CachePolicy::Static  then @cached_primitives ||= to_primitives(bounds)
    end
  end

  def cache_policy : CachePolicy
    CachePolicy::Dynamic
  end

  # Subclasses override this to describe what to draw.
  # The base class provides a concrete default (empty array) so pure-container
  # widgets like WindowPanel need not override it.
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    [] of DrawPrimitive
  end
end
```

`needs_render?` for a node-backed widget is derived from the node (`!node.valid?`), not a flag — see `docs/REACTIVITY.md` for the version-counting that makes this cheap.

### Subclasses: Just Describe, Don't Cache

**Widget authors focus only on "what to draw", never "when to cache"**

```crystal
class MenuItem < Widget
  include PrimitiveBuilder

  # 1. Declare cache policy (optional - defaults to Dynamic)
  def cache_policy : CachePolicy
    CachePolicy::Dynamic
  end

  # 2. Describe what to draw - NO cache management!
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      fill_rect(bounds, @hover_color) if @hovered
      draw_text("✓", pos, color) if @checked
      draw_text(@label, pos, color)
    end
  end

  # That's it! No @cached_primitives, no cache logic
  # Base class handles all caching automatically
end
```

**Benefits**:
1. Widget authors never write cache code
2. Consistent caching behavior across all widgets
3. Cache strategy can be changed globally
4. Simple, declarative approach

### Layer-Based Render Caching

Texture-level caching is handled by the layer architecture, not a per-widget `RenderCache` object. Each `Layer` owns a `RenderBackend` (an off-screen texture); the `LayerRenderer` composites all layers onto the window each frame. Per-widget render backends (`widget_backend`) are allocated by the renderer and hold the last-painted pixels for that widget — they are blitted from the blit-plan without re-running `to_primitives` when the widget's primitive cache is still fresh. The `buffer_origin` mechanism within viewport-cache layers handles large virtual grids by keeping only a window of rows/columns in GPU memory and shifting the origin on scroll.

See `docs/LAYER_RENDERING_ARCHITECTURE.md` for the full layer tree, blit-plan, and buffer-origin model.

### Cache Benefits with Primitives

1. **Lightweight**: Primitives are small structs, cheap to cache
2. **Testable**: Assert on cached primitives without rendering
3. **Clear invalidation**: Primitive-cache staleness (version key) vs layer re-composite

## The Resulting Architecture

The primitive-based pipeline is fully in place. The durable shape it settled into:

- **DrawPrimitive infrastructure**: a `DrawPrimitive` base with concrete structs (`FillRect`, `DrawText`, …) and the `PrimitiveBuilder` DSL mixin. Every widget implements `to_primitives(bounds)`; the old `render(context)`/`PaintContext` path is gone.
- **Backend-only renderer**: `SFMLRenderer` executes primitives and knows nothing about widgets.
- **Cache policies**: a `CachePolicy` enum (`Never`/`Dynamic`/`Static`) on `Widget`, with `Dynamic` the default. `Never` is declared by the two widgets that must regenerate every frame: `CursorOverlayWidget` (cursor highlight bands in `VirtualMatrix`) and `SimpleGhostWidget` (drag-ghost preview). `Static` is currently unused by any widget. All other widgets inherit `Dynamic`. There is no ad-hoc per-widget cache-skipping (`is_a?(Popup)` checks) — policy plus the version-keyed node decide everything.

**Optional optimizations not all enabled by default**: texture caching for expensive widgets, dirty-rectangle tracking, batched primitive rendering, GPU acceleration via alternate backends.

## Testing Strategy

### Unit Tests (Primitive Layer)

Test primitive generation without any rendering:

```crystal
describe MenuItem do
  describe "#to_primitives" do
    it "produces checkmark when checked" do
      item = MenuItem.new("Dark Mode", checked: true)
      bounds = Rect.new(0.0, 0.0, 200.0, 24.0)

      primitives = item.to_primitives(bounds)

      # Assert on primitives - no rendering needed!
      checkmark = primitives.find { |p|
        p.is_a?(DrawText) && p.text == "✓"
      }
      checkmark.should_not be_nil
    end

    it "produces correct number of primitives when hovered" do
      item = MenuItem.new("Copy", "Ctrl+C")
      item.on_mouse_enter  # Set hovered state
      bounds = Rect.new(0.0, 0.0, 200.0, 24.0)

      primitives = item.to_primitives(bounds)

      # Should have: hover background + label + shortcut
      primitives.size.should eq(3)
      primitives[0].should be_a(FillRect)  # Hover background
      primitives[1].should be_a(DrawText)  # Label
      primitives[2].should be_a(DrawText)  # Shortcut
    end

    it "uses correct colors for text" do
      item = MenuItem.new("Test")
      bounds = Rect.new(0.0, 0.0, 200.0, 24.0)

      primitives = item.to_primitives(bounds)

      text_primitive = primitives.find { |p| p.is_a?(DrawText) }.as(DrawText)
      text_primitive.color.should eq(Color.new(0, 0, 0, 255))
    end
  end
end
```

### Integration Tests (Widget Layer)

```crystal
describe MenuItem do
  it "fires callback on click" do
    clicked = false
    item = MenuItem.new("Test") { clicked = true }

    item.on_click

    clicked.should be_true
  end
end
```

### Pixel Tests (Rendering Verification)

Verify that primitives actually render to pixels correctly using `TestRenderBackend`:

**What is Pixel Testing?**
- Validates that rendering logic produces actual pixel output (not blank/white)
- Catches bugs where primitives are generated but coordinates are wrong
- Tests the full rendering pipeline without SFML window
- Lightweight: No GPU, no display, pure CPU-based rendering

**TestRenderBackend Usage**:
```crystal
require "../../src/testing/test_render_backend"

# Create backend with size and optional background color
backend = CrymbleUI::Testing::TestRenderBackend.new(
  200,  # width
  200,  # height
  CrymbleUI::Color.new(255, 255, 255, 255)  # Optional: white background
)

# Render primitives
primitives.each do |primitive|
  backend.execute_primitive(primitive)
end

# Check pixels: verify non-white pixels exist (content rendered)
white = CrymbleUI::Color.new(255, 255, 255, 255)
non_white_count = 0

20.times do |y|
  20.times do |x|
    pixel = backend.get_pixel(x, y)
    non_white_count += 1 if pixel && pixel != white
  end
end

# Assert that content was actually rendered
non_white_count.should be > 0
```

**Common Patterns**:

1. **Testing button rendering** (spec/rendering/actual_rendering_output_spec.cr):
   ```crystal
   it "renders button to layer texture (not blank)" do
     # Setup widget tree
     window = CrymbleUI::Window.new("Test", 800, 600)
     panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
     button = CrymbleUI::Button.new("Click") { }

     panel.add_child(button)
     window.add_child(panel)

     # Layout
     constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
     window.layout(constraints, CrymbleUI::Vec2.zero)

     # Create test backend matching layer size
     layer = panel.layer.not_nil!
     backend = CrymbleUI::Testing::TestRenderBackend.new(
       layer.bounds.width.to_i,
       layer.bounds.height.to_i,
       CrymbleUI::Color.new(255, 255, 255, 255)
     )

     # Render widgets to backend (with layer coordinate translation)
     layer_offset_x = layer.bounds.x
     layer_offset_y = layer.bounds.y

     layer.widgets.each do |widget|
       widget_abs = widget.absolute_bounds
       primitives = widget.get_primitives(widget.bounds)

       primitives.each do |primitive|
         # Translate from absolute coords to layer-local coords
         case primitive
         when CrymbleUI::FillRect
           local_bounds = CrymbleUI::Rect.new(
             widget_abs.x - layer_offset_x,
             widget_abs.y - layer_offset_y,
             primitive.bounds.width,
             primitive.bounds.height
           )
           backend.fill_rect(local_bounds, primitive.color)
         # ... handle other primitive types
         end
       end
     end

     # Verify pixels: button should render (not blank)
     white = CrymbleUI::Color.new(255, 255, 255, 255)
     non_white_pixels = 0

     20.times do |y|
       20.times do |x|
         pixel = backend.get_pixel(x, y)
         non_white_pixels += 1 if pixel && pixel != white
       end
     end

     non_white_pixels.should be > 0
   end
   ```

2. **Testing coordinate translation** (layer-local vs absolute):
   ```crystal
   it "translates widget absolute coords to layer-relative coords" do
     # Setup and layout
     window = CrymbleUI::Window.new("Test", 800, 600)
     panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
     button = CrymbleUI::Button.new("Button") { }

     panel.add_child(button)
     window.add_child(panel)

     constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
     window.layout(constraints, CrymbleUI::Vec2.zero)

     layer = panel.layer.not_nil!

     # With parent-relative bounds:
     # - button.bounds is relative to panel (e.g., x=0, y=30)
     # - button.absolute_bounds is in window coords (e.g., x=100, y=130)
     # - layer.bounds is absolute (panel position, e.g., x=98, y=98)

     # Calculate layer-local coordinates for rendering
     button_abs = button.absolute_bounds
     layer_offset_x = layer.bounds.x
     layer_offset_y = layer.bounds.y

     button_local_x = button_abs.x - layer_offset_x
     button_local_y = button_abs.y - layer_offset_y

     # Verify coordinates are within layer bounds
     button_local_x.should be >= 0
     button_local_y.should be >= 0
     button_local_x.should be < layer.bounds.width
     button_local_y.should be < layer.bounds.height
   end
   ```

**When to Use Pixel Testing**:
- ✅ Verifying layer rendering produces non-blank output
- ✅ Testing coordinate translation (absolute → layer-local)
- ✅ Catching rendering bugs where primitives exist but pixels don't
- ✅ Validating selective rendering updates only dirty areas
- ❌ Not needed for primitive-level tests (use `to_primitives()` assertions)
- ❌ Not needed for behavior tests (use state-level tests)

**Key Benefits**:
1. **Catches coordinate bugs**: Primitives might be generated with wrong offsets
2. **No visual inspection**: Automated verification of actual pixel output
3. **Fast**: CPU-based, no GPU/window initialization
4. **Deterministic**: Same primitives → same pixels every time

### Visual Tests (Rendering Layer)

Only final SFML rendering needs visual verification. Pixel tests cover rendering logic.

## Benefits

### Primary Goals Achieved

1. **100% Testable Logic**
   - State behavior: Unit test without rendering
   - Primitive generation: Assert on output without backend
   - No more "run app and look" debugging

2. **Clear Separation of Concerns**
   - UI DSL: Structure (widget tree)
   - State: Logic (behavior)
   - Primitives: Description (what to draw)
   - Renderer: Execution (backend-specific)

3. **No More Cache Bugs**
   - Explicit cache policies (Never/Dynamic/Static)
   - Clear invalidation rules
   - No ad-hoc "skip this widget" checks

4. **Backend Independence**
   - Swap SFML → OpenGL → Canvas by changing renderer
   - Same primitives work everywhere
   - Test rendering without graphics hardware

5. **Performance Without Complexity**
   - Two-level caching: primitives + textures
   - Lightweight primitive structs
   - Aggressive caching where safe

6. **Debuggability**
   - Inspect primitive list to see what was drawn
   - Serialize primitives for replay/debugging
   - State changes are explicit events

7. **Maintainability**
   - Logic is separated, easy to understand
   - Each layer has single responsibility
   - Can reason about each layer independently

## Text Measurement and Rendering

### The SFML Text Padding Problem

SFML text has built-in padding/offsets that must be handled consistently between measurement and rendering:

**SFML Text Bounds**:
- `local_bounds`: Full bounding box including padding (left/top can be negative)
  - `left`: Offset from position to first pixel (often negative, e.g., -2)
  - `top`: Offset from position to first pixel (often negative, e.g., -3)
  - `width`: Full extent including padding
  - `height`: Full extent including padding
- `global_bounds`: Visual text only, excludes some padding
  - `width`: Visual width only
  - `height`: Visual height only

### Architectural Decision: Measure and Render with Padding (Option A)

**Rule**: Measurement and rendering must use the SAME bounds. We chose to include SFML padding in BOTH.

**Implementation**:

1. **Measurement** (`Widget.measure_text` in widget.cr, delegates to `SFMLFont#measure_text`):
   ```crystal
   def self.measure_text(text : String, size : Float64) : Size
     return Size.new(0.0, 0.0) unless font = @@font
     key = {text, size}
     return cached if cached = @@measure_text_cache[key]?  # per-{text,size} memoization
     result = font.measure_text(text, size)
     # SFMLFont: width = local_bounds.width, height = font.get_line_spacing (consistent across glyphs)
     @@measure_text_cache[key] = result
     result
   end
   ```
   The cache is a class-level `Hash(Tuple(String,Float64), Size)` initialised at startup and flushed whenever the font changes.

2. **Rendering** (`draw_text` in primitive_builder.cr):
   ```crystal
   # Takes font_scale : Int32 (passed to FontSizing.calculate_size for zoom-aware sizing)
   def draw_text(text : String, position : Vec2, color : Color, font_scale : Int32 = 0)
     size = FontSizing.calculate_size(font_scale)
     if font = Widget.font
       # Left offset: text's own local_bounds.left.
       # Top offset: reference_top(size) — cached per font size using the glyph "Ag",
       #   so all same-size text shares the same baseline regardless of content.
       left_offset, top_offset = font.get_text_offsets(text, size)
       adjusted_position = Vec2.new(position.x - left_offset, position.y - top_offset)
       @primitives.not_nil! << DrawText.new(text, adjusted_position, color, size)
     else
       @primitives.not_nil! << DrawText.new(text, position, color, size)  # no font loaded
     end
   end
   ```

3. **Clipping** (explicit `PushClip`/`PopClip` primitives in the draw list):

   Clipping is not applied automatically by the renderer — widgets that need to clip their content emit `PushClip`/`PopClip` structs via the `push_clip(rect)` / `pop_clip` DSL helpers in `PrimitiveBuilder`:

   ```crystal
   # In a widget's to_primitives:
   push_clip(clip_rect)
   # ... primitives that must be clipped ...
   pop_clip
   ```

   The renderer executes `PushClip`/`PopClip` in the primitive stream as a scissor stack. The `rendering_leaf?` method exists on `Widget` but is not part of the clipping pipeline.

**How it works**:
- `measure_text` returns visual size: width from `local_bounds.width`, height from `font.get_line_spacing` (consistent across glyphs); results are memoized
- Widget.bounds is sized using measured size plus padding
- `draw_text` calls `font.get_text_offsets`: left comes from the text's `local_bounds.left`; top comes from a per-size reference glyph ("Ag") so all text at the same size shares the same baseline
- Visual glyphs render exactly at the requested position

**Why Option A**:
- Simple: One measurement function, one rendering function
- Consistent: Bounds match actual rendering extent
- Explicit: Clipping is declared by the widget, not inferred by the renderer

**Alternative Options Rejected**:
- **Option B** (Measure excluding padding, render excluding padding): Would show SFML baseline artifacts
- **Option C** (Separate rendering bounds): More complex, requires tracking two sets of bounds

### Text Rendering Best Practices

**Use `draw_text()` for all text rendering**:
- Automatically compensates for SFML baseline offsets (local_bounds.left/top)
- Ensures equal visual padding on all sides
- Text renders exactly at the requested position
- Based on SFML Game Development Book's centerOrigin() approach

**Use `measure_text()` for layout**:
- Returns visual text size (width, height) without offsets
- Matches `draw_text()` rendering extent exactly
- Widgets add padding on all sides equally

**How it works together**:
```crystal
# Measure text using a pixel size (returns width, height)
text_size = measure_text("Hello", FontSizing.calculate_size(@font_scale))  # => Size(50, 15)

# Size widget: add equal padding
widget_size = Size(text_size.width + 20, text_size.height + 20)  # Equal 10px padding

# Position text: simple padding offset
text_pos = Vec2(widget.x + 10, widget.y + 10)  # 10px from edges

# Render: draw_text takes font_scale (Int32) and compensates for SFML offsets automatically
draw_text("Hello", text_pos, color, @font_scale)  # Glyphs appear exactly at text_pos
```

**Result**: Equal visual padding on all sides, regardless of font size or glyphs (including descenders like 'y', 'g', 'q')

### SFML Text: Integer Coordinates Required

**CRITICAL**: All SFML text positions MUST be snapped to integer pixels before rendering —
via `PixelSnap.snap` (`src/rendering/pixel_snap.cr`), never `Float#round`.

Fractional (sub-pixel) coordinates cause GPU bilinear interpolation on the font glyph atlas,
producing visually washed-out/blurry text. This is most visible after zoom (e.g. 110%) where
centering arithmetic produces non-integer positions like (143.7, 28.3).

The snap must also be **translation-invariant** (`snap(v + n) == snap(v) + n` for integer n):
the same text primitive is rasterized either widget-LOCAL (into the widget's own texture,
blitted at an integer offset) or layer-LOCAL (offset added before rasterizing), and both must
land on the same device pixel. `Float#round`'s ties-to-even breaks this for exact .5 fractions
(the result depends on the integer part's parity) — a vertically-centered text y like 3.5 then
renders 1px lower via the texture path than via the direct path, and anything that flips a
cell's render path (a click, a cursor move, an invalidate) makes its text visibly jump 1px.
`PixelSnap.snap` is half-up (`floor(v + 0.5)`), which commutes with all integer offsets;
guarded by `spec/rendering/pixel_snap_spec.cr`.

This applies to ALL `SF::Text` position assignments across the codebase:
- `CrSFMLBackend.draw_text` — per-widget texture rendering
- `SFMLRenderer` DrawText execution — direct-to-window primitives
- `SFMLPaintContext.draw_text` — paint context text drawing

Similarly, sprite positions for layer compositing snap via PixelSnap (sub-pixel sprite
positioning caused ghosted text in viewport_cache layers; both the SFML and headless
compositors share the same snap, so instrument and production cannot drift).

**History**: Fixed in commit 20a683b (blurry button text) and commit 7fb1c03 (ghosted text);
the ties-to-even path divergence (1px cursor-cell text jitter) fixed with PixelSnap.

## Intrinsic Minimum Size & the WindowPanel Content Floor

`measure(constraints)` answers "how big do I *want* to be." A separate, parallel query —
`Widget#min_intrinsic_height(width)` — answers "what's the *smallest* height at which I still render
acceptably." It runs on its **own** recursive chain (not through `BoxConstraints`), because an
unbounded request mid-compose would be silently clamped: `VStack#measure` turns `INFINITY` into
`Float64::MAX`, which is `.finite?`, so a greedy widget keyed on `.finite?` never sees "unbounded."

- **Default** = `measure(...).height` — correct for leaves (they can't shrink below their content).
- **Containers override** to compose children's min the way they stack them: `VStack` sums,
  `Expanded`/`DropZoneBox` pass through, `TreeNode` = header + (expanded) indented children,
  `Content` = menubar + padding + body. A container that *forgets* to override falls through to the
  greedy `measure` default — a `-Dverify_bounds` warning fires when that happens on a widget that has
  children (the generic missed-container guard).
- **Shrinkable widgets report a small floor**: a `ScrollView` returns `0` (it scrolls); a fill
  `VirtualMatrix` returns `ruler + 1 row` (a virtual grid scrolls, so one row is its floor — a
  generic fact, not app policy). `VirtualMatrix#measure` itself is untouched.

`WindowPanel` uses this so its flexible content (e.g. a data grid) can never be starved to nothing by
rigid content above it: `panel_min = @content.min_intrinsic_height + chrome`, cached in
`perform_layout` (recomputed only on a *structural* change — expand/collapse/rebuild — and merely
READ by the resize fast-path, so a resize frame stays O(1); `@@min_floor_recompute_count` guards
this). The panel **won't resize below** `panel_min`, and **grows to it before** laying content out
(so opening a section enlarges the panel in a single pass). Growth is **downward-only** and
**grow-only** — collapsing a section does NOT shrink the panel back; a `maximized` panel skips the
floor and clips rather than overflow.

**Both axes.** The same protocol exists for WIDTH — `min_intrinsic_width(height)`: `HStack` sums
(width is *its* stacking axis; `HStack` also gains the cross-axis `min_intrinsic_height` twin),
`VStack`/`TreeNode`/`Content` take the MAX (width is their cross axis), `FlowLayout` reports its widest
single child (it wraps to one-per-row), and width-greedy widgets that fill (`MenuBar`, `ScrollView`,
fill `VirtualMatrix`) override or they poison the floor (`MenuBar` = Σ its menus; `VirtualMatrix` =
ruler-col + 1 col). `WindowPanel` floors **and grows-at-build on WIDTH exactly like height**. The
governing principle (the user's law): **scrolling is OPT-IN** — wrap content in a `ScrollView` (reports
min 0 on both axes) and the panel can shrink past it while the ScrollView clips/scrolls; otherwise the
floor guarantees **nothing clips**. The lib never imposes a scrollbar. **Window-boundary caveat**:
"never clips" holds only while the window can *contain* the content — a `maximized` panel (or a
free-floating one whose content exceeds the window) clips-to / overflows the window, exactly as the
height axis already did; the genuinely content-bigger-than-window case is a deferred follow-on
(auto-collapse chrome under pressure).

**Loose content + relaxation-skip (grow is O(1)).** A panel hands its content a **loose** box
(`min 0`, `max` = content area), NOT a tight one. So a non-fill body takes its **intrinsic** size (and
sits top-left with margin), while a fill body (`ScrollView`, statusbar, a full-width `VirtualMatrix`)
measures to the max and fills — standard loose-constraint semantics. This is what makes a resize *grow*
cheap: `Widget#can_skip_layout?` skips not only on identical constraints but on a **relaxation the body
didn't use** — if the last size still fits the new constraints and, in each axis whose max grew, the
body wasn't already at the old max (i.e. it wasn't filling), the layout can't have changed, so the whole
content subtree is skipped (zero re-measures). A fill body (size == max) fails the test and re-lays-out,
correctly. The one exception is a widget whose *arrangement* depends on the available space while its own
size stays sub-max — a wrapping `FlowLayout` re-packs rows against `max_width` — which would be silently
skipped; such widgets override `layout_depends_on_available_space? → true` to opt out of the relaxation
branch (they re-flow on any constraint change).

**The opt-out is SUBTREE-wide, not per widget.** Declaring it is not enough on its own: the skip that
matters happens at an *ancestor*, which returns before the wrapping widget's `layout()` is ever reached.
So `can_skip_layout?` consults `subtree_layout_depends_on_available_space?` — the closure of that
predicate over `@children`, recomputed bottom-up at the end of every non-skip `layout()` (a skipped
subtree cannot have changed, and any structural change marks the whole ancestor chain `NeedsLayout`
first). It is seeded `true` so a never-laid-out widget can never be wrongly skipped, and cleared by
`zero_bounds!` so a collapsed section — which is never re-laid-out — cannot latch its ancestors into
permanent re-layout. A container that lays out NON-children (`Menu` → its popup overlay,
`PopupHost`, `Window` → `@overlays`) is outside the closure and must opt out itself. Those cases are
safe today for a reason other than layer ownership (`Menu` owns no layer): `Window#perform_layout` lays
out every overlay on every pass, and `App#prepare_layout` only enters that pass when the root needs
layout, so the root never takes a skip branch — a `Menu` skip could strand a popup's POSITION, never
its internal arrangement.

**Consequence for the "grow is O(1)" claim above**: it holds for content that contains no wrapping
layout. A panel whose content *does* — e.g. embrace's shape panel while its Filter section is expanded —
re-measures that path on every grow frame, and returns to the fast path when the section is collapsed.
That is the price of a correct re-flow; `spec/layout/subtree_relaxation_skip_spec.cr` pins both halves
(the skip survives for non-wrapping content, and the cost stays bounded to the wrapping subtree).

Before the loose-content change, panel content got a tight width that changed every grow-frame ⇒ the
entire content tree was re-measured per frame (an ~30%-CPU live-resize cost). Consequence to know:
**content no longer auto-stretches to the panel width** — use a fill widget (or an explicit width) if
you want that. Pinned by `spec/rendering/grow_resize_perf_spec.cr` (measure/grow-frame is
content-independent *for content with no wrapping layout* — see the paragraph above for the exception).

*Deferred extensions*: a remembered desired-height to shrink back on collapse; growing **upward** /
clamping when a panel is pinned to the screen bottom (today an over-tall panel's bottom edge can go
off-screen, recoverable by dragging the title bar up).

## Event Handling and Input

### SFML Event Serialization (Verified 2024-11-10)

**Key Finding**: SFML properly queues and serializes all input events, eliminating the event-ordering problems seen in ImGui with fast input (e.g., AutoHotkey scripts).

**Test Results**: When sending rapid mixed input (e.g., "abc^S^Vdef"):
```
KeyPressed: A
TextEntered: 'a' (0x61)
KeyPressed: B
TextEntered: 'b' (0x62)
KeyPressed: C
TextEntered: 'c' (0x63)
KeyPressed: LControl
KeyPressed: Ctrl+S
TextEntered: <CTRL-S> (0x13)    ← Control character sent!
KeyPressed: D
TextEntered: 'd' (0x64)
...
```

**Observations**:
1. **Events are properly serialized**: Each `KeyPressed` is followed by its corresponding `TextEntered`
2. **Order is preserved**: Even with rapid input, SFML maintains correct sequence
3. **All events arrive in one poll loop**: Multiple events are queued by SFML, retrieved via `poll_event`
4. **Control characters ARE sent**: `Ctrl+S` generates `TextEntered(0x13)` control character
5. **No frame boundary issues**: All events between frames are properly queued

### Implementation Guidelines for Text Input

When implementing text fields, use the same pattern as SFML's text_input example:

```crystal
when SF::Event::KeyPressed
  # Handle shortcuts first (Ctrl+S, Ctrl+A, etc.)
  if event.control || event.alt || event.system
    handle_shortcut(event)
    # Don't return - let TextEntered be processed too
  end

  # Handle navigation keys (arrows, home, end, etc.)
  case event.code
  when SF::Keyboard::Left
    cursor_left()
  when SF::Keyboard::Right
    cursor_right()
  # ...
  end

when SF::Event::TextEntered
  # Filter: only accept printable characters
  if event.unicode >= ' '.ord && event.unicode != 0x7f
    # Insert character at cursor position
    insert_character(event.unicode.chr)
  end
  # Control characters (< 32) are automatically ignored
  # This filters out Ctrl+S (0x13), Ctrl+A (0x01), etc.
```

**Why This Works**:
- Shortcuts process `KeyPressed(Ctrl+S)` → trigger save action
- Text field ignores `TextEntered(0x13)` → control char filtered out
- Normal typing processes both `KeyPressed('a')` and `TextEntered('a')` → character inserted
- No event consumption tracking needed!

**Key Insight**: The `unicode >= ' '.ord` filter is all you need. SFML's event serialization handles the rest.

### No Complex Event Consumption System Needed

**Initial concern**: ImGui has issues when fast input (AHK) sends both normal characters and shortcuts in one frame, disrupting evaluation.

**Reality with SFML**: This doesn't happen because:
1. SFML queues events in order
2. Each event is processed individually via `poll_event`
3. `TextEntered` filtering handles control characters naturally
4. No need for event consumption tracking, priority systems, or event pairing

**Conclusion**: Keep the architecture simple. Text fields filter `TextEntered` events to only accept printable characters (≥ 32); the shortcut system and SFML's event queue handle everything else correctly.

<!-- (Historical "Open Questions"/"Next Steps" design-phase blocks removed — the state-ownership
     and change-batching questions were resolved by the shipped pull-based version-counting model,
     documented above and in REACTIVITY.md; the batching "Current proposal: Mark needs_render, render
     once per frame" was the OPPOSITE of what shipped.) -->

## Future Work

### Widget Property Standardization

**Problem**: Every widget class currently defines its own set of common properties (font_scale, text_color, background_color, etc.), leading to:
- Code duplication across 5+ widgets
- Inconsistent naming (`color:` vs `text_color:`)
- Maintenance burden when adding new common properties
- DSL helpers must explicitly forward every parameter

**Proposed Solutions**:

**Option A: Style Hash/Struct**
```crystal
cpu_monitor(style: { font_scale: 3, text_color: Color.gray })
```
- Pros: Flexible, easy to add properties, DRY
- Cons: Lose type safety, no autocomplete, runtime errors

**Option B: Mixin Modules** (Composition)
```crystal
class CPUMonitor
  include TextProperties      # adds font_scale, text_color
  include BackgroundProperties # adds background_color, border_color
end
```
- Pros: DRY, modular, type-safe, each widget includes what it needs
- Cons: Parameter passing complexity, macro overhead

**Option C: Base Widget Properties**
```crystal
class Widget
  property font_scale : Int32?
  property text_color : Color?
end
```
- Pros: Very DRY, standardized
- Cons: Not all widgets need all properties (containers don't need font_scale)

**Option D: Standardize Current Approach**
- Accept some duplication but enforce consistency
- Always use `text_color:` (not `color:`)
- Standard order: `id, font_scale, text_color, background_color`
- Document as convention

**Recommendation**: Option B (Mixins) + Option D (Standardization)
1. Create `TextProperties`, `BackgroundProperties` modules
2. Widgets include what they need
3. Standardize parameter names/order across all widgets
4. Leverage Crystal's named parameters for clarity
5. Keeps type safety, reduces duplication, stays idiomatic to Crystal

**Status**: Discussion phase - needs decision before implementation

### RenderBackend Pixel Access API

**Current state**:
- Single pixels: `get_pixel(x, y)` / `set_pixel(x, y, color)` - TestRenderBackend only
- Whole backends: `blit(source, dest_x, dest_y)` - abstract interface
- Rectangular regions: `blit_region(source, src_x, src_y, w, h, dest_x, dest_y)` - abstract interface

**Gap**: `get_pixels`/`set_pixels` for rectangular regions exist in TestRenderBackend but not in abstract interface.

```crystal
# TestRenderBackend has these (not in abstract interface):
def get_pixels(x, y, width, height) : Array(Color)
def set_pixels(x, y, width, height, pixels : Array(Color))
```

**Usage**: Currently used only for background memorization in tests. For SFML, `blit_region` handles this via GPU→GPU copy (much faster than pixel-by-pixel).

**Decision needed**: Should these be promoted to abstract interface, or keep using `blit_region` for the common case?

**Status**: Current approach (blit_region) works well - low priority
