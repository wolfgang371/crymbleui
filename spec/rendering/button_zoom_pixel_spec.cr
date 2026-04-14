require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Autotest: verify Button pixel colors inside VirtualMatrix are correct after zoom.
# Reproduces the "watery / greyish" button report.

class ButtonZoomAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@data_rows : Int32 = 20, @data_cols : Int32 = 10)
    @total_rows = 2 + @data_rows
    @total_cols = 2 + @data_cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows = (2...@total_rows).to_a + [1, 0]
    cols = (2...@total_cols).to_a + [1, 0]
    {rows, cols}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    row_heights = Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 }
    col_widths = Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }
    {row_heights, col_widths}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if row < 2 && col < 2
      CrymbleUI::Text.new("")
    elsif col < 2
      CrymbleUI::Text.new("r#{row}")
    elsif row < 2
      CrymbleUI::Text.new("c#{col}")
    elsif row == 5 && col == 4
      CrymbleUI::Button.new("Click", id: "vm_btn")
    else
      CrymbleUI::TextInput.new(value: "(#{row},#{col})", mode: CrymbleUI::TextInputMode::QuickEntry)
    end
  end
end

# Simulate zoom invalidation (same as SFMLRenderer.on_zoom_change callback)
private def simulate_zoom_invalidation(root : CrymbleUI::Widget)
  # Invalidate all widget backends
  invalidate_widget_backends_recursive(root)
  # Invalidate all layer backends
  CrymbleUI::Layer.active_layers(root).each do |layer|
    layer.backend = nil
    layer.reset_first_render
  end
  # Mark all layers NeedsLayout
  CrymbleUI::Layer.active_layers(root).each(&.mark_needs_layout)
  # Mark root NeedsLayout
  root.mark_needs_layout
end

private def invalidate_widget_backends_recursive(widget : CrymbleUI::Widget)
  widget.widget_backend = nil
  widget.background_backend = nil
  widget.children.each { |c| invalidate_widget_backends_recursive(c) }
  # VirtualMatrix active_cells are in children, so they're covered
end

# Sample pixel at center of a widget's backend
private def sample_widget_center(widget : CrymbleUI::Widget) : CrymbleUI::Color?
  wb = widget.widget_backend
  return nil unless wb.is_a?(CrymbleUI::Testing::TestRenderBackend)
  cx = wb.width // 2
  cy = wb.height // 2
  wb.get_pixel(cx, cy)
end

# Sample pixel at (dx, dy) offset into widget's backend
private def sample_widget_pixel(widget : CrymbleUI::Widget, dx : Int32, dy : Int32) : CrymbleUI::Color?
  wb = widget.widget_backend
  return nil unless wb.is_a?(CrymbleUI::Testing::TestRenderBackend)
  wb.get_pixel(dx, dy)
end

# Find a Button widget by searching active_cells
private def find_button_in_matrix(matrix : CrymbleUI::VirtualMatrix) : CrymbleUI::Button?
  matrix.active_cells.each_value do |widget|
    return widget if widget.is_a?(CrymbleUI::Button)
  end
  nil
end

