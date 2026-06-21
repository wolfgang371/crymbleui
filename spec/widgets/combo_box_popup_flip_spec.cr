require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"
require "../../src/widgets/window"

# Regression: the popup's flip-above placement (below the cell, or flipped up if it would
# run past the window bottom) is decided at open in mount_popup, but perform_layout re-runs
# on every rebuild and used to hardcode "below the cell". So a rebuild that keeps the popup
# open near the window bottom (e.g. a MultiComboBox gutter toggle) snapped the popup back
# below — it jumped. mount_popup and perform_layout now share PopupHost#popup_position.
describe "ComboBox popup flip-above stability across re-layout" do
  it "keeps the popup flipped above when re-laid-out (no jump on rebuild)" do
    window = CrymbleUI::Window.new("Test", 400, 300)
    combo = CrymbleUI::ComboBox.new(
      items: ["Apple", "Banana", "Cherry", "Date", "Elderberry"],
      selected: 0, width: 150.0, id: "c"
    )
    window.add_child(combo)
    window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)

    # Force the cell near the window bottom so the popup MUST flip above to fit.
    near_bottom = CrymbleUI::Rect.new(10.0, 260.0, 150.0, 28.0)
    combo.bounds = near_bottom
    combo.expand
    popup = combo.current_popup.not_nil!

    cell_top = combo.absolute_bounds.y
    popup.bounds.y.should be < cell_top # flipped ABOVE on open
    flipped_y = popup.bounds.y

    # Simulate the rebuild's re-layout (the gutter-toggle path): perform_layout must
    # re-anchor with the SAME flip, NOT snap the popup back below the cell.
    combo.perform_layout(
      CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(150.0, 28.0)),
      CrymbleUI::Vec2.new(10.0, 260.0)
    )

    popup.bounds.y.should be < combo.absolute_bounds.y # STILL above
    popup.bounds.y.should eq flipped_y                  # unchanged — no jump
  end
end
