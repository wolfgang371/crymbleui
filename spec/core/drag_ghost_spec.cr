require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# The default drag GhostWidget sources its fill, border and label from Theme.current, read at
# paint time (like the sibling SimpleGhostWidget). The fill MUST be OPAQUE: it sits on a
# transparent-black RenderTexture layer whose layer.opacity is GHOST_OPACITY (< 1), and a
# semi-transparent fill there is premultiplied over black (rgb * a) THEN attenuated AGAIN by
# layer.opacity -> muddy + darkened. The see-through comes from layer.opacity, never the fill alpha.
private def ghost_primitives(text : String? = nil) : Array(CrymbleUI::DrawPrimitive)
  ghost = CrymbleUI::GhostWidget.new(CrymbleUI::Size.new(40.0, 20.0), text, 0)
  ghost.to_primitives(CrymbleUI::Rect.new(0, 0, ghost.size.width, ghost.size.height))
end

private def ghost_fill : CrymbleUI::Color
  ghost_primitives.select(CrymbleUI::FillRect).first.color
end

private def ghost_border : CrymbleUI::Color
  ghost_primitives.select(CrymbleUI::DrawRect).first.color
end

private def ghost_label_color : CrymbleUI::Color
  ghost_primitives("X").select(CrymbleUI::DrawText).first.color
end

describe "GhostWidget drag preview (themed + premultiply-safe)" do
  describe "tracks the active theme" do
    # The :dark leg is the discriminator between read-at-paint and captured-at-construction:
    # a hardcoded light value would pass under the spec-default :light theme but fail here.
    it "sources the fill from Theme.current.drag_ghost" do
      ghost_fill.should eq(CrymbleUI::Theme.current.drag_ghost)
      begin
        CrymbleUI::Theme.set(:dark)
        ghost_fill.should eq(CrymbleUI::Theme.current.drag_ghost)
      ensure
        CrymbleUI::Theme.set(:light)
      end
    end

    it "derives the border as a darker shade of the themed fill" do
      ghost_border.should eq(CrymbleUI::Theme.current.drag_ghost.darken(CrymbleUI::GhostWidget::BORDER_DARKEN))
      # Intent, independent of the exact darken factor: strictly darker than the fill per channel
      # (guards against BORDER_DARKEN drifting to 0, which the eq-mirror alone would not catch).
      f = ghost_fill
      b = ghost_border
      b.r.should be < f.r
      b.g.should be < f.g
      b.b.should be < f.b
    end

    it "sources the label color from Theme.current.text_default (readable on the themed fill)" do
      ghost_label_color.should eq(CrymbleUI::Theme.current.text_default)
      begin
        CrymbleUI::Theme.set(:dark)
        ghost_label_color.should eq(CrymbleUI::Theme.current.text_default)
      ensure
        CrymbleUI::Theme.set(:light)
      end
    end
  end

  describe "premultiply-safe (opaque fill; see-through from layer.opacity)" do
    it "paints an OPAQUE fill shown through a sub-1.0 layer opacity" do
      ghost_fill.a.should eq(255_u8)
      CrymbleUI::DragManager::GHOST_OPACITY.should be < 1.0
      CrymbleUI::DragManager::GHOST_OPACITY.should be > 0.0
    end

    it "composites to the clean hue — an opaque fill takes no premultiply darkening" do
      # Model SFML's two BlendAlpha stages from the ACTUAL painted alpha (validate-the-instrument:
      # TestRenderBackend#fill_rect OVERWRITES, so a rendered pixel can't show SFML's premultiply).
      fill = ghost_fill
      op = CrymbleUI::DragManager::GHOST_OPACITY
      af = fill.a / 255.0
      composite_b = fill.b * af * (af * op) # stage 1 premultiply (xaf) then stage 2 composite (xaf*op)
      ideal_b = fill.b * op                 # opaque (af == 1): full hue, no premultiply loss
      # Holds iff af == 1. A semi-transparent fill (a < 255) darkens strictly below the ideal here.
      composite_b.should be_close(ideal_b, 0.001)
    end
  end
end

# Where the label sits. The label is the payload's (it can be longer than the source), drawn at the font scale of the
# source's first Text, centred in a ghost that is the source + 12 or, for a longer label, the label + its padding.
# Everything measured here independently of the ghost: the DrawText's position against measure_text of its own
# text at its own size, the block's height against TextLines.block_extent.

private class NoLabelData < CrymbleUI::DragData
  def data_type : String
    "nothing"
  end
end

