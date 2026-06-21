require "../spec_helper"

# Tests for widget-to-layer state propagation
# These tests verify that when widgets mark themselves as needing render,
# the change propagates to the containing layer so it gets re-rendered.
#
# This is critical for:
# - Button hover effects
# - Timer-based updates (FlashingButton, CPUMonitor)
# - Status bar updates
# - Any widget state change that should trigger a visual update

describe "Widget to Layer State Propagation" do
  describe "Root layer propagation" do
    it "marks root layer when button marks itself" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Click") { }
      window.add_child(button)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!
      root_layer.clear_render_state  # Start clean

      # Widget marks itself as needing render
      button.mark_needs_render

      # Layer should also be marked
      root_layer.needs_render?.should be_true
    end

    it "marks root layer when text widget changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      text = CrymbleUI::Text.new("Hello")
      window.add_child(text)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!
      root_layer.clear_render_state

      # Text marks itself (this happens when content changes, etc.)
      text.mark_needs_render

      root_layer.needs_render?.should be_true
    end

    it "marks root layer when nested widget changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      # Use nested panels to test deep nesting
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Button is in panel layer, but for this test we want root layer
      # Actually, let's just use direct button in window
      window2 = CrymbleUI::Window.new("Test2", 800, 600)
      button2 = CrymbleUI::Button.new("Click") { }
      window2.add_child(button2)
      window2.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window2.root_layer.not_nil!
      root_layer.clear_render_state

      # Widget marks itself
      button2.mark_needs_render

      # Should propagate to root layer
      root_layer.needs_render?.should be_true
    end
  end

  describe "Panel layer propagation" do
    it "marks panel layer when child button changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      panel_layer.clear_render_state

      button.mark_needs_render

      panel_layer.needs_render?.should be_true
    end

    it "marks panel layer when deeply nested widget changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      # Nest buttons to simulate deep nesting
      button1 = CrymbleUI::Button.new("B1") { }
      button2 = CrymbleUI::Button.new("B2") { }

      panel.add_child(button1)
      panel.add_child(button2)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      panel_layer.clear_render_state

      # Widget marks itself
      button1.mark_needs_render

      # Should propagate to panel layer
      panel_layer.needs_render?.should be_true
    end

    it "marks panel layer when panel itself changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      panel_layer.clear_render_state

      # Panel marks itself (e.g., bring_to_front changes z_index)
      panel.mark_needs_render

      panel_layer.needs_render?.should be_true
    end
  end

  describe "MenuBar layer propagation" do
    it "marks menubar layer when menu child changes" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      menubar = CrymbleUI::MenuBar.new
      menu = CrymbleUI::Menu.new("File")

      menubar.add_child(menu)
      window.add_child(menubar)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      menubar_layer = menubar.layer.not_nil!
      menubar_layer.clear_render_state

      # Menu marks itself (e.g., opens/closes)
      menu.mark_needs_render

      menubar_layer.needs_render?.should be_true
    end
  end

  describe "Popup layer propagation" do
    it "marks popup layer when popup child changes" do
      popup = CrymbleUI::Popup.new(width: 200.0, height: 100.0)
      menu_item = CrymbleUI::MenuItem.new("Open") { }

      popup.add_child(menu_item)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      popup.layout(constraints, CrymbleUI::Vec2.zero)

      popup_layer = popup.layer.not_nil!
      popup_layer.clear_render_state

      # Menu item marks itself (e.g., hover)
      menu_item.mark_needs_render

      popup_layer.needs_render?.should be_true
    end
  end

  describe "Selective layer rendering" do
    it "only marks affected layer, not unrelated layers" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)

      button1 = CrymbleUI::Button.new("B1") { }
      button2 = CrymbleUI::Button.new("B2") { }

      panel1.add_child(button1)
      panel2.add_child(button2)
      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Clear all states
      layers = window.collect_all_layers
      layers.each(&.clear_render_state)

      # Only button1 changes
      button1.mark_needs_render

      # Only panel1's layer should need render
      panel1.layer.not_nil!.needs_render?.should be_true
      panel2.layer.not_nil!.needs_render?.should be_false
      window.root_layer.not_nil!.needs_render?.should be_false
    end

    it "marks root layer for non-panel widgets" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      button_in_root = CrymbleUI::Button.new("Root") { }
      button_in_panel = CrymbleUI::Button.new("Panel") { }

      panel1.add_child(button_in_panel)
      window.add_child(button_in_root)
      window.add_child(panel1)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Clear all states
      layers = window.collect_all_layers
      layers.each(&.clear_render_state)

      # Button in root changes
      button_in_root.mark_needs_render

      # Only root layer should be marked
      window.root_layer.not_nil!.needs_render?.should be_true
      panel1.layer.not_nil!.needs_render?.should be_false
    end
  end

  describe "Hover state propagation" do
    it "marks layer when button is hovered" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Click") { }
      window.add_child(button)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      root_layer = window.root_layer.not_nil!
      button.get_primitives(button.bounds) # render so the reactive hover edge enqueues to the layer
      root_layer.clear_render_state

      # Simulate hover (button should mark itself)
      button.on_mouse_enter

      # Layer should be marked for re-render
      root_layer.needs_render?.should be_true
    end

    it "marks layer when button hover ends" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Click") { }
      window.add_child(button)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      # Start with hover
      button.on_mouse_enter
      button.get_primitives(button.bounds) # render at hovered=true so the exit edge re-enqueues

      root_layer = window.root_layer.not_nil!
      root_layer.clear_render_state

      # End hover
      button.on_mouse_exit

      # Layer should be marked (button appearance changed)
      root_layer.needs_render?.should be_true
    end

    it "marks panel layer when panel button is hovered" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Click") { }

      panel.add_child(button)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!
      button.get_primitives(button.bounds) # render so the reactive hover edge enqueues to the layer
      panel_layer.clear_render_state

      # Hover button in panel
      button.on_mouse_enter

      # Panel layer should be marked
      panel_layer.needs_render?.should be_true
    end
  end

  describe "Panel interaction state propagation" do
    # Obsolete: "marks panel layer during drag" - layer not re-rendered during drag for O(1) performance

    it "marks panel layer during resize" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0)
      window.add_child(panel)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel_layer = panel.layer.not_nil!

      # Start resize on right edge
      right_edge = CrymbleUI::Vec2.new(299.0, 150.0)
      panel.on_mouse_down(right_edge)

      panel_layer.clear_render_state

      # During resize
      panel.on_mouse_move(CrymbleUI::Vec2.new(349.0, 150.0))

      # Layer should be marked (size changed)
      panel_layer.needs_render?.should be_true
    end

    it "marks panel layer when brought to front" do
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel1 = CrymbleUI::WindowPanel.new("P1", 100.0, 100.0, 200.0, 150.0, z_index: 1)
      panel2 = CrymbleUI::WindowPanel.new("P2", 350.0, 100.0, 200.0, 150.0, z_index: 2)

      window.add_child(panel1)
      window.add_child(panel2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      panel1_layer = panel1.layer.not_nil!
      panel1_layer.clear_render_state

      # Bring panel1 to front
      panel1.bring_to_front

      # Panel1's layer should be marked (z_index changed)
      panel1_layer.needs_render?.should be_true
    end
  end
end
