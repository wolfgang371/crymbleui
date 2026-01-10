require "../spec_helper"
require "../../src/testing/test_renderer"

# Test for button flashing during panel drag
# User report: When dragging panel with a flashing button:
# - Button content renders (flashing works) ✓
# - Button appears at correct position during drag ✓
#
# Root cause of original bug: Selective rendering used stale widget.bounds (absolute coords)
# Fix: Use parent-relative bounds + absolute_bounds() for rendering
describe "Button Flash During Panel Drag" do
  it "flashing button renders at correct position during drag (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Flash") { }

    panel.add_child(button)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Get panel layer backend for pixel testing
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # With NEW architecture (Chrome/Content split):
    # - Button is child of Content (not panel directly)
    # - Content.bounds is relative to panel, at (CONTENT_PADDING, TITLE_BAR_HEIGHT + CONTENT_PADDING)
    # - Button.bounds is relative to Content
    # - To get layer-local coords: Content.bounds + Button.bounds
    # CONTENT_PADDING = 8, TITLE_BAR_HEIGHT = 30
    content_offset_x = 8.0  # CONTENT_PADDING
    content_offset_y = 38.0 # TITLE_BAR_HEIGHT (30) + CONTENT_PADDING (8)
    button_center_x = (content_offset_x + button.bounds.x + button.bounds.width / 2).to_i
    button_center_y = (content_offset_y + button.bounds.y + button.bounds.height / 2).to_i

    # Colors
    flash_color = CrymbleUI::Color.new(255, 0, 0, 255)    # Red

    # Start drag on panel title bar
    # Use app's mouse handling (tracks mouse_down_widget for drag)
    app.handle_mouse_down(CrymbleUI::Vec2.new(150.0, 115.0))
    renderer.render_frame(app)

    # Drag panel 200px to the right (far enough to avoid overlap with old position)
    app.handle_mouse_move(CrymbleUI::Vec2.new(350.0, 115.0))
    renderer.render_frame(app)

    # Flash button during drag (triggers selective re-render)
    button.background_color = flash_color

    # Render - button should render at its (relative) position
    renderer.render_frame(app)

    # With NEW architecture, button renders at Content.bounds + Button.bounds
    # in layer-local coordinates (Content offset + button offset within Content)
    pixel = backend.get_pixel(button_center_x, button_center_y)

    # Button should be visible at its correct position with flash color
    pixel.should eq(flash_color)
  end
end