# A source with no Text: a fixed box
private class Swatch < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(60.0, 20.0))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class GhostApp < CrymbleUI::App
  # chip: the source's text, or nil for a source with no Text; nested: the Text inside an HStack (Embrace's rows)
  def initialize(@payload : String?, @chip : String?, @font_scale : Int32 = -1, @nested : Bool = true)
    super()
  end

  def build : CrymbleUI::Widget
    window("Ghost", 900, 500) do
      vstack(padding: 20.0) do
        data = (p = @payload) ? CrymbleUI::TextDragData.new(p) : NoLabelData.new
        draggable(data: data, id: "chip") do
          label = @chip
          scale = @font_scale
          if label && @nested
            hstack(padding: 6.0) { text(label, font_scale: scale) }
          elsif label
            text(label, font_scale: scale)
          else
            widget(Swatch.new)
          end
        end
      end
    end
  end
end

# The ghost of a real drag, looked at before the drop: {its layer's rect, its label (nil without one), the source}
private def drag_ghost(app : GhostApp) : {CrymbleUI::Rect, CrymbleUI::DrawText?, CrymbleUI::Rect}
  renderer = CrymbleUI::Testing::TestRenderer.new(900, 500)
  app.build_tree
  renderer.settle_rendering(app)
  source = app.find("chip").not_nil!.viewport_bounds
  app.handle_mouse_down(source.center)
  app.handle_mouse_move(source.center + CrymbleUI::Vec2.new(40.0, 40.0))
  layer = app.drag_manager.ghost_layer.not_nil!
  ghost = layer.widgets.first
  label = ghost.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, layer.bounds.width, layer.bounds.height))
    .select(CrymbleUI::DrawText).first?
  app.handle_mouse_up(source.center + CrymbleUI::Vec2.new(40.0, 40.0))
  {layer.bounds, label.try(&.as(CrymbleUI::DrawText)), source}
end

# The label's gaps to the ghost's edges, left / right / top / bottom (ghost-local coordinates)
private def gaps(ghost : CrymbleUI::Rect, label : CrymbleUI::DrawText) : {Float64, Float64, Float64, Float64}
  width = CrymbleUI::Widget.measure_text(label.text, label.size).width
  height = CrymbleUI::TextLines.block_extent(CrymbleUI::TextLines.count(label.text), label.size)
  {label.position.x, ghost.width - (label.position.x + width), label.position.y, ghost.height - (label.position.y + height)}
end

private def centred_inside(ghost, label) : Nil
  left, right, top, bottom = gaps(ghost, label)
  {left, right, top, bottom}.each { |g| g.should be >= 0.0 }
  (left - right).abs.should be <= 1.0
  (top - bottom).abs.should be <= 1.0
end

describe "GhostWidget label placement (a real drag)" do
  it "fits a label longer than its source, centred - the ghost grows to the label and its padding" do
    ghost, label, source = drag_ghost(GhostApp.new("Text A is the payload", "Text"))
    centred_inside(ghost, label.not_nil!)
    ghost.width.should be > source.width + 12.0
  end

  it "centres a short label in a wider source, which keeps the source + 12" do
    ghost, label, source = drag_ghost(GhostApp.new("X", "A rather wide chip"))
    centred_inside(ghost, label.not_nil!)
    ghost.width.should be_close(source.width + 12.0, 0.01)
    ghost.height.should be_close(source.height + 12.0, 0.01)
  end

  it "draws the label at the font scale of the source's first Text, nested or not" do
    {true, false}.each do |nested|
      _, label, _ = drag_ghost(GhostApp.new("Text A", "Text", -1, nested))
      label.not_nil!.size.should eq CrymbleUI::FontSizing.calculate_size(-1)
    end
  end

  it "draws the label at the base scale for a source without a Text" do
    _, label, _ = drag_ghost(GhostApp.new("Text A", nil))
    label.not_nil!.size.should eq CrymbleUI::FontSizing.calculate_size(0)
  end

  it "centres a two-line label as a block" do
    ghost, label, _ = drag_ghost(GhostApp.new("first line\nsecond", "Text"))
    centred_inside(ghost, label.not_nil!)
  end

  it "still fits and centres at a zoom set before the drag" do
    CrymbleUI::FontSizing.zoom_in
    CrymbleUI::FontSizing.zoom_in
    ghost, label, _ = drag_ghost(GhostApp.new("Text A is the payload", "Text"))
    label.not_nil!.size.should eq CrymbleUI::FontSizing.calculate_size(-1)
    centred_inside(ghost, label.not_nil!)
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end

  it "keeps the source + 12 for a payload without a label" do
    ghost, label, source = drag_ghost(GhostApp.new(nil, "Text"))
    label.should be_nil
    ghost.width.should be_close(source.width + 12.0, 0.01)
    ghost.height.should be_close(source.height + 12.0, 0.01)
  end
end
