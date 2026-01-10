require "../spec_helper"
require "../../src/testing/test_render_backend"

# Tests that verify ACTUAL pixel output from rendering
# Uses TestRenderBackend to check if content is really rendered (not white)

# Helper to recursively render widget and children (NEW architecture support)
# Primitives use widget-local coords, so we need to translate: widget-local → absolute → layer-local
def render_widget_and_children_recursive(widget : CrymbleUI::Widget, backend, offset_x : Float64, offset_y : Float64)
  return if widget.skip_render?

  # Get widget's absolute position (in window coords)
  widget_abs_x = widget.absolute_bounds.x
  widget_abs_y = widget.absolute_bounds.y

  primitives = widget.get_primitives(widget.bounds)
  primitives.each do |primitive|
    case primitive
    when CrymbleUI::FillRect
      # Convert: widget-local → absolute → layer-local
      abs_x = primitive.bounds.x + widget_abs_x
      abs_y = primitive.bounds.y + widget_abs_y
      local_bounds = CrymbleUI::Rect.new(
        abs_x - offset_x,
        abs_y - offset_y,
        primitive.bounds.width,
        primitive.bounds.height
      )
      backend.fill_rect(local_bounds, primitive.color)
    when CrymbleUI::DrawRect
      # Convert: widget-local → absolute → layer-local
      abs_x = primitive.bounds.x + widget_abs_x
      abs_y = primitive.bounds.y + widget_abs_y
      local_bounds = CrymbleUI::Rect.new(
        abs_x - offset_x,
        abs_y - offset_y,
        primitive.bounds.width,
        primitive.bounds.height
      )
      backend.draw_rect(local_bounds, primitive.color)
    when CrymbleUI::DrawLine
      # Convert: widget-local → absolute → layer-local
      abs_from_x = primitive.from.x + widget_abs_x
      abs_from_y = primitive.from.y + widget_abs_y
      abs_to_x = primitive.to.x + widget_abs_x
      abs_to_y = primitive.to.y + widget_abs_y
      backend.draw_line(
        abs_from_x - offset_x,
        abs_from_y - offset_y,
        abs_to_x - offset_x,
        abs_to_y - offset_y,
        primitive.color
      )
    end
  end

  # Recursively render children (needed for Content and other container widgets)
  widget.children.each do |child|
    render_widget_and_children_recursive(child, backend, offset_x, offset_y)
  end
end

describe "Actual Rendering Output" do
  describe "Panel content rendering to layer texture" do
    it "renders button primitives to panel layer (not blank) - NEW recursive architecture" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Create test backend for layer texture
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        panel_layer.bounds.width.to_i,
        panel_layer.bounds.height.to_i,
        CrymbleUI::Color.new(255, 255, 255, 255)  # White background
      )

      # Apply layer offset (widgets use absolute coords, layer uses relative)
      layer_offset_x = panel_layer.bounds.x
      layer_offset_y = panel_layer.bounds.y

      # Render all widgets in layer (Chrome, Content) AND their children (button) recursively
      # This matches NEW architecture where button is child of panel/Content, not in layer.widgets
      panel_layer.widgets.each do |widget|
        render_widget_and_children_recursive(widget, backend, layer_offset_x, layer_offset_y)
      end

      # Check that SOME pixels are non-white (content was rendered)
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      non_white_pixels = 0

      20.times do |y|
        20.times do |x|
          pixel = backend.get_pixel(x, y)
          non_white_pixels += 1 if pixel && pixel != white
        end
      end

      # Should have SOME non-white pixels (button rendered)
      non_white_pixels.should be > 0
    end

    it "renders panel chrome to panel layer" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Create test backend
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        panel_layer.bounds.width.to_i,
        panel_layer.bounds.height.to_i
      )

      # NEW architecture: Chrome widget is first in layer.widgets
      chrome = panel_layer.widgets[0]
      chrome.should be_a(CrymbleUI::WindowPanel::Chrome)

      # Widget-local coordinates: primitives start at (0,0)
      # To render to layer, we need: widget-local + (widget.absolute - layer.origin)
      chrome_primitives = chrome.get_primitives(chrome.bounds)

      # Widget-local to layer-local translation
      widget_offset_x = chrome.absolute_bounds.x - panel_layer.bounds.x
      widget_offset_y = chrome.absolute_bounds.y - panel_layer.bounds.y

      chrome_primitives.each do |primitive|
        case primitive
        when CrymbleUI::FillRect
          layer_bounds = CrymbleUI::Rect.new(
            primitive.bounds.x + widget_offset_x,
            primitive.bounds.y + widget_offset_y,
            primitive.bounds.width,
            primitive.bounds.height
          )
          backend.fill_rect(layer_bounds, primitive.color)
        when CrymbleUI::DrawRect
          layer_bounds = CrymbleUI::Rect.new(
            primitive.bounds.x + widget_offset_x,
            primitive.bounds.y + widget_offset_y,
            primitive.bounds.width,
            primitive.bounds.height
          )
          backend.draw_rect(layer_bounds, primitive.color)
        end
      end

      # Panel chrome should render (title bar, borders)
      # Check for non-white pixels
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      non_white_count = 0

      50.times do |y|
        50.times do |x|
          pixel = backend.get_pixel(x, y)
          non_white_count += 1 if pixel && pixel != white
        end
      end

      # Chrome should be visible
      non_white_count.should be > 0
    end

    it "renders button in window root layer (not blank)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Root Button") { }
      window.add_child(button)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!

      # Create test backend (use smaller size for testing)
      backend = CrymbleUI::Testing::TestRenderBackend.new(200, 200)

      # Render button
      button_primitives = button.get_primitives(button.bounds)

      button_primitives.each do |primitive|
        backend.execute_primitive(primitive)
      end

      # Check that button rendered (non-white pixels)
      white = CrymbleUI::Color.new(255, 255, 255, 255)
      non_white_count = 0

      100.times do |y|
        100.times do |x|
          pixel = backend.get_pixel(x, y)
          non_white_count += 1 if pixel && pixel != white
        end
      end

      # Button should be visible
      non_white_count.should be > 0
    end
  end

  describe "Layer offset coordinate translation" do
    it "translates widget absolute coords to layer-relative coords" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # With parent-relative bounds architecture:
      # - button.bounds is relative to panel (e.g., x=0, y=30)
      # - button.absolute_bounds is in window coordinates (e.g., x=100, y=130)
      # - layer.bounds is absolute (panel position - border, e.g., x=98, y=98)

      # When rendering to layer texture, we need layer-relative coords
      # For a button at absolute (100, 130) with layer at (98, 98):
      # button_local = (100, 130) - (98, 98) = (2, 32)

      layer_offset_x = panel_layer.bounds.x
      layer_offset_y = panel_layer.bounds.y

      # Button's local position in layer texture (using absolute bounds)
      button_abs = button.absolute_bounds
      button_local_x = button_abs.x - layer_offset_x
      button_local_y = button_abs.y - layer_offset_y

      # Local coords should be small positive numbers (relative to layer origin)
      button_local_x.should be >= 0
      button_local_y.should be >= 0
      button_local_x.should be < panel_layer.bounds.width
      button_local_y.should be < panel_layer.bounds.height
    end
  end
end
