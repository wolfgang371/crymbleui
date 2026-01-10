require "../spec_helper"
require "../../src/testing/test_render_backend"

# Baseline tests for OLD rendering system
# These tests document and verify the behavior that MUST be preserved during layer migration
#
# All tests in this file should PASS with the current (pre-layer) rendering system.
# If any test fails after layer implementation, it indicates a regression.

describe "Panel Rendering Baseline (OLD system)" do
  describe "single panel highlight (topmost detection)" do
    it "only one panel is highlighted at a time" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)
      panel3 = CrymbleUI::WindowPanel.new("P3", 100.0, 300.0, 200.0, 150.0, z_index: 3)

      window.add_child(panel1)
      window.add_child(panel2)
      window.add_child(panel3)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Initially panel3 has highest z-index
      panel3.topmost?.should be_true
      panel2.topmost?.should be_false
      panel1.topmost?.should be_false

      # Bring panel1 to front
      panel1.bring_to_front

      # Now only panel1 is topmost
      panel1.topmost?.should be_true
      panel2.topmost?.should be_false
      panel3.topmost?.should be_false
    end

    it "clicking panel content brings it to front" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)

      button1 = CrymbleUI::Button.new("Button in P1") { }
      panel1.add_child(button1)

      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      initial_p1_z = panel1.z_index
      initial_p2_z = panel2.z_index

      # Panel2 starts on top
      panel2.z_index.should be > panel1.z_index

      # Click button in panel1 (simulates content click)
      button_center = CrymbleUI::Vec2.new(
        button1.bounds.x + button1.bounds.width / 2,
        button1.bounds.y + button1.bounds.height / 2
      )
      button1.on_mouse_down(button_center)

      # Panel1 should now be on top
      panel1.z_index.should be > initial_p2_z
      panel1.topmost?.should be_true
      panel2.topmost?.should be_false
    end
  end

  describe "z-order persistence across rebuilds" do
    it "preserves z_index during reconciliation" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 5)

      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Bring panel1 to front
      panel1.bring_to_front
      z_after_bring_to_front = panel1.z_index

      z_after_bring_to_front.should be > 5

      # Simulate reconciliation (rebuild with state copy)
      new_panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      new_panel1.copy_state_from(panel1)

      # Z-index should be preserved
      new_panel1.z_index.should eq(z_after_bring_to_front)
    end
  end

  describe "panel bounds and positioning" do
    it "panel chrome renders at correct position" do
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 50.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 50.0))

      panel.bounds.x.should eq(100.0)
      panel.bounds.y.should eq(50.0)
      panel.bounds.width.should eq(200.0)
      panel.bounds.height.should eq(150.0)
    end

    it "children positioned correctly inside panel" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

      button = CrymbleUI::Button.new("Test") { }
      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Button should be inside panel content area (below title bar)
      # With NEW architecture (Chrome/Content split), button.bounds is relative to Content (not panel)
      # Content is offset from panel by (CONTENT_PADDING, TITLE_BAR_HEIGHT + CONTENT_PADDING)
      # Button is first child of Content, so relative to Content it's at (0, 0)
      button.bounds.x.should eq(0.0)  # Relative to Content
      button.bounds.y.should eq(0.0)  # Relative to Content

      # Absolute position should match panel position + content offset
      button.absolute_bounds.x.should eq(108.0)  # Panel x (100) + CONTENT_PADDING (8)
      button.absolute_bounds.y.should eq(138.0)  # Panel y (100) + TITLE_BAR_HEIGHT (30) + CONTENT_PADDING (8)
    end
  end

  describe "drag behavior" do
    it "updates panel position during drag" do
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      # Start drag on title bar
      title_point = CrymbleUI::Vec2.new(150.0, 115.0)
      panel.on_mouse_down(title_point)

      # Drag to new position
      new_point = CrymbleUI::Vec2.new(200.0, 165.0)
      panel.on_mouse_move(new_point)

      # Panel position should update immediately
      panel.x.should be_close(150.0, 0.1)
      panel.y.should be_close(150.0, 0.1)
      panel.bounds.x.should be_close(150.0, 0.1)
      panel.bounds.y.should be_close(150.0, 0.1)
    end

    it "constrains panel to window bounds during drag" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Start drag
      title_point = CrymbleUI::Vec2.new(150.0, 115.0)
      panel.on_mouse_down(title_point)

      # Try to drag off top edge
      off_screen_point = CrymbleUI::Vec2.new(150.0, -50.0)
      panel.on_mouse_move(off_screen_point)

      # Should be constrained to y=0
      panel.y.should eq(0.0)
    end
  end

  describe "resize behavior" do
    it "updates panel size during resize (right edge)" do
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      # Start resize on right edge
      right_edge = CrymbleUI::Vec2.new(299.0, 150.0)
      panel.on_mouse_down(right_edge)

      # Drag right to resize
      new_point = CrymbleUI::Vec2.new(349.0, 150.0)
      panel.on_mouse_move(new_point)

      # Width should increase
      panel.width.should be_close(250.0, 1.0)
      panel.bounds.width.should be_close(250.0, 1.0)
    end

    it "enforces minimum size during resize" do
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      # Start resize on right edge
      right_edge = CrymbleUI::Vec2.new(299.0, 150.0)
      panel.on_mouse_down(right_edge)

      # Try to drag far left (make width negative)
      small_point = CrymbleUI::Vec2.new(50.0, 150.0)
      panel.on_mouse_move(small_point)

      # Should be clamped to minimum (100.0)
      panel.width.should eq(100.0)
    end
  end

  describe "buffer allocation constants" do
    it "WindowPanel has buffer constants defined" do
      CrymbleUI::WindowPanel::CACHE_BUFFER_FACTOR.should eq(0.2)
      CrymbleUI::WindowPanel::CACHE_MIN_BUFFER.should eq(50.0)
    end
  end

  describe "panel closure" do
    it "closed panel is not topmost" do
      window = CrymbleUI::Window.new("Test", 800, 600)

      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)

      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel2.topmost?.should be_true

      # Close panel2
      panel2.close

      # Panel1 becomes topmost (panel2 excluded from topmost calculation)
      panel1.topmost?.should be_true
      panel2.topmost?.should be_false  # Closed panels not topmost
    end

    it "closed panel returns nil for hit test" do
      panel = CrymbleUI::WindowPanel.new("Test", 100.0, 100.0, 200.0, 150.0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      panel.layout(constraints, CrymbleUI::Vec2.new(100.0, 100.0))

      panel.close

      point = CrymbleUI::Vec2.new(150.0, 150.0)
      panel.hit_test(point).should be_nil
    end
  end
end
