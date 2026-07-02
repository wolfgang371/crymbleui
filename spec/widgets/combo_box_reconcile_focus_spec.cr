require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/combo_box"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/input/focus_cycler"

# confirm/refute (surfaced by the code-gate, Concern 2):
# When a proxy-focused ComboBox cell WITH AN OPEN POPUP is reconciled (new instances) during a
# VirtualMatrix rebuild, does the orphaned old cell's teardown steal FocusManager focus to the
# DEAD old matrix (collapse -> find_window -> request_focus on the orphan), breaking proxy
# re-establish? Orphan detector: a live-tree widget's find_window is the live Window; a stranded
# orphan's find_window is the dead old Window (a different object).
class T027ComboAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    3
  end

  def col_count : Int32
    2
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if col == 1
      CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "combo_#{row}_#{col}")
    else
      CrymbleUI::TextInput.new(value: "R#{row}C#{col}", id: "cell_#{row}_#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
    end
  end
end

# DSL app (reconciles: build() makes NEW instances every call), matching embrace structure.
class T027ComboApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("T027", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        widget(CrymbleUI::VirtualMatrix.new(T027ComboAdapter.new, id: "combo_matrix"))
      end
    end
  end
end

describe "reconcile with an open ComboBox popup keeps focus on the live tree" do
  it "does not strand FocusManager focus on a dead/orphaned matrix after rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = T027ComboApp.new
    app.build_tree
    renderer.render_frame(app)

    matrix = app.find("combo_matrix").not_nil!.as(CrymbleUI::VirtualMatrix)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    fm.handle_key_down(SF::Keyboard::Key::Right, false, false) # proxy-focus the combo column
    renderer.render_frame(app)
    fm.handle_key_down(SF::Keyboard::Key::Enter, false, false) # open the popup
    renderer.render_frame(app)

    combo = matrix.active_cells[{0, 1}]?.try(&.as(CrymbleUI::ComboBox))
    combo.should_not be_nil
    combo.not_nil!.popup_open?.should be_true

    # The crux: force a reconcile (NEW instances) WHILE the popup is open. The old combo is
    # orphaned (its find_window is no longer the live window), exactly the teardown setup.
    app.rebuild
    renderer.render_frame(app)

    new_matrix = app.find("combo_matrix").not_nil!.as(CrymbleUI::VirtualMatrix)
    live_window = new_matrix.find_window.not_nil!

    # REFUTED: focus is NOT stranded on the dead/orphaned old matrix. Whoever holds focus
    # still reaches the LIVE window via its parent chain (here the popup's TextInput, migrated as
    # an overlay). unmount_popup's request_focus targets the live focus_scope_ancestor, so the
    # teardown path never hands focus to the orphan.
    focused = fm.focused_widget
    focused.should_not be_nil
    focused.not_nil!.find_window.should be(live_window)
  end
end
