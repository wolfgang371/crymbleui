require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for panel menubar hover highlighting
# Issue: Panel menubar menus don't show hover highlighting (window menubar does)
# Root cause: Menu.mark_needs_render should propagate to MenuBar layer

describe "Panel MenuBar Hover Highlighting" do
  it "panel menu renders with hover color when hovered (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new

    # Create menu with specific colors for testing
    menu_bg = CrymbleUI::Color.new(250, 250, 250, 255)
    menu_hover = CrymbleUI::Color.new(230, 230, 230, 255)
    menu = CrymbleUI::Menu.new("File",
      background_color: menu_bg,
      hover_color: menu_hover
    )

    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render (menu not hovered)
    renderer.render_frame(app)

    # Panel menubar is in panel layer (no separate layer)
    menubar.layer.should be_nil

    # Get panel layer backend for pixel testing
    panel_layer = panel.layer.not_nil!
    backend = panel_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Menu is in absolute coordinates, but panel layer is offset by panel position
    # Convert to panel-layer-local coordinates
    menu_abs = menu.absolute_bounds
    panel_offset_x = panel_layer.bounds.x
    panel_offset_y = panel_layer.bounds.y
    menu_center_x = (menu_abs.x - panel_offset_x + menu_abs.width / 2).to_i
    menu_center_y = (menu_abs.y - panel_offset_y + menu_abs.height / 2).to_i

    # Before hover - should be background color
    pixel_before = backend.get_pixel(menu_center_x, menu_center_y)
    pixel_before.should eq(menu_bg)

    # Simulate hover
    menu.on_mouse_enter

    # Render with hover
    renderer.render_frame(app)

    # After hover - should be hover color
    pixel_after = backend.get_pixel(menu_center_x, menu_center_y)
    pixel_after.should eq(menu_hover)
  end

  it "window menu renders with hover color when hovered (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    menubar = CrymbleUI::MenuBar.new

    # Create menu with specific colors for testing
    menu_bg = CrymbleUI::Color.new(250, 250, 250, 255)
    menu_hover = CrymbleUI::Color.new(230, 230, 230, 255)
    menu = CrymbleUI::Menu.new("File",
      background_color: menu_bg,
      hover_color: menu_hover
    )

    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window

    # Initial render (menu not hovered)
    renderer.render_frame(app)

    # Get menubar layer backend for pixel testing
    menubar_layer = menubar.layer.not_nil!
    backend = menubar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Menu should be at relative position (0, 0) in menubar layer
    menu_center_x = (menu.bounds.x + menu.bounds.width / 2).to_i
    menu_center_y = (menu.bounds.y + menu.bounds.height / 2).to_i

    # Before hover - should be background color
    pixel_before = backend.get_pixel(menu_center_x, menu_center_y)
    pixel_before.should eq(menu_bg)

    # Simulate hover
    menu.on_mouse_enter

    # Render with hover
    renderer.render_frame(app)

    # After hover - should be hover color
    pixel_after = backend.get_pixel(menu_center_x, menu_center_y)
    pixel_after.should eq(menu_hover)
  end

  it "marks panel layer when panel menu is hovered" do
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")

    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    # Panel menubar uses panel layer (no separate layer)
    menubar.layer.should be_nil

    panel_layer = panel.layer.not_nil!
    menu.get_primitives(menu.bounds) # render so the reactive hover edge enqueues to the layer
    panel_layer.clear_render_state

    # Simulate hover (menu should mark itself and propagate to panel layer)
    menu.on_mouse_enter

    # Panel layer should be marked for re-render
    panel_layer.needs_render?.should be_true
    # Menu should be in dirty widgets list
    panel_layer.dirty_widgets.should contain(menu)
  end

  it "panel menubar is in panel layer (no separate layer)" do
    window = CrymbleUI::Window.new("Test", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")

    menubar.add_child(menu)
    panel.add_child(menubar)
    window.add_child(panel)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    # Collect all layers
    layers = window.collect_all_layers

    # Should include only:
    # 1. Window root layer
    # 2. Panel layer
    # (Panel menubar is in panel layer, not separate)
    layers.size.should eq(2)

    # Panel menubar should not have its own layer
    menubar.layer.should be_nil
  end
end
