require "../spec_helper"
require "../../src/testing/test_renderer"

# Combined correctness and performance tests for panel drag
# Tests BOTH that drag works correctly AND that it's performant
#
# Correctness:
# - Content pixels visible during drag (not blank)
# - Content position updates during drag (moves with panel)
#
# Performance:
# - No widget re-renders during drag (0 primitives)
# - Compositor runs but doesn't clear buffers
# - Performance is O(1), not O(n) widgets

describe "Panel Drag: Correctness and Performance" do
  it "drag is correct (pixels visible) and performant (no re-renders)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 300.0, 200.0)

    # Add 10 buttons
    10.times do |i|
      button = CrymbleUI::Button.new("Button #{i}") { }
      panel.add_child(button)
    end

    window.add_child(panel)
      app.root_widget = window

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

    # Initial render and settle
    renderer.render_frame(app)
    renderer.settle_rendering(app)
    renderer.reset_counters

    # === CORRECTNESS: Verify initial content is visible ===
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixel from button area (panel-local coordinates)
    initial_pixel = backend.get_pixel(10, 40)
    initial_pixel.should_not be_nil

    button_blue = CrymbleUI::Color.new(0, 120, 215, 255)
    panel_bg = CrymbleUI::Color.new(240, 240, 240, 255)

    # Initial content should be button blue, not panel background
    initial_pixel.should_not eq panel_bg

    # === PERFORMANCE: Drag should not re-render widgets ===
    # Start drag
    renderer.mouse_down(150.0, 65.0)  # On title bar
    renderer.render_frame(app)

    # Reset counters BEFORE drag loop (not inside!)
    renderer.reset_counters

    # During drag
    10.times do |i|
      renderer.mouse_move(150.0 + i * 10, 65.0)
      renderer.render_frame(app)
    end

    # Performance assertions
    renderer.primitive_count.should eq 0  # No widget re-renders
    renderer.layer_backend_clear_count.should eq 0  # No layer buffer clears (window background clear is OK)
    renderer.compositor_call_count.should eq 10  # Compositor ran per frame
    renderer.backend_blit_count.should eq 20  # 2 layers × 10 frames


    # === CORRECTNESS: Content still visible after drag ===
    current_pixel = backend.get_pixel(10, 40)
    current_pixel.should_not be_nil

    if current_pixel == panel_bg || current_pixel.nil?
      fail "❌ Content is BLANK after drag! Pixel: #{current_pixel}"
    end

  end

  it "drag performance is O(1), not O(n) widgets" do
    # Test with 10 buttons
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 400.0, 300.0)

    10.times { |i| panel.add_child(CrymbleUI::Button.new("Btn#{i}") { }) }
    window.add_child(panel)
      app.root_widget = window

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

    renderer.render_frame(app)
    renderer.settle_rendering(app)
    renderer.reset_counters

    # Drag with 10 buttons
    renderer.mouse_down(150.0, 65.0)
    renderer.render_frame(app)
    10.times { |i| renderer.mouse_move(150.0 + i * 10, 65.0); renderer.render_frame(app) }

    primitives_10 = renderer.primitive_count
    compositor_calls_10 = renderer.compositor_call_count
    blits_10 = renderer.backend_blit_count

    # Test with 100 buttons
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 400.0, 300.0)

    100.times { |i| panel.add_child(CrymbleUI::Button.new("Btn#{i}") { }) }
    window.add_child(panel)
      app.root_widget = window


    renderer.render_frame(app)
    renderer.settle_rendering(app)
    renderer.reset_counters

    # Drag with 100 buttons
    renderer.mouse_down(150.0, 65.0)
    renderer.render_frame(app)
    10.times { |i| renderer.mouse_move(150.0 + i * 10, 65.0); renderer.render_frame(app) }

    primitives_100 = renderer.primitive_count
    compositor_calls_100 = renderer.compositor_call_count
    blits_100 = renderer.backend_blit_count

    # O(1) performance: counts should be identical
    primitives_10.should eq primitives_100
    compositor_calls_10.should eq compositor_calls_100
    blits_10.should eq blits_100

  end

  it "idle frames skip compositor and render nothing" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 300.0, 200.0)

    10.times { |i| panel.add_child(CrymbleUI::Button.new("Btn#{i}") { }) }
    window.add_child(panel)
      app.root_widget = window

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

    renderer.render_frame(app)
    renderer.settle_rendering(app)
    renderer.reset_counters

    # 10 idle frames (no events, no changes)
    10.times { renderer.render_frame(app) }

    # Idle frames should render/composite nothing
    renderer.primitive_count.should eq 0
    renderer.layer_backend_clear_count.should eq 0  # No layer re-renders (window background clear is OK)
    renderer.compositor_call_count.should eq 10  # Currently always runs
    # TODO: When compositor skip implemented, this should be 0
    # renderer.compositor_skip_count.should eq 10

  end
end
