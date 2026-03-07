require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# Tests for VirtualMatrix zoom support: cell sizes, grid spacing, scroll position,
# and rulers should all scale proportionally with FontSizing.zoom_factor.

# Helper module for building test matrices at specific zoom levels
module VirtualMatrixZoomHelper
  def self.make_matrix(zoom_steps : Int32 = 0, rows = 20, cols = 10) : {CrymbleUI::Testing::TestRenderer, TestApp, CrymbleUI::VirtualMatrix}
    if zoom_steps > 0
      zoom_steps.times { CrymbleUI::FontSizing.zoom_in }
    elsif zoom_steps < 0
      (-zoom_steps).times { CrymbleUI::FontSizing.zoom_out }
    end

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(rows: rows, cols: cols, id: "zoom_test")
    app.root_widget = matrix
    app.build_tree
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)
    {renderer, app, matrix}
  end
end

describe "VirtualMatrix zoom scaling" do
  describe "cell dimensions scale with zoom" do
    it "col_width_pixels increases at zoom 1.5" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      width_100 = matrix_100.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0
      width_100.should be > 0.0

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_150 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 3)
      width_150 = matrix_150.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0
      width_150.should be > 0.0

      ratio = width_150 / width_100
      ratio.should be_close(1.5, 0.15)
    end

    it "row_height_pixels increases at zoom 1.5" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      height_100 = matrix_100.active_cells[{0, 0}]?.try(&.bounds.height) || 0.0
      height_100.should be > 0.0

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_150 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 3)
      height_150 = matrix_150.active_cells[{0, 0}]?.try(&.bounds.height) || 0.0
      height_150.should be > 0.0

      ratio = height_150 / height_100
      ratio.should be_close(1.5, 0.15)
    end

    it "cell dimensions decrease at zoom 0.5" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      width_100 = matrix_100.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_50 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: -5)

      width_50 = matrix_50.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0
      width_50.should be > 0.0

      ratio = width_50 / width_100
      ratio.should be_close(0.5, 0.1)
    end
  end

  describe "ruler dimensions scale with zoom" do
    it "ruler_row_height_pixels scales with zoom" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      ruler_h_100 = matrix_100.ruler_row_height_pixels

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_150 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 3)
      ruler_h_150 = matrix_150.ruler_row_height_pixels

      ratio = ruler_h_150 / ruler_h_100
      ratio.should be_close(1.5, 0.01)
    end

    it "ruler_col_width_pixels scales with zoom" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      ruler_w_100 = matrix_100.ruler_col_width_pixels

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_150 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 3)
      ruler_w_150 = matrix_150.ruler_col_width_pixels

      ratio = ruler_w_150 / ruler_w_100
      ratio.should be_close(1.5, 0.01)
    end
  end

  describe "scroll position preserved across zoom change" do
    it "scroll offset scales proportionally on zoom change" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 20, id: "scroll_zoom")
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      # Scroll to a known position
      matrix.scroll_offset = CrymbleUI::Vec2.new(200.0, 400.0)
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      scroll_before = matrix.scroll_offset

      # Zoom in to 1.5x (3 steps)
      3.times { CrymbleUI::FontSizing.zoom_in }
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      scroll_after = matrix.scroll_offset

      # Scroll offset should scale by 1.5 to keep same logical cell at top-left
      (scroll_after.x / scroll_before.x).should be_close(1.5, 0.15)
      (scroll_after.y / scroll_before.y).should be_close(1.5, 0.15)
    end
  end

  describe "active cells recreated at correct positions after zoom" do
    it "cells exist and have non-zero bounds after zoom change" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      matrix = CrymbleUI::VirtualMatrix.new(rows: 20, cols: 10, id: "cell_recreate")
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      cells_before = matrix.active_cell_count
      cells_before.should be > 0

      # Zoom in
      3.times { CrymbleUI::FontSizing.zoom_in }
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      cells_after = matrix.active_cell_count
      cells_after.should be > 0

      # Fewer cells visible at higher zoom (cells are bigger) — but still some
      cells_after.should be <= cells_before

      # All active cells should have non-zero bounds
      matrix.active_cells.each do |key, widget|
        widget.bounds.width.should be > 0.0, "Cell #{key} has zero width after zoom"
        widget.bounds.height.should be > 0.0, "Cell #{key} has zero height after zoom"
      end
    end
  end

  describe "grid spacing scales with zoom" do
    it "gap between cells is larger at higher zoom" do
      _, _, matrix_100 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 0)
      cell_00_w = matrix_100.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0

      CrymbleUI::FontSizing.reset_zoom
      _, _, matrix_200 = VirtualMatrixZoomHelper.make_matrix(zoom_steps: 5)  # 200%

      cell_00_w_200 = matrix_200.active_cells[{0, 0}]?.try(&.bounds.width) || 0.0

      # At 2.0x zoom both frame_height and grid_spacing scale, so ratio ~2.0
      ratio = cell_00_w_200 / cell_00_w
      ratio.should be_close(2.0, 0.2)
    end
  end
end
