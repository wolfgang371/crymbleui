require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/layout/vstack"
require "../../src/layout/hstack"

# perf budget — the guard be1ffa9 said was MISSING (primitive_count is blind to the
# mark_needs_render PROPAGATION storm that forced live-resize to be reverted in Nov-2025). The
# live-content-layout policy must keep per-resize-frame work BOUNDED on the 400-button stress
# panel: no primitive REGEN storm (cached blit), no propagation storm (mark_render_count O(n)).

describe "live-resize perf budget (400-button stress panel)" do
  it "keeps per-frame primitive + propagation work bounded during a sustained resize" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("Stress", 1200, 900)
    panel = CrymbleUI::WindowPanel.new("Stress (400)", 50.0, 150.0, 700.0, 600.0)
    pv = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |col| hs.add_child(CrymbleUI::Button.new("#{row},#{col}") { }) }
      pv.add_child(hs)
    end
    panel.add_child(pv)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    right = 50.0 + 700.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, 400.0))
    3.times { |i| panel.on_mouse_move(CrymbleUI::Vec2.new(right + (i + 1) * 4.0, 400.0)); renderer.render_frame(app) }

    m = 20
    max_prims = 0
    max_marks = 0
    max_measures = 0
    m.times do |i|
      CrymbleUI::Widget.reset_mark_render_count
      CrymbleUI::Widget.reset_measure_count
      renderer.reset_counters
      panel.on_mouse_move(CrymbleUI::Vec2.new(right + (3 + i + 1) * 4.0, 400.0))
      renderer.render_frame(app)
      max_prims = Math.max(max_prims, renderer.primitive_count)
      max_marks = Math.max(max_marks, CrymbleUI::Widget.mark_render_count)
      max_measures = Math.max(max_measures, CrymbleUI::Widget.measure_count)
    end

    puts "\n[perf] over #{m} resize frames: max prims/frame=#{max_prims}  max marks/frame=#{max_marks}  max measures/frame=#{max_measures}"

    # No primitive REGEN storm — content blits from cache, only chrome regenerates.
    max_prims.should be < 60
    # No propagation storm (the be1ffa9 axis, invisible to prims). ~421 widgets → O(n); a storm
    # (O(n²)/cascade) would be far higher. Generous bound that still catches a regression.
    max_marks.should be < 3000
    # The measure-walk is the real cost: O(n), ~4×widget-count; bound well above, below O(n²).
    max_measures.should be < 6000
  end

  # The death-spiral guard: the event loop COALESCES events (polls every pending mouse-move, then
  # renders once). The resize layout MUST coalesce the same way — mark needs-layout per event, run
  # layout_children ONCE per frame in prepare_layout. If it lays out per event instead, a fast drag
  # runs the full content layout dozens of times per frame (measures explode 1600 → tens of
  # thousands, frames hit hundreds of ms — observed live on stress_panel_demo).
  it "coalesces many resize moves into ONE layout per frame (not one per event)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("Stress", 1200, 900)
    panel = CrymbleUI::WindowPanel.new("Stress (400)", 50.0, 150.0, 700.0, 600.0)
    pv = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |col| hs.add_child(CrymbleUI::Button.new("#{row},#{col}") { }) }
      pv.add_child(hs)
    end
    panel.add_child(pv)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    bottom = 150.0 + 600.0
    panel.on_mouse_down(CrymbleUI::Vec2.new(400.0, bottom - 3.0))

    # 12 mouse-moves WITHOUT rendering (the event loop coalesces them), then ONE render.
    CrymbleUI::Widget.reset_measure_count
    12.times { |i| panel.on_mouse_move(CrymbleUI::Vec2.new(400.0, bottom + (i + 1) * 8.0)) }
    moves_measures = CrymbleUI::Widget.measure_count
    renderer.render_frame(app)
    total_measures = CrymbleUI::Widget.measure_count

    # The 12 moves must NOT each lay out (they only mark) — and the single render lays out ONCE.
    moves_measures.should eq 0
    total_measures.should be < 3200 # one layout (~1600), NOT 12 × 1600
  end
end
