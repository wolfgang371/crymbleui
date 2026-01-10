require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for layer/widget clipping
# Issue: Widgets can draw outside their boundaries, causing visual artifacts
# This tests that rendering respects widget bounds and doesn't draw outside

describe "Clipping (Layer Bounds)" do
  describe "MenuItem in Popup" do
    it "does not draw outside popup bounds (pixel test)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("File")

      # Create menu item
      # Use a Popup with GRAY background so buffer area is visible if blitted
      item = CrymbleUI::MenuItem.new("Item",
        hover_color: CrymbleUI::Color.new(100, 150, 250, 255)
      )

      menu.add_child(item)
      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Open menu and hover item
      menu.on_click
      item.on_mouse_enter
      renderer.render_frame(app)

      # Get popup and its layer
      popups = window.find_all_popups
      popup = popups.first
      popup_layer = popup.layer.not_nil!
      popup_bounds = popup_layer.bounds

      # Get window backend to check pixels outside popup
      window_backend = renderer.backend

      # Check pixels just outside popup's right edge
      # These should NOT be affected by the menu item rendering
      outside_x = (popup_bounds.x + popup_bounds.width + 5).to_i
      center_y = (popup_bounds.y + popup_bounds.height / 2).to_i

      # Pixel outside should NOT be the menu item hover color (clipping working correctly)
      pixel_outside = window_backend.get_pixel(outside_x, center_y)

      # Should NOT be the hover color (meaning it didn't draw outside bounds)
      pixel_outside.should_not eq(CrymbleUI::Color.new(100, 150, 250, 255))
      # Should be either MenuBar background (gray) or window content (white),
      # depending on popup Y position (which may vary by overlay system)
      menubar_gray = CrymbleUI::Color.new(250, 250, 250, 255)
      window_white = CrymbleUI::Color.new(255, 255, 255, 255)
      (pixel_outside == menubar_gray || pixel_outside == window_white).should be_true
    end

    it "does not draw outside popup bounds on bottom edge (pixel test)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("File")

      # Create menu items that would overflow popup height
      5.times do |i|
        item = CrymbleUI::MenuItem.new("Item #{i}",
          hover_color: CrymbleUI::Color.new(100, 150, 250, 255)
        )
        menu.add_child(item)
      end

      menubar.add_child(menu)
      window.add_child(menubar)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)

      # Open menu
      menu.on_click
      renderer.render_frame(app)

      # Get popup bounds
      popups = window.find_all_popups
      popup = popups.first
      popup_layer = popup.layer.not_nil!
      popup_bounds = popup_layer.bounds

      # Get window backend
      window_backend = renderer.backend

      # Check pixel just outside popup's bottom edge
      center_x = (popup_bounds.x + popup_bounds.width / 2).to_i
      outside_y = (popup_bounds.y + popup_bounds.height + 5).to_i

      pixel_outside = window_backend.get_pixel(center_x, outside_y)

      # Should NOT be the menu item color
      pixel_outside.should_not eq(CrymbleUI::Color.new(100, 150, 250, 255))
      # Should be window background (white)
      pixel_outside.should eq(CrymbleUI::Color.new(255, 255, 255, 255))
    end
  end

end
