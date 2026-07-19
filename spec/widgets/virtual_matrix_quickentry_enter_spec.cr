require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# Regression: typing directly into a cursored cell (QuickEntry, immediate replace) then pressing Enter
# must ACCEPT the value and LEAVE edit mode (back to the cursor-flash nav state) — NOT open FullEdit.
# The Enter handler used to treat every Enter-in-QuickEntry as "open full-edit (F2-style)", ignoring
# that the user had already typed. It must only F2-open when PARKED (pending_replace still true).

private class QEEnterAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter assigned = [] of {Int32, Int32, String}

  def row_count : Int32
    10
  end

  def col_count : Int32
    5
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_assign(row : Int32, col : Int32, value : String)
    @assigned << {row, col, value}
    {row, col}
  end
end

describe "VirtualMatrix — Enter after typing in QuickEntry" do
  it "accepts the typed value and leaves edit mode (does NOT enter FullEdit)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    adapter = QEEnterAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "g")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    matrix.set_cursor_from_cell({1, 2})
    matrix.on_text_input('Z') # type directly in QuickEntry → immediate replace, pending_replace=false

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    # Left edit mode: the cursor cell shows its flash, not an edit caret.
    matrix.cursor_cell_draws_edit_caret?.should be_false
    # And specifically did NOT enter FullEdit.
    proxy = matrix.@proxy_focused_widget
    if proxy.is_a?(CrymbleUI::TextInput)
      proxy.edit_mode.should eq(CrymbleUI::TextInputMode::QuickEntry)
    end
    # The typed value was accepted (committed to the adapter).
    adapter.assigned.should contain({1, 2, "Z"})
  end

  it "still F2-opens FullEdit on Enter when PARKED (nothing typed yet)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    matrix = CrymbleUI::VirtualMatrix.new(QEEnterAdapter.new, id: "g2")
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    matrix.set_cursor_from_cell({1, 2}) # parked QuickEntry — nothing typed
    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)

    matrix.cursor_cell_draws_edit_caret?.should be_true # F2-style: opened full character edit
  end
end
