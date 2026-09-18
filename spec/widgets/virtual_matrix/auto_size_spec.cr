require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/widgets/virtual_matrix/adapter"
require "../../../src/widgets/text_input"
require "../../../src/testing/test_renderer"

# The matrix sizes its lines to their content.
#
# The measurements this rests on (embrace's design notes, spikes v4/v6/v7):
#   · a programmatic `col_width` does NOT reflow a live cell — the creation loop skips
#     already-laid-out cells, so the model says one thing and the pixels another;
#   · the drag branch DOES reflow, but it raises without a gesture
#     (`mark_ruler_widgets_dirty`) and cannot express a bulk change: it skips content columns
#     left of `resize_index`, measured leaving one at 100px/x=143 while its model said 240px;
#   · faking `resize_axis` is unsafe — a later mouse-up then persists auto widths into
#     `custom_col_widths`, overwriting what the user had dragged.
# Hence an axis-free entry point of its own, exercised below.

# Cells are TextInputs so they can report a content width. Column 1 is deliberately
# much wider than the rest.
class AutoSizeAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
    @wide = {} of Tuple(Int32, Int32) => String
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def text_at(row : Int32, col : Int32) : String
    @wide[{row, col}]? || (col == 1 ? "a rather wide value here" : "x")
  end

  def set(row : Int32, col : Int32, value : String) : Nil
    @wide[{row, col}] = value
  end

  def cell_read(row : Int32, col : Int32) : String
    text_at(row, col)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: text_at(row, col))
  end
end

# Same content, but with column 0 at the TAIL of the scroll order — which is how a sticky
# column is expressed, and what embrace's grids always look like. A headerless adapter has
# sticky_col_count 0 and therefore cannot exercise the corner strip at all.
class StickyAutoSizeAdapter < AutoSizeAdapter
  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows, cols = super
    {rows, cols[1..] + [cols[0]]}
  end

  def cell_get_header_info(row : Int32, col : Int32) : Tuple(Bool, Int32)?
    col == 0 ? {false, 0} : nil
  end
end

# The ROW dual of the fixture above: row 0 at the TAIL of the row order, which is how a sticky
# header row is expressed. Nothing else in the suite has a sticky row AND content-bearing cells,
# so the row half of the exclusion could not be tested at all before this.
class StickyRowAutoSizeAdapter < AutoSizeAdapter
  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows, cols = super
    {rows[1..] + [rows[0]], cols}
  end

  def cell_get_header_info(row : Int32, col : Int32) : Tuple(Bool, Int32)?
    row == 0 ? {true, 0} : nil
  end
end

private def rendered_matrix(adapter, w = 700, h = 400)
  matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "auto_size_test")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(w, h)
  renderer.settle_rendering(app)
  {matrix, app, renderer}
end

