require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for layout counter instrumentation
describe "Layout counter instrumentation" do
  it "counts layout calls during rendering" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    window = CrymbleUI::Window.new("Test", 800, 600)
    button = CrymbleUI::Button.new("Test") { }
    window.add_child(button)

    # Use App to get proper layout tracking
    app = TestApp.new
    app.root_widget = window

    # Initial state - no layouts yet
    renderer.reset_counters
    renderer.layout_count.should eq 0

    # Trigger layout via App.prepare_layout
    app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

    # Should have done one layout
    renderer.layout_count.should eq 1
  end

  it "layout_count stays at 0 when no layout needed" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    window = CrymbleUI::Window.new("Test", 800, 600)
    button = CrymbleUI::Button.new("Test") { }
    window.add_child(button)

    app = TestApp.new
    app.root_widget = window

    # First layout
    app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))
    renderer.reset_counters

    # Second prepare_layout - no changes, no layout
    app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))
    renderer.layout_count.should eq 0
  end

  it "detects layout during drag (regression test for performance bug)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    window.add_child(panel)

    app = TestApp.new
    app.root_widget = window

    # Initial layout
    app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))
    renderer.reset_counters

    # Drag panel
    panel.on_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
    panel.on_mouse_move(CrymbleUI::Vec2.new(200.0, 115.0))

    # Try to trigger layout (but shouldn't actually layout)
    app.prepare_layout(CrymbleUI::Size.new(800.0, 600.0))

    # Should NOT trigger layout during drag (O(1) performance)
    renderer.layout_count.should eq 0
  end
end
