require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for cursor state management
#
# BUG: When user releases mouse (mouse_up) after resize and quickly moves cursor,
# the resize cursor persists instead of changing back to arrow cursor.
#
# Root cause: mouse_up doesn't update cursor state, so cursor only updates
# on next mouse_move event, creating visible delay.

describe "Cursor State Management" do
  it "cursor resets to Arrow immediately after resize mouse_up" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Step 1: Hover over right edge - cursor becomes SizeHorizontal
    panel_right_edge = 100.0 + 200.0  # Panel at x=100, width=200
    renderer.mouse_move(panel_right_edge, 150.0)
    renderer.current_cursor.should eq(CrymbleUI::CursorType::SizeHorizontal)

    # Step 2: Mouse down on edge to start resize
    renderer.mouse_down(panel_right_edge, 150.0)

    # Step 3: Mouse up to end resize - move mouse slightly into content area
    # This simulates the bug scenario: quick mouse movement into content after resize
    content_x = panel_right_edge - 10.0  # 10px inside panel (not on edge)
    renderer.mouse_up(content_x, 150.0)

    # After mouse_up over content (not edge), cursor should immediately be Arrow
    # BUG: Without fix, cursor stays SizeHorizontal because mouse_up doesn't update it
    renderer.current_cursor.should eq(CrymbleUI::CursorType::Arrow)
  end

  it "cursor updates correctly on mouse_move over panel content" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Mouse move over panel content (not on resize edge)
    renderer.mouse_move(150.0, 150.0)

    # Cursor should be Arrow when over panel content
    renderer.current_cursor.should eq(CrymbleUI::CursorType::Arrow)
  end

  it "cursor updates to resize cursor when hovering over resize edge" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Mouse move over right edge (should set SizeHorizontal cursor)
    panel_right_edge = 100.0 + 200.0
    renderer.mouse_move(panel_right_edge, 150.0)

    # Cursor should be SizeHorizontal when hovering over right edge
    renderer.current_cursor.should eq(CrymbleUI::CursorType::SizeHorizontal)
  end
end
