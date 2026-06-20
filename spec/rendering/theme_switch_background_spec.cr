require "../spec_helper"
require "../../src/testing/test_renderer"

include CrymbleUI

# Widget that renders NOTHING — relies entirely on background_backend for its pixels.
# This is the most sensitive widget for the stale-background bug: after a theme switch,
# if background_backend isn't invalidated, this widget shows old parent background.
class TransparentBox < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  reactive_property fixed_width : Float64, layout: true
  reactive_property fixed_height : Float64, layout: true

  def initialize(fixed_width : Float64, fixed_height : Float64, id : String? = nil)
    @fixed_width = CrymbleUI::Source(Float64).new(fixed_width)
    @fixed_height = CrymbleUI::Source(Float64).new(fixed_height)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(fixed_width, fixed_height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    @state = CrymbleUI::WidgetState::Clean
    mark_needs_render
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    # Render nothing — background shows through entirely
    [] of CrymbleUI::DrawPrimitive
  end
end

# DSL-style app with a themed panel containing a transparent child.
# The transparent child's background_backend captures the panel background color.
# After theme switch, the bug causes the child to show old (light) panel background.
class ThemeSwitchPanelApp < CrymbleUI::App
  property panel_bg_color : Color = Theme.current.panel_background

  def build : CrymbleUI::Widget
    window = Window.new("Test", 400, 300)
    panel = WindowPanel.new("Panel", 10.0, 10.0, 200.0, 150.0, id: "panel")
    panel.background_color = @panel_bg_color
    panel.add_child(TransparentBox.new(80.0, 30.0, id: "tbox"))
    window.add_child(panel)
    window
  end
end

describe "Theme switch background" do
  it "updates child backgrounds when panel background changes after rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ThemeSwitchPanelApp.new

    # Render with light theme
    app.build_tree
    renderer.settle_rendering(app)

    # Find the transparent box and verify it has a background_backend
    tbox = app.find("tbox").not_nil!
    tbox.background_backend.should_not be_nil,
      "TransparentBox has no background_backend — test won't exercise the bug"

    # Sample pixel at the transparent box's location on the layer
    panel = app.find("panel").not_nil!.as(WindowPanel)
    layer = panel.layer.not_nil!
    layer_backend = layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    tbox_bounds = tbox.absolute_bounds
    panel_bounds = panel.absolute_bounds
    # Convert to layer-local coordinates
    sample_x = (tbox_bounds.x - panel_bounds.x + 5).to_i
    sample_y = (tbox_bounds.y - panel_bounds.y + 5).to_i

    light_pixel = layer_backend.get_pixel(sample_x, sample_y)
    light_pixel.should_not be_nil, "No pixel at sample point before theme switch"

    # Light theme panel_background is bright (R >= 200)
    light_pixel.not_nil!.r.should be >= 200_u8

    # Switch to dark theme and rebuild
    CrymbleUI::Theme.set(:dark)
    app.panel_bg_color = Theme.current.panel_background
    app.rebuild
    renderer.settle_rendering(app)

    # Re-find after rebuild (new widget instances)
    new_panel = app.find("panel").not_nil!.as(WindowPanel)
    new_layer = new_panel.layer.not_nil!
    new_layer_backend = new_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    new_tbox = app.find("tbox").not_nil!
    new_tbox_bounds = new_tbox.absolute_bounds
    new_panel_bounds = new_panel.absolute_bounds
    new_sample_x = (new_tbox_bounds.x - new_panel_bounds.x + 5).to_i
    new_sample_y = (new_tbox_bounds.y - new_panel_bounds.y + 5).to_i

    dark_pixel = new_layer_backend.get_pixel(new_sample_x, new_sample_y)
    dark_pixel.should_not be_nil, "No pixel at sample point after theme switch"

    # Dark theme background must be significantly darker
    dark_pixel.not_nil!.r.should be < 100_u8,
      "Background pixel still bright (R=#{dark_pixel.not_nil!.r}) after dark theme switch — stale background_backend?"
  end

  it "updates backgrounds when switching back from dark to light" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ThemeSwitchPanelApp.new

    app.build_tree
    renderer.settle_rendering(app)

    # Switch to dark
    CrymbleUI::Theme.set(:dark)
    app.panel_bg_color = Theme.current.panel_background
    app.rebuild
    renderer.settle_rendering(app)

    panel = app.find("panel").not_nil!.as(WindowPanel)
    layer_backend = panel.layer.not_nil!.backend.as(CrymbleUI::Testing::TestRenderBackend)
    tbox = app.find("tbox").not_nil!
    panel_bounds = panel.absolute_bounds
    tbox_bounds = tbox.absolute_bounds
    sample_x = (tbox_bounds.x - panel_bounds.x + 5).to_i
    sample_y = (tbox_bounds.y - panel_bounds.y + 5).to_i

    dark_pixel = layer_backend.get_pixel(sample_x, sample_y)
    dark_pixel.not_nil!.r.should be < 100_u8

    # Switch back to light
    CrymbleUI::Theme.set(:light)
    app.panel_bg_color = Theme.current.panel_background
    app.rebuild
    renderer.settle_rendering(app)

    new_panel = app.find("panel").not_nil!.as(WindowPanel)
    new_layer_backend = new_panel.layer.not_nil!.backend.as(CrymbleUI::Testing::TestRenderBackend)
    new_tbox = app.find("tbox").not_nil!
    new_panel_bounds = new_panel.absolute_bounds
    new_tbox_bounds = new_tbox.absolute_bounds
    new_sample_x = (new_tbox_bounds.x - new_panel_bounds.x + 5).to_i
    new_sample_y = (new_tbox_bounds.y - new_panel_bounds.y + 5).to_i

    light_pixel = new_layer_backend.get_pixel(new_sample_x, new_sample_y)
    light_pixel.not_nil!.r.should be >= 200_u8,
      "Background pixel still dark (R=#{light_pixel.not_nil!.r}) after light theme switch — stale background_backend?"
  end
end
