require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# The blinking cursor-cell FLASH must sit exactly on its cursor cell. It was drawn at the
# full row PITCH (row_height_pixels = grid_spacing + cell height) while the cell is laid out
# at the cell height only — so the flash overhangs the inter-row gap below the cell. As the
# flash blinks (400ms), that asymmetric overhang reads as the cell's text jittering ~1px
# (user-reported: "100 moves down when I click, back up when I click away"). Geometry test
# (disposition-not-pixels): assert the flash FillRect matches the cursor cell bounds.

private def flash_and_cell(zoom_steps : Int32)
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 500)
  matrix = CrymbleUI::VirtualMatrix.new(rows: 12, cols: 8, id: "m")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  zoom_steps.times { CrymbleUI::FontSizing.zoom_in }
  matrix.mark_needs_layout
  renderer.settle_rendering(app)
  matrix.set_cursor(3, 2)
  matrix.cursor_overlay_widget.not_nil!.flash_on = true
  renderer.settle_rendering(app)

  cell = matrix.active_cells[{3, 2}].not_nil!
  overlay = matrix.cursor_overlay_widget.not_nil!
  ob = overlay.bounds
  fills = overlay.to_primitives(ob).select(CrymbleUI::FillRect).map(&.as(CrymbleUI::FillRect))
  # The cell flash is the smallest-area fill: row band = wide×row_h, col band = col_w×tall,
  # cell flash = col_w×row_h (a single cell at the cursor).
  flash = fills.min_by? { |fr| fr.bounds.width * fr.bounds.height }
  {cell, flash}
end

describe "cursor flash rect aligns with the cursor cell" do
  it "flash covers exactly the cursor cell (zoom 1.0)" do
    cell, flash = flash_and_cell(0)
    flash.should_not be_nil
    f = flash.not_nil!.bounds
    b = cell.bounds
    # top edge and height must match the cell (not the inter-row pitch)
    f.y.should be_close(b.y, 0.5)
    (f.y + f.height).should be_close(b.y + b.height, 0.5)
  end

  it "flash covers exactly the cursor cell (fractional zoom 1.25)" do
    cell, flash = flash_and_cell(2)
    flash.should_not be_nil
    f = flash.not_nil!.bounds
    b = cell.bounds
    f.y.should be_close(b.y, 0.5)
    (f.y + f.height).should be_close(b.y + b.height, 0.5)
  end
end
