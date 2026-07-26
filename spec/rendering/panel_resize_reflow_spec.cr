require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/expanded"
require "../../src/widgets/separator"
require "../../src/layout/vstack"
require "../../src/layout/flow"
require "../../src/testing/test_renderer"

# End-to-end shape of the reported defect, driven through the real event path (App#handle_mouse_*)
# rather than by calling layout() directly: a panel whose body is
#   [ section > row > flow-of-chips, separator, Expanded(VirtualMatrix) ]
# — the embrace shape panel's structure, where the two vstacks between the panel body and the flow are
# sized by their content and therefore sub-max.
#
# Dragging the panel's right edge WIDER must re-pack the chips and must never pull the Expanded up into
# the chip rows. Both must hold DURING the drag and after mouse-up: the reported overlap survived
# release, which is what made it a layout defect rather than a paint one.
describe "panel resize re-flows wrapping content" do
    it "re-packs the chips and keeps the Expanded below them when the panel is widened" do
        renderer = CrymbleUI::Testing::TestRenderer.new(900, 700)
        app = TestApp.new
        window = CrymbleUI::Window.new("T", 900, 700)
        panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 700.0, 600.0, resizable: true, id: "panel")

        body = CrymbleUI::VStack.new(spacing: 5.0)
        flow = CrymbleUI::FlowLayout.new(hspacing: 8.0, vspacing: 4.0, id: "chips")
        8.times { |i| flow.add_child(CrymbleUI::Button.new("Chip #{i}") { }) }
        row = CrymbleUI::VStack.new(spacing: 2.0, id: "row")
        row.add_child(flow)
        section = CrymbleUI::VStack.new(spacing: 2.0, id: "section")
        section.add_child(row)
        body.add_child(section)
        body.add_child(CrymbleUI::Separator.new)
        exp = CrymbleUI::Expanded.new
        exp.add_child(CrymbleUI::VirtualMatrix.new(rows: 40, cols: 5, id: "m"))
        body.add_child(exp)
        panel.add_child(body)
        window.add_child(panel)
        app.root_widget = window

        renderer.render_frame(app)
        renderer.settle_rendering(app)

        rows_of = ->{ flow.children.map(&.absolute_bounds.y).uniq.size }
        # The flow's OWN bottom — never the section's, whose height is the stale value that lies.
        flow_bottom = ->{ flow.children.map { |c| c.absolute_bounds.bottom }.max }

        wide_rows = rows_of.call
        right = panel.x + panel.width

        # Narrow until the chips wrap onto more rows.
        app.handle_mouse_down(CrymbleUI::Vec2.new(right - 4.0, panel.y + 300.0))
        renderer.render_frame(app)
        app.handle_mouse_move(CrymbleUI::Vec2.new(right - 260.0, panel.y + 300.0))
        renderer.render_frame(app)
        app.handle_mouse_up(CrymbleUI::Vec2.new(right - 260.0, panel.y + 300.0))
        renderer.render_frame(app)
        renderer.settle_rendering(app)

        narrow_rows = rows_of.call
        narrow_rows.should be > wide_rows # precondition: the narrow drag really did re-pack
        exp.absolute_bounds.y.should be >= flow_bottom.call

        # Widen back. THIS is the reported defect: the chips stay packed for the old narrow width while
        # the Expanded is positioned against a freshly measured (short) section.
        right2 = panel.x + panel.width
        app.handle_mouse_down(CrymbleUI::Vec2.new(right2 - 4.0, panel.y + 300.0))
        renderer.render_frame(app)
        app.handle_mouse_move(CrymbleUI::Vec2.new(right2 + 260.0, panel.y + 300.0))
        renderer.render_frame(app)

        rows_of.call.should eq(wide_rows)                      # re-packs DURING the drag
        exp.absolute_bounds.y.should be >= flow_bottom.call     # and never overlaps mid-drag

        app.handle_mouse_up(CrymbleUI::Vec2.new(right2 + 260.0, panel.y + 300.0))
        renderer.render_frame(app)
        renderer.settle_rendering(app)

        rows_of.call.should eq(wide_rows)                      # …and still after release
        exp.absolute_bounds.y.should be >= flow_bottom.call
    end
end
