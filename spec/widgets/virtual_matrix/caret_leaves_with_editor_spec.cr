require "../../spec_helper"
require "./snap_to_cursor_spec"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Field report 2026-09-05: leaving a multi-line cell left its caret on screen, and only an unrelated
# action — Ctrl+0, a click — cleared it. Both of those run a matrix pass.
#
# Sticky layers are not viewport_cache: they are painted ONLY by reposition_sticky_cells /
# compute_sticky_blit_plans, and every route to those goes through update_visible_cells, i.e. a
# scroll or a pending update — not every frame. Leaving edit mode marks the cell (needs_render set,
# primitive cache dropped) but nothing consulted that for a sticky layer, so the layer kept the
# texture it last blitted: one drawn while the caret was showing.
#
# embrace paints QuickEntry cells (shape.cr:388-394); the library default FullEdit always draws a
# caret while proxy-focused and so cannot show this either way.
class QuickEntryAllStickyTall < AllStickyTallAdapter
  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: text_at(row, col),
      mode: CrymbleUI::TextInputMode::QuickEntry, multiline: true)
  end
end

describe "leaving an editor takes its caret off the sticky layer" do
  it "leaves no cell waiting for paint on the frame the editor closes" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    matrix = CrymbleUI::VirtualMatrix.new(QuickEntryAllStickyTall.new(20, 3), id: "caret_leaves")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    matrix.auto_size = true
    renderer.settle_rendering(app)

    matrix.sticky_col_count.should eq(3) # instrument: the cells really are on a sticky layer

    matrix.set_cursor_from_cell({3, 1})
    matrix.snap_to_cursor
    renderer.settle_rendering(app)
    at_cell_top = matrix.scroll_offset.y

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # open the editor
    renderer.settle_rendering(app)
    matrix.cursor_cell_draws_edit_caret?.should be_true        # instrument: a caret really is drawn

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false) # leave
    renderer.render_frame(app)                                 # ONE ordinary frame: no scroll, no click
    matrix.cursor_cell_draws_edit_caret?.should be_false       # the widget agrees the caret is gone
    matrix.scroll_offset.y.should eq(at_cell_top)              # ...and the view has not moved

    # A cell left WAITING for paint keeps whatever texture it last had — here one drawn with the
    # caret, which is exactly what stayed on screen until an unrelated action ran a pass. Confirmed
    # in the running app on both sides of the fix: the closing frame went from a `BLIT` of the caret
    # texture to `RENDER fresh caret=false` (CRYMBLE_CARET_LOG).
    #
    # Deliberately not asserted as pixels: a forced pass also re-fits the cell and paints its
    # parked-cursor highlight, so whole-cell ink differs for reasons unrelated to the caret (56 rows,
    # measured) and would make the assertion pass or fail for the wrong causes.
    cell = matrix.active_cells[{3, 1}]
    cell.has_valid_primitive_cache?.should be_true,
      "the cell was left waiting for paint, so its layer keeps the editor's pixels"
    cell.needs_render?.should be_false
  end
end
