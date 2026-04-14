require "../spec_helper"
require "../../src/testing/test_renderer"

include CrymbleUI

# App that overrides background color (simulates license-based coloring)
class CustomBgApp < CrymbleUI::App
  property custom_bg : CrymbleUI::Color? = nil

  def build : CrymbleUI::Widget
    Window.new("Test", 400, 300)
  end

  def app_background_color : CrymbleUI::Color?
    @custom_bg
  end
end

describe "App background color" do
  it "returns nil by default (use theme)" do
    app = TestApp.new
    app.app_background_color.should be_nil
  end

  it "renderer uses custom app background color when overridden" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = CustomBgApp.new
    dark_green = CrymbleUI::Color.new(0, 51, 0, 255)
    app.custom_bg = dark_green

    app.build_tree
    renderer.settle_rendering(app)

    # Sample the window backend at a corner not covered by any widget content
    # The window clear color should be dark green, not white
    window_backend = renderer.backend
    pixel = window_backend.get_pixel(0, 0)
    pixel.should_not be_nil, "No pixel at (0,0) on window backend"
    pixel = pixel.not_nil!
    pixel.r.should eq 0_u8
    pixel.g.should eq 51_u8
    pixel.b.should eq 0_u8
  end

  it "renderer falls back to default when app_background_color is nil" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = CustomBgApp.new
    # custom_bg is nil by default

    app.build_tree
    renderer.settle_rendering(app)

    # Should use default white (TestRenderer default)
    window_backend = renderer.backend
    pixel = window_backend.get_pixel(0, 0)
    pixel.should_not be_nil
    pixel = pixel.not_nil!
    pixel.r.should eq 255_u8
    pixel.g.should eq 255_u8
    pixel.b.should eq 255_u8
  end
end