describe "Button pixel colors in VirtualMatrix after zoom", tags: "slow" do
  before_each do
    CrymbleUI::FontSizing.reset_zoom
  end

  after_each do
    CrymbleUI::FontSizing.reset_zoom
  end

  it "button has opaque blue pixels at zoom 1.0" do
    adapter = ButtonZoomAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(
      adapter: adapter, id: "zoom_btn_test",
      content_background_color: CrymbleUI::Color.new(200, 200, 205, 255)
    )
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    btn = find_button_in_matrix(matrix)
    btn.should_not be_nil
    btn = btn.not_nil!

    # Sample center — should be on text (white) or blue bg
    center = sample_widget_center(btn)
    center.should_not be_nil
    center = center.not_nil!
    center.a.should eq(255_u8) # Must be fully opaque

    # Sample corner (2,2) — should be blue background
    corner = sample_widget_pixel(btn, 2, 2)
    corner.should_not be_nil
    corner = corner.not_nil!
    corner.r.should eq(0_u8)
    corner.g.should eq(120_u8)
    corner.b.should eq(215_u8)
    corner.a.should eq(255_u8)
  end

  it "button has same opaque blue pixels after zoom in" do
    adapter = ButtonZoomAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(
      adapter: adapter, id: "zoom_btn_test",
      content_background_color: CrymbleUI::Color.new(200, 200, 205, 255)
    )
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    # Verify pre-zoom state
    btn_pre = find_button_in_matrix(matrix)
    btn_pre.should_not be_nil
    pre_corner = sample_widget_pixel(btn_pre.not_nil!, 2, 2)
    pre_corner.should_not be_nil
    pre_corner = pre_corner.not_nil!
    pre_corner.r.should eq(0_u8)
    pre_corner.g.should eq(120_u8)
    pre_corner.b.should eq(215_u8)
    pre_corner.a.should eq(255_u8)

    # Zoom in (simulate full SFML zoom flow)
    CrymbleUI::FontSizing.zoom_in
    simulate_zoom_invalidation(app.root.not_nil!)
    renderer.settle_rendering(app)

    # Find button again (may be new instance after rebuild/reconciliation)
    btn_post = find_button_in_matrix(matrix)
    btn_post.should_not be_nil
    btn_post = btn_post.not_nil!

    # Corner pixel should still be opaque blue
    post_corner = sample_widget_pixel(btn_post, 2, 2)
    post_corner.should_not be_nil
    post_corner = post_corner.not_nil!
    post_corner.r.should eq(0_u8)
    post_corner.g.should eq(120_u8)
    post_corner.b.should eq(215_u8)
    post_corner.a.should eq(255_u8)
  end

  it "button has same opaque blue pixels after two zoom steps", tags: "slow" do
    adapter = ButtonZoomAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(
      adapter: adapter, id: "zoom_btn_test",
      content_background_color: CrymbleUI::Color.new(200, 200, 205, 255)
    )
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    # Two zoom steps
    2.times do
      CrymbleUI::FontSizing.zoom_in
      simulate_zoom_invalidation(app.root.not_nil!)
      renderer.settle_rendering(app)
    end

    btn = find_button_in_matrix(matrix)
    btn.should_not be_nil
    btn = btn.not_nil!

    # Corner pixel should be opaque blue (not grey/watery)
    corner = sample_widget_pixel(btn, 2, 2)
    corner.should_not be_nil
    corner = corner.not_nil!
    corner.a.should eq(255_u8) # Must be fully opaque
    corner.r.should eq(0_u8)
    corner.g.should eq(120_u8)
    corner.b.should eq(215_u8)
  end

  it "button background does NOT leak layer background color" do
    adapter = ButtonZoomAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(
      adapter: adapter, id: "zoom_btn_test",
      content_background_color: CrymbleUI::Color.new(200, 200, 205, 255)
    )
    app = TestApp.new
    app.root_widget = matrix
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    renderer.settle_rendering(app)

    # Zoom in
    CrymbleUI::FontSizing.zoom_in
    simulate_zoom_invalidation(app.root.not_nil!)
    renderer.settle_rendering(app)

    btn = find_button_in_matrix(matrix)
    btn.should_not be_nil
    btn = btn.not_nil!

    wb = btn.widget_backend
    wb.should_not be_nil
    wb = wb.as(CrymbleUI::Testing::TestRenderBackend)

    # Scan all pixels along a horizontal line at y=2 (top area, should be solid blue)
    grey_count = 0
    wb.width.times do |x|
      px = wb.get_pixel(x, 2)
      next unless px
      # Layer bg is (200, 200, 205) — if any pixel has this color, bg leaked
      if px.r == 200_u8 && px.g == 200_u8 && px.b == 205_u8
        grey_count += 1
      end
    end

    # At most 1 pixel grey (edge rounding) — not a full grey strip
    grey_count.should be <= 1
  end
end
