require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"

describe "ScrollView initial visibility" do
  describe "Item 9 visibility (showcase_demo bug)" do
    it "all visible items have render backends on initial render without click" do
      # This test reproduces the bug where the last item (Item 9) only shows
      # after first click on the panel
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

      window = CrymbleUI::Window.new("Test", 800, 600)

      # Create panel with ScrollView containing numbered items
      panel = CrymbleUI::WindowPanel.new("Preview (ScrollView)", 50.0, 50.0, 300.0, 300.0)
      scroll_view = CrymbleUI::ScrollView.new(id: "preview_scroll")
      content = CrymbleUI::VStack.new(spacing: 2.0)

      # Add 10 items (Item 0 through Item 9)
      10.times do |i|
        content.add_child(CrymbleUI::Text.new("Item #{i}"))
      end
      scroll_view.set_content(content)
      panel.add_child(scroll_view)
      window.add_child(panel)

      app.root_widget = window

      # Initial render (no clicks yet)
      renderer.render_frame(app)

      # Get the items that should be visible in the viewport
      visible_items = content.children.select do |item|
        # Item is visible if it's within the ScrollView's viewport
        item_bounds = item.absolute_bounds
        viewport_bounds = scroll_view.absolute_bounds
        item_bounds.y < viewport_bounds.y + viewport_bounds.height &&
          item_bounds.y + item_bounds.height > viewport_bounds.y
      end

      # Each visible item should have been rendered (has widget_backend)
      visible_items.each_with_index do |item, idx|
        item.widget_backend.should_not be_nil,
          "Item #{idx} should have widget_backend on initial render (before any click)"
      end
    end

    it "items in WindowPanel ScrollView are visible immediately after layout" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Test Panel", 50.0, 50.0, 300.0, 400.0)

      scroll_view = CrymbleUI::ScrollView.new(id: "test_scroll")
      content = CrymbleUI::VStack.new(spacing: 5.0)

      # Add items - some should be visible without scrolling
      9.times do |i|
        content.add_child(CrymbleUI::Button.new("Button #{i + 1}") { })
      end
      scroll_view.set_content(content)
      panel.add_child(scroll_view)
      window.add_child(panel)

      app.root_widget = window

      # Just layout, no render yet
      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # First render
      renderer.render_frame(app)

      # Check that ScrollView's internal layer exists and has content
      scroll_view.layer.should_not be_nil, "ScrollView should have internal layer after first render"

      # All buttons that fit in viewport should have been laid out with non-zero bounds
      content.children.each_with_index do |child, idx|
        child.bounds.width.should be > 0, "Button #{idx + 1} should have non-zero width"
        child.bounds.height.should be > 0, "Button #{idx + 1} should have non-zero height"
      end
    end
  end
end
