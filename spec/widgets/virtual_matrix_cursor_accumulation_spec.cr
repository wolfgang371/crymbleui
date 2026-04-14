require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Mutable adapter that supports invalidate_all! (simulates checkbox toggle → rebuild)
class CursorAccumulationAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    10
  end

  def col_count : Int32
    5
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("R#{row}C#{col}")
  end
end

# DSL-style app — VirtualMatrix inside WindowPanel (matches embrace structure)
class CursorAccumulationApp < CrymbleUI::App
  getter adapter : CursorAccumulationAdapter

  def initialize
    @adapter = CursorAccumulationAdapter.new
    super()
  end

  def build : CrymbleUI::Widget
    window("Test", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        widget(CrymbleUI::VirtualMatrix.new(@adapter, id: "accum_grid"))
      end
    end
  end
end

describe CrymbleUI::VirtualMatrix do
  describe "Cursor overlay accumulation after invalidate_all! + rebuild" do
    it "cursor overlay widget count stays at 1 after repeated rebuilds" do
      app = CursorAccumulationApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      renderer.settle_rendering(app)

      matrix = app.find("accum_grid").as(CrymbleUI::VirtualMatrix)
      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.widgets.size.should eq 1

      # Simulate 3 checkbox toggles: invalidate_all! + request_rebuild
      3.times do |i|
        app.adapter.invalidate_all!
        app.request_rebuild
        renderer.render_frame(app)
        renderer.render_frame(app)
      end

      # After 3 rebuilds, overlay should still have exactly 1 widget
      matrix = app.find("accum_grid").as(CrymbleUI::VirtualMatrix)
      overlay = matrix.cursor_overlay_layer.not_nil!
      overlay.widgets.size.should eq 1
    end

    it "composited pixel brightness is stable after repeated rebuilds" do
      app = CursorAccumulationApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      renderer.settle_rendering(app)

      matrix = app.find("accum_grid").as(CrymbleUI::VirtualMatrix)
      matrix_abs = matrix.absolute_bounds
      sample_x = (matrix_abs.x + matrix.ruler_col_width_pixels + 5).to_i
      sample_y = (matrix_abs.y + matrix.ruler_row_height_pixels + 5).to_i
      win_backend = renderer.backend

      # First rebuild
      app.adapter.invalidate_all!
      app.request_rebuild
      renderer.render_frame(app)
      renderer.render_frame(app)
      pixel_1 = win_backend.get_pixel(sample_x, sample_y).not_nil!

      # Second rebuild
      app.adapter.invalidate_all!
      app.request_rebuild
      renderer.render_frame(app)
      renderer.render_frame(app)
      pixel_2 = win_backend.get_pixel(sample_x, sample_y).not_nil!

      # Third rebuild
      app.adapter.invalidate_all!
      app.request_rebuild
      renderer.render_frame(app)
      renderer.render_frame(app)
      pixel_3 = win_backend.get_pixel(sample_x, sample_y).not_nil!

      # Brightness should be stable (no accumulation)
      delta_1_2 = (pixel_1.r.to_i - pixel_2.r.to_i).abs
      delta_2_3 = (pixel_2.r.to_i - pixel_3.r.to_i).abs
      delta_1_2.should be <= 2
      delta_2_3.should be <= 2
    end
  end
end
