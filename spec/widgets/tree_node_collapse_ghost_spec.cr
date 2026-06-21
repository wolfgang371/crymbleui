require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/tree_node"
require "../../src/widgets/text"
require "../../src/widgets/button"
require "../../src/widgets/window"
require "../../src/layout/vstack"
require "../../src/widgets/scroll_view"
require "../../src/widgets/expanded"
require "../../src/dsl/builder"

# Regression: collapsing a TreeNode inside a ScrollView left a GHOST — the children vanished
# for one frame, then a viewport_cache "visit-all-visible" pass re-blitted a grandchild's stale
# widget_backend a frame later. Root cause: zero_bounds! released only the collapsing node's own
# cached pixels, not its subtree's, so a grandchild kept stale bounds + a cached backend. Fixed by
# making zero_bounds! recurse (a vacated footprint releases the whole subtree's cached pixels).
private RED = CrymbleUI::Color.new(255_u8, 0_u8, 0_u8, 255_u8)

private def red_pixels(renderer) : Int32
  n = 0
  (0...500).each do |y|
    (0...500).each { |x| n += 1 if renderer.backend.get_pixel(x, y) == RED }
  end
  n
end

private def click_on(app, widget)
  b = widget.absolute_bounds
  c = CrymbleUI::Vec2.new(b.x + b.width / 2, b.y + b.height / 2)
  app.handle_mouse_down(c)
  app.handle_mouse_up(c)
end

# DSL app mirroring tutorial-25: scroll_view > vstack > tree_nodes, with a RED marker child
# in the first node and enough content below to scroll.
class TreeGhostDSLApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Tut25-like", 500, 500) do
      vstack(padding: 15.0, spacing: 10.0) do
        text("Collapsible Tree Sections", font_scale: 1)
        expanded do
          scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv") do
            vstack(spacing: 4.0) do
              tree_node("Getting Started", expanded: true, font_scale: 1, id: "first") do
                vstack(padding: 10.0, spacing: 5.0) do
                  b = button("CrymbleUI is a declarative GUI framework for Crystal.") { }
                  b.background_color = RED # RED marker so we can pixel-detect the ghost
                  text("It uses a reactive state model for automatic UI updates.")
                end
              end
              tree_node("Widgets", expanded: true) do
                vstack(padding: 10.0, spacing: 4.0) do
                  20.times { |i| text("- widget item #{i}") }
                end
              end
            end
          end
        end
      end
    end
  end
end

describe "TreeNode collapse clears its children inside a ScrollView (no stale ghost)" do
  it "shows no RED ghost on any frame after a real header click collapses the node" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 500)
    app = TreeGhostDSLApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Sanity: the RED marker child is on screen while expanded.
    red_pixels(renderer).should be > 0

    # Collapse "Getting Started" by clicking its header (children.first), through the App.
    node = app.find("first").not_nil!.as(CrymbleUI::TreeNode)
    click_on(app, node.children.first)

    # Drive EXPLICIT frames: settle_rendering stops at the first stable frame and would miss
    # the deferred ghost (it re-blits a frame later). No frame may show the RED child.
    worst = 0
    8.times do
      renderer.render_frame(app)
      worst = Math.max(worst, red_pixels(renderer))
    end
    worst.should eq(0)
  end
end
