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

### 2. Explicit Change Tracking

State changes propagate through a well-defined event system:

```crystal
struct StateChange
  property type : Symbol          # :toggled, :clicked, :value_changed
  property target : Widget        # What changed
  property scope : InvalidateScope # What needs redrawing
  property action : Symbol?        # Optional action request (e.g., :close_menu)
end

enum InvalidateScope
  Self      # Only this widget
  Children  # This widget + children
  Parent    # Invalidate upward (e.g., menu item → close menu)
  Global    # Full redraw (rare - major layout changes)
end
```

### 3. Testability First

All business logic must be testable without rendering:

```crystal
# GOOD: Pure state logic, fully testable
it "checkable menu items keep menu open" do
  item = MenuItemState.new("Dark Mode", checkable: true)
  change = item.click

  change.action.should be_nil  # No close action
  change.type.should eq(:item_toggled)
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
  Never    # Always render fresh (menus, popups)
end

class Menu < Widget
  def cache_policy : CachePolicy
    CachePolicy::Never  # Menus are always dynamic
  end
end

class Button < Widget
  def cache_policy : CachePolicy
    CachePolicy::Dynamic  # Cache until state changes
  end
end

class WindowChrome < Widget
  def cache_policy : CachePolicy
    CachePolicy::Static  # Cache until layout changes
  end
end
```

### Cache Invalidation Rules

Clear, explicit rules prevent bugs:

```crystal
class Widget
  # Called when state changes
  def on_state_change(change : StateChange)
    case change.scope
    when InvalidateScope::Self
      invalidate_own_cache
    when InvalidateScope::Children
      invalidate_tree_cache
    when InvalidateScope::Parent
      parent.try &.on_state_change(change)
    when InvalidateScope::Global
      root.invalidate_all_caches
    end

    mark_needs_render if should_render?(change)
  end

  private def should_render?(change : StateChange) : Bool
    # Only render if cache policy allows caching
    # or if this is a Never-cache widget
    cache_policy == CachePolicy::Never ||
      (cache_policy == CachePolicy::Dynamic && change.invalidates_cache?)
  end
end
```

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
  def primitives(&block)
    @primitives = [] of DrawPrimitive
    yield
    @primitives.not_nil!
  end

  # DSL methods - append to @primitives
  def fill_rect(bounds : Rect, color : Color)
    @primitives.not_nil! << FillRect.new(bounds, color)
  end

  def draw_text(text : String, pos : Vec2, color : Color, size : Float64 = 16.0)
    @primitives.not_nil! << DrawText.new(text, pos, color, size)
  end

  def draw_line(from : Vec2, to : Vec2, color : Color, width : Float64 = 1.0)
    @primitives.not_nil! << DrawLine.new(from, to, color, width)
  end

  def draw_circle(center : Vec2, radius : Float64, color : Color, fill : Bool = true)
    @primitives.not_nil! << DrawCircle.new(center, radius, color, fill)
  end
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

## Widget Property Macros: Automatic Invalidation

### The Problem

Widget properties need to trigger appropriate invalidation when changed:
- Visual properties (color, text) → `mark_needs_render` (selective render)
- Layout properties (size, padding) → `mark_needs_layout` (full layout + render)

Without macros, every property requires 4 lines of boilerplate:

```crystal
# Manual approach (before macros)
@background_color : Color
def background_color : Color; @background_color end
def background_color=(value : Color); @background_color = value; mark_needs_render end
```

For a widget with 5 properties, that's 20 lines of repetitive code!

### The Solution: Property Macros

The `Widget` base class provides three macros that eliminate boilerplate:

