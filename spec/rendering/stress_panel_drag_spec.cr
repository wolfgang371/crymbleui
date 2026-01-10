require "../spec_helper"
require "../../src/testing/test_renderer"

# Realistic stress test: Mirrors actual stress_panel_demo.cr
# Tests drag performance with:
# - CPUMonitor widget (has timer updating every 1s)
# - 400 FlashingButton widgets (timers not active until clicked)
# - Panel drag operation
#
# Expected: O(1) performance - drag should NOT re-render all 400 buttons

# FlashingButton - Button that flashes when selected (copied from stress_panel_demo.cr)
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
      background_color: background_color, border_color: border_color, padding: padding, on_click: block)
    @base_background_color = background_color
    @base_border_color = border_color
  end

  def start_flashing : Int32
    return @timer_id.not_nil! if @timer_id

    @flash_on = true
    update_colors

    timer_id = schedule_timer(400.milliseconds, repeating: true) {
      @flash_on = !@flash_on
      update_colors
    }
    @timer_id = timer_id
    timer_id
  end

  def stop_flashing
    if timer_id = @timer_id
      cancel_timer(timer_id)
      @timer_id = nil
      @flash_on = false
      update_colors
    end
  end

  private def update_colors
    if @flash_on
      self.background_color = CrymbleUI::Color.new(255, 165, 0, 255)
      self.border_color = CrymbleUI::Color.new(255, 140, 0, 255)
    else
      self.background_color = @base_background_color
      self.border_color = @base_border_color
    end
  end
end

describe "Stress Panel Drag Performance (Realistic)" do
  it "drag performance is O(1) with CPUMonitor and 400 buttons (no timers active)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new

    # Build realistic stress test window (mirrors stress_panel_demo.cr)
    window = CrymbleUI::Window.new("Stress Test", 1200, 900)

    # Add VStack with CPUMonitor (like real demo)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)

    # CPUMonitor has a timer that fires every 1s
    cpu_monitor = CrymbleUI::CPUMonitor.new
    vstack.add_child(cpu_monitor)

    # Add some text widgets (like real demo)
    vstack.add_child(CrymbleUI::Text.new("Stress Panel Demo: 400 Buttons"))
    vstack.add_child(CrymbleUI::Text.new("• Drag panel by title bar"))
    vstack.add_child(CrymbleUI::Text.new("Clicks: 0 | Last: none"))

    window.add_child(vstack)
    app.root_widget = window

    # Add panel with 400 FlashingButtons (20x20 grid, like real demo)
    panel = CrymbleUI::WindowPanel.new("Stress Test (400 buttons)", 50.0, 150.0, 700.0, 600.0)

    panel_vstack = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hstack = CrymbleUI::HStack.new(spacing: 2.0)
      20.times do |col|
        button = FlashingButton.new(
          "#{row},#{col}",
          font_scale: -5,
          padding: 3.0
        ) { } # Empty click handler - we won't click in this test
        hstack.add_child(button)
      end
      panel_vstack.add_child(hstack)
    end
    panel.add_child(panel_vstack)

    window.add_child(panel)
    app.root_widget = window

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1200.0, 900.0))

    # Initial render (don't count this)
    renderer.render_frame(app)
    initial_prims = renderer.primitive_count

    # Simulate drag sequence (like drag_scaling_spec.cr)
    drag_primitive_counts = [] of Int32

    # Mouse down on panel title bar
    renderer.reset_counters
    renderer.mouse_down(150.0, 165.0) # On title bar
    renderer.render_frame(app)
    mouse_down_prims = renderer.primitive_count
    drag_primitive_counts << mouse_down_prims

    # Drag move #1 (+50px)
    renderer.reset_counters
    renderer.mouse_move(200.0, 165.0)
    renderer.render_frame(app)
    move1_prims = renderer.primitive_count
    drag_primitive_counts << move1_prims

    # Drag move #2 (+50px more)
    renderer.reset_counters
    renderer.mouse_move(250.0, 165.0)
    renderer.render_frame(app)
    move2_prims = renderer.primitive_count
    drag_primitive_counts << move2_prims

    # Drag move #3 (+50px more)
    renderer.reset_counters
    renderer.mouse_move(300.0, 165.0)
    renderer.render_frame(app)
    move3_prims = renderer.primitive_count
    drag_primitive_counts << move3_prims

    # Mouse up
    renderer.reset_counters
    renderer.mouse_up(300.0, 165.0)
    renderer.render_frame(app)
    mouse_up_prims = renderer.primitive_count

    # CRITICAL ASSERTION: During drag, primitives should be ZERO (or very small constant)
    # The panel layer should NOT re-render its 400 buttons during drag!

    # All drag operations should be O(1) - ideally 0 primitives
    max_drag_prims = drag_primitive_counts.max

    # Allow up to 20 primitives for panel chrome (title bar, borders, etc.)
    # But NOT 400+ for all buttons!
    max_drag_prims.should be < 20

    if max_drag_prims >= 20
    else
    end
  end

  it "drag with active FlashingButton timer still maintains O(1) performance" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new

    # Same setup as above
    window = CrymbleUI::Window.new("Stress Test", 1200, 900)

    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    cpu_monitor = CrymbleUI::CPUMonitor.new
    vstack.add_child(cpu_monitor)
    vstack.add_child(CrymbleUI::Text.new("Stress Panel Demo"))
    window.add_child(vstack)
    app.root_widget = window

    panel = CrymbleUI::WindowPanel.new("Test", 50.0, 150.0, 700.0, 600.0)
    panel_vstack = CrymbleUI::VStack.new(spacing: 2.0)

    # Create one FlashingButton that we'll activate
    flashing_button = FlashingButton.new("0,0", font_scale: -5, padding: 3.0) { }

    hstack = CrymbleUI::HStack.new(spacing: 2.0)
    hstack.add_child(flashing_button)

    # Add 399 more regular buttons
    399.times do |i|
      button = FlashingButton.new("#{i}", font_scale: -5, padding: 3.0) { }
      hstack.add_child(button)
    end

    panel_vstack.add_child(hstack)
    panel.add_child(panel_vstack)
    window.add_child(panel)
    app.root_widget = window

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1200.0, 900.0))

    # Initial render
    renderer.render_frame(app)

    # Start the flashing timer on one button
    timer_id = flashing_button.start_flashing

    # Now test drag performance WITH an active timer
    renderer.reset_counters
    renderer.mouse_down(150.0, 165.0)
    renderer.render_frame(app)

    renderer.reset_counters
    renderer.mouse_move(200.0, 165.0)
    renderer.render_frame(app)
    drag_prims = renderer.primitive_count

    # Even with one flashing button, drag should be O(1)
    # We might see the one flashing button re-render (3 primitives)
    # But NOT all 400 buttons!
    drag_prims.should be < 20

    if drag_prims >= 20
    else
    end
  end
