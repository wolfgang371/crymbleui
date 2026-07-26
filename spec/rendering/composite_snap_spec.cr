require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"

# Layer composite positions snap via PixelSnap (half-up), identically in the headless
# and SFML compositors (parity by construction — both call PixelSnap.snap).
# Pinned by comparing whole-window output of a fractionally-positioned panel against
# the integer position snap maps it to:
#   +20.5 -> 21  (truncation — the old headless behavior — gave 20)
#   -20.5 -> -20 (ties-away — the old SFML behavior — gave -21; panels ARE draggable
#                 to negative x by design: min_x = window.x - width + margin)

# Captures the INTERIOR of the panel (edges excluded): the interior rides the panel
# LAYER's composite — the thing this spec pins — while the panel's edge fills are
# root-layer vector fills that rasterize sub-pixel BY POLICY (outside snap's scope).
private def panel_interior_at(x : Float64, snapped_x : Int32) : Array(UInt32)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  window = CrymbleUI::Window.new("t", 400, 300)
  panel = CrymbleUI::WindowPanel.new("P", x, 40.0, 200.0, 150.0)
  window.add_child(panel)
  app.root_widget = window
  app.build_tree
  renderer.settle_rendering(app)
  # interior rect in window coords, inset 4px from every panel edge, clipped to window
  ix = {snapped_x + 4, 0}.max
  iw = snapped_x + 200 - 4 - ix
  renderer.backend.capture_region_pixels(ix, 44, iw, 150 - 8)
end

describe "composite position snapping" do
  it "composites a panel at x=+20.5 exactly like x=+21 (snap, not truncation)" do
    panel_interior_at(20.5, 21).should eq(panel_interior_at(21.0, 21))
  end

  it "composites a panel at x=-20.5 exactly like x=-20 (snap, not ties-away)" do
    panel_interior_at(-20.5, -20).should eq(panel_interior_at(-20.0, -20))
  end

  it "composites a panel at x=+20.3 exactly like x=+20 (sub-.5 pins snap uniquely vs ceil)" do
    panel_interior_at(20.3, 20).should eq(panel_interior_at(20.0, 20))
  end
end
