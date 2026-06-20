require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# BACKSTOP-OFF completeness probe (load-bearing).
#
# The render decision is should_render? = (frame_aggregate_rev moved) OR Layer.any_needs_render? (the
# dirty-walk backstop). The completeness battery asserts render_frame_if_needed, which is that OR — so
# those guards would still pass even if the aggregate term were broken (the backstop carries them). The
# eventual deletion of `|| Layer.any_needs_render?` rests on the aggregate being complete ON ITS
# OWN. This probe drives each aggregate-owned axis through the REAL App event path and asserts
# Layer.frame_aggregate_rev moved WITHOUT consulting the backstop — the actual falsification.

private class BOMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    60
  end

  def col_count : Int32
    4
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

describe "Render-trigger completeness — backstop OFF (aggregate alone)" do
  it "SCROLL moves the aggregate alone" do
    matrix = CrymbleUI::VirtualMatrix.new(BOMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), CrymbleUI::Vec2.new(165.0, 100.0))
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg
  end

  it "a content EDIT moves the aggregate alone" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 150.0)
    input = CrymbleUI::TextInput.new(value: "ab", mode: CrymbleUI::TextInputMode::FullEdit)
    panel.add_child(input)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    click_on(app, input)
    renderer.settle_rendering(app)

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    type_text("c")
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg
  end

  it "a RESIZE moves the aggregate alone" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    panel.add_child(CrymbleUI::Button.new("X") { })
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    app.handle_mouse_down(CrymbleUI::Vec2.new(295.0, 175.0)) # right resize edge
    renderer.settle_rendering(app)

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    app.handle_mouse_move(CrymbleUI::Vec2.new(350.0, 175.0))
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg
  end

  it "a DRAG moves the aggregate alone (position axis)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    panel.add_child(CrymbleUI::Button.new("X") { })
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    app.handle_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0)) # title bar
    renderer.settle_rendering(app)

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    app.handle_mouse_move(CrymbleUI::Vec2.new(350.0, 115.0))
    CrymbleUI::Layer.frame_aggregate_rev(root).should_not eq agg
  end

  it "an idle no-op leaves the aggregate stable" do
    matrix = CrymbleUI::VirtualMatrix.new(BOMatrixAdapter.new, id: "m")
    renderer = CrymbleUI::Testing::TestRenderer.new(330, 220)
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(330.0, 200.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)
    root = app.root.not_nil!

    agg = CrymbleUI::Layer.frame_aggregate_rev(root)
    CrymbleUI::Layer.frame_aggregate_rev(root).should eq agg
  end
end
