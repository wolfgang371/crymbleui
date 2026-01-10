require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"

describe "WindowPanel with ScrollView z-index" do
  describe "scrollbar z-index bleeding (Issue D)" do
    it "back panel scrollbar z-index is less than front panel layer z-index" do
      # Setup: Window with two overlapping panels, each containing a ScrollView
      window = CrymbleUI::Window.new("Test", 800, 600)

      # Create Panel A with ScrollView (will be BACK panel)
      panel_a = CrymbleUI::WindowPanel.new("Panel A", 50.0, 50.0, 300.0, 250.0, z_index: 1)
      scroll_a = CrymbleUI::ScrollView.new(id: "scroll_a")
      content_a = CrymbleUI::VStack.new
      # Add enough items to trigger scrollbar
      10.times { |i| content_a.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll_a.set_content(content_a)
      panel_a.add_child(scroll_a)  # add_child redirects to panel's content

      # Create Panel B with ScrollView (will be FRONT panel)
      panel_b = CrymbleUI::WindowPanel.new("Panel B", 100.0, 100.0, 300.0, 250.0, z_index: 2)
      scroll_b = CrymbleUI::ScrollView.new(id: "scroll_b")
      content_b = CrymbleUI::VStack.new
      10.times { |i| content_b.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll_b.set_content(content_b)
      panel_b.add_child(scroll_b)  # add_child redirects to panel's content

      window.add_child(panel_a)
      window.add_child(panel_b)

      # Layout to initialize layers
      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Bring Panel B to front (it should already be front, but this triggers z-index update)
      panel_b.bring_to_front

      # Get z-indices
      panel_a_layer_z = panel_a.layer.not_nil!.z_index
      panel_b_layer_z = panel_b.layer.not_nil!.z_index

      # Get scrollbar layer z-indices (if they exist)
      scroll_a_scrollbar_z = scroll_a.scrollbar_layer.try(&.z_index) || 0
      scroll_b_scrollbar_z = scroll_b.scrollbar_layer.try(&.z_index) || 0

      # The CRITICAL assertion: Back panel's scrollbar must be BELOW front panel's layer
      # This should FAIL with current code because:
      # - Panel A: z=1, scrollbar z=3 (1+2)
      # - Panel B brought to front: z=2 (1+1), scrollbar z=4
      # - Panel A scrollbar (3) > Panel B layer (2) -- BUG!
      scroll_a_scrollbar_z.should be < panel_b_layer_z,
        "Back panel (A) scrollbar z=#{scroll_a_scrollbar_z} should be < front panel (B) layer z=#{panel_b_layer_z}"
    end

    it "after multiple bring_to_front calls, scrollbars stay behind front panel" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel_a = CrymbleUI::WindowPanel.new("Panel A", 50.0, 50.0, 300.0, 250.0, z_index: 1)
      scroll_a = CrymbleUI::ScrollView.new(id: "scroll_a")
      content_a = CrymbleUI::VStack.new
      10.times { |i| content_a.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll_a.set_content(content_a)
      panel_a.add_child(scroll_a)

      panel_b = CrymbleUI::WindowPanel.new("Panel B", 100.0, 100.0, 300.0, 250.0, z_index: 2)
      scroll_b = CrymbleUI::ScrollView.new(id: "scroll_b")
      content_b = CrymbleUI::VStack.new
      10.times { |i| content_b.add_child(CrymbleUI::Text.new("Item #{i}")) }
      scroll_b.set_content(content_b)
      panel_b.add_child(scroll_b)

      window.add_child(panel_a)
      window.add_child(panel_b)

      constraints = CrymbleUI::BoxConstraints.new(800.0, 600.0)
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Simulate user clicking between panels multiple times
      panel_a.bring_to_front  # A to front
      panel_b.bring_to_front  # B to front
      panel_a.bring_to_front  # A to front again

      # Now Panel A is front, Panel B is back
      panel_a_layer_z = panel_a.layer.not_nil!.z_index
      scroll_b_scrollbar_z = scroll_b.scrollbar_layer.try(&.z_index) || 0

      # Panel B's scrollbar must be below Panel A's layer
      scroll_b_scrollbar_z.should be < panel_a_layer_z,
        "Back panel (B) scrollbar z=#{scroll_b_scrollbar_z} should be < front panel (A) layer z=#{panel_a_layer_z}"
    end
  end
end
