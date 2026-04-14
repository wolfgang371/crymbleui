require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/scroll_view"

# App with tall scrollable content
class ScrollableApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        window("Test", 400, 300) do
            scroll_view(id: "sv") do
                vstack(spacing: 0.0) do
                    40.times do |i|
                        text("Line #{i}", id: "line_#{i}")
                    end
                end
            end
        end
    end
end

describe "Viewport cache scroll recenter" do
    it "recenters buffer when scroll_offset moves beyond cache bounds" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = ScrollableApp.new
        app.build_tree
        renderer.settle_rendering(app)

        sv = app.find("sv").not_nil!.as(CrymbleUI::ScrollView)
        layer = sv.content_layer.not_nil!
        layer.viewport_cache.should be_true

        initial_origin = layer.buffer_origin.y

        # Scroll far down — past the cache extent buffer
        # Setting scroll_offset on a viewport_cache layer auto-marks it dirty
        layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 400.0)

        # Layer should be auto-marked dirty by the scroll_offset setter
        layer.needs_render?.should be_true

        renderer.render_frame(app)

        # Buffer should have recentered to accommodate scroll_offset=400
        layer.buffer_origin.y.should_not eq(initial_origin)

        # Scroll back to 0
        old_origin = layer.buffer_origin.y
        layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
        renderer.render_frame(app)

        # Buffer should recenter again
        layer.buffer_origin.y.should_not eq(old_origin)
    end

    it "does not mark layer dirty when scroll_offset doesn't change" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = ScrollableApp.new
        app.build_tree
        renderer.settle_rendering(app)

        sv = app.find("sv").not_nil!.as(CrymbleUI::ScrollView)
        layer = sv.content_layer.not_nil!

        # Setting same offset shouldn't mark dirty
        current = layer.scroll_offset
        layer.scroll_offset = current
        layer.needs_render?.should be_false
    end
end