```crystal
# Widget base class (src/core/widget.cr)
abstract class Widget
  # Macro for visual properties (triggers render only)
  # Optional reconcile parameter adds @[Reconcile] annotation for auto-copy
  macro render_property(declaration, reconcile = false)
    {% if reconcile %}
      @[Reconcile]
    {% end %}
    {% if declaration.is_a?(TypeDeclaration) %}
      {% if !declaration.value.is_a?(Nop) %}
        @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
      {% else %}
        @{{declaration.var}} : {{declaration.type}}
      {% end %}

      def {{declaration.var}} : {{declaration.type}}
        @{{declaration.var}}
      end

      def {{declaration.var}}=(value : {{declaration.type}})
        @{{declaration.var}} = value
        mark_needs_render
      end
    {% end %}
  end

  # Macro for layout properties (triggers layout + render)
  # Optional reconcile parameter adds @[Reconcile] annotation for auto-copy
  macro layout_property(declaration, reconcile = false)
    {% if reconcile %}
      @[Reconcile]
    {% end %}
    {% if declaration.is_a?(TypeDeclaration) %}
      {% if !declaration.value.is_a?(Nop) %}
        @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
      {% else %}
        @{{declaration.var}} : {{declaration.type}}
      {% end %}

      def {{declaration.var}} : {{declaration.type}}
        @{{declaration.var}}
      end

      def {{declaration.var}}=(value : {{declaration.type}})
        @{{declaration.var}} = value
        mark_needs_layout
      end
    {% end %}
  end

  # Macro for reconcile-only properties (no invalidation, always adds @[Reconcile])
  macro reconcile_property(declaration)
    @[Reconcile]
    {% if declaration.is_a?(TypeDeclaration) %}
      {% if !declaration.value.is_a?(Nop) %}
        @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
      {% else %}
        @{{declaration.var}} : {{declaration.type}}
      {% end %}

      def {{declaration.var}} : {{declaration.type}}
        @{{declaration.var}}
      end

      def {{declaration.var}}=(value : {{declaration.type}})
        @{{declaration.var}} = value
      end
    {% end %}
  end
end
```

**The `reconcile` parameter**: When `reconcile: true` is passed to `render_property` or `layout_property`, the macro adds `@[Reconcile]` annotation. Properties with this annotation are automatically copied during widget reconciliation via `auto_copy_reconcile_properties()`. Use this for state that must persist across DSL rebuilds (e.g., scroll_offset, selected colors).

### Usage in Widgets

Widgets use these macros to declare properties with automatic invalidation:

```crystal
class Button < Widget
  include PrimitiveBuilder

  # Font scale (uses FontSizing module for computed font_size)
  @font_scale : Int32 = 0
  def font_scale=(v); @font_scale = v; mark_needs_layout; end
  def font_size : Float64; FontSizing.calculate_size(@font_scale); end

  # Visual properties (mark_needs_render when changed)
  render_property text_color : Color
  render_property background_color : Color
  render_property border_color : Color

  # Layout properties (mark_needs_layout when changed)
  layout_property padding : Float64
end
```

```crystal
class StatusBar < Widget
  include PrimitiveBuilder

  # Font scale (default -1 for smaller text)
  @font_scale : Int32 = -1
  def font_scale=(v); @font_scale = v; mark_needs_layout; end
  def font_size : Float64; FontSizing.calculate_size(@font_scale); end

  # Visual properties
  render_property text_color : Color
  render_property background_color : Color
  render_property border_color : Color

  # Layout properties
  layout_property height : Float64
  layout_property padding : Float64
end
```

### Benefits

1. **Consistent invalidation**: All properties use the same pattern
2. **Clear semantics**:
   - `render_property` = visual change only
   - `layout_property` = structural change
3. **Less boilerplate**: ~75% code reduction (from 4 lines to 1 line per property)
4. **Automatic cache invalidation**: Properties trigger `mark_needs_render` or `mark_needs_layout`, which the base `Widget` class uses to invalidate primitive caches
5. **Type-safe**: Full Crystal type checking preserved
6. **Default values**: Supports default values via type declaration syntax

### Integration with Primitive Caching

The property macros integrate seamlessly with the primitive caching system:

