require "../spec_helper"
require "../../src/core/drag_manager"

# The default drag GhostWidget sources its fill, border and label from Theme.current, read at
# paint time (like the sibling SimpleGhostWidget). The fill MUST be OPAQUE: it sits on a
# transparent-black RenderTexture layer whose layer.opacity is GHOST_OPACITY (< 1), and a
# semi-transparent fill there is premultiplied over black (rgb * a) THEN attenuated AGAIN by
# layer.opacity -> muddy + darkened. The see-through comes from layer.opacity, never the fill alpha.
private def ghost_primitives(text : String? = nil) : Array(CrymbleUI::DrawPrimitive)
  ghost = CrymbleUI::GhostWidget.new(40.0, 20.0, text)
  ghost.to_primitives(CrymbleUI::Rect.new(0, 0, 40.0, 20.0))
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
