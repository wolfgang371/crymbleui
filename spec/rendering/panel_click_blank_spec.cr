require "../spec_helper"
require "../../src/testing/test_renderer"

# Test widget that draws a black rectangle
class BlackRectWidget < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize
    super(id: "black_rect")
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 100.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(100.0, 100.0))
    @state = CrymbleUI::WidgetState::Clean
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(
        CrymbleUI::Rect.new(CrymbleUI::Vec2.zero, CrymbleUI::Size.new(100.0, 100.0)),
        CrymbleUI::Color.new(0, 0, 0, 255)  # Black
      )
    end
  end
end

# Regression test: Panel content should NOT go blank when clicking on panel
# Bug: bring_to_front calls mark_needs_render which invalidates children backgrounds
describe "Panel Click Blank Bug" do
  it "panel content stays black after clicking white area (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create panel with a simple black rectangle
    panel = CrymbleUI::WindowPanel.new("Test Panel", 100.0, 100.0, 300.0, 200.0)

    black_rect = BlackRectWidget.new
    panel.add_child(black_rect)

    window.add_child(panel)
    app.root_widget = window

    # Initial render - settle to stable state
    renderer.settle_rendering(app)

    # Get panel layer backend
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixel in black rectangle (layer-local coordinates)
    # Black rect is at position (0, 0) in panel content after title bar
    # Title bar is ~30px, so content starts at y=30 in layer
    sample_x = 50  # Middle of 100px wide rect
    sample_y = 50  # Middle of 100px tall rect (accounting for title bar ~30px)

    # Check initial pixel is black
    initial_pixel = backend.get_pixel(sample_x, sample_y)
    if initial_pixel
      initial_brightness = initial_pixel.r.to_i + initial_pixel.g.to_i + initial_pixel.b.to_i
      initial_brightness.should be < 50  # Should be very dark/black
    else
      fail "Could not read initial pixel"
    end

    # Click on white area of panel (not on black rect, but in panel)
    # This triggers bring_to_front -> mark_needs_render
    click_point = CrymbleUI::Vec2.new(250.0, 150.0)  # White area right of black rect

    # Simulate click
    app.handle_mouse_down(click_point)
    renderer.render_frame(app)

    # CRITICAL PIXEL TEST: After click, pixel should STILL be black!
    after_click_pixel = backend.get_pixel(sample_x, sample_y)
    if after_click_pixel
      after_click_brightness = after_click_pixel.r.to_i + after_click_pixel.g.to_i + after_click_pixel.b.to_i

      # If bug exists, this would be white (brightness ~765) or blank
      after_click_brightness.should be < 50  # Should STILL be dark/black
    else
      fail "Could not read pixel after click"
    end

    app.handle_mouse_up(click_point)
    renderer.render_frame(app)

    # Verify still black after mouse up
    final_pixel = backend.get_pixel(sample_x, sample_y)
    if final_pixel
      final_brightness = final_pixel.r.to_i + final_pixel.g.to_i + final_pixel.b.to_i
      final_brightness.should be < 50
    else
      fail "Could not read final pixel"
    end
  end

  it "panel content stays black during resize (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create panel with black rectangle
    panel = CrymbleUI::WindowPanel.new("Test Panel", 100.0, 100.0, 300.0, 200.0)

    black_rect = BlackRectWidget.new
    panel.add_child(black_rect)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.settle_rendering(app)

    # Get panel layer backend
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixel in black rectangle
    sample_x = 50
    sample_y = 50

    # Check initial pixel
    initial_pixel = backend.get_pixel(sample_x, sample_y)
    if initial_pixel
      initial_brightness = initial_pixel.r.to_i + initial_pixel.g.to_i + initial_pixel.b.to_i
      initial_brightness.should be < 50
    else
      fail "Could not read initial pixel"
    end

    # Start resize (mouse down on right edge)
    resize_point = CrymbleUI::Vec2.new(400.0, 200.0)  # Right edge of panel
    app.handle_mouse_down(resize_point)
    renderer.render_frame(app)

    # Get updated backend (might have been recreated during resize)
    backend = panel_layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    # CRITICAL PIXEL TEST: During resize, pixel should STILL be black (not blank)
    during_resize_pixel = backend.get_pixel(sample_x, sample_y)
    if during_resize_pixel
      during_resize_brightness = during_resize_pixel.r.to_i + during_resize_pixel.g.to_i + during_resize_pixel.b.to_i
      during_resize_brightness.should be < 50
    else
      fail "Could not read pixel during resize"
    end

    # Complete resize
    app.handle_mouse_up(resize_point)
    renderer.settle_rendering(app)

    # Get final backend
    backend = panel_layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    # After resize completes, verify still black
    after_resize_pixel = backend.get_pixel(sample_x, sample_y)
    if after_resize_pixel
      after_resize_brightness = after_resize_pixel.r.to_i + after_resize_pixel.g.to_i + after_resize_pixel.b.to_i
      after_resize_brightness.should be < 50
    else
      fail "Could not read final pixel"
    end
  end
end
