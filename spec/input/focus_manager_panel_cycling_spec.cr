require "../spec_helper"
require "../../src/widgets/window_panel"

# Helper to create test panels with minimal setup
private def create_test_panel(title : String, id : String, z : Int32 = 0) : CrymbleUI::WindowPanel
  panel = CrymbleUI::WindowPanel.new(title, 0.0, 0.0, 200.0, 150.0, z_index: z, id: id)
  panel
end

describe CrymbleUI::FocusManager do
  describe "#cycle_panel" do
    it "cycles to next panel (forward)" do
      fm = CrymbleUI::FocusManager.new

      # Create root with 3 panels
      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      panel2 = create_test_panel("Panel 2", "panel2", 2)
      panel3 = create_test_panel("Panel 3", "panel3", 3)
      root.add_child(panel1)
      root.add_child(panel2)
      root.add_child(panel3)

      # Cycle forward from topmost (panel3) should go to next in order
      result = fm.cycle_panel(forward: true, root: root)

      # Result should be the panel that was activated
      result.should_not be_nil
      result.should eq(panel1)  # Wraps around to first
    end

    it "cycles to previous panel (backward)" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      panel2 = create_test_panel("Panel 2", "panel2", 2)
      panel3 = create_test_panel("Panel 3", "panel3", 3)
      root.add_child(panel1)
      root.add_child(panel2)
      root.add_child(panel3)

      # Cycle backward from topmost (panel3) should go to panel2
      result = fm.cycle_panel(forward: false, root: root)

      result.should_not be_nil
      result.should eq(panel2)
    end

    it "wraps around at end (forward)" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      panel2 = create_test_panel("Panel 2", "panel2", 2)
      root.add_child(panel1)
      root.add_child(panel2)

      # Cycle forward from panel2 (topmost) should wrap to panel1
      result = fm.cycle_panel(forward: true, root: root)

      result.should eq(panel1)
    end

    it "wraps around at start (backward)" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 2)  # Topmost
      panel2 = create_test_panel("Panel 2", "panel2", 1)
      root.add_child(panel1)
      root.add_child(panel2)

      # Cycle backward from panel1 (topmost) should wrap to panel2
      result = fm.cycle_panel(forward: false, root: root)

      result.should eq(panel2)
    end

    it "brings cycled panel to front" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      panel2 = create_test_panel("Panel 2", "panel2", 2)  # Initially topmost
      root.add_child(panel1)
      root.add_child(panel2)

      # Cycle to panel1
      fm.cycle_panel(forward: true, root: root)

      # panel1 should now be topmost
      root.find_topmost_panel.should eq(panel1)
    end

    it "returns nil when no panels" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      # No panels added

      result = fm.cycle_panel(forward: true, root: root)

      result.should be_nil
    end

    it "returns nil when only one panel" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      root.add_child(panel1)

      # With only one panel, cycling should return nil since there's nothing to cycle to
      result = fm.cycle_panel(forward: true, root: root)

      result.should be_nil
    end

    it "skips closed panels" do
      fm = CrymbleUI::FocusManager.new

      root = CrymbleUI::VStack.new
      panel1 = create_test_panel("Panel 1", "panel1", 1)
      panel2 = create_test_panel("Panel 2", "panel2", 2)
      panel3 = create_test_panel("Panel 3", "panel3", 3)
      root.add_child(panel1)
      root.add_child(panel2)
      root.add_child(panel3)

      # Close panel1
      panel1.close

      # Cycle forward from panel3 should skip closed panel1 and go to panel2
      result = fm.cycle_panel(forward: true, root: root)

      result.should eq(panel2)
    end
  end
end
