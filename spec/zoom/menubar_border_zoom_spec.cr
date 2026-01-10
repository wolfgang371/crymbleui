require "../spec_helper"
require "../../src/testing/test_renderer"

# TEST: MenuBar border should be visible at ALL zoom levels
#
# BUG: Border disappears at zoom levels 3, 5, 8 but visible at 4, 6, 7
# This pattern suggests a layer/bounds mismatch or clipping issue, not simple
# sub-pixel rendering problems.
#
# Zoom levels from default (100%):
# - Level 3 (1.5x): height=35.0 - NO border (BUG)
# - Level 4 (1.75x): height=38.5 - border visible
# - Level 5 (2.0x): height=42.0 - NO border (BUG)
# - Level 6 (2.5x): height=49.0 - border visible
# - Level 7 (3.0x): height=56.0 - border visible

class MenuBarZoomTestApp < CrymbleUI::App
  property root_widget : CrymbleUI::Widget?

  def build : CrymbleUI::Widget
    @root_widget.not_nil!
  end

  def root_widget=(widget : CrymbleUI::Widget)
    @root_widget = widget
    @root = widget
  end
end

describe "MenuBar border at zoom levels" do
  # Test checking the FINAL WINDOW BUFFER (after compositing)
  # This is what the user actually sees - catches compositing bugs that layer-only tests miss
  it "border visible in WINDOW buffer at zoom level 3 (1.5x)" do
    3.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    # Verify zoom level
    CrymbleUI::FontSizing.zoom_factor.should be_close(1.5, 0.01)

    # Get menubar height and calculate border position
    expected_height = menubar.menubar_height
    expected_height.should be_close(35.0, 0.5)

    # Check the WINDOW buffer (renderer.backend), not just the layer backend
    # This is what the user actually sees after compositing
    window_backend = renderer.backend
    border_y = (expected_height - 1).to_i  # y=34 for height=35
    border_x = 400

    border_pixel = window_backend.get_pixel(border_x, border_y)

    # Border should be visible in the final window buffer
    border_pixel.should eq(menubar.border_color)
  end

  it "border visible in WINDOW buffer at zoom level 5 (2.0x)" do
    5.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    CrymbleUI::FontSizing.zoom_factor.should be_close(2.0, 0.01)

    expected_height = menubar.menubar_height
    expected_height.should be_close(42.0, 0.5)

    window_backend = renderer.backend
    border_y = (expected_height - 1).to_i
    border_x = 400

    border_pixel = window_backend.get_pixel(border_x, border_y)

    border_pixel.should eq(menubar.border_color)
  end

  # --- Original tests below (check layer backend) ---

  it "border is visible at zoom level 3 (1.5x)" do
    # Zoom in 3 times from default to reach 1.5x
    3.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    # Verify zoom is at expected level
    CrymbleUI::FontSizing.zoom_factor.should be_close(1.5, 0.01)

    # Get menubar layer
    menubar_layer = menubar.layer.not_nil!
    backend = menubar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Calculate expected menubar height at this zoom
    expected_height = menubar.menubar_height
    expected_height.should be_close(35.0, 0.5)  # 14*1.5 + 14 = 35

    # Border should be at bottom of menubar (height - 1)
    # In layer-local coordinates, border is at y = height - 1
    border_y = (expected_height - 1).to_i
    border_x = 400  # Middle of menubar

    # Border pixel should have border color (gray: 200,200,200)
    border_pixel = backend.get_pixel(border_x, border_y)

    border_pixel.should eq(menubar.border_color)
  end

  it "border is visible at zoom level 5 (2.0x)" do
    # Zoom in 5 times from default to reach 2.0x
    5.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    # Verify zoom is at expected level
    CrymbleUI::FontSizing.zoom_factor.should be_close(2.0, 0.01)

    # Get menubar layer
    menubar_layer = menubar.layer.not_nil!
    backend = menubar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Calculate expected menubar height at this zoom
    expected_height = menubar.menubar_height
    expected_height.should be_close(42.0, 0.5)  # 14*2.0 + 14 = 42

    # Border at bottom
    border_y = (expected_height - 1).to_i
    border_x = 400

    border_pixel = backend.get_pixel(border_x, border_y)

    border_pixel.should eq(menubar.border_color)
  end

  it "border is visible at zoom level 8 (3.0x - max)" do
    # Zoom in 7 times from default to reach 3.0x (max)
    7.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    # Verify zoom is at expected level (3.0x is max)
    CrymbleUI::FontSizing.zoom_factor.should be_close(3.0, 0.01)

    # Get menubar layer
    menubar_layer = menubar.layer.not_nil!
    backend = menubar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Calculate expected menubar height at this zoom
    expected_height = menubar.menubar_height
    expected_height.should be_close(56.0, 0.5)  # 14*3.0 + 14 = 56

    # Border at bottom
    border_y = (expected_height - 1).to_i
    border_x = 400

    border_pixel = backend.get_pixel(border_x, border_y)

    border_pixel.should eq(menubar.border_color)
  end

  # Control test: verify border works at a "good" zoom level
  it "border is visible at zoom level 4 (1.75x) - control" do
    # Zoom in 4 times from default to reach 1.75x
    4.times { CrymbleUI::FontSizing.zoom_in }

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = MenuBarZoomTestApp.new

    menubar = CrymbleUI::MenuBar.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)

    # Verify zoom is at expected level
    CrymbleUI::FontSizing.zoom_factor.should be_close(1.75, 0.01)

    # Get menubar layer
    menubar_layer = menubar.layer.not_nil!
    backend = menubar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    expected_height = menubar.menubar_height
    border_y = (expected_height - 1).to_i
    border_x = 400

    border_pixel = backend.get_pixel(border_x, border_y)

    # This one should pass (control test)
    border_pixel.should eq(menubar.border_color)
  end
end
