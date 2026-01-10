require "../spec_helper"
require "../../src/testing/test_renderer"

# GOAL: Reproduce the performance issue the user is experiencing:
# - At idle: 10% CPU, everything normal
# - During drag: 100% CPU, 1 second lag before window updates
# - After drop: back to normal
#
# This test simulates a realistic drag scenario with:
# - 400 FlashingButtons (like stress_panel_demo)
# - CPUMonitor widget with timer
# - Realistic mouse event stream (100+ events during drag)
# - Comprehensive performance instrumentation

# FlashingButton - Button that flashes when selected
class FlashingButton < CrymbleUI::Button
  @timer_id : Int32?
  @flash_on : Bool = false
  @base_background_color : CrymbleUI::Color
  @base_border_color : CrymbleUI::Color

  def initialize(
    text : String,
    id : String? = nil,
    font_scale : Int32 = 0,
    text_color : CrymbleUI::Color = CrymbleUI::Color.new(255, 255, 255, 255),
    background_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 120, 215, 255),
    border_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 100, 180, 255),
    padding : Float64 = 10.0,
    &block : -> Nil
  )
    super(text, shortcut: nil, id: id, font_scale: font_scale, text_color: text_color,
          background_color: background_color, border_color: border_color, padding: padding, &block)
    @base_background_color = background_color
    @base_border_color = border_color
  end
end

describe "Drag Performance - Instrumented Reproduction" do
  it "reproduces the 100% CPU issue during drag with 400 buttons" do
      app = TestApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
      app = TestApp.new

    # Build realistic stress test window (mirrors stress_panel_demo.cr)
    window = CrymbleUI::Window.new("Stress Test", 1200, 900)

    # Add VStack with CPUMonitor
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    cpu_monitor = CrymbleUI::CPUMonitor.new
    vstack.add_child(cpu_monitor)
    vstack.add_child(CrymbleUI::Text.new("Stress Panel Demo: 400 Buttons"))
    vstack.add_child(CrymbleUI::Text.new("Clicks: 0 | Last: none"))
    window.add_child(vstack)
      app.root_widget = window

    # Add panel with 400 FlashingButtons (20x20 grid)
    panel = CrymbleUI::WindowPanel.new("Stress Test (400 buttons)", 50.0, 150.0, 700.0, 600.0)
    panel_vstack = CrymbleUI::VStack.new(spacing: 2.0)

    20.times do |row|
      hstack = CrymbleUI::HStack.new(spacing: 2.0)
      20.times do |col|
        button = FlashingButton.new("#{row},#{col}", font_scale: -5, padding: 3.0) { }
        hstack.add_child(button)
      end
      panel_vstack.add_child(hstack)
    end
    panel.add_child(panel_vstack)
    window.add_child(panel)
      app.root_widget = window

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1200.0, 900.0))

    # === PHASE 1: Initial render ===
    renderer.reset_counters

    renderer.render_frame(app)


    # === PHASE 2: Idle state (no events) ===
    renderer.reset_counters

    # Simulate 10 idle frames (no events, just compositor checking)
    10.times do
      renderer.render_frame(app)
    end


    # === PHASE 3: Start drag (mouse down) ===
    renderer.reset_counters

    renderer.mouse_down(150.0, 165.0)  # On panel title bar
    renderer.render_frame(app)


    # === PHASE 4: DRAG MOVEMENT (THE CRITICAL TEST) ===
    # Simulate realistic drag with 100+ mouse events
    renderer.reset_counters

    # Simulate smooth drag: 100 mouse events over ~500 pixels
    start_x = 150.0
    end_x = 650.0
    num_events = 100

    num_events.times do |i|
      # Interpolate position
      progress = i.to_f / num_events
      x = start_x + (end_x - start_x) * progress

      renderer.mouse_move(x, 165.0)
      renderer.render_frame(app)
    end


    # === PHASE 5: Drop (mouse up) ===
    renderer.reset_counters

    renderer.mouse_up(end_x, 165.0)
    renderer.render_frame(app)


    # === ANALYSIS (instrumentation counters only) ===

    # During drag, we should render ~100 times (once per event) but primitives should be LOW
    # because we're NOT re-rendering the 400 buttons, just moving the layer
    expected_primitives_per_drag_frame = 20  # Just panel chrome, not 400 buttons
    actual_primitives_per_drag_frame = renderer.primitive_count / num_events


    # Assertion based on instrumentation counters only (not wall-clock time)
    actual_primitives_per_drag_frame.should be < expected_primitives_per_drag_frame
  end
end
