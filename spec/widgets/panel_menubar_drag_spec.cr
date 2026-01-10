require "../spec_helper"
require "../../src/testing/test_renderer"

# Test for panel menubar movement during drag
describe "Panel MenuBar Drag" do
  it "panel menubar moves with panel during drag (no separate layer)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create panel with menubar at initial position
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    panel.add_child(menubar)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Panel menubar should NOT have its own layer (uses panel layer)
    menubar.layer.should be_nil

    # Panel layer should be positioned at panel position (no border offset)
    panel_layer = panel.layer.not_nil!
    initial_panel_x = panel_layer.bounds.x
    initial_panel_x.should eq(50.0)

    # Start drag on title bar
    renderer.mouse_down(150.0, 60.0)  # On title bar
    renderer.render_frame(app)

    # Drag 100px to the right
    renderer.mouse_move(250.0, 60.0)
    renderer.render_frame(app)

    # During drag: panel layer should move, menubar moves with it automatically
    current_panel_x = panel_layer.bounds.x
    current_panel_x.should eq(150.0)  # No border offset
    # Menubar is rendered in panel layer, so it moves automatically!
  end

  it "panel layer includes menubar (architecture verification)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("Edit")
    menubar.add_child(menu)
    panel.add_child(menubar)

    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    # Panel menubar should NOT have its own layer
    menubar.layer.should be_nil

    # Panel layer should include chrome and content widgets
    panel_layer = panel.layer.not_nil!
    panel_layer.widgets.size.should eq(2)  # Chrome and Content

    # Menubar should be inside content widget (not directly in layer.widgets)
    content = panel_layer.widgets.find { |w| w.is_a?(CrymbleUI::WindowPanel::Content) }
    content.should_not be_nil
    content = content.not_nil!
    content.children.should contain(menubar)
  end
end
