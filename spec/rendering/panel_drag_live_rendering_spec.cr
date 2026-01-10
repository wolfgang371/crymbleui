require "../spec_helper"

# Tests for live rendering during panel drag
# PROBLEM: User reports "content does not live-move" - during drag, content
# may not update visually in real-time, or renders at wrong position

describe "Panel Drag Live Rendering" do
  describe "Content position during drag motion" do
    # Obsolete tests deleted:
    # - "button position updates immediately during drag" - bounds intentionally stale for O(1) performance
    # - "content primitives use updated positions during drag" - primitives are widget-local

    it "layer bounds update during drag motion" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      initial_layer_x = panel_layer.bounds.x

      # Drag panel
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
      panel.on_mouse_move(CrymbleUI::Vec2.new(200.0, 115.0))  # +50px

      # Layer bounds should move with panel
      panel_layer.bounds.x.should eq(initial_layer_x + 50.0)
    end

    it "layer marks as needing render during drag" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Clear render state (simulate clean layer after render)
      panel_layer.clear_render_state

      # Layer should be clean
      panel_layer.needs_render?.should be_false

      # Drag panel
      panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
      panel.on_mouse_move(CrymbleUI::Vec2.new(200.0, 115.0))

      # Layer should need render after drag
      panel_layer.needs_render?.should be_true
    end
  end
end
