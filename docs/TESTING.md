# Testing a CrymbleUI app: by widget id, the way a use case reads

A use-case spec should read like the use case: open a file, right-click a row, choose Rename,
type the new name, see it in the status bar. It should not know pixels, coordinates, SFML enums,
object ids or an app's internals. `CrymbleUI::Testing::Driver` (`src/testing/driver.cr`) is the tool
for that; this page is its philosophy and its reference.

```crystal
require "crymble-ui/testing/driver"

ui = CrymbleUI::Testing::Driver.new(MyApp.new)
ui.click "menu_file"
ui.click "menu_load"
ui.within(ui.only("load_dialog_")) { ui.open_file "dirbrowser", "examples/demo.emb" }
ui.right_click "field_sales_region"
ui.click "ctx_rename"
ui.type "renamer_name", "Area"
ui.press "Enter"
ui.text("statusbar").should contain "Renamed"
```

A worked example to start from: tutorial 29 - a small app (`tutorials/tutorial-29.cr`) and its spec
(`spec/tutorials/tutorial_29_spec.cr`). The spec requires the app's own file; its run line is guarded
with `{% unless @top_level.has_constant?("Spec") %}` (`require "spec"` defines `Spec`), so requiring
it opens no window.

## The rules

1. **Act on logical ids.** A widget a user acts on carries a stable id. A spec names that id, never
   a position.
2. **Ids are handles, never content.** An id is never rendered and never derived from user-visible
   text (a label, a name, hover text): a rename would change the handle, and widget ids also drive
   reconciliation across rebuilds. Derive ids from identities that survive a rename.
3. **Never pixels, never internals as a proxy.** Assert what the user can see through the Driver's
   reads - text, enabled, checked, present, focus - not an adapter's fields or a model.
4. **A flow the Driver cannot reach is a harness gap** to fix here, not a reason to test lower.

## Trigger semantics

An act runs what real input runs AROUND a handler and skips only finding the widget by position:

1. close the popups a click at the widget's centre would close (`App#dismiss_popups`) - for
   `drag_cell`, at the cell it presses;
2. close open menus unless the widget is inside an overlay surface (`App#dismiss_menus`);
3. bring the containing panel to front;
4. call the handler (`trigger_click`, `trigger_right_click`, `DragManager#drag_onto`, typing);
5. settle - render until nothing changes (a requested rebuild is applied by the first frame).

The Driver's lookup covers what a user can see: the window's tree, then its overlays (popups,
context menus). The app's own lookups (`App#find`, `Widget#find_by_id`, `find_all`) stay tree-only on
purpose: menus close each other through `find_all`, and seeing into popups would change that.

### What the trigger semantics leave out

Where each of these is covered instead:

