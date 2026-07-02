require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/menubar"
require "../../src/widgets/menu"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/expanded"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# a SELECTIVE panel resize re-blits the menubar over its full strip; its Menu children are
# SEPARATE widgets that aren't dirty, so they're not re-blitted -> the menubar's chrome backend
# (BlendNone-replaced) overwrites their text. Pin it headlessly via the COMPOSITED frame + a TEXT
# (dark) pixel metric (the menu's own light bg masks a naive non-bg count), driven through the App's
# handle_mouse_* selective-resize path (NOT panel.on_mouse_*, which my first repro wrongly used).
describe "MenuBar text survives a selective panel resize" do
  it "keeps menu text painted in the composited frame during a widen-resize" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 700)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 800, 700)
    panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 500.0, 600.0, resizable: true, id: "panel")
    menubar = CrymbleUI::MenuBar.new(id: "menubar")
    menubar.add_child(CrymbleUI::Menu.new("Edit"))
    menubar.add_child(CrymbleUI::Menu.new("View"))
    panel.add_child(menubar)
    vstack = CrymbleUI::VStack.new(spacing: 4.0)
    3.times { |i| vstack.add_child(CrymbleUI::Button.new("Section #{i}") { }) }
    exp = CrymbleUI::Expanded.new
    exp.add_child(CrymbleUI::VirtualMatrix.new(rows: 40, cols: 5, id: "m"))
    vstack.add_child(exp)
    panel.add_child(vstack)
    window.add_child(panel)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    edit = menubar.children.first
    dark_text = ->do
      b = edit.absolute_bounds
      n = 0
      ((b.x.to_i + 2)...(b.x + b.width).to_i - 2).each do |px|
        ((b.y.to_i + 2)...(b.y + b.height).to_i - 2).each do |py|
          c = renderer.backend.get_pixel(px, py)
          n += 1 if c && (c.r.to_i + c.g.to_i + c.b.to_i) < 300
        end
      end
      n
    end

    dark_text.call.should be > 0 # "Edit" glyphs present at settle

    right = panel.x + panel.width
    app.handle_mouse_down(CrymbleUI::Vec2.new(right - 4.0, panel.y + 200.0))
    renderer.render_frame(app)
    app.handle_mouse_move(CrymbleUI::Vec2.new(right + 30.0, panel.y + 200.0)) # widen, DURING the drag
    renderer.render_frame(app)

    # The menu text must SURVIVE the selective resize. RED without the fix: the menubar's re-blit
    # covers the strip and the non-dirty menus are never re-painted.
    dark_text.call.should be > 0
  end
end
