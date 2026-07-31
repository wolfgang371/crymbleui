require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/button"
require "../../src/widgets/text"

# OCCLUSION CULLING.
#
# A layer lying entirely behind an opaque layer that composites above it cannot be seen, so
# rendering its body is pure waste — measured 171 -> 71 ms per interaction on a ten-Shape demo,
# 9 of 93 layers rendering instead of 81.
#
# The saving is only legitimate if it is INVISIBLE. Three properties carry that, and each names a
# way the optimisation could ship a bug instead of a speed-up:
#   1. it must skip what is genuinely covered (or it does nothing at all);
#   2. it must never skip what is visible — partial cover, translucent cover;
#   3. a REVEAL must paint correct pixels in the very frame that reveals, not a frame later.
# (3) is the one that would show as a flash of stale content, and it is why the skip does not clear
# the layer's render mark: the gate is a level-triggered pull, so the frame in which the occluder
# moves finds the layer still stale and renders it before that frame's composite.
private BACK_COLOR = CrymbleUI::Color.new(0_u8, 0_u8, 255_u8, 255_u8)

# Two overlapping panels. As declared, the front panel contains the back one outright, the 3 px
# occluder inset included: back (60,60)-(180,160) sits inside front's inset (43,43)-(337,287).
class OcclusionApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Occlusion", 500, 400) do
      window_panel("Back", x: 60.0, y: 60.0, width: 120.0, height: 100.0, id: "back") do
        b = button("back content", id: "back_btn") { }
        b.background_color = BACK_COLOR
      end
      window_panel("Front", x: 40.0, y: 40.0, width: 300.0, height: 250.0, id: "front") do
        text("front content", id: "front_text")
      end
    end
  end
end

# Move the occluder by mutating the WIDGET, which is what a drag does. WindowPanel#x is
# `reconcile: true` — a panel's position deliberately survives rebuilds, so re-running build() with
# a different declared x cannot move it (that would snap a dragged panel back on every rebuild).
private def move_front_to(app, x : Float64)
  app.find("front").not_nil!.as(CrymbleUI::WindowPanel).x = x
end

# WindowPanel names its internal layer "panel_#{id}", so this is the back panel's own layer.
private def back_layers(app) : Array(CrymbleUI::Layer)
  CrymbleUI::Layer.active_layers(app.root.not_nil!).select { |l| l.id == "panel_back" }
end

private def back_rendered?(app) : Bool
  CrymbleUI::LayerRenderer.rendered_layer_ids.includes?("panel_back")
end

# Dirty the back panel's content, so that WITHOUT culling the renderer would certainly render it.
private def dirty_back(app)
  app.find("back_btn").not_nil!.mark_needs_render
end

# One frame whose counters describe THAT frame. reset_frame_counters is called by the SFML loop,
# never by TestRenderer, so without this rendered_layer_ids accumulates over every frame the spec
# has ever drawn and "was it rendered?" would answer for the whole run.
private def frame(renderer, app)
  CrymbleUI::LayerRenderer.reset_frame_counters
  renderer.render_frame(app)
end

private def back_pixels_visible?(renderer) : Bool
  (62...178).any? do |x|
    (62...158).any? { |y| renderer.backend.get_pixel(x, y) == BACK_COLOR }
  end
end

describe "Occlusion culling" do
  it "skips a fully covered layer that would otherwise have rendered" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app = OcclusionApp.new
    app.build_tree
    renderer.settle_rendering(app)

    dirty_back(app)
    frame(renderer, app)

    CrymbleUI::LayerRenderer.frame_layers_occluded.should be > 0
    back_rendered?(app).should be_false
  end

  it "does not skip a layer that is only partially covered" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app = OcclusionApp.new
    app.build_tree
    renderer.settle_rendering(app)
    move_front_to(app, 120.0) # now overlaps the back panel's right part only
    renderer.settle_rendering(app)

    dirty_back(app)
    frame(renderer, app)

    back_rendered?(app).should be_true
  end

  it "does not skip a layer covered by a TRANSLUCENT one, which composites it through" do
    # WindowPanel#compute_background_for_layer forwards the widget's colour live, so this reaches
    # the layer the culler inspects.
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app = OcclusionApp.new
    app.build_tree
    renderer.settle_rendering(app)

    front = app.find("front").not_nil!.as(CrymbleUI::WindowPanel)
    front.background_color = CrymbleUI::Color.new(200_u8, 200_u8, 200_u8, 200_u8)
    dirty_back(app)
    frame(renderer, app)

    back_rendered?(app).should be_true
  end

  it "paints the revealed layer in the same frame the occluder moves away (no stale flash)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app = OcclusionApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Several frames in which the back panel is stale AND skipped — the state a reveal must survive.
    3.times do
      dirty_back(app)
      frame(renderer, app)
      back_rendered?(app).should be_false
    end

    # The reveal. Exactly ONE frame is drawn: what it leaves on screen is what the user sees.
    move_front_to(app, 260.0)
    frame(renderer, app)

    back_pixels_visible?(renderer).should be_true
  end

  it "clears a skipped layer's dirty-widget set, so it cannot pin discarded widget generations" do
    # The skip path bypasses render_layer, and @dirty_widgets is only emptied by that method's
    # clear_render_state. Left alone, an occluded layer accumulates every widget ever marked on it
    # and keeps whole dead generations alive: measured 28 -> 90 MB of heap over a few hundred
    # rebuilds, while GPU memory fell. An empty set also means "all dirty" (Layer#widget_dirty?),
    # which is the right disposition for a layer that has been invisible for a while.
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
    app = OcclusionApp.new
    app.build_tree
    renderer.settle_rendering(app)

    back_layers(app).should_not be_empty

    5.times do
      dirty_back(app)
      frame(renderer, app)
    end

    back_layers(app).each { |l| l.dirty_widgets.should be_empty }
  end
end