```crystal
# When a render_property changes:
widget.background_color = Color.red  # Calls mark_needs_render
# → Widget.state = WidgetState::NeedsRender
# → Next get_primitives() call regenerates cached primitives

# When a layout_property changes:
widget.padding = 20.0  # Calls mark_needs_layout
# → Widget.state = WidgetState::NeedsLayout
# → Widget.invalidate_last_constraints() called
# → Next layout() call recalculates bounds (can't skip - constraints invalidated)
# → Next get_primitives() call regenerates cached primitives
```

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

Some properties need custom logic beyond simple invalidation:

```crystal
class Text < Widget
  # Text property with custom setter logic
  @text : String
  def text : String
    @text
  end

  def text=(value : String)
    @text = value
    # Custom logic: also update label
    mark_needs_render
  end

  # Font scale with computed font_size
  @font_scale : Int32 = 0
  def font_scale=(v); @font_scale = v; mark_needs_layout; end
  def font_size : Float64; FontSizing.calculate_size(@font_scale); end

  # Simple properties can use macros
  render_property color : Color
end
```

## Layered Widget Composition

Widgets form layers, from primitive to complex. All share the same interface: `to_primitives()`.

### Layer 1: Primitive Widgets

Directly produce DrawPrimitives:

```crystal
class Text < Widget
  include PrimitiveBuilder

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      draw_text(@text, bounds.position, @color, font_size)  # font_size is computed from @font_scale
    end
  end
end

class Rectangle < Widget
  include PrimitiveBuilder

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      fill_rect(bounds, @color)
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

Layout children, aggregate their primitives:

```crystal
class VStack < Widget
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    # After layout phase has set child.bounds
    children.flat_map { |child| child.to_primitives(child.bounds) }
  end
end

class HStack < Widget
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    children.flat_map { |child| child.to_primitives(child.bounds) }
  end
end
```

### Layer 4: Complex Composites

Mix direct primitives with child aggregation:

```crystal
class WindowPanel < Widget
  include PrimitiveBuilder

  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    prims = [] of DrawPrimitive

    # Panel chrome (direct primitives)
    prims += primitives do
      fill_rect(bounds, @bg_color)
      fill_rect(title_bar_bounds, @title_bg_color)
      draw_text(@title, title_pos, @title_color)
    end

    # Content area (aggregate children)
    prims += children.flat_map { |child| child.to_primitives(child.bounds) }

    prims
  end
end
```

**Key**: Every widget implements `to_primitives()`. Composition is natural.

## Proposed Architecture

### State Layer (Pure, Testable)

```crystal
module CrymbleUI::State
  # Pure state objects - no rendering knowledge
  # All logic is here, fully unit testable

  class MenuItemState
    property label : String
    property checked : Bool
    property checkable : Bool
    property callback : Proc(Nil)?

    def initialize(@label, @checked = false, @checkable = false, @callback = nil)
    end

    # Pure logic - returns what should happen
    def click : StateChange
      # Execute callback (business logic)
      @callback.try &.call

      if @checkable
        @checked = !@checked
        StateChange.new(
          type: :item_toggled,
          target: self,
          scope: InvalidateScope::Self,
          action: nil  # Checkable items don't close menu
        )
      else
        StateChange.new(
          type: :item_activated,
          target: self,
          scope: InvalidateScope::Parent,
          action: :close_menu  # Action items request close
        )
      end
    end
  end

  class MenuState
    property label : String
    property open : Bool
    property items : Array(MenuItemState)

    def initialize(@label, @items = [] of MenuItemState)
      @open = false
    end

    def toggle : StateChange
      @open = !@open
      StateChange.new(
        type: @open ? :menu_opened : :menu_closed,
        target: self,
        scope: InvalidateScope::Children,
        action: nil
      )
    end

    def close : StateChange
      @open = false
      StateChange.new(
        type: :menu_closed,
        target: self,
        scope: InvalidateScope::Children,
        action: nil
      )
    end

    def handle_item_click(item : MenuItemState) : StateChange
      change = item.click

      # If item requests menu close
      if change.action == :close_menu
        close
      else
        change
      end
    end
  end
