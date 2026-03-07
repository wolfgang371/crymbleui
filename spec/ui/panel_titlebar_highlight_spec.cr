require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: Panel titlebar highlighting should be immediate and work from any click
#
# BUG 1: Titlebar only highlights when clicking titlebar itself
# Expected: Clicking panel content (buttons, etc.) should also highlight titlebar
# Actual: Only titlebar clicks trigger highlight
#
# BUG 2: Titlebar highlights on mouse UP, not mouse DOWN
# Expected: Titlebar should highlight immediately on mouse down
# Actual: Titlebar only highlights after mouse up (laggy/delayed)
#
# Root Cause: bring_to_front calls mark_needs_render, but App only rebuilds
# when root.needs_layout? is true. mark_needs_render doesn't set layout flag,
# so visual update is delayed until next rebuild (often on mouse_up).

class PanelTitlebarTestApp < CrymbleUI::App
  property root_widget : CrymbleUI::Widget?

  def build : CrymbleUI::Widget
    @root_widget.not_nil!
  end

  # Fix: Also set inherited @root so render_all_layers executes
  def root_widget=(widget : CrymbleUI::Widget)
    @root_widget = widget
    @root = widget
  end
end

describe "Panel titlebar highlighting" do
  it "highlights titlebar immediately on mouse DOWN when clicking titlebar" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelTitlebarTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create two panels - panel2 starts on top
    panel1 = CrymbleUI::WindowPanel.new("Panel 1", 50.0, 50.0, 300.0, 200.0)
    panel2 = CrymbleUI::WindowPanel.new("Panel 2", 100.0, 100.0, 300.0, 200.0)

    window.add_child(panel1)
    window.add_child(panel2)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Establish z-order: bring panel1 to front first, then panel2
    # This ensures panel1 is NOT topmost (z=0, inactive) and panel2 IS topmost (z=1, active)
    panel1.bring_to_front
    renderer.render_frame(app)
    panel2.bring_to_front
    renderer.render_frame(app)

    # Test initial state: panel2 is topmost (active), panel1 is not topmost (inactive)
    panel2.topmost?.should be_true
    panel1.topmost?.should be_false

    # Get initial titlebar pixel colors from panel layers
    panel1_layer = panel1.layer.not_nil!
    panel1_backend = panel1_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Titlebar is at y=0 in layer-local coordinates, middle of title bar
    titlebar_y = (panel1.title_bar_height / 2).to_i
    titlebar_x = (panel1.width / 2).to_i

    initial_color = panel1_backend.get_pixel(titlebar_x, titlebar_y)

    # Verify initial titlebar shows INACTIVE color (darker blue) since panel1 is not topmost
    inactive_color = CrymbleUI::Theme.current.panel_title_bar_inactive
    initial_color.should eq(inactive_color)

    # Mouse DOWN on panel1 titlebar (not mouse up yet!)
    titlebar_click_x = panel1.x + panel1.width / 2
    titlebar_click_y = panel1.y + panel1.title_bar_height / 2

    renderer.mouse_down(titlebar_click_x, titlebar_click_y)

    # BUG: At this point (after mouse_down, before mouse_up), the titlebar
    # should already be highlighted because bring_to_front was called.
    # But the visual update is delayed until mouse_up or next rebuild.

    # Render to apply the z-order change (titlebar should update immediately after mouse_down)
    renderer.render_frame(app)

    # Verify panel1 is now topmost after clicking its titlebar
    panel1.topmost?.should be_true
    panel2.topmost?.should be_false

    # Verify titlebar pixel color changed to ACTIVE (bright blue) immediately on mouse_down
    after_mousedown_color = panel1_backend.get_pixel(titlebar_x, titlebar_y)
    active_color = CrymbleUI::Theme.current.panel_title_bar_active
    after_mousedown_color.should eq(active_color)
    after_mousedown_color.should_not eq(inactive_color)
  end

  it "highlights titlebar when clicking panel CONTENT (not just titlebar)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelTitlebarTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create two NON-OVERLAPPING panels with buttons
    panel1 = CrymbleUI::WindowPanel.new("Panel 1", 50.0, 50.0, 300.0, 200.0)
    button1 = CrymbleUI::Button.new("Button 1")
    panel1.add_child(button1)

    panel2 = CrymbleUI::WindowPanel.new("Panel 2", 400.0, 50.0, 300.0, 200.0)
    button2 = CrymbleUI::Button.new("Button 2")
    panel2.add_child(button2)

    window.add_child(panel1)
    window.add_child(panel2)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Establish z-order: panel1 first, then panel2
    panel1.bring_to_front
    renderer.render_frame(app)
    panel2.bring_to_front
    renderer.render_frame(app)

    # Test initial state: panel2 is topmost (active), panel1 is not topmost (inactive)
    panel2.topmost?.should be_true
    panel1.topmost?.should be_false

    # Get initial titlebar color
    panel1_layer = panel1.layer.not_nil!
    panel1_backend = panel1_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    titlebar_y = (panel1.title_bar_height / 2).to_i
    titlebar_x = (panel1.width / 2).to_i

    initial_color = panel1_backend.get_pixel(titlebar_x, titlebar_y)
    inactive_color = CrymbleUI::Theme.current.panel_title_bar_inactive
    initial_color.should eq(inactive_color)

    # Click button1 (panel CONTENT, not titlebar) - should still bring panel to front
    button1_abs = button1.absolute_bounds
    button_click_x = button1_abs.x + button1_abs.width / 2
    button_click_y = button1_abs.y + button1_abs.height / 2

    renderer.mouse_down(button_click_x, button_click_y)
    renderer.render_frame(app)

    # Verify panel1 became topmost from content click (not just titlebar clicks)
    panel1.topmost?.should be_true
    panel2.topmost?.should be_false

    # Verify titlebar color updated to ACTIVE after clicking panel content
    after_content_click_color = panel1_backend.get_pixel(titlebar_x, titlebar_y)
    active_color = CrymbleUI::Theme.current.panel_title_bar_active
    after_content_click_color.should eq(active_color)
    after_content_click_color.should_not eq(inactive_color)
  end

  it "dims old topmost panel titlebar when bringing another panel to front" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelTitlebarTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)

    panel1 = CrymbleUI::WindowPanel.new("Panel 1", 50.0, 50.0, 300.0, 200.0)
    panel2 = CrymbleUI::WindowPanel.new("Panel 2", 100.0, 100.0, 300.0, 200.0)

    window.add_child(panel1)
    window.add_child(panel2)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Establish z-order: panel1 first, then panel2
    panel1.bring_to_front
    renderer.render_frame(app)
    panel2.bring_to_front
    renderer.render_frame(app)

    panel2.topmost?.should be_true
    panel1.topmost?.should be_false

    # Get panel2 titlebar color (should be ACTIVE)
    panel2_layer = panel2.layer.not_nil!
    panel2_backend = panel2_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    titlebar_y = (panel2.title_bar_height / 2).to_i
    titlebar_x = (panel2.width / 2).to_i

    panel2_initial_color = panel2_backend.get_pixel(titlebar_x, titlebar_y)
    active_color = CrymbleUI::Theme.current.panel_title_bar_active
    panel2_initial_color.should eq(active_color)

    # Click panel1 to bring it to front
    panel1_click_x = panel1.x + panel1.width / 2
    panel1_click_y = panel1.y + panel1.title_bar_height / 2

    renderer.mouse_down(panel1_click_x, panel1_click_y)
    renderer.render_frame(app)

    # Panel1 should now be topmost
    panel1.topmost?.should be_true
    panel2.topmost?.should be_false

    # Panel2 titlebar should now be INACTIVE (dimmed)
    panel2_after_color = panel2_backend.get_pixel(titlebar_x, titlebar_y)
    inactive_color = CrymbleUI::Theme.current.panel_title_bar_inactive

    # BUG: This should be inactive color, but the old topmost panel doesn't
    # update its titlebar when another panel is brought to front
    panel2_after_color.should eq(inactive_color)
    panel2_after_color.should_not eq(active_color)
  end
end
