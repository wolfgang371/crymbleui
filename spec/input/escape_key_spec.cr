require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for ESC key behavior
# ESC should cancel menus and drags

describe "ESC Key Handling" do
  describe "handle_escape" do
    it "closes open menus" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new

      menu = CrymbleUI::Menu.new("File")
      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      renderer.render_frame(app)

      # Open the menu
      menu.on_click
      menu.open?.should be_true
      menubar.menu_system_active.should be_true

      # Press ESC
      handled = app.handle_escape
      handled.should be_true

      # Menu should be closed
      menu.open?.should be_false
      menubar.menu_system_active.should be_false
    end

    it "cancels active drag" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)

      # Create a draggable widget with content (DraggableBox needs child for size)
      draggable = CrymbleUI::DraggableBox.new(
        drag_data: CrymbleUI::TextDragData.new("test"),
        id: "drag_source"
      )
      content = CrymbleUI::Text.new("Drag me")
      draggable.add_child(content)
      window.add_child(draggable)
      app.root_widget = window

      renderer.render_frame(app)

      # Start dragging (simulate mouse down + move past threshold)
      drag_start = CrymbleUI::Vec2.new(50.0, 50.0)
      app.handle_mouse_down(drag_start)
      app.handle_mouse_move(CrymbleUI::Vec2.new(100.0, 100.0))

      # Should be dragging
      app.drag_manager.dragging?.should be_true

      # Press ESC
      handled = app.handle_escape
      handled.should be_true

      # Drag should be cancelled
      app.drag_manager.dragging?.should be_false
    end

    it "returns false when nothing to cancel" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      app.root_widget = window

      renderer.render_frame(app)

      # Press ESC with nothing open
      handled = app.handle_escape
      handled.should be_false
    end

    it "drag cancel takes priority (menu auto-closes on click outside)" do
      # Note: When you click to start a drag, handle_mouse_down auto-closes menus
      # because clicking outside a menu closes it. So in practice you can't have
      # both an open menu AND an active drag simultaneously.
      # This test verifies drag cancel works independently.
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)

      draggable = CrymbleUI::DraggableBox.new(
        drag_data: CrymbleUI::TextDragData.new("test"),
        id: "drag_source"
      )
      content = CrymbleUI::Text.new("Drag me")
      draggable.add_child(content)
      window.add_child(draggable)
      app.root_widget = window

      renderer.render_frame(app)

      # Start drag
      drag_start = CrymbleUI::Vec2.new(10.0, 10.0)
      app.handle_mouse_down(drag_start)
      app.handle_mouse_move(CrymbleUI::Vec2.new(60.0, 60.0))
      app.drag_manager.dragging?.should be_true

      # ESC cancels drag and returns true
      handled = app.handle_escape
      handled.should be_true
      app.drag_manager.dragging?.should be_false

      # ESC again returns false (nothing to cancel)
      handled = app.handle_escape
      handled.should be_false
    end
  end
end
