require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for panel text content padding
# Issue: In panels_demo, the first text row has no padding on top or left
# This looks ugly - text should have reasonable padding from panel edges

describe "Panel Text Padding" do
  it "text content has padding from top edge (at least 1px)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create panel with text content
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    text = CrymbleUI::Text.new("First line of text")

    panel.add_child(text)
    window.add_child(panel)
    app.root_widget = window

    # Layout and render
    renderer.render_frame(app)

    # Panel content starts after title bar
    # Title bar is typically ~30px, so content area starts at panel.y + title_height
    # Text should NOT be at the very top of content area - needs padding

    # Get text position
    text_bounds = text.bounds
    text_abs = text.absolute_bounds

    # Panel content area starts after title (panel.y + title_height)
    # Assuming title bar is ~30px (this might vary based on panel implementation)
    panel_content_top = panel.absolute_bounds.y + 30.0  # Approximate title height

    # Text should have at least 1px padding from content area top
    # (text.absolute_bounds.y should be > panel_content_top)
    padding_top = text_abs.y - panel_content_top
    padding_top.should be >= 1.0  # At least 1 pixel padding
  end

  it "text content has reasonable padding from top edge (at least 5px recommended)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    text = CrymbleUI::Text.new("First line of text")

    panel.add_child(text)
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    text_abs = text.absolute_bounds
    panel_content_top = panel.absolute_bounds.y + 30.0

    # Reasonable padding for aesthetics
    padding_top = text_abs.y - panel_content_top
    padding_top.should be >= 5.0  # At least 5 pixels for good aesthetics
  end

  it "text content has padding from left edge (at least 1px)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    text = CrymbleUI::Text.new("First line of text")

    panel.add_child(text)
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # Text should NOT be at the very left edge of panel content area
    text_abs = text.absolute_bounds

    # Panel content area left edge (accounting for border)
    # Panel border is typically 2px
    panel_content_left = panel.absolute_bounds.x + 2.0  # Border width

    # Text should have at least 1px padding from left edge
    padding_left = text_abs.x - panel_content_left
    padding_left.should be >= 1.0  # At least 1 pixel padding
  end

  it "text content has reasonable padding from left edge (at least 5px recommended)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    text = CrymbleUI::Text.new("First line of text")

    panel.add_child(text)
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    text_abs = text.absolute_bounds
    panel_content_left = panel.absolute_bounds.x + 2.0

    # Reasonable padding for aesthetics
    padding_left = text_abs.x - panel_content_left
    padding_left.should be >= 5.0  # At least 5 pixels for good aesthetics
  end

  it "multiple text widgets all have consistent padding" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

    # Add multiple text widgets
    text1 = CrymbleUI::Text.new("First line")
    text2 = CrymbleUI::Text.new("Second line")
    text3 = CrymbleUI::Text.new("Third line")

    panel.add_child(text1)
    panel.add_child(text2)
    panel.add_child(text3)

    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # All text widgets should have the same left padding
    panel_content_left = panel.absolute_bounds.x + 2.0

    text1_abs = text1.absolute_bounds
    text2_abs = text2.absolute_bounds
    text3_abs = text3.absolute_bounds

    padding_left_1 = text1_abs.x - panel_content_left
    padding_left_2 = text2_abs.x - panel_content_left
    padding_left_3 = text3_abs.x - panel_content_left

    # All should have at least 1px padding
    padding_left_1.should be >= 1.0
    padding_left_2.should be >= 1.0
    padding_left_3.should be >= 1.0

    # All should have consistent padding (same value)
    padding_left_1.should eq(padding_left_2)
    padding_left_2.should eq(padding_left_3)
  end

  it "text doesn't touch panel border (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    text = CrymbleUI::Text.new("Test text")

    panel.add_child(text)
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # Panel has its own layer - check pixels in panel layer backend, not root
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Check pixels in layer-local coordinates (relative to panel)
    # Should be panel background, NOT text color (text should have padding)

    # In layer-local coords: x=0 is left edge, content starts at x=8 (CONTENT_PADDING)
    # Check at x=4 (between border and content)
    content_left_x = 4  # Inside padding area
    content_top_y = 35  # Below title bar

    panel_bg = panel.background_color
    pixel_at_left_edge = backend.get_pixel(content_left_x, content_top_y)

    # Should be panel background, not text (because text has padding)
    pixel_at_left_edge.should eq(panel_bg)
  end

  it "panel with VStack container has padding for text children" do
    # This is closer to panels_demo which uses VStack for layout
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

    # Use VStack like panels_demo does
    vbox = CrymbleUI::VStack.new(spacing: 5.0)
    text1 = CrymbleUI::Text.new("Line 1")
    text2 = CrymbleUI::Text.new("Line 2")

    vbox.add_child(text1)
    vbox.add_child(text2)
    panel.add_child(vbox)

    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # VStack should have padding from panel edges
    vbox_abs = vbox.absolute_bounds
    panel_content_left = panel.absolute_bounds.x + 2.0  # Border
    panel_content_top = panel.absolute_bounds.y + 30.0  # Title

    # VStack should have padding
    vbox_padding_left = vbox_abs.x - panel_content_left
    vbox_padding_top = vbox_abs.y - panel_content_top

    vbox_padding_left.should be >= 1.0
    vbox_padding_top.should be >= 1.0

    # First text in VStack should inherit this padding
    text1_abs = text1.absolute_bounds
    text1_padding_left = text1_abs.x - panel_content_left
    text1_padding_top = text1_abs.y - panel_content_top

    text1_padding_left.should be >= 1.0
    text1_padding_top.should be >= 1.0
  end
end
