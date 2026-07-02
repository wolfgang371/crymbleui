require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/button"
require "../../src/widgets/scroll_view"
require "../../src/layout/hstack"

# (option X): width is symmetric with height — the panel floors at its content's min-intrinsic
# WIDTH and auto-GROWS to it at build, so non-scrolling chrome never clips (window-permitting). Opt-in
# scrolling: wrap content in a ScrollView (min-width 0) and the panel can shrink past it.
private def build_wide_panel(built_width = 150.0, scrolled = false)
  renderer = CrymbleUI::Testing::TestRenderer.new(1400, 800)
  app = TestApp.new
  window = CrymbleUI::Window.new("T", 1400, 800)
  panel = CrymbleUI::WindowPanel.new("P", 40.0, 40.0, built_width, 400.0)
  row = CrymbleUI::HStack.new(spacing: 4.0)
  8.times { |i| row.add_child(CrymbleUI::Button.new("Item#{i}") { }) } # a wide row, min-width >> 150
  if scrolled
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both, id: "sv")
    sv.set_content(row)
    panel.add_child(sv)
  else
    panel.add_child(row)
  end
  window.add_child(panel)
  app.root_widget = window
  renderer.settle_rendering(app)
  {renderer, app, panel}
end

describe "WindowPanel width floor (option X)" do
  it "auto-grows a panel built narrower than its content width (chrome never clips at build)" do
    renderer, app, panel = build_wide_panel(built_width: 150.0)
    # The width grew at build to fit the row — RED without the perform_layout width-grow (stays ~150).
    panel.width.should be > 300.0
  end

  it "refuses to shrink width below the content floor on a resize-drag" do
    renderer, app, panel = build_wide_panel(built_width: 600.0)
    ey = panel.y + panel.height / 2.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ey))
    panel.on_mouse_move(CrymbleUI::Vec2.new(panel.x + 10.0, ey)) # ask for a ~10px-wide panel
    renderer.render_frame(app)
    # Floored well above MIN_PANEL_SIZE (the content row's width) — RED without the min_w clamp (→ 100).
    panel.width.should be > 300.0
  end

  it "lets a ScrollView-wrapped body shrink past the content (opt-in scroll, escape valve)" do
    renderer, app, panel = build_wide_panel(built_width: 600.0, scrolled: true)
    ey = panel.y + panel.height / 2.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ey))
    panel.on_mouse_move(CrymbleUI::Vec2.new(panel.x + 10.0, ey))
    renderer.render_frame(app)
    # The ScrollView reports min-width 0, so the panel shrinks to ~MIN_PANEL_SIZE and scrolls the row.
    panel.width.should be < 150.0
  end
end