end

describe "Stress Panel Resize Performance (Realistic)" do
  it "resize performance is O(1) with 400 buttons" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new

    # Build realistic stress test window (same as drag test above)
    window = CrymbleUI::Window.new("Stress Test", 1200, 900)

    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    cpu_monitor = CrymbleUI::CPUMonitor.new
    vstack.add_child(cpu_monitor)
    vstack.add_child(CrymbleUI::Text.new("Stress Panel Demo: 400 Buttons"))
    window.add_child(vstack)
    app.root_widget = window

    # Add panel with MenuBar and 400 FlashingButtons (20x20 grid)
    panel = CrymbleUI::WindowPanel.new("Stress Test (400 buttons)", 50.0, 150.0, 700.0, 600.0)

    # Add MenuBar (triggers special resize handling at line 603-617)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    panel.add_child(menubar)

    panel_vstack = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hstack = CrymbleUI::HStack.new(spacing: 2.0)
      20.times do |col|
        button = FlashingButton.new(
          "#{row},#{col}",
          font_scale: -5,
          padding: 3.0
        ) { } # Empty click handler
        hstack.add_child(button)
      end
      panel_vstack.add_child(hstack)
    end
    panel.add_child(panel_vstack)

    window.add_child(panel)
    app.root_widget = window

    # Initial render (don't count this)
    renderer.render_frame(app)

    # Simulate RESIZE sequence (drag right edge)
    resize_primitive_counts = [] of Int32

    # Mouse down on panel RIGHT EDGE (not title bar!)
    panel_right_edge = panel.x + panel.width
    edge_y = panel.y + panel.height / 2

    renderer.reset_counters
    renderer.mouse_down(panel_right_edge, edge_y)
    renderer.render_frame(app)
    mouse_down_prims = renderer.primitive_count
    resize_primitive_counts << mouse_down_prims

    # Resize move #1 (+50px)
    renderer.reset_counters
    renderer.mouse_move(panel_right_edge + 50.0, edge_y)
    renderer.render_frame(app)
    move1_prims = renderer.primitive_count
    resize_primitive_counts << move1_prims

    # Resize move #2 (+50px more)
    renderer.reset_counters
    renderer.mouse_move(panel_right_edge + 100.0, edge_y)
    renderer.render_frame(app)
    move2_prims = renderer.primitive_count
    resize_primitive_counts << move2_prims

    # Resize move #3 (+50px more) - this should cross buffer threshold
    renderer.reset_counters
    renderer.mouse_move(panel_right_edge + 150.0, edge_y)

    renderer.render_frame(app)
    move3_prims = renderer.primitive_count
    resize_primitive_counts << move3_prims

    # Mouse up
    renderer.reset_counters
    renderer.mouse_up(panel_right_edge + 150.0, edge_y)
    renderer.render_frame(app)

    # CRITICAL ASSERTION: During resize, primitives should be small constant
    # The panel should NOT re-render all 400 buttons during resize!
    # Only chrome (titlebar) should re-render
    max_resize_prims = resize_primitive_counts.max

    # NOTE: After fixing TestRenderer to count widget backends, we now see REAL primitive counts!
    # If this test fails with high counts (>15), it means widgets are being re-rendered during resize.
    # Threshold increased from 10 to 15 to account for maximize button in chrome
    max_resize_prims.should be <= 15
  end

  it "resize performance is O(1) when SHRINKING panel with 400 buttons" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new

    # Build same stress test window
    window = CrymbleUI::Window.new("Stress Test", 1200, 900)

    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    cpu_monitor = CrymbleUI::CPUMonitor.new
    vstack.add_child(cpu_monitor)
    vstack.add_child(CrymbleUI::Text.new("Stress Panel Demo: 400 Buttons"))
    window.add_child(vstack)
    app.root_widget = window

    # Add panel with MenuBar + 400 FlashingButtons (20x20 grid)
    panel = CrymbleUI::WindowPanel.new("Stress Test (400 buttons)", 50.0, 150.0, 700.0, 600.0)

    # Add MenuBar (triggers special resize handling)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    panel.add_child(menubar)

    panel_vstack = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |row|
      hstack = CrymbleUI::HStack.new(spacing: 2.0)
      20.times do |col|
        button = FlashingButton.new(
          "#{row},#{col}",
          font_scale: -5,
          padding: 3.0
        ) { } # Empty click handler
        hstack.add_child(button)
      end
      panel_vstack.add_child(hstack)
    end
    panel.add_child(panel_vstack)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Simulate SHRINK sequence (drag LEFT edge INWARD)
    resize_primitive_counts = [] of Int32

    # Mouse down on panel LEFT EDGE
    panel_left_edge = panel.x
    edge_y = panel.y + panel.height / 2

    renderer.reset_counters
    renderer.mouse_down(panel_left_edge, edge_y)
    renderer.render_frame(app)
    mouse_down_prims = renderer.primitive_count
    resize_primitive_counts << mouse_down_prims

    # Shrink move #1 (move left edge +50px inward, shrinking panel)
    renderer.reset_counters
    renderer.mouse_move(panel_left_edge + 50.0, edge_y)
    renderer.render_frame(app)
    move1_prims = renderer.primitive_count
    resize_primitive_counts << move1_prims

    # Shrink move #2 (+50px more inward)
    renderer.reset_counters
    renderer.mouse_move(panel_left_edge + 100.0, edge_y)
    renderer.render_frame(app)
    move2_prims = renderer.primitive_count
    resize_primitive_counts << move2_prims

    # Shrink move #3 (+50px more inward)
    renderer.reset_counters
    renderer.mouse_move(panel_left_edge + 150.0, edge_y)
    renderer.render_frame(app)
    move3_prims = renderer.primitive_count
    resize_primitive_counts << move3_prims

    # Mouse up
    renderer.reset_counters
    renderer.mouse_up(panel_left_edge + 150.0, edge_y)
    renderer.render_frame(app)

    # CRITICAL ASSERTION: During shrink, primitives should be small constant
    # The panel should NOT re-render all 400 buttons during shrink!
    # Even as buttons scroll out of view, only chrome should re-render
    max_resize_prims = resize_primitive_counts.max

    # Same expectation as enlarge test: ≤15 primitives (only chrome, incl. maximize button)
    max_resize_prims.should be <= 15
  end
end