end
```

### Widget Layer (Coordination)

```crystal
class MenuItem < Widget
  include PrimitiveBuilder

  # Widget owns the state
  property state : State::MenuItemState

  def initialize(label : String, checked : Bool? = nil, &block : -> Nil)
    super()
    @state = State::MenuItemState.new(
      label: label,
      checked: checked || false,
      checkable: !checked.nil?,
      callback: block
    )
  end

  # Declare caching behavior
  def cache_policy : CachePolicy
    CachePolicy::Dynamic
  end

  # Handle click event
  def on_click
    # Delegate to pure state logic
    change = @state.click

    # Propagate change upward
    propagate_change(change)
  end

  # Produce rendering primitives based on state
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    primitives do
      # Hover background
      fill_rect(bounds, @hover_color) if @hovered

      # Checkmark
      if @state.checked
        check_pos = Vec2.new(bounds.x + 8.0, bounds.y + 4.0)
        draw_text("✓", check_pos, text_color, font_size)
      end

      # Label
      label_pos = Vec2.new(bounds.x + 24.0, bounds.y + 4.0)
      draw_text(@state.label, label_pos, text_color, font_size)

      # Shortcut (if present)
      if @state.shortcut
        shortcut_pos = Vec2.new(bounds.x + bounds.width - 40.0, bounds.y + 4.0)
        draw_text(@state.shortcut, shortcut_pos, @shortcut_color, font_size)
      end
    end
  end
end
```

### Rendering Layer (Backend Execution)

**Critical**: The renderer knows NOTHING about widgets. It only executes primitives.

```crystal
# Backend-specific renderer (SFML implementation)
class SFMLRenderer
  def initialize(@render_target : SF::RenderTarget, @font : SF::Font)
  end

  # Execute a list of primitives
  def render(primitives : Array(DrawPrimitive))
    primitives.each do |primitive|
      execute_primitive(primitive)
    end
  end

  # Dispatch primitive to backend-specific implementation
  private def execute_primitive(primitive : DrawPrimitive)
    case primitive
    when FillRect
      execute_fill_rect(primitive)
    when DrawText
      execute_draw_text(primitive)
    when DrawLine
      execute_draw_line(primitive)
    when DrawCircle
      execute_draw_circle(primitive)
    end
  end

  private def execute_fill_rect(p : FillRect)
    rect = SF::RectangleShape.new(SF.vector2f(p.bounds.width, p.bounds.height))
    rect.position = SF.vector2f(p.bounds.x, p.bounds.y)
    rect.fill_color = to_sf_color(p.color)
    @render_target.draw(rect)
  end

  private def execute_draw_text(p : DrawText)
    text = SF::Text.new(p.text, @font, p.size.to_u32)
    text.position = SF.vector2f(p.position.x, p.position.y)
    text.fill_color = to_sf_color(p.color)
    @render_target.draw(text)
  end

  private def execute_draw_line(p : DrawLine)
    line = SF::VertexArray.new(SF::Lines, 2)
    line[0] = SF::Vertex.new(SF.vector2f(p.from.x, p.from.y), to_sf_color(p.color))
    line[1] = SF::Vertex.new(SF.vector2f(p.to.x, p.to.y), to_sf_color(p.color))
    @render_target.draw(line)
  end

  private def execute_draw_circle(p : DrawCircle)
    circle = SF::CircleShape.new(p.radius)
    circle.position = SF.vector2f(p.center.x - p.radius, p.center.y - p.radius)
    if p.fill
      circle.fill_color = to_sf_color(p.color)
    else
      circle.fill_color = SF::Color::Transparent
      circle.outline_color = to_sf_color(p.color)
      circle.outline_thickness = 1.0
    end
    @render_target.draw(circle)
  end

  private def to_sf_color(c : Color) : SF::Color
    SF::Color.new(c.r, c.g, c.b, c.a)
  end
