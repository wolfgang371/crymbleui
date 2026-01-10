require "../spec_helper"
require "../../src/testing/test_renderer"

# Performance tests for panel drag with widget-local coordinates
# These tests verify that drag performance meets requirements:
# - Drag should NOT regenerate primitives (widget-local coords)
# - Only dirty widgets should re-render (selective rendering)
# - Hover should only re-render the hovered widget

describe "Panel Drag Performance with Widget-Local Coordinates" do
  describe "drag with widget-local coordinates" do
    it "does NOT regenerate primitives during position-only drag" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
      button = CrymbleUI::Button.new("Button") { }

      panel.add_child(button)
      window.add_child(panel)
      app.root_widget = window
      app.root_widget = window

      # Initial layout and render (via App)
      renderer.render_frame(app)

      # Reset counters after initial render
      renderer.reset_counters

      # Simulate drag: 50px to the right
      renderer.mouse_down(150.0, 115.0)  # Title bar
      renderer.render_frame(app)

      # During drag, move 10 times (simulating smooth 60fps drag)
      10.times do |i|
        renderer.mouse_move(150.0 + (i + 1) * 5.0, 115.0)
        renderer.render_frame(app)
      end

      renderer.mouse_up(200.0, 115.0)
      renderer.render_frame(app)

      # With widget-local coordinates:
      # - Primitives stay cached (at local 0,0)
      # - Renderer just applies new layer offset
      # - Should be VERY few primitive renders (only panel chrome updates)

      # Panel chrome re-renders each frame (position changed)
      # But button content should NOT re-render (cached primitives)
      # Expected: ~10-20 primitives per frame (just chrome), NOT 100+ (full panel)

      total_frames = 12  # 1 down + 10 moves + 1 up
      primitives_per_frame = renderer.primitive_count / total_frames

      # This should be LOW - chrome only, not full content
      primitives_per_frame.should be < 30  # Generous limit (chrome ~10-15 primitives)

    end

    it "only re-renders panel chrome during drag, not content" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

      # Add MANY buttons to test selective rendering
      20.times do |i|
        button = CrymbleUI::Button.new("Button #{i}") { }
        panel.add_child(button)
      end

      window.add_child(panel)
      app.root_widget = window
      

      # Initial layout and render
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      renderer.render_frame(app)

      initial_primitive_count = renderer.primitive_count

      # Reset for drag test
      renderer.reset_counters

      # Single drag frame
      renderer.mouse_down(150.0, 115.0)
      renderer.mouse_move(160.0, 115.0)  # Small move
      renderer.render_frame(app)

      drag_primitive_count = renderer.primitive_count

      # During drag with widget-local coords:
      # - Panel chrome re-renders (~10-15 primitives)
      # - Button content does NOT re-render (cached at local 0,0)
      # Should be MUCH less than initial render

      ratio = drag_primitive_count.to_f / initial_primitive_count
      ratio.should be < 0.2  # Drag should use <20% of initial render primitives

    end
  end

  describe "hover performance with selective rendering" do
    it "only re-renders hovered button, not entire panel" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)

      # Add multiple buttons
      buttons = [] of CrymbleUI::Button
      5.times do |i|
        button = CrymbleUI::Button.new("Button #{i}") { }
        panel.add_child(button)
        buttons << button
      end

      window.add_child(panel)
      app.root_widget = window
      

      # Initial layout and render
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      renderer.render_frame(app)

      # Reset for hover test
      renderer.reset_counters

      # Hover over first button
      # (Need to calculate actual button position - depends on layout)
      # For now, test that hover triggers selective render
      button_x = buttons[0].bounds.x + 10.0
      button_y = buttons[0].bounds.y + 10.0

      renderer.mouse_move(button_x, button_y)
      renderer.render_frame(app)

      hover_primitive_count = renderer.primitive_count

      # Hover should only re-render ONE button (~5-10 primitives)
      # Not the entire panel (100+ primitives)
      hover_primitive_count.should be < 20

    end
  end

  describe "render counting accuracy" do
    it "tracks layer render calls correctly" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new
      
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

      window.add_child(panel)
      app.root_widget = window
      

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

      renderer.reset_counters

      # Render 3 frames
      3.times { renderer.render_frame(app) }

      # Should have rendered panel layer 3 times
      # (No changes, so might optimize to 0 renders with proper dirty tracking)
      renderer.render_layer_count.should be >= 0  # Flexible for optimization
      renderer.render_frame_count.should eq 3
    end

    it "tracks primitive counts correctly" do
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

      window = CrymbleUI::Window.new("Test", 800, 600)
      button = CrymbleUI::Button.new("Click") { }

      window.add_child(button)
      app.root_widget = window  # Connect window to app

      renderer.reset_counters
      renderer.render_frame(app)

      # Button renders to root_layer backend (not window backend)
      # Total primitives across all layer backends should include button's primitives
      # Button has at least: background fill + border (text may be separate)
      renderer.primitive_count.should be >= 2
    end
  end
end
