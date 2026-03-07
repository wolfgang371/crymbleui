require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: Chrome should not render into panel content area when clicking highlighted panel
#
# BUG: After layout isolation changes, when clicking on a highlighted (topmost) panel,
# the chrome (titlebar, borders) gets rendered additionally in the content area.
#
# Expected: Chrome only renders at panel edges (titlebar at top, borders at edges)
# Actual: Chrome primitives also appear in content area after click

class PanelChromeTestApp < CrymbleUI::App
  property root_widget : CrymbleUI::Widget?

  def build : CrymbleUI::Widget
    @root_widget.not_nil!
  end

  def root_widget=(widget : CrymbleUI::Widget)
    @root_widget = widget
    @root = widget
  end
end

describe "Panel chrome rendering on click" do
  it "does not render chrome in content area when clicking already-topmost panel (panels_demo scenario)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelChromeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create 3 panels like panels_demo - Tools, Inspector, Info
    panel1 = CrymbleUI::WindowPanel.new("Tools", 50.0, 100.0, 200.0, 150.0)
    button1 = CrymbleUI::Button.new("Increment")
    panel1.add_child(button1)

    panel2 = CrymbleUI::WindowPanel.new("Inspector", 550.0, 100.0, 220.0, 200.0)
    button2 = CrymbleUI::Button.new("Inspect")
    panel2.add_child(button2)

    # Panel3 matches panels_demo: text widgets, no buttons
    panel3 = CrymbleUI::WindowPanel.new("Info", 300.0, 350.0, 200.0, 120.0)
    text1 = CrymbleUI::Text.new("Info Panel", font_scale: -1)
    text2 = CrymbleUI::Text.new("Version: 1.0", font_scale: -2)
    panel3.add_child(text1)
    panel3.add_child(text2)

    window.add_child(panel1)
    window.add_child(panel2)
    window.add_child(panel3)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Bring panel3 to front (make it topmost/highlighted)
    panel3.bring_to_front
    renderer.render_frame(app)

    # Verify panel3 is topmost
    panel3.topmost?.should be_true
    panel1.topmost?.should be_false
    panel2.topmost?.should be_false

    # Get panel3 layer to check pixels
    panel3_layer = panel3.layer.not_nil!
    panel3_backend = panel3_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixel in content area GAP (between titlebar and button)
    # Titlebar ends at y=30, Content widget starts at y=38 (CONTENT_PADDING=8)
    # Check y=34 which is in the gap - should be panel background, NOT titlebar color
    content_y = 34  # In gap between titlebar and button
    content_x = (panel3.width / 2).to_i  # Center of panel

    # Define titlebar colors for comparison
    titlebar_active_color = CrymbleUI::Theme.current.panel_title_bar_active
    titlebar_inactive_color = CrymbleUI::Theme.current.panel_title_bar_inactive

    # Get initial gap pixel color (before click)
    initial_content_pixel = panel3_backend.get_pixel(content_x, content_y)

    # Click on panel3 titlebar (which is ALREADY highlighted/topmost)
    # This is the scenario from panels_demo - clicking an already-highlighted panel
    titlebar_click_x = panel3.x + panel3.width / 2
    titlebar_click_y = panel3.y + panel3.title_bar_height / 2

    renderer.mouse_down(titlebar_click_x, titlebar_click_y)
    renderer.render_frame(app)

    # Get content pixel color after click
    after_click_content_pixel = panel3_backend.get_pixel(content_x, content_y)

    # BUG CHECK: Gap area (between titlebar and content) should NOT have titlebar color
    # If chrome is leaking, we'll see titlebar color in the gap area (y=30-37)

    # Gap pixel should NOT be titlebar color - should be panel background
    # Debug: Print 10x10 pixel grid if test fails
    if after_click_content_pixel == titlebar_active_color || after_click_content_pixel == titlebar_inactive_color
      puts "\n=== DEBUG INFO ==="
      puts "Panel3 size: #{panel3.width}x#{panel3.height}"
      puts "Panel3 layer size: #{panel3_backend.width}x#{panel3_backend.height}"
      puts "Checking gap pixel at: (#{content_x}, #{content_y})"
      puts "Expected: #{panel3_layer.background_color} (panel background)"
      puts "Got: #{after_click_content_pixel.inspect} (titlebar color - CHROME LEAK!)"

      puts "\n=== 10x10 Pixel Grid Around (#{content_x}, #{content_y}) ==="
      puts "Legend: 0=black, f=white, 7=#0078D7 (active titlebar)"
      start_y = content_y - 5
      start_x = content_x - 5
      (0...10).each do |dy|
        row = ""
        (0...10).each do |dx|
          sample_x = start_x + dx
          sample_y = start_y + dy
          if sample_x >= 0 && sample_x < panel3_backend.width && sample_y >= 0 && sample_y < panel3_backend.height
            pixel = panel3_backend.get_pixel(sample_x, sample_y)
            if pixel
              # Convert to grayscale: 0.299*R + 0.587*G + 0.114*B
              grey = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).to_i
              # Get high nibble (0-15)
              nibble = (grey >> 4) & 0xF
              row += nibble.to_s(16)
            else
              row += "?"
            end
          else
            row += "."
          end
        end
        puts row
      end
      puts "=== End Grid ==="
    end

    after_click_content_pixel.should_not eq(titlebar_active_color)
    after_click_content_pixel.should_not eq(titlebar_inactive_color)

    # Content pixel should remain the same as before click (stable content rendering)
    after_click_content_pixel.should eq(initial_content_pixel)
  end

  it "does not render border chrome in content center when clicking highlighted panel" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelChromeTestApp.new

    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create panel with distinct background color
    panel = CrymbleUI::WindowPanel.new("Test Panel", 100.0, 100.0, 400.0, 300.0)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Get panel layer backend
    panel_layer = panel.layer.not_nil!
    panel_backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Sample pixel in center of content area (should be panel background, NOT border color)
    center_x = (panel.width / 2).to_i
    center_y = (panel.height / 2).to_i

    # Get initial center pixel
    initial_center_pixel = panel_backend.get_pixel(center_x, center_y)

    # Click panel titlebar
    titlebar_click_x = panel.x + panel.width / 2
    titlebar_click_y = panel.y + panel.title_bar_height / 2

    renderer.mouse_down(titlebar_click_x, titlebar_click_y)
    renderer.render_frame(app)

    # Get center pixel after click
    after_click_center_pixel = panel_backend.get_pixel(center_x, center_y)

    # Border color from panel instance
    border_color = panel.border_color

    # Center of content should NOT have border color (that should only be at edges)
    after_click_center_pixel.should_not eq(border_color)

    # Content center should remain stable
    after_click_center_pixel.should eq(initial_center_pixel)
  end
end