end

# Alternative backend: OpenGL renderer
class OpenGLRenderer
  def render(primitives : Array(DrawPrimitive))
    primitives.each do |primitive|
      case primitive
      when FillRect
        # OpenGL implementation
      when DrawText
        # OpenGL implementation
      end
    end
  end
end

# Alternative backend: HTML Canvas renderer
class CanvasRenderer
  def render(primitives : Array(DrawPrimitive)) : String
    js = [] of String
    primitives.each do |primitive|
      case primitive
      when FillRect
        js << "ctx.fillRect(#{primitive.bounds.x}, #{primitive.bounds.y}, ...);"
      when DrawText
        js << "ctx.fillText('#{primitive.text}', #{primitive.position.x}, ...);"
      end
    end
    js.join("\n")
  end
end
```

**Key**: Same primitives work with any backend. Swap SFML → OpenGL by changing one line.

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

```crystal
# Widget base class (widget.cr)
abstract class Widget
  # Cache storage (base class only)
  @cached_primitives : Array(DrawPrimitive)?

  # Public API: Get primitives (may be cached)
  # Renderer calls this method
  def get_primitives(bounds : Rect) : Array(DrawPrimitive)
    case cache_policy
    when CachePolicy::Never
      # Always generate fresh (menus, popups)
      to_primitives(bounds)

    when CachePolicy::Dynamic
      # Cache primitives, invalidate on state change (buttons, text)
      if needs_render? || @cached_primitives.nil?
        @cached_primitives = to_primitives(bounds)
      else
        @cached_primitives.not_nil!
      end

    when CachePolicy::Static
      # Cache primitives forever (window chrome)
      @cached_primitives ||= to_primitives(bounds)
    end
  end

  # Invalidate primitive cache (called on state changes)
  def invalidate_primitive_cache
    @cached_primitives = nil
  end

  # Subclasses declare policy (default: Dynamic)
  def cache_policy : CachePolicy
    CachePolicy::Dynamic
  end

  # Subclasses implement this - just describe what to draw
  abstract def to_primitives(bounds : Rect) : Array(DrawPrimitive)
end
```

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

### Render Cache (Optional - For Expensive Widgets)

Some widgets may additionally cache the rendered texture (after executing primitives):

```crystal
class RenderCache
  # Map widget → cached texture (optional, for expensive rendering)
  @texture_cache : Hash(Widget, CachedTexture)

  struct CachedTexture
    property texture : SF::RenderTexture
    property valid : Bool
  end

  def get_or_render(widget : Widget, renderer : SFMLRenderer) : SF::Texture
    # First, get primitives (may be cached)
    primitives = widget.get_primitives(widget.bounds)

    # Then, optionally cache texture rendering
    if widget.cache_policy == CachePolicy::Static
      entry = @texture_cache[widget]?
      if entry && entry.valid
        return entry.texture.texture
      end
    end

    # Render primitives to texture
    texture = render_to_texture(primitives, renderer)

    # Cache texture if static policy
    if widget.cache_policy == CachePolicy::Static
      @texture_cache[widget] = CachedTexture.new(texture, true)
    end

    texture.texture
  end

  private def render_to_texture(primitives, renderer)
    texture = SF::RenderTexture.new(...)
    renderer.render_target = texture
    renderer.render(primitives)
    texture
  end
end
```

### Cache Benefits with Primitives

1. **Lightweight**: Primitives are small structs, cheap to cache
2. **Testable**: Assert on cached primitives without rendering
3. **Flexible**: Can cache primitives, textures, or both
4. **Clear invalidation**: Primitive cache vs texture cache

**Example**:
```crystal
class Menu < Widget
  def cache_policy : CachePolicy
    CachePolicy::Never  # Menu primitives always regenerated
  end