describe "VirtualMatrix auto-size" do
  before_each { CrymbleUI::Widget.font = CrymbleUI::Testing::TestFont.new }

  it "off by default: nothing about sizing changes" do
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, _app, _r = rendered_matrix(adapter)
    matrix.auto_size.should be_false
    matrix.get_col_width(1).should eq(CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH)
  end

  it "sizes a column to its widest cell, and the LIVE cell reflows with it" do
    # The assertion is on the laid-out cell, never on get_col_width: those two disagreeing is
    # precisely the defect that made the first design look like it worked.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    narrow_before = matrix.active_cells[{0, 0}]?.try(&.bounds.width)
    wide_before = matrix.active_cells[{0, 1}]?.try(&.bounds.width)
    narrow_before.should_not be_nil
    wide_before.should eq(narrow_before) # both at the default to begin with

    matrix.auto_size = true
    renderer.settle_rendering(app)

    wide_after = matrix.active_cells[{0, 1}].bounds.width
    narrow_after = matrix.active_cells[{0, 0}].bounds.width
    wide_after.should be > wide_before.not_nil!   # the wide column grew ...
    narrow_after.should be < wide_after           # ... and the narrow one did not follow it
  end

  it "reflows EVERY changed column, including one left of another (the drag branch cannot)" do
    # Spike v7: with two non-sticky content columns changed and the drag branch armed on the
    # right-hand one, the LEFT column kept both its stale width and its stale x. The auto path
    # must not inherit that skip.
    adapter = AutoSizeAdapter.new(6, 3)
    adapter.set(0, 0, "also quite a wide value")
    matrix, app, renderer = rendered_matrix(adapter)
    before_left = matrix.active_cells[{0, 0}].bounds.width
    before_right_x = matrix.active_cells[{0, 1}].bounds.x

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.width.should be > before_left      # left widened ...
    matrix.active_cells[{0, 1}].bounds.x.should be > before_right_x       # ... and pushed its neighbour
  end

  it "keeps the computed sizes across a structural announce" do
    # flush_invalidate_all reinstalls adapter.get_sizes over the widths, so a re-measure that
    # ran BEFORE it would be silently overwritten and the mode would look like it stopped
    # working after any data change. Measured as 18.0 -> 5.0 during the plan gate.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    sized = matrix.active_cells[{0, 1}].bounds.width
    sized.should be > matrix.active_cells[{0, 0}].bounds.width

    adapter.invalidate_all!
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 1}].bounds.width.should eq(sized)
  end

  it "re-measures when the zoom changes" do
    # A cell's text scales with zoom; its padding and border do not. Sizes computed at one zoom
    # therefore stop fitting at another, and the cut marker would return under a mode that
    # promises to fit.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    at_default_zoom = matrix.active_cells[{0, 1}].bounds.width

    begin
      CrymbleUI::FontSizing.zoom_in
      renderer.settle_rendering(app)
      matrix.active_cells[{0, 1}].bounds.width.should_not eq(at_default_zoom)
    ensure
      CrymbleUI::FontSizing.zoom_out
      renderer.settle_rendering(app)
    end
  end

  it "grows a line for a live cell WITHOUT replacing the widget (the editor must survive)" do
    # This is the whole reason the incremental path exists: the caller is typing into that cell,
    # so tearing it down would take the editor and the caret with it. The structural re-measure
    # destroys and rebuilds; this one must not.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    cell = matrix.active_cells[{0, 0}]
    before_width = cell.bounds.width

    matrix.fit_cell_to_content(0, 0, before_width + 120.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].should be(cell)          # the very same widget object
    matrix.active_cells[{0, 0}].bounds.width.should be > before_width
  end

  it "never narrows a line below what its OTHER cells still hold" do
    # This was "grows only" until 2026-09-17, and its rationale was that shrinking per keystroke
    # would "narrow the column below what OTHER rows hold, banding cells the user is not editing".
    # That concern is exactly right and is now enforced directly rather than by refusing to shrink
    # at all: the matrix records the two largest cells per line, so a line falls back to the
    # RUNNER-UP and never below it. The other half of the old rationale — "a full-column rescan
    # every time" — costs nothing now either, since the runner-up is already known.
    #
    # Column 1 is wide in EVERY row of this fixture, so shortening one row's cell must move nothing.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    wide = matrix.active_cells[{0, 1}].bounds.width

    matrix.fit_cell_to_content(0, 1, 20.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 1}].bounds.width.should eq(wide),
      "the five other rows still hold the wide value, so the column must not have narrowed"
  end

  it "does narrow the line when the cell that was holding it wide is the one edited down" do
    # The counterpart, and the report that prompted the change: a column widened by one long value
    # stayed wide forever after that value was shortened, because the shrink was left to a
    # structural re-measure that an ordinary edit never triggers.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    narrow = matrix.active_cells[{1, 0}].bounds.width # a neighbour row in the same column

    matrix.fit_cell_to_content(0, 0, 300.0, 20.0, 1)
    renderer.settle_rendering(app)
    matrix.active_cells[{0, 0}].bounds.width.should be > narrow

    matrix.fit_cell_to_content(0, 0, 20.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 0}].bounds.width.should be_close(narrow, 1.0)
  end

  it "the incremental path leaves gesture state and dragged sizes alone" do
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.fit_cell_to_content(0, 0, 400.0, 20.0, 1)
    renderer.settle_rendering(app)

    matrix.resize_axis.should eq(CrymbleUI::VirtualMatrix::ResizeAxis::None)
    adapter.custom_col_widths.should be_nil
  end

  it "does nothing when the mode is off" do
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    before = matrix.active_cells[{0, 0}].bounds.width
    matrix.fit_cell_to_content(0, 0, 400.0, 20.0, 1)
    renderer.settle_rendering(app)
    matrix.active_cells[{0, 0}].bounds.width.should eq(before)
  end

  it "re-lays-out the sticky corner widgets, which change size with the columns" do
    # Field report: with the mode on, the leftmost header label drifted off its column. The
    # corner strip is what labels the STICKY column, and its WIDTH is ruler + sticky column —
    # so when auto-size narrows that column the strip must be re-laid-out, exactly as the drag
    # path does in flush_resize_update. Invalidating its primitive cache is not enough: it keeps
    # drawing inside a box sized for the old widths, overlapping the first data column.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    renderer.settle_rendering(app)
    matrix.sticky_col_count.should eq(1) # instrument: the fixture really has a sticky column

    matrix.auto_size = true
    renderer.settle_rendering(app)

    expected = matrix.ruler_col_width_pixels + matrix.sticky_col_width_pixels
    if corner = matrix.corner_ruler_widget
      corner.bounds.width.should be_close(expected, 0.5)
    end
    expected_h = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
    if strip = matrix.corner_row_strip_widget
      strip.bounds.height.should be_close(matrix.sticky_row_height_pixels, 0.5)
    end
  end

  it "invalidates the RULERS' cached primitives, which is what the screen actually draws" do
    # Field report: the horizontal ruler kept the default ~100px pitch while the columns below
    # were auto-sized. The rulers are CachePolicy::Dynamic, so the screen shows their CACHED
    # primitives — and flush_auto_size never invalidated them (only the typing path did). Note
    # that calling `to_primitives` in a test recomputes and therefore CANNOT see this: the
    # earlier alignment examples passed while the app drew a stale ruler.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    renderer.settle_rendering(app)
    ruler = matrix.col_ruler_widget.not_nil!
    ruler.has_valid_primitive_cache?.should be_true # instrument: it really is cached to begin with

    matrix.auto_size = true
    matrix.pre_render_flush # the frame's flush, WITHOUT a re-render rebuilding the cache

    ruler.has_valid_primitive_cache?.should be_false
    # Every ruler surface draws from the same sizes, so every one of them goes stale together.
    matrix.row_ruler_widget.try { |w| w.has_valid_primitive_cache?.should be_false }
    matrix.corner_ruler_widget.try { |w| w.has_valid_primitive_cache?.should be_false }
    matrix.corner_row_strip_widget.try { |w| w.has_valid_primitive_cache?.should be_false }
  end

  it "invalidates them for the TYPING path too, not just the toggle" do
    # fit_cell_to_content changes a column width per keystroke; the ruler is just as stale then,
    # and this is the path a user spends the most time in.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    ruler = matrix.col_ruler_widget.not_nil!
    ruler.has_valid_primitive_cache?.should be_true

    matrix.fit_cell_to_content(0, 1, 400.0, 20.0, 1)
    matrix.pre_render_flush

    ruler.has_valid_primitive_cache?.should be_false
  end

  it "invalidates them when the mode is switched OFF and the adapter's sizes come back" do
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    ruler = matrix.col_ruler_widget.not_nil!
    ruler.has_valid_primitive_cache?.should be_true

    matrix.auto_size = false
    matrix.pre_render_flush

    ruler.has_valid_primitive_cache?.should be_false
  end

  it "sizes a SMALL grid, where every line derives as sticky" do
    # FIELD REPORT (2026-09-02): on a 2-column grid the mode did nothing at all. `derive_sticky_count`
    # walks the scroll order from the end and counts the trailing entries that form {0..N-1}; for
    # two columns the order is [1, 0], so BOTH qualify and the count equals the column count. The
    # The sticky-line exclusion read that as "these are pinned headers" and skipped every line — the feature
    # disabled itself on any grid small enough. Diagnostic from the running app: `sticky=(1,2)` with
    # `cols=2 rows=1`, `widest=[18.0, 10.0]`, and `widths AFTER == widths BEFORE`.
    #
    # "Every line is sticky" means the grid does not scroll at all, and a line that cannot scroll
    # because there is nothing to scroll has no unreachable overflow — the case the exclusion exists
    # for cannot arise. So it must not fire here.
    adapter = StickyAutoSizeAdapter.new(1, 2) # order [1, 0], exactly embrace's shape
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_col_count.should eq(2) # instrument: the derivation really does call both sticky
    matrix.sticky_row_count.should eq(1) # ...and the single row too — the app reported (1,2)
    before = matrix.get_col_width(1)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(1).should_not eq(before)
  end

  it "COMPACTS a sticky column whose content is short" do
    # Field report: with the mode on, the record-label column stayed at its default width beside
    # compacted data columns — a wide empty stripe, which is not "sized to content" by any reading.
    # Shrinking a pinned line hides nothing: it is only GROWING one past a viewport it cannot
    # scroll that puts content out of reach.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    adapter.set(0, 0, "1") # a short record label, like a rank
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_col_count.should eq(1)
    before = matrix.get_col_width(0)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(0).should be < before # it compacted...
    matrix.get_col_width(0).should be >= 1.0   # ...but not past its own ruler label
  end

  it "sizes a STICKY column to its content, BOUNDED so the strip cannot swallow the viewport" do
    # Changed 2026-09-13. This asserted that a sticky line is never sized at all, because sizing it
    # past the viewport would put content where no gesture can reach — a pinned line does not
    # scroll. True, but banning growth made a too-narrow header column a DEAD END: the mode would
    # not widen it and the drag is refused while the mode is on, so the label stayed cut with no
    # way out ("I cannot resize c1 and c2 if auto-size is active").
    #
    # The invariant that actually mattered is kept, and asserted below: the pinned strip may not
    # take more than its share of the grid. Within that, it fits its content like any other line.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    adapter.set(0, 0, "a very long record label that would swallow the whole viewport")
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_col_count.should eq(1) # instrument: the fixture really has a sticky column
    sticky_before = matrix.get_col_width(0)
    neighbour_before = matrix.get_col_width(1)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(0).should be > sticky_before, "the header column stayed cut"
    matrix.get_col_width(1).should_not eq(neighbour_before) # the control moved too
    grid = 700.0 - matrix.ruler_col_width_pixels
    matrix.sticky_col_width_pixels.should be <= grid * 0.5 + 1.0,
      "the pinned strip took more than its share of the grid, so the content lost its room"
  end

  it "sizes a sticky column while TYPING too, under the same bound" do
    # The per-keystroke path writes @col_widths directly, so it needs the same rule as the toggle:
    # were it left refusing, typing into a header cell would re-cut the very column the toggle had
    # just fitted.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    sticky_before = matrix.get_col_width(0)
    neighbour_before = matrix.get_col_width(1)

    matrix.fit_cell_to_content(0, 0, 900.0, 20.0, 1) # a long value typed into the record label
    matrix.fit_cell_to_content(0, 1, 900.0, 20.0, 1) # the same into an ordinary column: the control
    matrix.pre_render_flush

    matrix.get_col_width(0).should be > sticky_before
    matrix.get_col_width(1).should be > neighbour_before
    grid = 700.0 - matrix.ruler_col_width_pixels
    matrix.sticky_col_width_pixels.should be <= grid * 0.5 + 1.0,
      "900px of typed content pushed the pinned strip past its share of the grid"
  end

  it "sizes a STICKY ROW on both paths, bounded by its share of the grid" do
    # Same change as the column above, on the other axis: 40 lines in a pinned header row used to
    # be left cut with no way to reveal them.
    adapter = StickyRowAutoSizeAdapter.new(6, 3)
    adapter.set(0, 1, (1..40).map { |i| "line#{i}" }.join("\n"))
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_row_count.should eq(1) # instrument
    sticky_before = matrix.get_row_height(0)
    grid = 400.0 - matrix.ruler_row_height_pixels

    matrix.auto_size = true
    renderer.settle_rendering(app)
    matrix.get_row_height(0).should be > sticky_before, "the pinned header row stayed one line tall"
    matrix.sticky_row_height_pixels.should be <= grid * 0.5 + 1.0

    matrix.fit_cell_to_content(0, 1, 60.0, 900.0, 40)
    matrix.pre_render_flush
    matrix.sticky_row_height_pixels.should be <= grid * 0.5 + 1.0,
      "the typing path grew the pinned row past its share of the grid"
  end

  it "a sticky column's cell still votes its LINE COUNT to its own row" do
    # The rule is per AXIS, not per cell: what a sticky column cannot do is drive its own WIDTH.
    # Its row scrolls normally, so a multi-line record label still grows it — which is what
    # "empty lines count as lines" promises for every value.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    adapter.set(2, 0, (1..8).map { |i| "l#{i}" }.join("\n"))
    matrix, app, renderer = rendered_matrix(adapter)
    before = matrix.get_row_height(2)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(0).should_not be > 20.0 # the width is still not sized
    matrix.get_row_height(2).should be > before  # ...but the row it lives in grew for it
  end

  it "a cut sticky cell can still be READ — the editor scrolls where the view cannot" do
    # This is what makes the sticky exclusion honest rather than a silent loss. The mode leaves a
    # header column at its own width, so a long record label is cut and the band lights; the value
    # is then reachable because the EDITOR scrolls its own content, even though the matrix cannot
    # scroll a line that is pinned. (Measured: offset 440px into a 63-character value in a 100px
    # box.) Together with the handle the sticky-line rule gives back, that is two ways out of a cut header cell.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    adapter.set(0, 0, "a record label far too long to fit in this narrow header column")
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_col_count.should eq(1) # instrument
    matrix.auto_size = true
    renderer.settle_rendering(app)

    # Focus the matrix first — Enter on an unfocused grid opens nothing, sticky or not.
    matrix.set_cursor_from_cell({0, 1})
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)
    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false)

    matrix.set_cursor_from_cell({0, 0})
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)
    editor = matrix.proxy_focused_widget
    editor.should be_a(CrymbleUI::TextInput)
    editor.as(CrymbleUI::TextInput).effective_scroll_offset.x.should be > 0.0
  end

  it "still RAISES a sticky column that sits below its own ruler label" do
    # The one thing the exclusion must not take away. `auto_col_floor_units` exists because the
    # ruler strip is the one place that paints no cut marker, so a cut `c1` label is a silent loss —
    # the exact thing the mode promises against. The floor is not content sizing: the mode may raise
    # a below-label header column, and never sizes it otherwise.
    adapter = StickyAutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.sticky_col_count.should eq(1) # instrument
    matrix.col_width(0, CrymbleUI::VirtualMatrix::MIN_COL_WIDTH) # dragged to the minimum
    renderer.settle_rendering(app)
    matrix.get_col_width(0).should be < 1.0 # control: it really is below the label floor now

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.get_col_width(0).should be > 1.0 # raised to fit its label...
    matrix.get_col_width(0).should be < 5.0 # ...and not sized to its content
  end

  it "gives a value all the room it needs — there is no product cap" do
    # Was capped at 30 units (~600px) wide and 10 units tall. Dropped on Wolfgang's call: a
    # value gets the room it asks for and the user scrolls. Asserted against the CONTENT, so
    # the example states the property rather than a number that would need editing next time.
    long = "wide " * 100
    tall = (1..40).map { |i| "line#{i}" }.join("\n")
    adapter = AutoSizeAdapter.new(6, 3)
    adapter.set(0, 1, long)
    adapter.set(1, 1, tall)
    matrix, app, renderer = rendered_matrix(adapter)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    fs = CrymbleUI::FontSizing.calculate_size(0)
    matrix.active_cells[{0, 1}].bounds.width
      .should be >= CrymbleUI::Widget.measure_text(long, fs).width
    matrix.active_cells[{1, 1}].bounds.height
      .should be >= CrymbleUI::TextLines.block_extent(40, fs)
  end

  it "still stops at the renderer's ceiling, which is not a policy but a driver limit" do
    # Past LayerRenderer::MAX_WIDGET_SPAN a widget is drawn TRUNCATED. A cell sized beyond it
    # would lose content while its cut marker — which compares the text against the box it was
    # given — still reported everything as fitting. So the box stops there and the marker,
    # which now has something to report, tells the truth instead.
    adapter = AutoSizeAdapter.new(6, 3)
    adapter.set(0, 1, "x" * 20_000)
    matrix, app, renderer = rendered_matrix(adapter)

    matrix.auto_size = true
    renderer.settle_rendering(app)

    fs = CrymbleUI::FontSizing.calculate_size(0)
    CrymbleUI::Widget.measure_text("x" * 20_000, fs).width
      .should be > CrymbleUI::LayerRenderer::MAX_WIDGET_SPAN # else the clamp never binds here

    width = matrix.active_cells[{0, 1}].bounds.width
    width.should be <= CrymbleUI::LayerRenderer::MAX_WIDGET_SPAN
    width.should be >= CrymbleUI::LayerRenderer::MAX_WIDGET_SPAN - matrix.grid_spacing - 1.0
  end

  it "grows a row for the breaks the user typed, and marks them when the cap cannot" do
    # Field report, twice. First round: a value ending in bare breaks grew its row but showed no
    # cut marker. Second round: sizing to the content-bearing lines instead CUT those breaks —
    # what the user typed stopped being visible. Breaks are content: the row grows for them.
    adapter = AutoSizeAdapter.new(6, 3)
    adapter.set(0, 1, "one line\n\n\n\n\n")
    matrix, app, renderer = rendered_matrix(adapter)
    default_h = matrix.active_cells[{0, 1}].bounds.height

    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 1}].bounds.height.should be > default_h
  end

  it "hands the sizes it computed over to the adapter when the mode goes off" do
    # Switching off means "I'll take it from here": what the mode measured becomes the user's
    # own custom sizes, so nothing on screen moves and the resize gesture can drag on from
    # there. Reverting to the adapter's stored sizes would throw the measurement away.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)
    measured = matrix.active_cells[{0, 1}].bounds.width
    measured_units = matrix.get_col_width(1)
    measured_units.should_not eq(CrymbleUI::VirtualMatrix::DEFAULT_COLUMN_WIDTH) # else vacuous

    matrix.auto_size = false
    renderer.settle_rendering(app)

    matrix.active_cells[{0, 1}].bounds.width.should eq(measured) # nothing moved on screen
    matrix.get_col_width(1).should eq(measured_units)
    # ...and they are OWNED now: stored on the adapter, so the next rebuild reproduces them.
    adapter.custom_col_widths.not_nil![1].should eq(measured_units)
    adapter.get_sizes[1][1].should eq(measured_units)
  end

  it "never writes the user's dragged sizes while sizing itself" do
    # Faking `resize_axis` would let a later mouse-up persist auto widths into the adapter,
    # destroying what the user had dragged. The auto path must leave that state alone.
    adapter = AutoSizeAdapter.new(6, 3)
    matrix, app, renderer = rendered_matrix(adapter)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.resize_axis.should eq(CrymbleUI::VirtualMatrix::ResizeAxis::None)
    adapter.custom_col_widths.should be_nil
    adapter.custom_row_heights.should be_nil
  end
end
