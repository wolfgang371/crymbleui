require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"

# DSL app with a closeable panel
class ClosablePanelApp < CrymbleUI::App
    state show_panel : Bool = true

    def build : CrymbleUI::Widget
        window("Test", 400, 300) do
            if @show_panel
                window_panel("My Panel", x: 50.0, y: 50.0, width: 200.0, height: 150.0, id: "panel") do
                    text("Panel content", id: "panel_text")
                end
            end
        end
    end
end

describe "Closed panel ghost rendering" do
    it "closed panel is not visible after close (X button path)" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = ClosablePanelApp.new
        app.build_tree
        renderer.settle_rendering(app)

        # Record pixel at title bar area while panel is open
        pixel_open = renderer.backend.get_pixel(75, 55)

        # Close via X button (@closed = true, panel stays in tree)
        panel = app.find("panel").not_nil!.as(CrymbleUI::WindowPanel)
        panel.close
        app.rebuild
        renderer.render_frame(app)

        # Panel still in tree but closed
        new_panel = app.find("panel").not_nil!.as(CrymbleUI::WindowPanel)
        new_panel.closed.should be_true

        # Pixel at panel area should NOT be the panel's title bar color anymore
        pixel_closed = renderer.backend.get_pixel(75, 55)
        pixel_closed.should_not eq(pixel_open)
    end
end
