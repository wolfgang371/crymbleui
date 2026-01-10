require "../spec_helper"
require "../../src/testing/test_renderer"

# Performance test: VStack should not measure children twice per layout
# Bug: When VStack has no Expanded children, Pass 1 still measures all children
# This doubles the measure calls and causes lag during panel resize
describe "VStack measure count optimization" do
  it "non-Expanded VStack only measures children once per layout" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    window = CrymbleUI::Window.new("Test", 400, 300)

    # Create VStack with 20 buttons (like stress_panel_demo)
    vstack = CrymbleUI::VStack.new
    20.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }
    window.add_child(vstack)

    app.root_widget = window

    # Initial render to establish state
    renderer.render_frame(app)

    # Reset measure counter
    CrymbleUI::Widget.reset_measure_count

    # Trigger layout (simulates panel resize)
    # This calls VStack.perform_layout which should measure each child once
    vstack.mark_needs_layout
    renderer.render_frame(app)

    # Get measure count
    measure_count = CrymbleUI::Widget.measure_count

    # Debug output
    # puts "Measure count for 20 buttons: #{measure_count}"

    # Expected: ~40 measures (2 per button: VStack.measure + perform_layout)
    # Bug was: ~60 measures (VStack.measure + Pass 1 + Pass 2)
    #
    # At dacd384, VStack measured children twice: once in measure(), once in layout loop
    # The fix removes the extra Pass 1 when no Expanded children present
    measure_count.should be <= 45  # ~40 expected (2 per child), allow small overhead
  end

  it "Expanded VStack uses two-pass layout (acceptable overhead)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    window = CrymbleUI::Window.new("Test", 400, 300)

    # Create VStack with Expanded child containing buttons
    vstack = CrymbleUI::VStack.new
    5.times { |i| vstack.add_child(CrymbleUI::Button.new("Button #{i}") { }) }

    # Add Expanded with a button inside
    expanded = CrymbleUI::Expanded.new
    expanded.add_child(CrymbleUI::Button.new("Expanded Button") { })
    vstack.add_child(expanded)

    window.add_child(vstack)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Reset and measure
    CrymbleUI::Widget.reset_measure_count
    vstack.mark_needs_layout
    renderer.render_frame(app)

    # With Expanded, two-pass layout is expected and acceptable
    # The 5 fixed buttons will be measured in Pass 1 AND Pass 2 (10 total)
    # Plus the Expanded button - this is acceptable overhead for flex layout
    measure_count = CrymbleUI::Widget.measure_count
    measure_count.should be >= 5  # At least measure some buttons
  end
end