end

class Button < Widget
  def cache_policy : CachePolicy
    CachePolicy::Dynamic  # Cache primitives until state changes
  end
end

class WindowChrome < Widget
  def cache_policy : CachePolicy
    CachePolicy::Static  # Cache primitives + texture aggressively
  end
end
```

## Migration Path

**Strategy**: Incremental refactoring, one widget at a time. Keep everything working.

### Phase 1: Introduce DrawPrimitive Infrastructure

1. Create `DrawPrimitive` base and concrete structs (`FillRect`, `DrawText`, etc.)
2. Create `PrimitiveBuilder` mixin module with DSL methods
3. Add `to_primitives(bounds)` method to `Widget` base class (default: call old render)
4. Update `SFMLRenderer` to execute primitives
5. Verify: Existing widgets still work via old render path

### Phase 2: Migrate One Widget to Primitives

Start with `Text` widget (simplest):

1. Add `include PrimitiveBuilder` to `Text`
2. Implement `to_primitives` using DSL
3. Write unit tests asserting on primitive output
4. Remove old `render` method
5. Verify visual output unchanged

### Phase 3: Add Cache Policies

1. Add `CachePolicy` enum (Never, Dynamic, Static)
2. Add `cache_policy` method to `Widget` base class (default: Dynamic)
3. Override for specific widgets:
   - `Menu` → Never
   - `Popup` → Never
   - `Button` → Dynamic
   - `Text` → Dynamic
4. Implement primitive caching in `Widget.get_primitives`
5. Remove all ad-hoc cache skipping code (those `is_a?(Popup)` checks)

### Phase 4: Add State Layer for Complex Widgets

For widgets with complex behavior (Menu, MenuItem):

1. Create `State::MenuItemState` with pure logic
2. Write comprehensive unit tests for state (100% coverage)
3. Move behavior from `MenuItem.on_click` to `MenuItemState.click`
4. Update `MenuItem.to_primitives` to use state
5. Verify behavior unchanged (now fully tested!)

### Phase 5: Migrate Remaining Widgets

Continue pattern for all widgets:
- Primitive widgets: Just `to_primitives`
- Interactive widgets: State + `to_primitives`
- Containers: Aggregate child primitives

### Phase 6: Remove Old Rendering Path

1. Remove `render(context)` method from all widgets
2. Remove `PaintContext` (replaced by primitives)
3. Renderer only knows primitives, nothing about widgets
4. Clean, separated architecture complete!

### Phase 7: Advanced Optimizations (Optional)

1. Texture caching for expensive widgets
2. Dirty rectangle tracking
3. Batched primitive rendering
4. GPU acceleration via custom backends

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

### Unit Tests (State Layer)

```crystal
describe State::MenuItemState do
  describe "#click" do
    context "checkable item" do
      it "toggles checked state" do
        item = State::MenuItemState.new("Dark Mode", checked: false, checkable: true)
        item.click
        item.checked.should be_true
      end

      it "returns StateChange with no close action" do
        item = State::MenuItemState.new("Dark Mode", checkable: true)
        change = item.click
        change.action.should be_nil
      end

      it "invalidates only self" do
        item = State::MenuItemState.new("Dark Mode", checkable: true)
        change = item.click
        change.scope.should eq(InvalidateScope::Self)
      end
    end

    context "action item" do
      it "requests menu close" do
        item = State::MenuItemState.new("New File", checkable: false)
        change = item.click
        change.action.should eq(:close_menu)
      end

      it "invalidates parent" do
        item = State::MenuItemState.new("New File", checkable: false)
        change = item.click
        change.scope.should eq(InvalidateScope::Parent)
      end
    end

    it "executes callback" do
      called = false
      item = State::MenuItemState.new("Test") { called = true }
      item.click
      called.should be_true
    end
  end
