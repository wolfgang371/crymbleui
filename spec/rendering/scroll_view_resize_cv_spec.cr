require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/scroll_view"
require "../../src/layout/vstack"
require "../../src/layout/hstack"

# — the ScrollView cv gap. cv-coherency previously had ZERO ScrollView specs, yet a ScrollView's
# content layer is the primary viewport_cache consumer this refactor touches. Under -Dcache_validation the
# after_each re-renders the content layer via to_primitives() and compares it pixel-by-pixel against the
# cached buffer — a shifted/stale composite after a scroll or resize fails the example. Solid-color cells
# (no text, no AA jitter) keep that comparison clean; the get_pixel assertions below make the specs
# meaningful when run WITHOUT the flag too (they catch a blank leading edge from a shifted composite).

# Fixed-size, solid-color cell — cv-safe (integer-aligned fill, no anti-aliased text).
private class CvCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  COLOR = CrymbleUI::Color.new(45, 50, 55, 255)

  def initialize(@w : Float64, @h : Float64, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@w, @h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), COLOR)
    end
  end
end

# Build a ScrollView of solid CvCells (content ≫ viewport, spacing 0 so the content fully covers the
# viewport) inside a floored panel, settled at 1600×900.
private def make_cv_scrollview(panel_w = 480.0, panel_h = 480.0)
  renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
  app = TestApp.new
  window = CrymbleUI::Window.new("T", 1600, 900)
  panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, panel_w, panel_h)
  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
  grid = CrymbleUI::VStack.new(spacing: 0.0)
  30.times do |r|
    hs = CrymbleUI::HStack.new(spacing: 0.0)
    30.times { |c| hs.add_child(CvCell.new(60.0, 24.0)) }
    grid.add_child(hs)
  end
  sv.set_content(grid)
  panel.add_child(sv)
  window.add_child(panel)
  app.root_widget = window
  renderer.settle_rendering(app)
  {renderer, app, panel, sv}
end

# Scan the leftmost `width` px of the ScrollView's interior for the cell colour — the leading edge must
# stay painted (a shifted composite blanks it).
private def leading_edge_is_content?(renderer, sv, width = 16)
  b = sv.absolute_bounds
  x0 = b.x.to_i + 1
  y0 = b.y.to_i + 4
  y1 = (b.y + b.height).to_i - 4
  (x0...(x0 + width)).each do |x|
    (y0...y1).step(2) do |y|
      if px = renderer.backend.get_pixel(x, y)
        return true if px.r == CvCell::COLOR.r && px.g == CvCell::COLOR.g && px.b == CvCell::COLOR.b
      end
    end
  end
  false
end

describe "ScrollView viewport-cache coherency across scroll + resize (cv)" do
  it "keeps the leading edge painted after scrolling past cache_extent" do
    renderer, app, _panel, sv = make_cv_scrollview
    cl = sv.content_layer.not_nil!

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(cl.cache_extent + 40.0, cl.cache_extent + 40.0))
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    leading_edge_is_content?(renderer, sv).should be_true
  end

  it "keeps the leading edge painted after a scrolled grow-resize" do
    renderer, app, panel, sv = make_cv_scrollview
    cl = sv.content_layer.not_nil!

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(cl.cache_extent + 20.0, cl.cache_extent + 20.0))
    renderer.render_frame(app)

    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 240.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 160.0, panel.y + 240.0)) # grow > cache_extent
    renderer.render_frame(app)
    panel.on_mouse_up(CrymbleUI::Vec2.new(right + 160.0, panel.y + 240.0))
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    leading_edge_is_content?(renderer, sv).should be_true
  end
end
