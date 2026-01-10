require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for CPU monitor rendering
#
# BUG: When CPU text shrinks (e.g., "12.3%" → "1.2%"), the background
# also shrinks, leaving artifacts from the previous longer text visible.
#
# Root cause: cpu_monitor.cr:137 uses dynamically measured width for background:
#   width = text_size.width + 8.0
#   local_bounds = Rect.new(0.0, 0.0, width, height)
#
# When text shrinks, background shrinks too, not covering old pixels.
#
# Solution: Use bounds.width instead of dynamic width:
#   local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

describe "CPU Monitor Rendering" do
  it "background covers full widget bounds even when text shrinks" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new

    cpu_monitor = CrymbleUI::CPUMonitor.new
    # Set opaque background for non-overlay use (default is transparent)
    cpu_monitor.background_color = CrymbleUI::Color.new(255, 255, 255, 255)

    # Set explicit bounds for the widget (e.g., 80x30)
    cpu_monitor.bounds = CrymbleUI::Rect.new(10.0, 10.0, 80.0, 30.0)

    window = CrymbleUI::Window.new("Test", 200, 100)
    window.add_child(cpu_monitor)
    app.root_widget = window

    renderer.render_frame(app)

    # Get primitives for current text (could be any value)
    primitives = cpu_monitor.get_primitives(cpu_monitor.bounds)

    # Find background FillRect primitive (should be first primitive)
    background = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }
    background.should_not be_nil

    bg_rect = background.as(CrymbleUI::FillRect).bounds

    # BUG: Background uses dynamic width (text_size.width + 8.0)
    # Expected: Background should cover full widget bounds
    # This prevents artifacts when text shrinks

    bg_rect.width.should eq(cpu_monitor.bounds.width)
    bg_rect.height.should eq(cpu_monitor.bounds.height)
  end

  it "background position starts at widget origin" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new

    cpu_monitor = CrymbleUI::CPUMonitor.new
    cpu_monitor.background_color = CrymbleUI::Color.new(255, 255, 255, 255)
    cpu_monitor.bounds = CrymbleUI::Rect.new(10.0, 10.0, 80.0, 30.0)

    window = CrymbleUI::Window.new("Test", 200, 100)
    window.add_child(cpu_monitor)
    app.root_widget = window

    renderer.render_frame(app)

    primitives = cpu_monitor.get_primitives(cpu_monitor.bounds)
    background = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }

    bg_rect = background.as(CrymbleUI::FillRect).bounds

    # Background should start at (0, 0) in widget-local coordinates
    bg_rect.x.should eq(0.0)
    bg_rect.y.should eq(0.0)
  end

  it "default background is transparent for overlay use (alpha=0)" do
    cpu_monitor = CrymbleUI::CPUMonitor.new

    # Default background should be transparent (alpha=0)
    cpu_monitor.background_color.a.should eq(0)
  end

  it "transparent background still covers full bounds (for layer clearing)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new

    cpu_monitor = CrymbleUI::CPUMonitor.new
    # Use default transparent background
    cpu_monitor.bounds = CrymbleUI::Rect.new(10.0, 10.0, 80.0, 30.0)

    window = CrymbleUI::Window.new("Test", 200, 100)
    window.add_child(cpu_monitor)
    app.root_widget = window

    renderer.render_frame(app)

    primitives = cpu_monitor.get_primitives(cpu_monitor.bounds)
    background = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }

    bg_rect = background.as(CrymbleUI::FillRect).bounds

    # Even transparent background covers full bounds (layer clearing uses this)
    bg_rect.width.should eq(cpu_monitor.bounds.width)
    bg_rect.height.should eq(cpu_monitor.bounds.height)
  end
end
