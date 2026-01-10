require "../spec_helper"
require "../../src/testing/test_renderer"

# BUG: Menu text (labels like "File", "Edit") is invisible during panel resize.
# Text only appears after resize stops (on mouse_up).
#
# Root cause: During selective rendering, only MenuBar is marked dirty.
# Menu children (which render the text) are NOT marked, so they're skipped.
# When resize stops, full layout triggers full render → text appears.

describe "MenuBar text during resize" do
  it "Menu text should be rendered during panel resize (not just after)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with menubar containing a menu
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 300.0, 200.0)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)

    panel.add_child(menubar)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Verify Menu was rendered initially (check BEFORE settle_rendering)
    initial_primitive_count = renderer.primitive_count
    initial_primitive_count.should be > 0

    # Let rendering settle (additional frames until stable)
    renderer.settle_rendering(app)

    # Start resize on right edge
    panel_right_edge = 100.0 + 300.0
    renderer.mouse_down(panel_right_edge, 150.0)
    renderer.render_frame(app)

    # Reset counters to measure just the resize frame
    renderer.reset_counters

    # Drag to resize panel by 50px (DURING resize, before mouse_up)
    renderer.mouse_move(panel_right_edge + 50.0, 150.0)

    # Check dirty_widgets BEFORE render (render clears them)
    panel_layer = panel.layer.not_nil!
    dirty_widgets = panel_layer.dirty_widgets.dup  # Copy before render clears it
    menu_in_dirty = dirty_widgets.any? { |w| w.is_a?(CrymbleUI::Menu) }

    renderer.render_frame(app)

    # Panel bounds should be updated
    panel.width.should eq(350.0)

    # Verify Menu was in dirty_widgets (the fix adds it during resize)
    # Without fix (BUG): Only Chrome + MenuBar are dirty, Menu is missing
    menu_in_dirty.should be_true,
      "Menu should be in dirty_widgets during resize (dirty: #{dirty_widgets.map(&.class.name).join(", ")})"
  end
end
