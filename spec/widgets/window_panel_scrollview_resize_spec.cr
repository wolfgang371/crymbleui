require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"

describe "WindowPanel with ScrollView resize" do
  describe "layer bounds during resize (delta-based)" do
    it "ScrollView layer bounds shrink proportionally during panel resize" do
      # Setup: Window with panel containing label + ScrollView
      # The label above ScrollView means ScrollView doesn't fill entire content area
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 400.0, 300.0, z_index: 1)

      # Add a label above the ScrollView (simulates showcase_demo pattern)
      label = CrymbleUI::Text.new("Header Label")
      panel.add_child(label)

      scroll = CrymbleUI::ScrollView.new(id: "scroll")
      content = CrymbleUI::VStack.new
      20.times { |i| content.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll.set_content(content)
      panel.add_child(scroll)

      window.add_child(panel)

      # Layout to initialize layers
      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Capture initial layer bounds
      initial_layer_bounds = scroll.layer.not_nil!.bounds.dup
      initial_scrollbar_bounds = scroll.scrollbar_layer.not_nil!.bounds.dup

      # Sanity check: ScrollView layer should have non-zero size
      initial_layer_bounds.width.should be > 0.0
      initial_layer_bounds.height.should be > 0.0

      # Simulate resize start (mouse down on resize corner)
      resize_point = CrymbleUI::Vec2.new(panel.x + panel.width - 4.0, panel.y + panel.height - 4.0)
      panel.on_mouse_down(resize_point)
      panel.resizing?.should be_true

      # Simulate resize: shrink by 50 pixels in each direction
      delta_width = -50.0
      delta_height = -50.0
      new_point = CrymbleUI::Vec2.new(resize_point.x + delta_width, resize_point.y + delta_height)
      panel.on_mouse_move(new_point)

      # Get updated layer bounds during resize
      resized_layer_bounds = scroll.layer.not_nil!.bounds
      resized_scrollbar_bounds = scroll.scrollbar_layer.not_nil!.bounds

      # Key assertion: Layer bounds should change by EXACTLY the delta amount
      # (not be replaced with panel content area size)
      width_change = resized_layer_bounds.width - initial_layer_bounds.width
      height_change = resized_layer_bounds.height - initial_layer_bounds.height

      width_change.should be_close(delta_width, 1.0),
        "Layer width change (#{width_change}) should match delta (#{delta_width})"
      height_change.should be_close(delta_height, 1.0),
        "Layer height change (#{height_change}) should match delta (#{delta_height})"

      # Also check scrollbar layer
      sb_width_change = resized_scrollbar_bounds.width - initial_scrollbar_bounds.width
      sb_height_change = resized_scrollbar_bounds.height - initial_scrollbar_bounds.height

      sb_width_change.should be_close(delta_width, 1.0)
      sb_height_change.should be_close(delta_height, 1.0)

      # Cleanup
      panel.on_mouse_up(new_point)
    end

    it "ScrollView layer position is preserved during panel resize" do
      # The bug was that layer position was being overwritten
      # during resize instead of preserved
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 400.0, 300.0, z_index: 1)

      # Add widgets above ScrollView to create offset
      label = CrymbleUI::Text.new("Header")
      panel.add_child(label)

      scroll = CrymbleUI::ScrollView.new(id: "scroll")
      content = CrymbleUI::VStack.new
      15.times { |i| content.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll.set_content(content)
      panel.add_child(scroll)

      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Capture initial layer position
      initial_layer_x = scroll.layer.not_nil!.bounds.x
      initial_layer_y = scroll.layer.not_nil!.bounds.y

      # Start resize
      resize_point = CrymbleUI::Vec2.new(panel.x + panel.width - 4.0, panel.y + panel.height - 4.0)
      panel.on_mouse_down(resize_point)

      # Resize by growing
      new_point = CrymbleUI::Vec2.new(resize_point.x + 100.0, resize_point.y + 100.0)
      panel.on_mouse_move(new_point)

      # Layer position should NOT change during resize
      resized_layer_x = scroll.layer.not_nil!.bounds.x
      resized_layer_y = scroll.layer.not_nil!.bounds.y

      resized_layer_x.should eq(initial_layer_x),
        "Layer X position should be preserved during resize"
      resized_layer_y.should eq(initial_layer_y),
        "Layer Y position should be preserved during resize"

      panel.on_mouse_up(new_point)
    end

    it "layer bounds clipping prevents content overflow during resize" do
      # This tests the actual clipping behavior - layer bounds should
      # prevent content from rendering outside the panel during resize
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 400.0, 300.0, z_index: 1)

      scroll = CrymbleUI::ScrollView.new(id: "scroll")
      content = CrymbleUI::VStack.new
      30.times { |i| content.add_child(CrymbleUI::Text.new("Long item text #{i}")) }
      scroll.set_content(content)
      panel.add_child(scroll)

      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Start resize (shrink)
      resize_point = CrymbleUI::Vec2.new(panel.x + panel.width - 4.0, panel.y + panel.height - 4.0)
      panel.on_mouse_down(resize_point)

      # Shrink panel significantly
      new_point = CrymbleUI::Vec2.new(resize_point.x - 150.0, resize_point.y - 100.0)
      panel.on_mouse_move(new_point)

      # Get layer bounds
      layer_bounds = scroll.layer.not_nil!.bounds

      # Layer right edge should be within panel bounds
      panel_right = panel.x + panel.width
      layer_right = layer_bounds.x + layer_bounds.width

      layer_right.should be <= panel_right,
        "Layer right edge (#{layer_right}) should not exceed panel right edge (#{panel_right})"

      # Layer bottom edge should be within panel bounds
      panel_bottom = panel.y + panel.height
      layer_bottom = layer_bounds.y + layer_bounds.height

      layer_bottom.should be <= panel_bottom,
        "Layer bottom edge (#{layer_bottom}) should not exceed panel bottom edge (#{panel_bottom})"

      panel.on_mouse_up(new_point)
    end
  end
end
