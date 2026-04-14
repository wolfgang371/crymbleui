require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/expanded"
require "../../src/widgets/tree_node"

class ScrollbarResizeApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Test", 600, 600) do
      vstack(spacing: 0.0) do
        tree_node("Section", expanded: false, id: "section") do
          vstack { 20.times { |i| text("Extra #{i}") } }
        end
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(adapter: MergeableTestAdapter.new(20, 5), id: "matrix"))
        end
      end
    end
  end
end

describe "VirtualMatrix scrollbar on resize (pixel test)" do
  it "scrollbar track pixel appears when tree_node expand shrinks VirtualMatrix" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 600)
    app = ScrollbarResizeApp.new
    app.build_tree
    renderer.settle_rendering(app)

    m = app.root.not_nil!.find_by_id("matrix").not_nil!.as(CrymbleUI::VirtualMatrix)
    sv = m.content_scroll_view.not_nil!
    sec = app.root.not_nil!.find_by_id("section").not_nil!.as(CrymbleUI::TreeNode)

    # Collapsed: 20 rows fit in 562px viewport → no scrollbar
    sv.content_size.height.should be <= sv.viewport_size.height

    # Expand section → VirtualMatrix shrinks to 92px → content (480) > viewport → needs scrollbar
    sec.toggle
    renderer.settle_rendering(app)

    sv2 = m.content_scroll_view.not_nil!
    sv2.content_size.height.should be > sv2.viewport_size.height  # Needs scrollbar

    # Scrollbar layer has correct bounds and primitives
    sbl = sv2.scrollbar_layer.not_nil!
    prims = sv2.to_primitives(sv2.bounds)
    prims.size.should be > 0  # Scrollbar primitives generated

    # Pixel at scrollbar position should show scrollbar track color
    track_color = CrymbleUI::Theme.current.scrollbar_track
    sb_x = (sbl.bounds.x + sbl.bounds.width - 8).to_i
    sb_y = (sbl.bounds.y + 30).to_i
    pixel = renderer.backend.get_pixel(sb_x, sb_y)
    pixel.should_not be_nil
    p = pixel.not_nil!
    # Pixel should be scrollbar track (#DCDCDC) or thumb (#969696), not white (#FFFFFF)
    is_background = p.r == 255_u8 && p.g == 255_u8 && p.b == 255_u8
    is_background.should be_false  # Scrollbar must be composited to window
  end
end
