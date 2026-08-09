# Migration guide

Breaking changes for code built on CrymbleUI, newest first. See `docs/REACTIVITY.md` for the *why*.

---

## `Clipboard#string` / `#string=` are now `#text` / `#text=`, and the getter is nilable

```crystal
# before
Widget.clipboard.string = tsv          # String
text = Widget.clipboard.string         # String — "" also meant "nothing on the clipboard"

# after
Widget.clipboard.text = tsv            # String
if text = Widget.clipboard.text        # String? — nil means NOTHING is on the clipboard
  # ...
end
```

**Why rename rather than just make the getter nilable.** Keeping the name would give only a partial
compile guard: reads like `clipboard.string.empty?` stop compiling, but `clipboard.string = x` keeps
working silently — the worst outcome for a published shard. The rename forces every call site to be
visited exactly once.

**There is deliberately no provenance.** The clipboard carries text and nothing else — no "who wrote
this" tag. A component that copies structured data (a spreadsheet-style grid, say) puts text on the
clipboard like anything else, and pasting it into a text field yields that text. That is the user's
own doing, and the library does not police it.

**What `nil` means, and what it does not mean yet.** The type now admits absence: `nil` is "there is
nothing on the clipboard", a different state from an empty string having been copied. **The SFML
backend cannot produce `nil` today** — `sfClipboard_getString` returns an empty string for no-owner,
for a timed-out conversion, and for a genuinely empty clipboard alike, so those three are one value at
that layer. Until the X11 selection reader lands, `nil` is reachable only from
`Testing::TestClipboard`. Treat the distinction as something you may write against, not yet as a
capability the SFML path delivers.

**Paste behaviour also changed** (`TextInput`). A pasted payload is now flattened for a single-line
field: the `\r\n` pair collapses to `\n`, leading/trailing line breaks are trimmed, then `\n`, `\r` and
**tab** each become a single space, then anything the typing path refuses (`< 32`, and 127) is removed.
Content is kept — nothing is truncated. Tab becomes a space rather than being dropped because it is the
TSV field separator; dropping it would silently weld `"Mueller\t30"` into `"Mueller30"`. The trim is
why copying one spreadsheet cell (`"value\r\n"`) pastes as `"value"`, and why copying an *empty* cell
(`"\r\n"`) pastes nothing at all rather than replacing your selection with a space. Spaces you actually
copied are never trimmed.

**Non-ASCII now round-trips correctly — this was previously broken in both directions.** The wrapper
bound only the ANSI CSFML entry points, which convert through the `"C"` locale and delete every
non-ASCII codepoint: copying `Müller` put `Mller` on the OS clipboard, and reading it back yielded
`Mller`. `SF::Clipboard` now uses the UTF-32 entry points and validates foreign codepoints as it
decodes, so a value outside Unicode's range or a lone surrogate becomes U+FFFD instead of raising —
another application's bytes must not be able to crash the process.

Verified across a real process boundary in both directions (`tools/clipboard-roundtrip-probe.cr`),
since `Testing::TestClipboard` stores a Crystal `String` verbatim and therefore cannot fail on this bug.

### A parked `TextInput` no longer consumes ANY clipboard key

`TextInput` now touches the clipboard **only while it is actually editing text**. While PARKED in
`QuickEntry` (focus armed `pending_replace`, nothing typed yet) the widget is a grid cell, not a text
field, so **every** clipboard key is declined and bubbles to the owner: `Ctrl+C`/`Ctrl+Insert`,
`Ctrl+X`/`Shift+Delete`, `Ctrl+V`/`Shift+Insert`. Once typing starts, or in `FullEdit`, they act on the
text as before. `Backspace` and `Ctrl+A` are not clipboard ops and are unaffected.

Previously only the keys that had a "competing cell-op" were declined — which gated a generic widget on
which shortcuts one consumer happened to register. The consequence was that `Ctrl+C` and `Shift+Insert`
were swallowed before an application that grew a grid-level copy/paste could ever see them.

**What to check in your app:** any clipboard key you want to act on at cell/grid level now reaches your
shortcut handler while a cell is parked — register it. Conversely, `Shift+Insert` into a parked cell
used to paste text into the cell editor and now does nothing unless you bind it.

**Two test-harness changes** that affect consumer suites:

- `Testing::TestClipboard` now starts at `nil` where it used to start at `""`. A spec asserting
  `clipboard.text == ""` on a fresh instance must become `.nil?`.
- `Testing::TestRenderer` now installs a `TestClipboard` **if and only if** none is installed. Copy and
  paste paths previously raised `"Clipboard not initialized"` in a suite that installed none; they now
  work. If your suite installs its own, it is left untouched.

---

## Reactive fields are now `Source`-backed (auto-capture)

`render_property` fields (and `VirtualMatrix#scroll_offset`) are no longer plain ivars — each is a
`::CrymbleUI::Source(T)`. The getter auto-captures the read (so `to_primitives` declares its dependencies);
the setter notifies, so you no longer hand-wire invalidation. This changes how you write a custom widget that
uses these fields.

### 1. Read the getter, never the `@ivar`

The `@field` ivar is now the `Source` object, not the value. Only the **getter** returns the value *and*
registers the auto-capture dependency. A raw `@field` read won't even compile regardless of nilability — the ivar is always a `Source(T)`, never `T` or `T?`.

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

`reconcile_property` is **kept but narrowed**: it now declares any *non-reactive*, plain-ivar state that must
survive a rebuild. Managed `Layer`/`Widget` refs are the prototypical case, but non-reactive interaction
state — drag anchors, scrollbar-mode enums, layout caches, bool flags — qualifies equally. It stays a plain
ivar (not a `Source`); use it in place of a hand-written `@[Reconcile]` annotation. Reactive values always
use `reactive_property` (optionally `reconcile: true`). The rule of thumb is **Source-back what renders**.
