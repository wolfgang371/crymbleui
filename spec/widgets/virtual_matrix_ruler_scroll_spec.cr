require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Headerless adapter (no sticky rows/cols) — matches showcase_demo configuration.
# With show_rulers=true (default), sticky layers exist for rulers but
# reposition_sticky_cells exits early because sticky_row_count=0.
class RulerScrollTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    20
  end

  def col_count : Int32
    10
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

# DSL-style app for ruler scroll tests
class RulerScrollDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VirtualMatrix.new(
      adapter: RulerScrollTestAdapter.new,
      id: "ruler_scroll_test"
    )
  end
end

private def make_ruler_scroll_dsl
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 400)
  app = RulerScrollDSLApp.new
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("ruler_scroll_test").as(CrymbleUI::VirtualMatrix)
  {renderer, app, matrix}
end

describe "VirtualMatrix ruler scroll update (headerless adapter)" do
  describe "sticky layer re-render on scroll" do
    it "sticky_row_layer is marked dirty after horizontal scroll" do
      renderer, app, matrix = make_ruler_scroll_dsl

      sv = matrix.@content_scroll_view
      sv.should_not be_nil
      row_layer = sv.not_nil!.sticky_row_layer
      row_layer.should_not be_nil

      # Scroll horizontally (shift+scroll)
      scroll_point = CrymbleUI::Vec2.new(400.0, 200.0)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), scroll_point, shift: true)

      # After scroll, sticky_row_layer should be marked for re-render
      # BUG: With headerless adapter, reposition_sticky_cells exits early
      # (sticky_row_count=0) and never marks sticky layers dirty
      state = row_layer.not_nil!.state
      dirty = row_layer.not_nil!.dirty_widgets.size
      (state == CrymbleUI::WidgetState::NeedsLayout ||
       state == CrymbleUI::WidgetState::NeedsRender ||
       dirty > 0).should be_true
    end

    it "sticky_col_layer is marked dirty after vertical scroll" do
      renderer, app, matrix = make_ruler_scroll_dsl

      sv = matrix.@content_scroll_view
      sv.should_not be_nil
      col_layer = sv.not_nil!.sticky_col_layer
      col_layer.should_not be_nil

      # Scroll vertically
      scroll_point = CrymbleUI::Vec2.new(400.0, 200.0)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), scroll_point)

      # After scroll, sticky_col_layer should be marked for re-render
      state = col_layer.not_nil!.state
      dirty = col_layer.not_nil!.dirty_widgets.size
      (state == CrymbleUI::WidgetState::NeedsLayout ||
       state == CrymbleUI::WidgetState::NeedsRender ||
       dirty > 0).should be_true
    end

    it "column ruler labels rendered at correct position after horizontal scroll" do
      renderer, app, matrix = make_ruler_scroll_dsl

      # Get initial c1 label x position (first non-sticky col = col 0 for headerless)
      ruler = matrix.col_ruler_widget.not_nil!
      prims_before = ruler.to_primitives(ruler.bounds)
      c1_before = prims_before.select(CrymbleUI::DrawText).find { |t| t.text == "c1" }
      c1_before.should_not be_nil
      c1_x_before = c1_before.not_nil!.position.x

      # Scroll horizontally
      scroll_point = CrymbleUI::Vec2.new(400.0, 200.0)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), scroll_point, shift: true)
      renderer.render_frame(app)

      # After scroll+render, verify scroll offset actually changed
      matrix = app.find("ruler_scroll_test").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset.x.should be > 0.0

      # Ruler primitives should reflect the new scroll offset
      ruler_after = matrix.col_ruler_widget.not_nil!
      prims_after = ruler_after.to_primitives(ruler_after.bounds)
      c1_after = prims_after.select(CrymbleUI::DrawText).find { |t| t.text == "c1" }
      c1_after.should_not be_nil
      c1_after.not_nil!.position.x.should be < c1_x_before
    end

    it "row ruler labels rendered at correct position after vertical scroll" do
      renderer, app, matrix = make_ruler_scroll_dsl

      ruler = matrix.row_ruler_widget.not_nil!
      prims_before = ruler.to_primitives(ruler.bounds)
      r1_before = prims_before.select(CrymbleUI::DrawText).find { |t| t.text == "1" }
      r1_before.should_not be_nil
      r1_y_before = r1_before.not_nil!.position.y

      # Small vertical scroll
      scroll_point = CrymbleUI::Vec2.new(400.0, 200.0)
      app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), scroll_point)
      renderer.render_frame(app)

      matrix = app.find("ruler_scroll_test").as(CrymbleUI::VirtualMatrix)
      matrix.scroll_offset.y.should be > 0.0

      ruler_after = matrix.row_ruler_widget.not_nil!
      prims_after = ruler_after.to_primitives(ruler_after.bounds)
      r1_after = prims_after.select(CrymbleUI::DrawText).find { |t| t.text == "1" }
      r1_after.should_not be_nil
      r1_after.not_nil!.position.y.should be < r1_y_before
    end
  end
end