end
```

### Integration Tests (Widget Layer)

```crystal
describe MenuItem do
  it "delegates click to state" do
    clicked = false
    item = MenuItem.new("Test") { clicked = true }

    item.on_click

    clicked.should be_true
    item.state.should_not be_nil
  end

  it "propagates state changes upward" do
    # Test change propagation without rendering
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

1. **Measurement** (`Widget.measure_text` in widget.cr):
   ```crystal
   def self.measure_text(text : String, size : Float64) : Size
     sf_text = SF::Text.new(text, font, size.to_u32)
     bounds = sf_text.local_bounds  # ← Uses local_bounds to include padding
     Size.new(bounds.width.to_f64, bounds.height.to_f64)
   end
   ```

2. **Rendering** (`draw_text` in primitive_builder.cr):
   ```crystal
   def draw_text(text : String, position : Vec2, color : Color, size : Float64 = 16.0)
     sf_text = SF::Text.new(text, font, size.to_u32)
     left_offset = sf_text.local_bounds.left
     top_offset = sf_text.local_bounds.top
     # Compensate for SFML offsets so visual glyphs appear at requested position
     adjusted_position = Vec2.new(position.x - left_offset, position.y - top_offset)
     @primitives.not_nil! << DrawText.new(text, adjusted_position, color, size)
   end
   ```

3. **Clipping** (renderer automatically clips rendering leaves to bounds):
   ```crystal
   # In sfml_renderer.cr, before executing primitives:
   if widget.rendering_leaf? && ctx.is_a?(SFMLPaintContext)
     ctx.push_clip(widget.bounds)  # Clip to measured bounds
   end
   ```

**How it works**:
- `measure_text` returns visual size only: `(local_bounds.width, local_bounds.height)`
- Widget.bounds is sized using measured size plus padding
- `draw_text` shifts rendering position backwards by `local_bounds.left/top`
- Visual glyphs render exactly at requested position
- Text stays within measured bounds (no overflow)

**Why Option A**:
- Simple: One measurement function, one rendering function
- Safe: Automatic clipping prevents overflow artifacts
- Consistent: Bounds match actual rendering extent
- No stale bounds issues: Even if bounds are slightly stale, clipping prevents artifacts

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
# Measure text (returns width, height only)
text_size = measure_text("Hello", 16.0)  # => Size(50, 15)

# Size widget: add equal padding
widget_size = Size(text_size.width + 20, text_size.height + 20)  # Equal 10px padding

# Position text: simple padding offset
text_pos = Vec2(widget.x + 10, widget.y + 10)  # 10px from edges

# Render: draw_text compensates for SFML offsets automatically
draw_text("Hello", text_pos, color, 16.0)  # Glyphs appear exactly at text_pos
```

**Result**: Equal visual padding on all sides, regardless of font size or glyphs (including descenders like 'y', 'g', 'q')

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

**Conclusion**: Keep the architecture simple. When implementing text fields later, just filter `TextEntered` events to only accept printable characters (≥ 32). The existing shortcut system and SFML's event queue handle everything else correctly.

## Open Questions

1. **State ownership**: Should state live in widgets or be external (like Elm model)?
   - Current proposal: Widgets own state (easier migration)
   - Alternative: External state tree (more pure, harder to migrate)

2. **Immutability**: Should state be immutable with snapshots?
   - Current proposal: Mutable state (simpler, faster)
   - Alternative: Immutable snapshots for rendering (safer, more memory)

3. **Change batching**: How do we batch multiple state changes before render?
   - Current proposal: Mark needs_render, render once per frame
   - Alternative: Event queue with batch processing

## Next Steps

1. **Review this architecture** - Is this the right direction?
2. **Prototype with Menu** - Implement for one widget as proof of concept
3. **Iterate based on learnings** - Refine architecture based on what we discover
4. **Roll out incrementally** - Migrate widget by widget, not all at once

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
