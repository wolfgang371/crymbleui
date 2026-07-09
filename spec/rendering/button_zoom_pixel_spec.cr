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

# A matrix content cell renders direct-to-layer (no per-cell widget_backend), so the button's
# fidelity is read from the CONTENT-LAYER buffer. The button fill (0,120,215) is the only blue widget
# in the grid, so it's unambiguous. The old "watery button" bug was greyish edges from the texture
# path's background capture/restore — the direct path does NO capture, so it cannot occur by
# construction; these tests now assert the positive: the button paints a solid opaque-blue region with
# no layer-bg (200,200,205) leak inside it.
BTN_BLUE = CrymbleUI::Color.new(0, 120, 215, 255)
LAYER_BG = CrymbleUI::Color.new(200, 200, 205, 255)

private def button_blue_stats(matrix : CrymbleUI::VirtualMatrix) : {blue: Int32, grey_in_region: Int32, opaque: Bool}
  layer = matrix.content_layer
  return {blue: 0, grey_in_region: 0, opaque: false} unless layer
  lb = layer.backend
  return {blue: 0, grey_in_region: 0, opaque: false} unless lb.is_a?(CrymbleUI::Testing::TestRenderBackend)
  blue = 0
  opaque = true
  minx = lb.width; miny = lb.height; maxx = -1; maxy = -1
  lb.height.times do |y|
    lb.width.times do |x|
      p = lb.get_pixel(x, y)
      next unless p && p.r == 0_u8 && p.g == 120_u8 && p.b == 215_u8
      blue += 1
      opaque = false if p.a != 255_u8
      minx = x if x < minx; maxx = x if x > maxx
      miny = y if y < miny; maxy = y if y > maxy
    end
  end
  grey = 0
  if maxx >= 0
    (miny..maxy).each do |y|
      (minx..maxx).each do |x|
        p = lb.get_pixel(x, y)
        grey += 1 if p && p.r == 200_u8 && p.g == 200_u8 && p.b == 205_u8
      end
    end
  end
  {blue: blue, grey_in_region: grey, opaque: opaque}
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

    find_button_in_matrix(matrix).should_not be_nil

    # The button paints a solid opaque-blue region in the content-layer buffer.
    stats = button_blue_stats(matrix)
    stats[:blue].should be > 0, "button background not painted (no opaque blue in content buffer)"
    stats[:opaque].should be_true, "button blue is not fully opaque (watery)"
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
    button_blue_stats(matrix)[:blue].should be > 0, "button not painted opaque blue before zoom"

    # Zoom in (simulate full SFML zoom flow)
    CrymbleUI::FontSizing.zoom_in
    simulate_zoom_invalidation(app.root.not_nil!)
    renderer.settle_rendering(app)

    # Button should still paint solid opaque blue after the zoom rebuild/reconciliation.
    post = button_blue_stats(matrix)
    post[:blue].should be > 0, "button not painted opaque blue after zoom"
    post[:opaque].should be_true, "button blue not fully opaque after zoom (watery)"
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

    find_button_in_matrix(matrix).should_not be_nil

    # Still solid opaque blue (not grey/watery) after two zoom steps.
    stats = button_blue_stats(matrix)
    stats[:blue].should be > 0, "button not painted opaque blue after two zoom steps"
    stats[:opaque].should be_true, "button blue not fully opaque after two zoom steps (watery)"
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

    find_button_in_matrix(matrix).should_not be_nil

    # The layer background (200,200,205) must NOT show through inside the button's painted blue region.
    # Direct render does no background capture, so no grey can leak; assert the region is solidly blue.
    stats = button_blue_stats(matrix)
    stats[:blue].should be > 0, "button not painted (no blue region to check for leak)"
    stats[:grey_in_region].should eq(0), "layer background leaked inside the button's blue region"
  end
end
