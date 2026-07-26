require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/testing/test_renderer"

# Headless twin for the retired scrollview_panel_autotest (bug-1: drag-reveal ghost).
#
# When a front panel is dragged off an overlapping back panel, the strip it uncovers
# must repaint with the BACK panel's pixels — not a ghost of the front panel's old
# content. The original SFML-only symptom was a descendant layer whose bounds failed
# to follow the panel during a drag, so it kept compositing at the OLD location.
#
# This twin samples the WINDOW COMPOSITE (r.backend, the composited root — the same
# view compositing_z_index_spec.cr uses), not any single panel's own layer, because
# the reveal is a cross-layer compositing property. Two overlapping panels carry
# DISTINCT solid backgrounds (back = red, front = green) over the distinct default
# window background; the front is dragged away and the revealed strip is checked.
#
# The FIRST `it` is the mandated PRE-CHECK: prove the headless window composite models
# overlap-repaint on CURRENT-GOOD code (else this is a harness gap, not a twin). The
# SECOND `it` is the twin proper, whose RED is a seeded ghost (see the block comment
# there) — the 685adef drag-layer hunk (update_scrollview_layers_for_drag) no longer
# exists (pull-based bounds superseded it), so it is not separably revertible.
private BACK_COLOR  = CrymbleUI::Color.new(200, 0, 0, 255)   # red
private FRONT_COLOR = CrymbleUI::Color.new(0, 200, 0, 255)   # green

# Build two overlapping panels, render, then drag the FRONT panel down-right so it no
# longer covers the sample strip. Returns the settled renderer with the composite drawn.
private def render_after_reveal_drag : {CrymbleUI::Testing::TestRenderer, CrymbleUI::WindowPanel}
  renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", 800, 600)

  back = CrymbleUI::WindowPanel.new("back", 100.0, 100.0, 400.0, 400.0, id: "back")
  back.background_color = BACK_COLOR
  back.z_index = 0

  front = CrymbleUI::WindowPanel.new("front", 250.0, 250.0, 300.0, 300.0, id: "front")
  front.background_color = FRONT_COLOR
  front.z_index = 10

  window.add_child(back)
  window.add_child(front)
  app.root_widget = window

  renderer.render_frame(app)
  renderer.settle_rendering(app)

  # Grab the front panel by its title bar (central, clear of the resize edges and the
  # close button) and drag it +200,+200 so the overlap strip is uncovered.
  down = CrymbleUI::Vec2.new(front.x + 150.0, front.y + front.title_bar_height * 0.5)
  renderer.mouse_down(down.x, down.y)
  renderer.render_frame(app)
  front.dragging?.should be_true

  renderer.mouse_move(down.x + 200.0, down.y + 200.0)
  renderer.render_frame(app)

  renderer.mouse_up(down.x + 200.0, down.y + 200.0)
  {renderer, front}
end

# Sample grid inside the revealed strip: points that WERE under the front panel
# (front originally covered 250..550) and, after the +200 drag (front now 450..750),
# are uncovered again while still inside the back panel (100..500) and below both
# title bars.
private SAMPLE_POINTS = [
  {300, 300}, {340, 340}, {380, 380}, {420, 420},
  {300, 420}, {420, 300},
]

describe "Panel drag reveal (back-panel repaint, no front ghost)" do
  it "PRE-CHECK: the headless window composite models overlap-repaint (reveal shows back)" do
    renderer, _front = render_after_reveal_drag

    # If this fails on current-good code, the composite cannot model the reveal — that is
    # a HARNESS GAP to surface, not a passing twin.
    SAMPLE_POINTS.each do |(sx, sy)|
      p = renderer.backend.get_pixel(sx, sy)
      p.should_not be_nil, "no composited pixel at (#{sx},#{sy})"
      px = p.not_nil!
      {px.r, px.g, px.b}.should eq({BACK_COLOR.r, BACK_COLOR.g, BACK_COLOR.b}),
        "revealed strip at (#{sx},#{sy}) is RGBA(#{px.r},#{px.g},#{px.b},#{px.a}), expected back red"
    end
  end

  it "revealed strip repaints with the back panel color, not a front-panel ghost" do
    renderer, _front = render_after_reveal_drag

    SAMPLE_POINTS.each do |(sx, sy)|
      p = renderer.backend.get_pixel(sx, sy).not_nil!
      # A ghost of the front panel would leave FRONT_COLOR (green) here.
      {p.r, p.g, p.b}.should eq({BACK_COLOR.r, BACK_COLOR.g, BACK_COLOR.b}),
        "reveal ghost at (#{sx},#{sy}): RGBA(#{p.r},#{p.g},#{p.b},#{p.a}) — front pixels left in the strip"
    end
  end
end
