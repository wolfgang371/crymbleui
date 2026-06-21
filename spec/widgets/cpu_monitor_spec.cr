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

  it "every CPUMonitor re-renders when the CPU value changes (not only the last one)" do
    # The old code pushed re-render through a single @@current_instance pointer, so a
    # SECOND monitor never updated. The value is now a class-level Source that every
    # monitor auto-captures while painting, so a change re-renders ALL of them.
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 120)
    app = TestApp.new
    m1 = CrymbleUI::CPUMonitor.new(id: "m1")
    m2 = CrymbleUI::CPUMonitor.new(id: "m2")
    m1.bounds = CrymbleUI::Rect.new(0.0, 0.0, 80.0, 30.0)
    m2.bounds = CrymbleUI::Rect.new(0.0, 40.0, 80.0, 30.0)
    window = CrymbleUI::Window.new("Test", 200, 120)
    window.add_child(m1)
    window.add_child(m2)
    app.root_widget = window

    CrymbleUI::CPUMonitor.cpu_percent = 10.0
    renderer.render_frame(app) # both render and capture the cpu Source

    CrymbleUI::CPUMonitor.cpu_percent = 73.5 # change the shared value, NO manual mark
    m1.needs_render?.should be_true          # the FIRST monitor is stale too (was the single-slot bug)
    m2.needs_render?.should be_true
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
