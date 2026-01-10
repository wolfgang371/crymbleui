require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for panel resize performance and correctness
#
# PERFORMANCE PRINCIPLE: ONLY render newly visible areas, never full panel re-renders
# - Small resize (within 20% buffer): Backend unchanged, render new strip only
# - Large resize (beyond 20% buffer): Backend recreated, but STILL only render new strip
#   (copy old pixels to new backend, then render newly visible area)
# - After resize ends (mouse_up): Screen should be CLEAN (no continuous re-renders)
#
# CORRECTNESS: No ghost rectangles from old panel borders
#
# Texture buffer: Layer backend is 20% over-allocated to avoid frequent recreation

describe "Panel Resize Ghost Rectangles" do
  it "small resize within texture buffer (< 20%) - no full re-renders during drag" do
    # Test WITHIN buffer: 200px + 10px = 5% growth
    # Backend NOT recreated, render only the 10px newly visible strip
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Small extend: 10px on 200px = 5% growth (well within 20% buffer)
    panel_right_edge = 100.0 + 200.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    # Reset counters before drag
    renderer.reset_counters

    # Drag - should NOT trigger full re-renders
    renderer.mouse_move(panel_right_edge + 10.0, 150.0)
    renderer.render_frame(app)

    # Check immediately - panel chrome may update (few primitives OK), but no full layer clear
    renderer.layer_backend_clear_count.should eq 0  # No full layer re-render
    renderer.primitive_count.should be < 20  # Panel chrome only, not all children
  end

  it "large resize beyond texture buffer (> 20%) - no full re-renders during drag" do
    # Test BEYOND buffer: 200px + 50px = 25% growth
    # Backend IS recreated, but should STILL only render the 50px newly visible strip
    # (NOT full panel re-render - copy old pixels, render new strip only)
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Large extend: 50px on 200px = 25% growth (exceeds 20% buffer)
    panel_right_edge = 100.0 + 200.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    # Reset counters before drag
    renderer.reset_counters

    # Drag - should NOT trigger full re-renders (even though backend recreated)
    renderer.mouse_move(panel_right_edge + 50.0, 150.0)
    renderer.render_frame(app)

    # Check immediately - panel chrome may update (few primitives OK), but no full layer clear
    renderer.layer_backend_clear_count.should eq 0  # No full layer re-render
    renderer.primitive_count.should be < 20  # Panel chrome only, not all children
  end

  it "extending panel height - no full re-renders during drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Extend panel height by dragging bottom edge down
    panel_bottom_edge = 100.0 + 150.0
    renderer.mouse_down(150.0, panel_bottom_edge)
    renderer.render_frame(app)

    # Reset counters before drag
    renderer.reset_counters

    # Drag - should NOT trigger full re-renders
    renderer.mouse_move(150.0, panel_bottom_edge + 50.0)
    renderer.render_frame(app)

    # Check immediately - panel chrome may update (few primitives OK), but no full layer clear
    renderer.layer_backend_clear_count.should eq 0  # No full layer re-render
    renderer.primitive_count.should be < 20  # Panel chrome only, not all children
  end

  it "shrinking panel width - no full re-renders during drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Shrink panel by dragging right edge to the left
    panel_right_edge = 100.0 + 300.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    # Reset counters before drag
    renderer.reset_counters

    # Drag - should NOT trigger full re-renders
    renderer.mouse_move(panel_right_edge - 100.0, 150.0)
    renderer.render_frame(app)

    # Check immediately - panel chrome may update (few primitives OK), but no full layer clear
    renderer.layer_backend_clear_count.should eq 0  # No full layer re-render
    renderer.primitive_count.should be < 20  # Panel chrome only, not all children
  end

  it "shrinking panel height - no full re-renders during drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 250.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Shrink panel by dragging bottom edge up
    panel_bottom_edge = 100.0 + 250.0
    renderer.mouse_down(150.0, panel_bottom_edge)
    renderer.render_frame(app)

    # Reset counters before drag
    renderer.reset_counters

    # Drag - should NOT trigger full re-renders
    renderer.mouse_move(150.0, panel_bottom_edge - 100.0)
    renderer.render_frame(app)

    # Check immediately - panel chrome may update (few primitives OK), but no full layer clear
    renderer.layer_backend_clear_count.should eq 0  # No full layer re-render
    renderer.primitive_count.should be < 20  # Panel chrome only, not all children
  end

  it "no ghost border pixels after extending panel width (pixel test)" do
    # CORRECTNESS: Verify old border pixels are cleared when panel grows
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render at 200px width
    renderer.render_frame(app)

    # Extend panel width: 200px -> 250px (25% growth, exceeds buffer)
    panel_right_edge = 100.0 + 200.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    renderer.mouse_move(panel_right_edge + 50.0, 150.0)
    renderer.render_frame(app)

    # Check pixels: Old right edge should NOT have border pixels (ghost)
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    panel_bg = panel.background_color
    border_color = CrymbleUI::Color.new(200, 200, 200, 255)  # Panel border (gray)

    # Panel is at (100, 100), so in layer-local coords:
    # Old right edge was at x=200 (layer-local), now at x=250
    # Old border position (x=200 in layer-local) should be background or content, NOT border
    old_border_x = 200  # Layer-local coordinate (panel was 200px wide)
    pixel_at_old_edge = backend.get_pixel(old_border_x, 50)  # y=50 in layer-local (middle of panel height)

    # This pixel should NOT be the border color (that would be a ghost border)
    pixel_at_old_edge.should_not eq(border_color)
  end

  it "no ghost border pixels after extending panel height (pixel test)" do
    # CORRECTNESS: Verify old border pixels are cleared when panel grows vertically
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Button")
    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render at 150px height
    renderer.render_frame(app)

    # Extend panel height: 150px -> 200px
    panel_bottom_edge = 100.0 + 150.0
    renderer.mouse_down(150.0, panel_bottom_edge)
    renderer.render_frame(app)

    renderer.mouse_move(150.0, panel_bottom_edge + 50.0)
    renderer.render_frame(app)

    # Check pixels: Old bottom edge should NOT have border pixels (ghost)
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    border_color = CrymbleUI::Color.new(200, 200, 200, 255)

    # Panel was 150px tall, now 200px tall
    # Old bottom edge at y=150 (layer-local), should NOT have border
    old_border_y = 150  # Layer-local coordinate (old panel height)
    pixel_at_old_edge = backend.get_pixel(100, old_border_y)  # x=100 in layer-local (middle of panel width)

    # This pixel should NOT be the border color (that would be a ghost border)
    pixel_at_old_edge.should_not eq(border_color)
  end
end
