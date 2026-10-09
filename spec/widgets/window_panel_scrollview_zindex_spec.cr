require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"

describe "WindowPanel with ScrollView z-index" do
  describe "scrollbar z-index bleeding (Issue D)" do
    it "a back panel's scrollbar composites below the front panel" do
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

      # The CRITICAL assertion: the back panel's scrollbar composites BELOW the front panel's layer
      # (it once bled through when both took absolute z from their panels)
      order = window.collect_all_layers
      back_bar = order.index!(scroll_a.scrollbar_layer.not_nil!)
      front = order.index!(panel_b.layer.not_nil!)
      back_bar.should be < front, "back panel (A) scrollbar composites at #{back_bar}, over the front panel (B) at #{front}"
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

      # Now Panel A is front, Panel B is back: B's scrollbar composites below A's layer
      order = window.collect_all_layers
      back_bar = order.index!(scroll_b.scrollbar_layer.not_nil!)
      front = order.index!(panel_a.layer.not_nil!)
      back_bar.should be < front, "back panel (B) scrollbar composites at #{back_bar}, over the front panel (A) at #{front}"
    end
  end
end
