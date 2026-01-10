require "../spec_helper"
require "../../src/widgets/popup"
require "../../src/widgets/scroll_view"
require "../../src/widgets/button"
require "../../src/widgets/window"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# Test that ScrollView content renders correctly when nested inside Popup
# This tests the nested layer-owning widget architecture
describe "ScrollView inside Popup" do
  describe "content rendering" do
    it "ScrollView content renders inside Popup (widget_backend not nil)" do
      # Create Window to host the overlay
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create Popup containing ScrollView with content
      popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
      scroll_view = CrymbleUI::ScrollView.new
      vstack = CrymbleUI::VStack.new

      # Add buttons to VStack (use add_child to set parent properly)
      buttons = [] of CrymbleUI::Button
      5.times do |i|
        btn = CrymbleUI::Button.new("Item #{i}") { }
        buttons << btn
        vstack.add_child(btn)
      end

      # Wire up the hierarchy
      scroll_view.set_content(vstack)
      scroll_view.parent = popup
      popup.children << scroll_view

      # Add popup as overlay
      window.add_overlay(popup)

      # Create app and render
      app = TestApp.new
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      # CRITICAL ASSERTION: Content widgets should have render backends
      # This proves they were actually rendered, not just created
      first_button = buttons.first
      first_button.widget_backend.should_not be_nil,
        "Button inside ScrollView inside Popup has no render backend - content not rendered"
    end

    it "ScrollView layer is collected when inside Popup" do
      # Create Window to host the overlay
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create Popup containing ScrollView
      popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
      scroll_view = CrymbleUI::ScrollView.new
      vstack = CrymbleUI::VStack.new
      3.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)
      scroll_view.parent = popup
      popup.children << scroll_view
      window.add_overlay(popup)

      # Create app and render
      app = TestApp.new
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      # Verify ScrollView's layer exists and has backend
      scroll_view.layer.should_not be_nil, "ScrollView should have a layer"
      scroll_view.layer.not_nil!.backend.should_not be_nil, "ScrollView layer should have backend"
    end

    it "ScrollView layer.widgets contains content" do
      # Create Window to host the overlay
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create Popup containing ScrollView
      popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0)
      scroll_view = CrymbleUI::ScrollView.new
      vstack = CrymbleUI::VStack.new
      3.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)
      scroll_view.parent = popup
      popup.children << scroll_view
      window.add_overlay(popup)

      # Create app and render
      app = TestApp.new
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      # Verify layer.widgets is populated (set during perform_layout)
      layer = scroll_view.layer.not_nil!
      layer.widgets.should_not be_empty, "ScrollView layer.widgets should contain content"
      layer.widgets.first.should eq vstack
    end

    it "ScrollView content renders to its own layer backend" do
      # Create Window to host the overlay
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create Popup containing ScrollView
      popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, padding: 4.0)
      scroll_view = CrymbleUI::ScrollView.new
      vstack = CrymbleUI::VStack.new
      5.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)
      scroll_view.parent = popup
      popup.children << scroll_view
      window.add_overlay(popup)

      # Create app and render
      app = TestApp.new
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      # Get ScrollView's layer backend
      layer = scroll_view.layer.not_nil!
      backend = layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

      # Check for non-transparent pixels in the content area
      # For viewport_cache layers, content is offset by buffer_origin
      # buffer_origin = (-100, -100) means content at layer_local (0,0) renders at buffer (100, 100)
      buffer_offset_x = (-layer.buffer_origin.x).to_i
      buffer_offset_y = (-layer.buffer_origin.y).to_i

      non_transparent_count = 0
      10.times do |y|
        10.times do |x|
          pixel = backend.get_pixel(x + buffer_offset_x + 5, y + buffer_offset_y + 5)
          if pixel && pixel.a > 0
            non_transparent_count += 1
          end
        end
      end

      non_transparent_count.should be > 0,
        "ScrollView layer has no visible content at buffer position (#{buffer_offset_x}, #{buffer_offset_y})"
    end

    it "ScrollView content is composited to final window output (nested layer collected)" do
      # This test verifies the FINAL composited output contains ScrollView content
      # It will FAIL if ScrollView's layer is orphaned (not collected for rendering)

      # Create Window to host the overlay
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create Popup at specific position containing ScrollView
      popup = CrymbleUI::Popup.new(width: 200.0, height: 150.0, padding: 4.0)
      scroll_view = CrymbleUI::ScrollView.new
      vstack = CrymbleUI::VStack.new
      5.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)
      scroll_view.parent = popup
      popup.children << scroll_view
      window.add_overlay(popup)

      # Create app and render
      app = TestApp.new
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.render_frame(app)

      scroll_layer = scroll_view.layer.not_nil!
      final_backend = renderer.backend

      # Check pixels inside the popup area (where ScrollView content should be visible)
      composite_x = scroll_layer.bounds.x.to_i
      composite_y = scroll_layer.bounds.y.to_i

      # Sample a region at the composite destination
      non_transparent_count = 0
      20.times do |y|
        20.times do |x|
          pixel = final_backend.get_pixel(composite_x + x, composite_y + y)
          if pixel && pixel.a > 0
            non_transparent_count += 1
          end
        end
      end

      # This test will FAIL if ScrollView's layer is not composited to window
      non_transparent_count.should be > 0,
        "ScrollView content not visible in final window output at (#{composite_x}, #{composite_y}) - nested layer NOT composited"
    end
  end
end
