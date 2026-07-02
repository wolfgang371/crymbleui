require "../spec_helper"
require "../../src/testing/test_renderer"

# pixel coverage: a checkable MenuItem's check-glyph must actually be DRAWN — the existing
# specs only assert primitive objects / internal check_state. Here we open the menu, sample the
# item's left gutter (where the box/check is drawn) in the composited popup-layer backend, and
# require the CHECKED rendering to differ in pixels from the UNCHECKED one. If the checkbox stops
# reflecting its state visually, this fails even though check_state is "correct".
private def gutter_pixels(backend, item, gutter_w = 28) : Array(CrymbleUI::Color)
  x0 = item.bounds.x.to_i
  y0 = item.bounds.y.to_i
  w = Math.min(gutter_w, item.bounds.width.to_i)
  h = item.bounds.height.to_i
  result = [] of CrymbleUI::Color
  (x0...(x0 + w)).each do |x|
    (y0...(y0 + h)).each do |y|
      if (p = backend.get_pixel(x, y))
        result << p
      end
    end
  end
  result
end

describe "checkable MenuItem draws its check-glyph in pixels" do
  it "the gutter pixels differ between checked and unchecked (the check is actually rendered)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)
    menubar = CrymbleUI::MenuBar.new
    menu = CrymbleUI::Menu.new("Options")
    item = CrymbleUI::MenuItem.new("Show Grid", checked: true) { }
    menu.add_child(item)
    menubar.add_child(menu)
    window.add_child(menubar)
    app.root_widget = window

    renderer.render_frame(app)
    menu.on_click # open the dropdown
    renderer.render_frame(app)

    popup = window.find_all_popups.first
    backend = popup.layer.not_nil!.backend.as(CrymbleUI::Testing::TestRenderBackend)

    checked = gutter_pixels(backend, item)
    checked.should_not be_empty # the box/check is drawn at all

    item.checked = false # reactive setter -> re-render
    renderer.render_frame(app)
    unchecked = gutter_pixels(backend, item)

    # The visible state MUST change — a checkbox that renders identically checked/unchecked is broken.
    checked.should_not eq(unchecked)
  end
end
