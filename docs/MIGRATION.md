# Migration guide

Breaking changes for code built on CrymbleUI, newest first. See `docs/REACTIVITY.md` for the *why*.

---

## Reactive fields are now `Source`-backed (auto-capture)

`render_property` fields (and `VirtualMatrix#scroll_offset`) are no longer plain ivars — each is a
`::CrymbleUI::Source(T)`. The getter auto-captures the read (so `to_primitives` declares its dependencies);
the setter notifies, so you no longer hand-wire invalidation. This changes how you write a custom widget that
uses these fields.

### 1. Read the getter, never the `@ivar`

The `@field` ivar is now the `Source` object, not the value. Only the **getter** returns the value *and*
registers the auto-capture dependency. A raw `@field` read won't even compile (it's a `Source(T)`, not a `T`)
for non-nilable fields — and for nilable ones it silently breaks reactivity, so sweep them.

```crystal
# before
def to_primitives(bounds : Rect)
  primitives { draw_text(@text, ...); fill_rect(bounds, @background_color) }
end

# after — the getters (no @)
def to_primitives(bounds : Rect)
  primitives { draw_text(text, ...); fill_rect(bounds, background_color) }
end
```

This applies everywhere the field is read (`measure`, helpers, debug strings, hit-testing) — not just
`to_primitives`.

### 2. Constructors build the `Source`

A constructor that auto-assigned the field as a parameter must construct the `Source` in the body.

```crystal
# before
def initialize(@text : String, @background_color : Color? = nil)
end

# after
def initialize(text : String, background_color : Color? = nil)
  @text = Source(String).new(text)
  @background_color = Source(Color?).new(background_color)
end
```

(Build the `Source`s *before* `super` if anything in construction reads the getter, e.g. `label`.)

### 3. Stop calling `mark_needs_render` after setting a reactive field

Auto-capture invalidates for you, and the `Source` equality gate already suppresses no-op writes. The manual
mark is redundant — and for a *reconcile* field it's gone entirely from the generated setter.

```crystal
# before
self.hover_state = true
mark_needs_render          # ← delete; the field setter handles it

# after
self.hover_state = true
```

If you set several fields and want exactly one invalidation, you don't need to do anything — a node that's
already stale stays stale (re-marking is idempotent).

### 4. `needs_render?` is node-derived

For a node-backed (`Dynamic`, rendered) widget, `needs_render?` now reflects whether the primitives cache is
stale (`!node.valid?`), not the `@state` flag. If you read `needs_render?` (e.g. in a custom blit path),
nothing changes for you — it's *more* precise. But don't rely on `@state == NeedsRender` as a proxy for
"this widget's content changed"; a `Source`-backed setter no longer sets it.

### 5. `VirtualMatrix#scroll_offset =` now applies the scroll

Setting the matrix's `scroll_offset` used to trigger `mark_needs_layout` (a full re-layout). It now does the
right, cheap thing directly: notify the captured readers **and** apply the scroll (composite the content
layer + recenter visible cells). No re-layout. If you set it expecting a layout side-effect, you don't need
one — the view scrolls correctly without it.

### 6. The property macros collapsed to `reactive_property` + `reconcile_property`

`render_property` and `layout_property` are **removed** (no alias, no deprecation shim — the rename is
mechanical). Every reactive value is declared with `reactive_property` (a `Source(T)`); the two old macros'
behaviours are now flags:

```crystal
# before                                    # after
render_property    color : Color            reactive_property color : Color
layout_property    padding : Float64         reactive_property padding : Float64, layout: true
reconcile_property mode : Mode              reactive_property mode : Mode, reconcile: true
```

- `render_property X` → `reactive_property X` (render-reactivity is decided by reading the field in
  `to_primitives`, not by the macro name; storage was already a `Source`, so this is a pure rename).
- `layout_property X` → `reactive_property X, layout: true` (the setter still marks layout). The field is now
  a `Source`, so sweep its raw `@X` reads to the getter `X` and build the `Source` in the constructor
  (sections 1–2 above). Constructor writes use `@X.set(value)`, not `self.X = value` — a method call on
  `self` before all ivars are initialized makes Crystal treat later ivars as indirectly-initialized.
- `reconcile_property X` holding a **value** → `reactive_property X, reconcile: true`.

`reconcile_property` is **kept but narrowed**: it now declares only *non-reactive* infrastructure that must
survive a rebuild — a managed `Layer`/`Widget` ref. It stays a plain ivar (not a `Source`); use it in place
of a hand-written `@[Reconcile]` annotation. Reactive values never use it. The rule of thumb is
**Source-back what renders**.
