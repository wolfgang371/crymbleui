# Migration guide

Breaking changes for code built on CrymbleUI, newest first. See `docs/REACTIVITY.md` for the *why*.

---

## A panel the user never moved keeps its bottom inside the window; `user_moved` is `user_moved_x` (1.8.0)

A WindowPanel's y is now fitted like its x: unless the user moved it vertically, it is the app's ask (the
build's `y:`, or the last `y=` / `move_to` from code), shifted up so the bottom stays inside the panel area,
the top winning for a panel taller than the window (the height itself is not capped). See ARCHITECTURE.md
"A panel lies inside its window". What an app or its specs may notice:

- A panel asked low in a short window opens higher than its `y:`; it lifts when the window loses height or
  its content grows past the bottom, and returns to its `y:` when there is room. A bottom-edge resize past
  the window makes it hop up on release.
- Panels asked at different `y:` can share one y in a short window (their x is fitted too): an app that
  cascades panels may want to step only as far as the window allows.
- `WindowPanel#user_moved` is renamed `user_moved_x`, beside the new `user_moved_y` (set by a drag that
  changed y, or a top handle). A spec that set `user_moved = true` for a "dragged" premise sets the flag of
  the axis it means.
- `y=` from code is an ask (as `x=` is): writing back the current value changes nothing.

---

## The panel in front holds the keyboard, and Tab stays inside it (1.8.0)

Keyboard focus follows the front WindowPanel: whatever raises a panel - a press in it or on its title bar,
Ctrl+Tab, a panel the app opens or reopens, the panel open at launch - hands it the keyboard (its last widget,
else `home_focus`, else its first Tab stop). See LAYER_RENDERING_ARCHITECTURE.md "Keyboard and panels". What
an app or its specs may notice:

- Tab, Shift+Tab and the arrows no longer leave a WindowPanel, nor enter one from the window body. Inside a panel
  a grid keeps Tab for its cursor; Ctrl+Tab is the way out of the panel (not to the panel's other widgets).
- F6 / Shift+F6 walk the panel's parts - its Tab stops, whatever holds the keyboard: the way out of a grid. Taken
  before the widget, as Ctrl+Tab; an app's own F6 without a modifier no longer reaches it (Ctrl+F6, Alt+F6 do).
- Any raise moves the keyboard, and a press anywhere in a panel moves it there. Code that raised a panel and
  expected the keyboard to stay behind focuses after the raise. A build-time focus into a panel behind raises
  that panel - unless a panel opened in the same rebuild: the opening entry wins, over a build-time focus on a body
  widget or into a panel behind, and so does the launch.
- `Button#focus_on_click = false` keeps the keyboard where it is only within the button's own panel: a press in a
  panel behind still raises it, and the raised panel takes the keyboard.
- The panel open at launch holds the keyboard after the first frame. A spec that asserted "nothing focused" -
  or a button's untinted pixels - clears it first (`Widget.focus_manager.clear_focus`).
- Every panel shortcut follows the keyboard's panel: a widget of the window body no longer triggers the front
  panel's Enter / Escape / other shortcuts. When nobody holds the keyboard they go to the front panel, as before.
  A list open in a dialog takes Escape (it closes the list, not the dialog).
- Enter and Space press a focused Button, Checkbox, tab or section header first (`Widget#takes_activation_keys?`),
  before the panel's Enter shortcut.
- Disabled widgets, the widgets under a collapsed TreeNode and the inactive pages of Tabs are no Tab stops
  (`Widget#shown_children`).
- `window_panel(home_focus: "id")` names where the keyboard lands in a panel with no memory of one.
- Ctrl+Tab with one open panel enters it; Ctrl+Shift+Tab is the true reverse of Ctrl+Tab (it no longer flips the
  top two). Ctrl+Tab closes open popups and menus first.
- A WindowPanel without an id is no longer raised at every rebuild; a reopened panel (`open`, `toggle`, a build
  flipping `closed:`) is raised and takes the keyboard.
- `Widget#on_focus` no longer scrolls the widget into view - `FocusManager#focus(widget, reveal = true)` does
  (`Widget#scroll_into_view`, public, was the private `request_scroll_into_view`). An override of `on_focus` that
  relied on `super` for the scroll needs nothing; one that called `request_scroll_into_view` calls
  `scroll_into_view`.
- `FocusManager#reconcile_focus` returns a Bool; `FocusManager#cycle_panel` raises a single open panel instead of
  returning nil.
- The test Driver's acts focus a widget that takes focus on a click before raising its panel, as a press does;
  `focus_cell` / `cell_text` raise the grid's panel. New: `press_title(panel_id)`, `close_panel(panel_id)`.

---

## A render scale (`fitted { }`): primitives scale, and `Layer#size` is the scaled extent

`fitted { }` draws its subtree at a factor, through the existing renderer. Two consequences for code outside the
library:

- `DrawPrimitive#scaled(f : Float64) : DrawPrimitive?` is ABSTRACT. A primitive struct defined outside crymbleui
  must implement it: every position and extent multiplied by `f` (about the widget's origin), nil when nothing is
  left to draw. The library's own copy themselves and set the scaled fields:

  ```crystal
  def scaled(f : Float64) : DrawPrimitive?
    copy = self
    copy.bounds = DrawPrimitive.scale_rect(@bounds, f)
    copy
  end
  ```

- `Layer#size` is the layer's extent in buffer and window pixels: `content_rect.size * render_scale`. It equals
  `content_rect.size` for every layer but a fitted's. Code that wants the layer's pixel extent reads `size`;
  `content_rect.size` is the content-space size (unscaled). `Layer#bounds` is `(content_rect.position -
  owner.enclosing_scroll, size)`.
- A full-area background is `fill_background(bounds, color)` (it marks the fill `covers`, so a scaled widget's
  background fills its device span exactly); a hand-written `fill_rect(Rect.new(0, 0, bounds.width,
  bounds.height), ...)` still works, but can leave an edge column below a fitted.
- `Widget#enclosing_scroll` asserts it is never asked inside a fitted: cross with `to_window` / `to_content` /
  `viewport_bounds`, which scale.

---

## One input model for a grid: the non-interactive mode, `SimpleMatrix` and the DSL `matrix` are gone

A grid had two input models: the default, where the grid takes every press and forwards it to the cell under its
cursor (proxy focus), and `interactive_cells = false`, where a click went straight to the widget under the point.
The second doubled every input rule a grid has (hit testing, the wheel, a press on a cell that leaves, focus inside
a cell) for one use - small static tables. It is removed, with the sugar built on it.

- `VirtualMatrix#interactive_cells` is gone. Every grid takes the press: a cell's widget hears a click through the
  grid's release (`trigger_click` forwarded to the cursor cell), a ComboBox cell opens on a double-click, keys go
  to the cursor cell. A cell widget is never hit, hovered, a drop target or focused on its own.
- The DSL `matrix(...) { |m| m.header ...; m.row { |r| r << ... } }`, `SimpleMatrixAdapter` and
  `SimpleMatrixBuilder` are gone. The sugar gave: any widget per cell, header rows that stay sticky, a size to
  content capped by `max_height`, no rulers, direct clicks. Replace it with one of:
  - `recursive_grid { [[a, b], [c, d]] }` - any widget per cell, direct clicks, sizes to content; no sticky
    header, no virtualization, no height cap (wrap it in `scroll_view(max_height: ...)` to scroll);
  - a `VirtualMatrix` with your own adapter, `shrink_to_content = true`, `show_rulers = false` and
    `max_height = ...` - sticky headers, virtualization and a height cap; the grid's input model (a cursor, a
    click through the grid, a ComboBox opened by a double-click). A sketch, for `rows : Array(Array(String))`
    with one header row:

    ```crystal
    class TableAdapter
      include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

      def initialize(@rows : Array(Array(String)))
      end

      # Row 0 last: the sticky tail of a scroll order reads DESCENDING (see MatrixAdapter#get_scrollorder)
      def get_scrollorder : {Array(Int32), Array(Int32)}
        {(1...@rows.size).to_a + [0], (0...@rows[0].size).to_a}
      end

      def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
        CrymbleUI::Text.new(@rows[row][col])
      end
    end

    grid = CrymbleUI::VirtualMatrix.new(adapter: TableAdapter.new(rows), id: "summary")
    grid.shrink_to_content = true
    grid.show_rulers = false
    grid.max_height = 200.0
    ```
- `Testing::Driver#click` and the keyboard acts (`type`, `press(on:)`) refuse a widget inside a grid, naming the
  cell act to use (`click_cell`, `focus_cell`); the grid itself is clicked and focused as before. `select_file` /
  `open_file` press the DirBrowser row through the grid, as the mouse does.

---

## A grid cell that owns a layer lives like any widget; a stuck scroller passes the wheel on

A grid cell holding a layer owner (a ScrollView, a LayerBox, a nested grid) was not composited until some later
layout re-collected the frame's layers, and kept its layers registered (and their GPU surfaces) after it left. A
scroll view that could not move the way the wheel went swallowed the event.

- **`on_mouse_wheel(delta, point, shift) : Vec2`** returns the part of `delta` the widget did NOT take, in the input
  frame (unswapped, whatever `shift` did); `App#handle_mouse_wheel` hands it to the next ancestor that handles the
  wheel, until nothing is left. A custom widget implementing it must return `delta` when it did nothing and
  `Vec2.zero` when it took everything. ScrollView and VirtualMatrix take an axis they moved on (a partial move
  takes it whole) and hand on an axis they cannot move on; there is no latching.
- `ScrollView#hands_wheel_on?` (set by a VirtualMatrix on its chrome view): the wheel over a grid's scrollbar does
  what it does over the grid.
- A cell leaving a grid is DETACHED, never destroyed - an adapter may hand the same widget back (one that keeps
  its cell widgets does). Its layers are retired (`Layer#retire`: surface disposed, out of the registry,
  widgets kept) and re-registered when it returns (`Layer#register`); its widgets let go of what they hold -
  their pull node (the subscription to the global zoom/theme Sources), their own surfaces, their slot stamp
  (`Widget#release_own`, `#release_subtree`; `dispose_subtree` uses the former, `#free_own_surfaces` is the
  surface part).
- `Widget#each_layer_in_subtree` - every layer a subtree owns (was LayerRenderer's private `add_subtree_layers`).
- `Layer.reorder!` / `Layer.order_version` also announce a change of the composite SET: a container attaching or
  detaching a layer owner without a layout (a grid's cells). The renderer re-collects at a frame's start and after
  any owner's flush that moved it (`LayerRenderer.frame_in_loop_recollect_count`).
- A layer owner is painted only in the layers it owns - never into a layer it merely stands on (a grid cell that is
  a ScrollView no longer has its scrollbars painted into the grid's buffer as well).

---

## A sticky cell is where it is painted; one placement rule for a grid

`VirtualMatrix#paint_shift_for` shifted sticky cells by the scroll on their scrolling axis - but the matrix moves
them itself (their bounds hold the scroll), so a header's `viewport_bounds`, dropdown, delivered click and drag
ghost sat a scroll away; the drag decal, the change glow and the cursor marks each re-derived cell positions from
float sizes and a float scroll.

- `paint_shift_for` shifts content cells only; sticky cells, rulers and anything else by nothing. Anything that
  compensated for the double shift (added the scroll back for a header) must stop.
- New: `VirtualMatrix#painted_rect(region, pitch = true)` / `#painted_rects` - what of a region of the grid is
  painted, in the matrix's space (the visible part; nil when none) - the way to place anything on cells;
  `#painted_col` / `#painted_row` (a line), `#placed_col_start` / `#placed_row_start` (laid out),
  `#painted_scroll` (the whole scroll the grid paints with), `#placed_col_sizes` / `#placed_row_sizes`,
  `VirtualMatrix::Region`; `ScrollView#sticky_regions` (the band geometry, clamped); `Rect#union`.
- `sticky_col_width_pixels` / `sticky_row_height_pixels` are sums of the placed (whole) sizes, and the ruler
  widths are whole - a fractional width no longer puts the band edge a fraction off its cells.
- `cell_screen_position` asks the placed cells (a test helper): it raises for a cell nothing of which is painted.
- `drag_ghost_bounds` answers the drag box's painted part; nothing painted is an EMPTY rect (never nil - nil
  meant "use the whole matrix"), and DragManager shows no ghost for an empty rect. A grid replaced mid-press, not
  yet laid out, answers with the box's lines.
- The Driver aims a cell act at the centre of what of the cell's own lines is painted (a merged cell: its top-left
  part); a target with nothing painted is refused as not on screen.
- The change glow draws once per cell BOX (a merged cell once, at the strongest alpha of its cells).

---

## A layer is painted in its owner's content space, composited where drawn, clipped by its scrollers

`compute_bounds_for_layer` used to answer in WINDOW space (`viewport_bounds`), and the renderer painted a layer's
widgets relative to that - so a layer owner inside scrolled content (a ScrollView in a ScrollView, a grid in a
ScrollView) repainted its content shifted by the ancestor's scroll, and nothing clipped a nested layer to its
scrollers (it composited over what lay above them).

- **`compute_bounds_for_layer` answers in CONTENT space** - where the widget is laid out (`absolute_bounds`).
  The Layer keeps it as `Layer#content_rect` (the render origin) and derives `Layer#bounds = content_rect -
  owner.enclosing_scroll` (window space, where it composites). An override still returning `viewport_bounds` shows
  itself as content drawn a scroll away after the first repaint inside a scrolled view - correct until something
  scrolls. `spec/rendering/layer_content_space_lint_spec.cr` catches the direct spelling only (it reads source
  text): a helper that returns `viewport_bounds` is not seen. A WindowPanel's rect is window space and must not
  sit under a scroller (`LayerSpaceError` under `-Dverify_bounds`).
- Render-side code reads `layer.content_rect`, composite-side `layer.bounds`, size-only `layer.size`.
- **The composite clip is declared per child**: override `Widget#clip_for(child)` (window space, nil for no
  limit) where a widget clips what it holds; the default clips to the owner's primary layer. `ancestor_clip`
  intersects the chain. `WindowPanel#descendant_layer_clip_bounds` is gone (its interior is its `clip_for`), as
  are `LayerRenderer#find_descendant_clip_bounds` and `SFMLRenderer#composite_viewport_cache_layer`;
  `composite_layer_to_window(layer, clip)` takes the clip, and every composite goes through
  `LayerRenderer#composite_region`.
- `Widget#enclosing_scroll` is public; it, `viewport_bounds` and `ancestor_clip` stop shifting/clipping after an
  overlay (a popup places itself in window space). A tree popup with a target is clamped into where its parent is
  DRAWN and stays where it opened until a re-layout; one without a target is placed at its layout position as
  painted.
- A LayerBox is placed where it is laid out (`absolute_bounds`), not at its parent-relative bounds.
- `Widget.absolute_bounds_count` now counts parent-chain STEPS in every geometry walk (`viewport_bounds`,
  `enclosing_scroll` and `ancestor_clip` too), so walks compare by cost; budgets written against the old count
  read higher numbers.

---

## One composite order: a layer composites within the layer it is painted into

Layers used to composite by (the nearest panel's z, then a flat layer z), with every layer owner adding its offsets
to its parent's z - so a scroll view nested in a grid cell sorted its scrollbar over the grid's sticky header, and
bring_to_front re-based every nested z. Now `Layer.composite_order(root)` is the one order (the renderer, a frame
capture, `Window#collect_all_layers`, `RenderDebug.dump`, and - backwards - hit testing): a layer composites
directly above the layer it is painted into (`Widget#painting_layer`), below that layer's later siblings.

- `z_index` of a nested layer is LOCAL: it orders its owner's own layers only. `parent_layer_z_index`,
  `ScrollView#update_layer_z_indices` and the base-z parameters are gone; ScrollView and VirtualMatrix use local
  constants (VirtualMatrix: CONTENT_LAYER_Z 1, CURSOR_OVERLAY_Z 2, DRAG_OVERLAY_Z 3).
- `LayerOwner#on_ancestor_z_index_changed(base_z)` / `Widget#notify_layer_owners_z_index_changed(z)` became
  `on_ancestor_raised` / `notify_layer_owners_raised`: a raised panel's layer owners repaint; order is not theirs.
- New: `Widget#ranks_children?` / `#composite_rank(owner)` (a container ranks what is painted into its layers -
  VirtualMatrix its chrome over its cells, Window its own menubar and statusbar over every panel),
  `Widget#painting_layer`, `Widget#children_in_hit_order` (use it in any hit_test that walks children),
  `#composites_as_overlay?` (Popup), `Layer.order_version` / `Layer.reorder!`, `Layer.strict_nesting` /
  `Layer.orphaned_nestings`, `CompositeOrderError`. `RenderDefect` is the common base of the errors both frame
  loops let out of recovery.
- Behaviour: the window's menubar and statusbar composite (and take clicks) over every panel; a panel drag stops
  at the panel area, between the bars; a LayerBox composites within the layer it sits in, by its z; plain window
  content always under panels (even a z-0 one); `Window#collect_all_layers` returns composite order, not z order;
  `Popup#compositing_z_index` returns its z (overlay status is `composites_as_overlay?`);
  `Window#sorted_children` / `Widget#sorted_children` are removed.

---

## The drop highlight shows only what is visible of its target, in the target's place in the stack

The highlight layer used to cover the target's whole `viewport_bounds` at z 1000 - over a scroll view's
edge, a panel in front, a grid's sticky band. Now its bounds are the target's new `Widget#visible_bounds`
(nil when nothing shows: then there is no highlight), and the renderer composites it directly after the last
layer that paints the target (`Layer#composite_anchor`).

- `DragManager::HIGHLIGHT_Z_INDEX` is removed.
- `highlight_layer.bounds` is the VISIBLE part of the target; code reading it as the full `viewport_bounds`
  changes. A hidden highlight has no `composite_anchor` (its bounds used to be moved to -1000).
- The drag's ghost and highlight layers are released when the drag ends (`highlight_layer` / `ghost_layer`
  are nil again); `Layer.cleanup_orphaned_layers` judges owned layers only - an ownerless layer is its
  creator's to release, with the new `Layer#release(root)`.
- `DropTarget#highlight_color`'s default is the theme's `drag_highlight` (was a fixed light blue).
- `Widget#containing_layer` (was the protected `containing_layer_for_repair`) and `Rect#intersection` are new
  public API.

---

## Panel shortcuts are keyed by the panel, not its path; a drag follows the tree under a still pointer

`ShortcutManager#register(shortcut, ShortcutContext::Panel, panel)` and `#trigger(shortcut, panel)` take the
panel widget itself (were its `path_id`): two panels with the same path - no id, the same title - no longer
share one set of shortcuts (either one's key ran the last-registered handler). `trigger` needs the LIVE panel
(found after the last rebuild). `ShortcutManager#clear_panel` is removed (it had no callers).

```crystal
# before
Widget.shortcut_manager.trigger("Escape", panel.path_id)
# after
Widget.shortcut_manager.trigger("Escape", panel)
```

During a drag, the drop target, its highlight and a grid's target cell now follow what is under the pointer
when the tree moves under it (a wheel scroll, a re-layout) - re-resolved once a frame and at the release, so
the drop lands where the highlight shows. `DropTarget#on_drag_over` is therefore also called once a frame
while the pointer is still: keep it cheap and idempotent.

---

## A grid refuses another grid's cell; `CellDragData` names its source grid

A cell dragged onto a DIFFERENT grid used to be applied there as that grid's own move - the source's
coordinates on the target's data. Now a grid takes only its own cells: an untagged grid its own (by its path,
id else index and class per ancestor - stable across a rebuild), tagged grids those with the same
`drag_owner_key`. Another owner's cell goes to `cross_drop_handler` if one is set, else it is refused (no
highlight, no drop); an untagged cell from another grid is refused everywhere - it has no owner to route to.

`CellDragData.new(row, col, display, source_path:, owner_key: nil)` - `source_path` is new and required
(named); `owner_key` keeps its meaning and becomes a named argument. Update direct constructions:

```crystal
# before
CrymbleUI::CellDragData.new(0, 0, "R0C0", owner_key: "shape-B")
# after
CrymbleUI::CellDragData.new(0, 0, "R0C0", source_path: "...", owner_key: "shape-B")
```

---

## `VirtualMatrix#drag_source_was_preexisting` is removed

A drag source set from outside (`drag_source_cell=`, e.g. a cut highlight) is now kept by the grid itself: a
press remembers it, and whatever of that press does not end in a drop puts it back - a click on another cell, on
an empty cell, a drag dropped nowhere. Stop setting the flag; setting `drag_source_cell` is enough. After a DROP
the source is cleared (rows may have moved); re-arm it from `on_cell_drop_handler` if it should outlive the move.

A cell drag also survives a rebuild between the press and the drag threshold: the payload is the gesture's,
taken from the pressed instance, and the rebuilt grid takes the drag over. For a `Draggable` of your own this
means `get_drag_data` may be asked while the press is pending (a rebuild), not only when the drag starts, and
`on_drag_start` may reach the instance a rebuild put in place of the one pressed - which is then the one that
hears `on_drag_end`. `DragManager#cancel_drag` now calls `on_drag_end` only for a drag that started. A host that sets
`drag_source_cell` while the button is held (a cut during the press) now sees it cleared after that drag DROPS,
as after any drop - before, it stayed marked on a row the move had shifted.
`App#rebuild` hands the drag, and the pressed widget, to the widgets reconcile paired them with
(`DragManager#rebind`, which takes that resolver as a block; was `DragState#update_widget_references` with a
path search) - two id-less siblings no longer share a re-find. A drag whose source a rebuild removes ends
(no `on_drag_end`); a target a rebuild replaces hears `on_drag_enter` and is hovered.

---

## `TestRenderer#render_layer_count` and `#compositor_skip_count` are removed

Neither was ever incremented - both read 0 whatever happened - so an assert on them could not fail.
Count rendered layers with `LayerRenderer.frame_layer_count`.

`TestRenderer#settle_rendering` now stops where the live loop would idle (a pending rebuild, the input barrier,
or a moved frame aggregate) instead of always rendering `max_frames` frames. A spec that relied on the extra
frames was relying on idle composites.

---

## `SFMLPaintContext` and `LibGL` are removed; a window-direct draw refuses clips

`CrymbleUI::SFMLPaintContext`, `SFMLRenderer#paint_context` and the top-level `lib LibGL` (with its
`@[Link("GL")]`) are gone: the paint context was constructed but never drew, and it was the last raw
GL scissor path. SFML links GL itself.

`App#overlay_primitives` and `Renderer#render_primitives` draw straight to the window, which has no
clip stack. A `PushClip`/`PopClip` there used to be IGNORED - its ink drew outside the clip. It now
raises `WindowDirectClipError`, before anything of the list is drawn, and frame recovery does not
swallow it. Draw clipped content in a widget instead (`PrimitiveBuilder#clipped`).

---

## `Testing::WidgetTester` is removed - use `Testing::Driver`

```crystal
# before
tester = CrymbleUI::Testing::WidgetTester.new
tester.pump(app)
tester.tap("save")
tester.text("status")

# after
require "crymble-ui/testing/driver"
ui = CrymbleUI::Testing::Driver.new(app)
ui.click "save"
ui.text("status")
```

WidgetTester built and laid out the tree but never rendered a frame, so anything a frame does - a
requested rebuild, a flush, an overlay's layout - happened only as far as it reimplemented it. The
Driver renders headlessly (TestRenderer) and runs what real input runs around a handler; see
`docs/TESTING.md`. `find_by_path`, `find_all`, `root` and `window_size` have no Driver counterpart:
a use-case spec names widgets by id, and reaches the app through `ui.app` when it must.

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
copied are never trimmed. A consumer that knows its payload's format can read it first through
`TextInput#paste_transform` (additive, off by default; nil from it means "not my format"); the
flattening applies to what it returns.

**`TextInput` gained a `multiline:` flag** (constructor and all three `text_input*` DSL helpers),
default `false`, which changes two things and only two: Alt+Enter / Ctrl+Enter insert a hard line
break, and a pasted break SURVIVES instead of becoming a space (tab still becomes a space on both
paths — it is the TSV field separator — and only a TERMINATING break is trimmed, so a leading blank
line is kept as content). DISPLAY is not gated by it: any `TextInput` handed a value containing `\n`
now measures, centres, carets and marks it honestly, because a consumer can set one through `value=`
or an adopted `bind:` Source and a widget that renders what it cannot describe is worse than either.
Consequently `measure_text` reports a taller box for a multi-line string (see ARCHITECTURE.md), so a
`Text` or `Button` label containing a break now lays out at its true height rather than overflowing
a one-line box.

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
