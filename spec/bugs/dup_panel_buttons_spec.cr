require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"
require "../../src/widgets/tree_node"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Minimal adapter for VirtualMatrix
class DupPanelMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32; 10 end
  def col_count : Int32; 5 end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("r#{row}c#{col}")
  end
end

# DSL app with one panel containing buttons + VirtualMatrix.
# Simulates "dup shape" by switching to two panels on rebuild.
class DupPanelApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property panel_count : Int32 = 1

  def build : CrymbleUI::Widget
    window("Host", 1200, 800) do
      panel_count.times do |i|
        window_panel("Shape#{i}", x: 20.0 + i * 400.0, y: 20.0, width: 380.0, height: 600.0, id: "panel_#{i}") do
          vstack(spacing: 5.0) do
            tree_node("Perspective", expanded: true, id: "perspective_#{i}") do
              hstack(spacing: 5.0, id: "buttons_#{i}") do
                button("Add field", id: "addf_#{i}") { }
                button("...", id: "addf_dlg_#{i}") { }
                button("Add record", id: "addr_#{i}") { }
              end
              expanded do
                widget(CrymbleUI::VirtualMatrix.new(
                  adapter: DupPanelMatrixAdapter.new,
                  id: "matrix_#{i}",
                ))
              end
            end
          end
        end
      end
    end
  end
end

describe "Dup panel - buttons must remain visible after adding second panel" do
  it "left panel buttons are rendered after dup (second panel added)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = DupPanelApp.new
    app.panel_count = 1
    app.build_tree
    renderer.settle_rendering(app)

    # Verify buttons exist and are rendered in single-panel state
    btn_add = app.find("addf_0").not_nil!
    assert_rendered(btn_add, "Add field button before dup")

    btn_record = app.find("addr_0").not_nil!
    assert_rendered(btn_record, "Add record button before dup")

    # Simulate "dup shape" — add second panel, trigger rebuild
    app.panel_count = 2
    app.rebuild
    renderer.settle_rendering(app)

    # Verify left panel buttons are STILL rendered
    btn_add_after = app.find("addf_0")
    btn_add_after.should_not be_nil, "Add field button not found after dup"
    assert_rendered(btn_add_after.not_nil!, "Add field button after dup")

    btn_record_after = app.find("addr_0")
    btn_record_after.should_not be_nil, "Add record button not found after dup"
    assert_rendered(btn_record_after.not_nil!, "Add record button after dup")

    # Also verify right panel exists (button may not be findable if panel was just created)
    panel_right = app.find("panel_1")
    panel_right.should_not be_nil, "Right panel not found after dup"
  end

  it "left panel buttons have non-zero size and are within panel bounds" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 800)
    app = DupPanelApp.new
    app.panel_count = 2  # Start with 2 panels directly
    app.build_tree
    renderer.settle_rendering(app)

    # Verify left panel button
    btn_add = app.find("addf_0").not_nil!
    pos = btn_add.absolute_bounds
    pos.width.should be > 0
    pos.height.should be > 0

    # Button should be within the panel bounds
    panel = app.find("panel_0").not_nil!
    panel_abs = panel.absolute_bounds
    pos.x.should be >= panel_abs.x
    pos.y.should be >= panel_abs.y
    (pos.x + pos.width).should be <= (panel_abs.x + panel_abs.width)
    (pos.y + pos.height).should be <= (panel_abs.y + panel_abs.height)
  end
end
