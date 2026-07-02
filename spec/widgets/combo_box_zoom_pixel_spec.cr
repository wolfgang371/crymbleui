require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# pixel coverage: zooming must visibly SCALE the combo's rendered text — not merely change
# its measured size. The existing combo_box_zoom specs assert measured bounds/heights; this asserts
# the actual drawn glyph extent grows in pixels. Reuses the zoom-invalidation pattern from
# button_zoom_pixel_spec (a real zoom invalidates every backend + relayouts).
private def zoom_invalidate(root : CrymbleUI::Widget)
  invalidate_backends_rec(root)
  CrymbleUI::Layer.active_layers(root).each do |layer|
    layer.backend = nil
    layer.reset_first_render
    layer.mark_needs_layout
  end
  root.mark_needs_layout
end

private def invalidate_backends_rec(widget : CrymbleUI::Widget)
  widget.widget_backend = nil
  widget.background_backend = nil
  widget.children.each { |c| invalidate_backends_rec(c) }
end

# Horizontal extent (max_x - min_x) of the dark/drawn pixels in a widget's own backend.
private def drawn_text_extent(widget) : Int32
  wb = widget.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  return 0 unless wb
  min_x = Int32::MAX
  max_x = -1
  (0...wb.width).each do |x|
    (0...wb.height).each do |y|
      if (p = wb.get_pixel(x, y)) && p.r < 50 && p.g < 50 && p.b < 50
        min_x = x if x < min_x
        max_x = x if x > max_x
      end
    end
  end
  max_x < 0 ? 0 : (max_x - min_x)
end

class ZoomComboApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Zoom", 400, 300) do
      vstack(padding: 20.0, spacing: 8.0) do
        combo_box(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "combo")
      end
    end
  end
end

describe "zoom scales the combo's rendered text in pixels" do
  Spec.before_each { CrymbleUI::FontSizing.reset_zoom }
  Spec.after_each { CrymbleUI::FontSizing.reset_zoom }

  it "zoom_in widens the combo's drawn text glyphs" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ZoomComboApp.new
    app.build_tree
    renderer.settle_rendering(app)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    before = drawn_text_extent(combo)
    before.should be > 0 # "Apple" + arrow are drawn

    CrymbleUI::FontSizing.zoom_in
    zoom_invalidate(app.root.not_nil!)
    2.times do
      app.rebuild if app.root.try(&.needs_layout?)
      renderer.render_frame(app)
    end

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    after = drawn_text_extent(combo)
    after.should be > before # the glyphs actually render larger, not just measure larger
  end
end
