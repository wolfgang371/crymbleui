require "../spec_helper"
require "../../src/testing/test_renderer"

# BUG: When a menu dropdown is OPEN and the user zooms, the dropdown popup width
# is not re-adjusted — labels get clipped. It only corrects on toggling an item
# or re-opening. Root: measure/layout is not a reactive node, so a zoom change
# must explicitly invalidate + re-layout. SFML does this via FontSizing.on_zoom_change;
# headless TestRenderer previously did NOT (the instrument diverged from SFML), so
# this class of bug was invisible to specs. The TestRenderer now mirrors the SFML
# zoom response (apply_zoom_change) via a per-frame zoom-epoch check.
describe "Menu dropdown width on zoom (while open)" do
  it "widens the OPEN dropdown popup when zooming in" do
    CrymbleUI::FontSizing.reset_zoom # hermetic — global zoom leaks across specs

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menu.add_child(CrymbleUI::MenuItem.new("Open a rather long menu label"))
    menu.add_child(CrymbleUI::MenuItem.new("Save"))
    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app) # first layout captures the menu items

    menu.on_click # open the dropdown
    menu.open?.should be_true
    renderer.render_frame(app)

    window.overlays.empty?.should be_false
    width_at_100 = window.overlays.first.bounds.width
    width_at_100.should be > 0.0

    # Zoom in while the dropdown stays open.
    3.times { CrymbleUI::FontSizing.zoom_in } # -> 1.5x
    renderer.render_frame(app)

    width_zoomed = window.overlays.first.bounds.width

    # The open popup must grow with zoom (labels are wider). Before the fix the width
    # stayed frozen at the 100% measurement and long labels clipped. At 1.5x zoom the
    # label column scales ~1.5x (padding scales slightly less), so >1.2x is a safe gate.
    width_zoomed.should be > width_at_100 * 1.2
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end

  it "widens the menubar bar item itself on zoom" do
    CrymbleUI::FontSizing.reset_zoom

    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("File")
    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)
    bar_width_at_100 = menu.bounds.width
    bar_width_at_100.should be > 0.0

    3.times { CrymbleUI::FontSizing.zoom_in } # -> 1.5x
    renderer.render_frame(app)

    # The bar label re-measures at the new zoom (the whole tree re-layouts). Before the
    # fix, non-keyboard zoom marked only layers (re-render), never the root widget
    # (re-layout), so the bar item kept its old width.
    menu.bounds.width.should be > bar_width_at_100 * 1.2
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end
end
