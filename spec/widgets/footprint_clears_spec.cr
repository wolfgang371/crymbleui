require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/tree_node"
require "../../src/widgets/button"
require "../../src/widgets/text"
require "../../src/widgets/window"
require "../../src/layout/vstack"
require "../../src/widgets/scroll_view"
require "../../src/widgets/expanded"
require "../../src/dsl/builder"

# Generic guard for the unifying invariant: a footprint-vacate must release the WHOLE
# subtree's cached pixels, at ANY depth. This is the deep companion to the depth-2
# tree_node_collapse_ghost_spec — here the RED marker is a great-grandchild behind a NESTED
# TreeNode, so collapsing the outer node must zero it via zero_bounds!'s recursion, leaving
# no stale ghost for a viewport_cache layer to re-blit. Driven through a real DSL app + a
# real header click (the faithful path that reproduced the original bug).
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

# RED marker deep behind a NESTED TreeNode, inside a scrollable ScrollView.
class NestedCollapseApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("NestedCollapse", 500, 500) do
      vstack(padding: 15.0, spacing: 10.0) do
        text("Header", font_scale: 1)
        expanded do
          scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv") do
            vstack(spacing: 4.0) do
              tree_node("Outer", expanded: true, id: "outer") do
                vstack(padding: 10.0, spacing: 5.0) do
                  tree_node("Inner", expanded: true) do
                    vstack(padding: 10.0, spacing: 5.0) do
                      b = button("DEEP RED MARKER") { }
                      b.background_color = RED
                    end
                  end
                end
              end
              20.times { |i| text("- item #{i}") }
            end
          end
        end
      end
    end
  end
end

describe "footprint-vacate releases the whole subtree's cached pixels (no deep ghost)" do
  it "collapsing an outer TreeNode clears a marker behind a nested TreeNode" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 500)
    app = NestedCollapseApp.new
    app.build_tree
    renderer.settle_rendering(app)
    red_pixels(renderer).should be > 0 # sanity: deep marker visible while expanded

    node = app.find("outer").not_nil!.as(CrymbleUI::TreeNode)
    click_on(app, node.children.first) # collapse the OUTER node

    worst = 0
    8.times do
      renderer.render_frame(app)
      worst = Math.max(worst, red_pixels(renderer))
    end
    worst.should eq(0) # no ghost from the deep (great-grandchild) marker
  end
end
