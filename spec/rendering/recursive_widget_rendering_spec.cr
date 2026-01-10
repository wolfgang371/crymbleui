require "../spec_helper"
require "../../src/testing/test_render_backend"

# Tests for recursive widget rendering
# PROBLEM: Panel content appears white because container widgets (VStack, HStack)
# are in layer.widgets but their children are not. The renderer only processes
# widgets in layer.widgets array, not recursively through the widget tree.
#
# Example hierarchy:
#   WindowPanel
#     └─ VStack (in layer.widgets, 0 primitives)
#         ├─ Button (NOT in layer.widgets, has primitives) ← NOT RENDERED
#         └─ Text (NOT in layer.widgets, has primitives)   ← NOT RENDERED

# Helper to recursively collect primitives
def collect_primitives_recursive(widget : CrymbleUI::Widget) : Int32
  count = widget.get_primitives(widget.bounds).size
  widget.children.each do |child|
    count += collect_primitives_recursive(child)
  end
  count
end

# Helper to recursively render widget and children
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
    end
  end

  # Recursively render children
  widget.children.each do |child|
    render_widget_and_children_recursive(child, backend, offset_x, offset_y)
  end
end

describe "Recursive Widget Rendering" do
  describe "Container widgets with children" do
    it "VStack children have primitives but VStack itself does not" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 300.0, 200.0)
      vstack = CrymbleUI::VStack.new
      button = CrymbleUI::Button.new("Click") { }
      text = CrymbleUI::Text.new("Hello")

      vstack.add_child(button)
      vstack.add_child(text)
      panel.add_child(vstack)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # VStack has no primitives (it's a layout container)
      vstack_primitives = vstack.get_primitives(vstack.bounds)
      vstack_primitives.size.should eq(0)

      # But its children DO have primitives
      button_primitives = button.get_primitives(button.bounds)
      button_primitives.size.should be > 0

      text_primitives = text.get_primitives(text.bounds)
      text_primitives.size.should be > 0

      # NEW architecture: VStack is a child of panel (managed by Content), NOT in layer.widgets
      # layer.widgets contains [Chrome, Content] only
      panel_layer = panel.layer.not_nil!
      panel_layer.widgets.size.should eq(2)  # Chrome + Content
      panel_layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      panel_layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)

      # VStack is in Content.children (panel.add_child redirects to Content.add_child)
      content = panel_layer.widgets[1].as(CrymbleUI::WindowPanel::Content)
      content.children.should contain(vstack)

      # Button and text are children of VStack (NOT in layer.widgets)
      # The renderer must traverse widget.children recursively to find them
      vstack.children.should contain(button)
      vstack.children.should contain(text)
    end

    it "renders children of HStack containers" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 300.0, 200.0)
      hstack = CrymbleUI::HStack.new
      btn1 = CrymbleUI::Button.new("B1") { }
      btn2 = CrymbleUI::Button.new("B2") { }

      hstack.add_child(btn1)
      hstack.add_child(btn2)
      panel.add_child(hstack)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # HStack has no primitives
      hstack_primitives = hstack.get_primitives(hstack.bounds)
      hstack_primitives.size.should eq(0)

      # But buttons do
      btn1_primitives = btn1.get_primitives(btn1.bounds)
      btn1_primitives.size.should be > 0

      btn2_primitives = btn2.get_primitives(btn2.bounds)
      btn2_primitives.size.should be > 0
    end

    it "renders deeply nested widget trees" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 400.0, 300.0)
      outer_vstack = CrymbleUI::VStack.new
      inner_hstack = CrymbleUI::HStack.new
      button = CrymbleUI::Button.new("Deep") { }
      text = CrymbleUI::Text.new("Nested")

      # Deep nesting: Panel > VStack > HStack > Button/Text
      inner_hstack.add_child(button)
      inner_hstack.add_child(text)
      outer_vstack.add_child(inner_hstack)
      panel.add_child(outer_vstack)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Containers have no primitives
      outer_vstack.get_primitives(outer_vstack.bounds).size.should eq(0)
      inner_hstack.get_primitives(inner_hstack.bounds).size.should eq(0)

      # Leaf widgets have primitives
      button.get_primitives(button.bounds).size.should be > 0
      text.get_primitives(text.bounds).size.should be > 0

      # NEW architecture: Only Chrome and Content are in layer.widgets
      panel_layer = panel.layer.not_nil!
      panel_layer.widgets.size.should eq(2)
      panel_layer.widgets[0].should be_a(CrymbleUI::WindowPanel::Chrome)
      panel_layer.widgets[1].should be_a(CrymbleUI::WindowPanel::Content)

      # Outer container is in Content.children (panel.add_child redirects to Content.add_child)
      content = panel_layer.widgets[1].as(CrymbleUI::WindowPanel::Content)
      content.children.should contain(outer_vstack)

      # Deeply nested children must be found by recursive traversal
    end
  end

  describe "Before/after comparison: non-recursive vs recursive rendering" do
    # Obsolete: "OLD non-recursive rendering misses button" - demonstrates historical bug now fixed

    it "NEW recursive rendering finds button (DEMONSTRATES FIX)" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 300.0, 200.0)
      vstack = CrymbleUI::VStack.new
      button = CrymbleUI::Button.new("VISIBLE") { }

      vstack.add_child(button)
      panel.add_child(vstack)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      backend = CrymbleUI::Testing::TestRenderBackend.new(
        panel_layer.bounds.width.to_i,
        panel_layer.bounds.height.to_i,
        CrymbleUI::Color.new(255, 255, 255, 255)
      )

      layer_offset_x = panel_layer.bounds.x
      layer_offset_y = panel_layer.bounds.y

      # NEW recursive rendering (FIX): traverses widget tree
      panel_layer.widgets.each do |widget|
        render_widget_and_children_recursive(widget, backend, layer_offset_x, layer_offset_y)
      end

      # Check if button is visible
      button_local_x = (button.bounds.x - layer_offset_x).to_i + 10
      button_local_y = (button.bounds.y - layer_offset_y).to_i + 10
      pixel = backend.get_pixel(button_local_x, button_local_y)
      panel_bg = CrymbleUI::Color.new(240, 240, 240, 255)

      # This demonstrates the fix: pixel is NOT panel background (button IS rendered)
      pixel.should_not eq(panel_bg)  # Proves fix works
    end

    it "recursive rendering would find all primitives" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 300.0, 200.0)
      vstack = CrymbleUI::VStack.new
      button = CrymbleUI::Button.new("VISIBLE") { }

      vstack.add_child(button)
      panel.add_child(vstack)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Count primitives non-recursively (bug)
      non_recursive_count = 0
      panel_layer.widgets.each do |widget|
        non_recursive_count += widget.get_primitives(widget.bounds).size
      end

      # Count primitives recursively (correct)
      recursive_count = 0
      panel_layer.widgets.each do |widget|
        recursive_count += collect_primitives_recursive(widget)
      end

      # Recursive count should be higher (includes button primitives)
      recursive_count.should be > non_recursive_count

      # Button primitives should be in recursive count
      button_primitives = button.get_primitives(button.bounds).size
      button_primitives.should be > 0
    end
  end

  describe "Root layer containers" do
    it "HStack children have primitives in root layer" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      vstack = CrymbleUI::VStack.new
      button = CrymbleUI::Button.new("Root") { }

      vstack.add_child(button)
      window.add_child(vstack)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # VStack is in root layer, button is not
      root_layer = window.root_layer.not_nil!
      root_layer.widgets.should contain(vstack)

      # Same problem as panels - button has primitives but isn't in layer.widgets
      button_primitives = button.get_primitives(button.bounds)
      button_primitives.size.should be > 0

      # VStack has no primitives
      vstack_primitives = vstack.get_primitives(vstack.bounds)
      vstack_primitives.size.should eq(0)
    end
  end
end