| Not covered by the Driver | Owned by |
|---|---|
| hit-testing and occlusion - a button under a modal popup still fires by trigger, and a popup whose area contains the clicked widget stays open | `spec/ui/popup_event_blocking_spec.cr` |
| drag thresholds and hover feedback during a drag | `spec/core/drag_drop_spec.cr` |
| point spaces (a widget inside a scroll view) | `spec/input/event_point_space_spec.cr` |
| the WindowPanel title-bar right-click (`on_title_bar_right_click_handler`, gated on the title bar's area) | no spec yet - a known gap |

Three acts go by position. `hover(id)` does, because the hover path is position-based: it raises when
something else sits on the widget's centre. `click_cell` and `drag_cell` do, because a grid acts on
the cell under the mouse: see Grids below.

## Reference

**Lookup.** `find(id)` - raises, naming the ids that look like the missing one. `present?(id)`.
`only(prefix)` - the one widget whose id starts with `prefix` and has no ancestor that also does
(a dialog by its kind, not the fields inside it). `within(id or widget) { ... }` - scope every lookup
to a subtree.

**Acts** (each settles; none returns a value):

| Act | Notes |
|---|---|
| `click(id)` | raises when the widget is disabled - present but refusing, and for a widget inside a grid (the grid takes every press: `click_cell`) - the grid itself is clicked |
| an act whose handler raises | raises - a spec never passes over a failed assert inside a handler. A REFUSAL the app reports (real input hands it to `on_event_exception`; embrace shows it in the status bar) is asserted with `expect_reported(message) { ... }`: inside it the Driver reports as real input does, and every exception must match. Covers `press` and `keys` too, frames included (a report there aborts the remaining events). The Driver's own refusals (`Driver::Refusal`, an `ArgumentError`) always raise |
| `right_click(id)` | raises when no handler sits at or above the widget |
| `drag(id, onto: id)` | the Draggable and the DropTarget at or ABOVE each id, as real input finds a draggable from the widget under the mouse; the drop lands at the target's centre; raises with the reason when refused ("\"shut\" is not shown") |
| `can_drop?(id, onto: id)` | whether that drag would land - for asserting a refusal |
| `type(id, text)` | raises unless the widget can take focus, and for a widget inside a grid (the grid keeps the focus and hands keys to its cursor cell: `focus_cell`); focuses it, then types as SFML delivers typing |
| `press(chord, on: id?)` | `"Enter"`, `"Escape"`, `"Ctrl+S"`, `"Ctrl+Shift+Z"`; `on:` focuses first, refused as for `type` |
| `keys(events)` | raw events built with `Testing::Keys`, when `type`/`press` cannot say it |
| `hover(id)` | the app's real hover path at the widget's centre |
| `advance(seconds)` | lets time pass for the app's timers (accumulates; never behind the real clock) - including those its `on_start` started, which the first frame runs |

`press` takes SFML's key names (`SF::Keyboard::Key`): `Enter`, `Escape`, `Tab`, `Space`,
`Backspace`, `Delete`, `Insert`, `Home`, `End`, `PageUp`, `PageDown`, `Left`, `Right`, `Up`, `Down`,
`A`-`Z`, `Num0`-`Num9`, `F1`-`F15`. An unknown name raises (`"Esc"` is not one).

**Grids and file browsers** (VirtualMatrix): `focus_cell(matrix_id, row, col)` focuses the matrix
on a cell and brings it into view - an off-screen cell has no widget until the matrix materializes
it. `cell_text(matrix_id, row, col)` is what the cell DISPLAYS, not the stored value (a stored 42.0
may display as "42"); it moves the cursor there. `select_file(matrix_id, name)` and
`open_file(matrix_id, name)` click a DirBrowser row once or twice, by file name, as `click_cell` does; a path
`"sub/x.emb"` opens each directory on the way. The browser acts on a second click whenever it comes, so
`open_file`'s second click is not refused as a double-click. `cursor(matrix_id)` reads the cursor cell and moves
nothing.

`click_cell(matrix_id, row, col)` clicks one cell as the mouse does. It brings the cell into view, then
presses and releases through the grid's own handlers with frames between. The release over the grid
then clicks the cell's widget, so a checkbox cell toggles. Its limits:
- A merged cell is clicked by its top-left.
- A second click on the same cell straight after the first is a double-click and is refused (see below).

`right_click_cell(matrix_id, row, col)` right-clicks one cell the same way: the grid puts its cursor there and
hands the press to the right-click handler at or above it (a host's cell menu), at the press point in window
space. No click follows a right release, and a right press is never a double-click. Its limits are
`click_cell`'s.

`drag_cell(matrix_id, row, col, onto: {matrix_id, row, col})` drags one cell onto another, in the
same grid or another one, as the mouse does. It presses the source cell through the matrix's own
`on_mouse_down`, lets frames run, and drops at the target cell's centre (for a merged cell, the
centre of its top-left part) with `DragManager#drag_onto`. Each cell is named by its top-left (a merge is one cell). Only the source
is brought into view: a real drag never moves the target's cursor, so the target must already be on
screen. It raises (`Driver::Refusal`) for what real input would not turn into this drag, naming why:
- a cell covered at its centre: the press must hit the grid, and the drop must reach it the way a
  moving drag finds its target - where a click there would land, so any panel in front covers it.
  Also a cell under a sticky band that takes the drop;
- a target not on screen;
- an empty source;
- the target refusing the drop.

A press that does not become a drag is released as App releases it: its pending drag is cancelled, then
`on_mouse_up` - never a click, so a refused act triggers no cell.
Two refusals are limits of this act, not app behaviour:

- **The same cell as source and target.** A user can drag out of a cell and back; this act has one
  point per cell, so a press and release that close is a click.
- **A second `drag_cell` from the same cell straight after the first.** That is a double-click: the
  grid times clicks with the real clock, which `advance` cannot move. Drag another cell, or set the
  grid's `double_click_interval` shorter.

**Reads.** `text(id)` - a Text's text, a Button's or a Checkbox's label, a TextInput's value, a StatusBar's text, a ComboBox's selected value;
any other widget answers its Text descendants' texts joined with a space, in tree order.
`enabled?(id)`, `checked?(id)` (Checkbox, MenuItem), `focused_id`.

## Lower-level tools

`TestRenderer` (`src/testing/test_renderer.cr`) renders headlessly and simulates the mouse by
coordinates - the tool for the coordinate specs above. Its `mouse_down`/`mouse_move`/`mouse_up` go
through `MouseDispatch`, the path SFMLRenderer's run loop takes: a press focuses what it hits, and a
move drags while a button is down and hovers otherwise. `TestRenderer#deliver` hands keyboard and
mouse events over in the batches the run loop forms (`EventBatch`), one frame per batch: the path for
anything that depends on how QUEUED input interleaves with frames - a click and the typing after it
arriving together, a script typing. Build the events with `Testing::Keys` (`typed`, `click_at`,
`press_at`, `move_to`, ...). `TestRenderer#key_down` renders after every key and so cannot show a
batch. The Driver's acts are not affected: they trigger handlers by id, not through this path.

Nothing releases an app a spec is done with: its widgets stay registered with the global zoom and theme
Sources, and a grid's layer-hosted overlays hold the grid, so a suite's memory grows with every app it
builds. Arm `TestRenderer.rendered_apps = [] of App` once, and call `TestRenderer.release_rendered_apps`
at the top of `Spec.before_each` (after clearing focus, before `Layer.clear_registry`): every app a
TestRenderer rendered - the Driver's too - is released the way a rebuild releases a discarded tree. An
app, and its renderer, must then not outlive its example. crymble-ui's own `spec/spec_helper.cr` does.
