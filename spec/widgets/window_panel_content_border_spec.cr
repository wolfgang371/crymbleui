require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/virtual_matrix"

# A descendant layer (e.g. a VirtualMatrix's viewport-cache layer) must NEVER paint
# over the panel's 1px border. The compositor clips descendant layers to "their
# panel" — but if that clip is the FULL panel bounds it INCLUDES the border row
# (drawn fresh at y+height-1, after the content), so a squeezed matrix that
# overflows its tiny content area overpaints the bottom border. The clip must be
# the panel INTERIOR (inside the border). Reproduced at small panel heights.
# Count pixels on the panel's bottom-border row (inside the L/R borders) that are
# NOT the border color — i.e. overpainted by content.
private def border_overpaint(renderer, panel) : Int32
  border = CrymbleUI::Theme.current.panel_border
  brow = (panel.y + panel.height - 1).to_i
  n = 0
  ((panel.x.to_i + 2)...(panel.x + panel.width).to_i - 2).each do |x|
    p = renderer.backend.get_pixel(x, brow)
    n += 1 if p && p != border
  end
  n
end

describe "WindowPanel border is not overpainted by a squeezed descendant layer" do
  {52.0, 55.0, 58.0}.each do |h|
    it "keeps the bottom border intact with a matrix squeezed into a #{h.to_i}px-tall panel" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 20.0, 200.0, h)
      panel.add_child(CrymbleUI::VirtualMatrix.new(rows: 50, cols: 5, id: "m"))
      window.add_child(panel)
      app.root_widget = window
      app.build_tree
      window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
      renderer.render_frame(app)

      border_overpaint(renderer, panel).should eq(0)
    end
  end
end
