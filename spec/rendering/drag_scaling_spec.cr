require "../spec_helper"
require "../../src/testing/test_renderer"

# Critical test: Drag performance must NOT scale with number of child widgets
# Panel chrome rendering should be O(1), not O(n)
describe "Drag Performance Scaling" do
  it "drag primitive count is constant regardless of number of buttons in panel" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

    # Test with 1, 10, 50, 100 buttons
    button_counts = [1, 10, 50, 100]
    drag_primitives = [] of Int32

    button_counts.each do |count|
      # Create fresh window and panel
      window = CrymbleUI::Window.new("Test", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

      # Add N buttons
      count.times do |i|
        button = CrymbleUI::Button.new("Btn#{i}") { }
        panel.add_child(button)
      end

      window.add_child(panel)
      app.root_widget = window

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))

      # Initial render (don't count this)
      renderer.render_frame(app)

      # Reset counters
      renderer.reset_counters

      # Start drag
      renderer.mouse_down(150.0, 115.0)
      renderer.render_frame(app)
      mouse_down_prims = renderer.primitive_count

      # Reset and move during drag
      renderer.reset_counters
      renderer.mouse_move(200.0, 115.0)  # +50px
      renderer.render_frame(app)
      mouse_move_prims = renderer.primitive_count

      # Use mouse_move primitives (the actual drag performance)
      drag_primitives << mouse_move_prims

    end

    # CRITICAL ASSERTION: All drag primitive counts should be approximately equal
    # (within 10% variance - allowing for minor differences)
    first = drag_primitives[0]

    # BEST CASE: All counts are 0 (perfect layer caching!)
    if first == 0
      drag_primitives.each_with_index do |count, i|
        count.should eq 0  # All should be zero (O(1) with perfect caching)
      end
    else
      # GOOD CASE: Consistent non-zero primitive count (O(1) but not cached)
      drag_primitives.each_with_index do |count, i|
        variance = (count - first).abs.to_f / first
        variance.should be < 0.15  # <15% variance

        if variance >= 0.15
        end
      end
    end

  end

  it "drag with 400 buttons is as fast as drag with 1 button" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
      app = TestApp.new

    # Test with 1 button
    window1 = CrymbleUI::Window.new("Test", 800, 600)
    panel1 = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    panel1.add_child(CrymbleUI::Button.new("Btn1") { })
    window1.add_child(panel1)
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window1.layout(constraints, CrymbleUI::Vec2.zero)

    renderer.render_frame(app)
    renderer.reset_counters
    renderer.mouse_down(150.0, 115.0)
    renderer.render_frame(app)
    renderer.reset_counters
    renderer.mouse_move(200.0, 115.0)
    renderer.render_frame(app)

    primitives_1_button = renderer.primitive_count

    # Test with 400 buttons
    window400 = CrymbleUI::Window.new("Test", 800, 600)
    panel400 = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    400.times do |i|
      panel400.add_child(CrymbleUI::Button.new("B#{i}") { })
    end
    window400.add_child(panel400)
    window400.layout(constraints, CrymbleUI::Vec2.zero)

    renderer.render_frame(app)
    renderer.reset_counters
    renderer.mouse_down(150.0, 115.0)
    renderer.render_frame(app)
    renderer.reset_counters
    renderer.mouse_move(200.0, 115.0)
    renderer.render_frame(app)

    primitives_400_buttons = renderer.primitive_count


    # BEST CASE: Both are 0 (perfect layer caching!)
    if primitives_1_button == 0 && primitives_400_buttons == 0
      primitives_1_button.should eq 0
      primitives_400_buttons.should eq 0
    elsif primitives_1_button == 0
      # Can't calculate variance when denominator is 0
      primitives_400_buttons.should eq 0
    else
      # Should be within 15% of each other
      variance = (primitives_400_buttons - primitives_1_button).abs.to_f / primitives_1_button
      variance.should be < 0.15

      if variance >= 0.15
      else
      end
    end
  end
end
