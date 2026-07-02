require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/button"
require "../../src/layout/hstack"
require "../../src/testing/test_renderer"

# / when a materialized (non-viewport_cache) layer GROWS within its over-allocated backend,
# LayerRenderer#repaint_exposed_on_grow scissored-clears the newly-exposed strip and selectively re-renders
# only the widgets it uncovered (no full clear, no propagation storm).
#
# NOTE (option X): the original symptom — content CLIPPED beyond a narrow panel, then exposed
# on widen ("nonappearing buttons during resize") — can no longer occur for non-scrolling content: the
# panel now floors+grows to its content width, so chrome never clips (that behaviour is covered by
# spec/rendering/panel_width_floor_spec.cr). The two clip-then-expose tests that proved the old symptom were
# retired with that change. repaint_exposed_on_grow still earns its keep on the grow path: it clears the
# newly-exposed MARGIN (stale pixels) and stays storm-free — which the tests below pin.

describe "Materialized layer grow services the newly-exposed strip" do
  it "clears the newly-exposed bottom strip on a height grow" do
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 700)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 700, 700)
    panel = CrymbleUI::WindowPanel.new("Shape", 80.0, 60.0, 400.0, 300.0, resizable: true, id: "panel")
    hstack = CrymbleUI::HStack.new(spacing: 4.0)
    hstack.add_child(CrymbleUI::Button.new("only") { }) # short content → panel keeps its 300px height
    panel.add_child(hstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    layer = panel.layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    bottom = panel.y + panel.height # 360.0
    old_h = panel.height
    app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + 150.0, bottom - 3.0))
    renderer.render_frame(app)
    # Poke a stale color into the bottom margin (layer-local y just beyond the old height 300), in a
    # region the heighten will EXPOSE but no widget covers.
    stale = CrymbleUI::Color.new(255, 0, 0, 255)
    backend.fill_rect(CrymbleUI::Rect.new(40.0, 305.0, 8.0, 8.0), stale)
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + 150.0, bottom + 30.0)) # heighten: 300 → 330
    renderer.render_frame(app)

    panel.height.should be > old_h # the drag actually grew the panel
    backend.get_pixel(44, 307).should eq layer.background_color # bottom strip cleared
  end

  it "re-renders nothing when the grow exposes no widget (no accidental always-render)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Shape", 100.0, 80.0, 500.0, 300.0, resizable: true, id: "panel")
    hstack = CrymbleUI::HStack.new(spacing: 4.0)
    3.times { |i| hstack.add_child(CrymbleUI::Button.new("B#{i}") { }) } # all well within the panel
    panel.add_child(hstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    buttons = hstack.children.map(&.as(CrymbleUI::Button))
    right = panel.x + panel.width
    app.handle_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 150.0))
    renderer.render_frame(app)
    app.handle_mouse_move(CrymbleUI::Vec2.new(right + 20.0, panel.y + 150.0)) # widen into empty space
    renderer.render_frame(app)

    # The strip holds no content → no content widget should be re-rendered.
    buttons.count { |b| renderer.widget_disposition(b) == :rendered }.should eq 0
  end

  it "clears the newly-exposed strip so a stale margin (e.g. after a reactive theme recolor) is wiped" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Shape", 100.0, 80.0, 400.0, 300.0, resizable: true, id: "panel")
    hstack = CrymbleUI::HStack.new(spacing: 4.0)
    hstack.add_child(CrymbleUI::Button.new("only") { }) # one button at the far left
    panel.add_child(hstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    layer = panel.layer.not_nil!
    backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    right = panel.x + panel.width # 500.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 150.0))
    renderer.render_frame(app)
    # Poke a stale color into the over-allocated margin (layer-local x just beyond the old width 400),
    # in a region the coming grow will EXPOSE but no widget covers. Simulates a margin left stale by a
    # reactive theme recolor (which doesn't reclear the backend). Without the scissored-clear it lingers.
    stale = CrymbleUI::Color.new(255, 0, 0, 255)
    backend.fill_rect(CrymbleUI::Rect.new(405.0, 40.0, 8.0, 8.0), stale)
    app.handle_mouse_move(CrymbleUI::Vec2.new(right + 30.0, panel.y + 150.0)) # grow: width 400 → 430
    renderer.render_frame(app)

    # local (407,44) is in the strip [400,430], covered by no widget → must be the background, not stale.
    backend.get_pixel(407, 44).should eq layer.background_color
  end

  it "renders only the exposed sliver across a sustained widen (no propagation storm)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 900, 600)
    panel = CrymbleUI::WindowPanel.new("Shape", 100.0, 80.0, 500.0, 400.0, resizable: true, id: "panel")
    hstack = CrymbleUI::HStack.new(spacing: 4.0)
    16.times { |i| hstack.add_child(CrymbleUI::Button.new("B#{i}") { }) }
    panel.add_child(hstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    buttons = hstack.children.map(&.as(CrymbleUI::Button))
    right = panel.x + panel.width
    app.handle_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 200.0))
    renderer.render_frame(app)

    max_rendered = 0
    8.times do |i|
      app.handle_mouse_move(CrymbleUI::Vec2.new(right + (i + 1) * 6.0, panel.y + 200.0)) # +6px per frame
      renderer.render_frame(app)
      rc = buttons.count { |b| renderer.widget_disposition(b) == :rendered }
      max_rendered = Math.max(max_rendered, rc)
    end

    # A storm would re-render many/all 16 every frame; the selective grow path stays bounded.
    max_rendered.should be < 5
  end
end
