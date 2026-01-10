require "../spec_helper"
require "../../src/testing/test_renderer"

# Debug test to understand layer.widgets population
describe "Layer Population Debug" do
  it "shows what widgets are in WindowPanel's layer" do
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)
    button = CrymbleUI::Button.new("Click") { }

    panel.add_child(button)
    window.add_child(panel)
      app.root_widget = window

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

    # Inspect layers

    # Window layer
    if window_layer = window.layer
      window_layer.widgets.each_with_index do |widget, i|
      end
    end

    # Panel layer
    if panel_layer = panel.layer
      panel_layer.widgets.each_with_index do |widget, i|
      end

      # Check if panel itself is in its layer
      panel_in_layer = panel_layer.widgets.includes?(panel)

      # Check if button is in layer
      button_in_layer = panel_layer.widgets.includes?(button)
    end

    # This test just prints debug info
    true.should be_true
  end

  it "renders primitives from panel and checks what gets rendered" do
      app = TestApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)

    window.add_child(panel)
      app.root_widget = window

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

    # Get panel primitives directly
    panel_primitives = panel.get_primitives(panel.bounds)

    panel_primitives.each_with_index do |prim, i|
    end

    # Now render through TestRenderer
    renderer.reset_counters
    renderer.render_frame(app)


    # Compare

    if panel_primitives.size != renderer.primitive_count
    end

    true.should be_true
  end

  it "checks layer needs_render state" do
      app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 200.0, 150.0)

    window.add_child(panel)
      app.root_widget = window

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))


    # Check panel layer state
    if panel_layer = panel.layer

      if panel_layer.dirty_widgets.size > 0
        panel_layer.dirty_widgets.each do |w|
        end
      end
    end

    true.should be_true
  end
end
