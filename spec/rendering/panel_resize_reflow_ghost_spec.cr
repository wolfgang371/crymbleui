require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/expanded"
require "../../src/widgets/separator"
require "../../src/layout/vstack"
require "../../src/layout/flow"
require "../../src/testing/test_renderer"

# A panel-resize drag renders SELECTIVELY on purpose: `on_mouse_move` flags @resize_relayout_pending and
# marks needs_render (never needs_layout), and pre_render_flush re-lays the content out ONCE per frame,
# so only changed widgets repaint. Selective rendering repairs CONTENT, never GEOMETRY — it repaints a
# chip at its new spot, but nothing owns the pixels it VACATED. A beta tester saw exactly that: leftovers
# in the gaps between filter chips while the mouse was held, gone on release (mouse-up marks needs_layout
# = a full render).
#
# The metric is deliberately two-sided. A one-sided "no stale pixels" count is passed by a BLANK panel —
# which is the failure mode of a fix that clears the buffer and then renders nothing into it — so every
# frame also asserts each chip is actually inked at its new footprint.
describe "panel resize re-flow repairs vacated pixels" do
    it "leaves no stale pixels in the chip area on any drag frame, and keeps the chips painted" do
        renderer = CrymbleUI::Testing::TestRenderer.new(900, 700)
        app = TestApp.new
        window = CrymbleUI::Window.new("T", 900, 700)
        panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 700.0, 600.0, resizable: true, id: "panel")

        body = CrymbleUI::VStack.new(spacing: 5.0)
        flow = CrymbleUI::FlowLayout.new(hspacing: 8.0, vspacing: 4.0, id: "chips")
        # Buttons, not Checkboxes: a solid fill is a far stronger ghost signal than a checkbox's mostly
        # empty box. The real embrace chips are checkboxes — this fixture deliberately amplifies.
        10.times { |i| flow.add_child(CrymbleUI::Button.new("Chip #{i}") { }) }
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

        layer = panel.layer.not_nil!
        bg = layer.background_color
        chip_bg = flow.children.first.as(CrymbleUI::Button).background_color
        # Without this the whole metric is identically zero and proves nothing.
        chip_bg.should_not eq(bg)

        # Whole-pixel footprint, using the renderer's own arithmetic (PixelSnap) rather than a tolerance:
        # a chip inks exactly [origin(x), origin(x)+span) — no dilation, so a 1px ghost cannot hide.
        snapped = ->(r : CrymbleUI::Rect) do
            {CrymbleUI::PixelSnap.origin(r.x), CrymbleUI::PixelSnap.origin(r.y),
             CrymbleUI::PixelSnap.span(r.x, r.width), CrymbleUI::PixelSnap.span(r.y, r.height)}
        end
        same = ->(c : CrymbleUI::Color?, o : CrymbleUI::Color) { !c.nil? && c.r == o.r && c.g == o.g && c.b == o.b }

        # Probe rect: the chips' CURRENT horizontal extent, but the union of their VERTICAL extent over
        # the drag, so a row vacated by a re-pack is still probed. The x-range must NOT be unioned: as
        # the panel narrows, the old flow rect reaches past the panel's content edge into the border and
        # then outside the panel entirely, and neither of those is the layer's background colour — a
        # unioned x-range reports them as "stale" and the metric measures the panel edge, not ghosts.
        probe_y0 = flow.absolute_bounds.y
        probe_y1 = flow.absolute_bounds.bottom
        probe = ->do
            f = flow.absolute_bounds
            CrymbleUI::Rect.new(f.x, probe_y0, f.width, probe_y1 - probe_y0)
        end
        grow_y = ->do
            probe_y0 = Math.min(probe_y0, flow.absolute_bounds.y)
            probe_y1 = Math.max(probe_y1, flow.absolute_bounds.bottom)
        end

        # A ghost is a CHIP-coloured pixel where no chip currently is. Keying on the chip's own colour
        # rather than "not the background" is what makes the metric survive a moving layout: the band a
        # re-pack vacates is immediately occupied by the separator and the matrix, and the panel's border
        # sits just outside the content area — all legitimate, none of them chip-coloured. Scanned over
        # the panel's whole content area, so a chip stranded anywhere in the panel counts.
        stale = ->do
            rects = flow.children.map { |c| snapped.call(c.absolute_bounds) }
            area = panel.content_area
            px0, py0, pw, ph = snapped.call(area)
            n = 0
            (px0...(px0 + pw)).each do |x|
                (py0...(py0 + ph)).each do |y|
                    next if rects.any? { |(rx, ry, rw, rh)| x >= rx && x < rx + rw && y >= ry && y < ry + rh }
                    n += 1 if same.call(renderer.backend.get_pixel(x, y), chip_bg)
                end
            end
            n
        end
        # presence dual: every chip must be inked somewhere inside its own footprint
        unpainted_chips = ->do
            flow.children.count do |c|
                rx, ry, rw, rh = snapped.call(c.absolute_bounds)
                found = false
                (rx...(rx + rw)).each do |x|
                    (ry...(ry + rh)).each do |y|
                        if same.call(renderer.backend.get_pixel(x, y), chip_bg)
                            found = true
                            break
                        end
                    end
                    break if found
                end
                !found
            end
        end

        packing = ->{ flow.children.map { |c| {c.bounds.x, c.bounds.y, c.bounds.width, c.bounds.height} } }

        stale.call.should eq(0)          # calibrates the colour oracle: a wrong bg explodes here
        unpainted_chips.call.should eq(0)

        # One render_frame per mouse-move — the real loop never gets a settle frame mid-drag.
        repacks = 0
        drag = ->(steps : Array(Float64)) do
            right = panel.x + panel.width
            app.handle_mouse_down(CrymbleUI::Vec2.new(right - 4.0, panel.y + 300.0))
            renderer.render_frame(app)
            before = packing.call
            steps.each do |dx|
                grow_y.call
                app.handle_mouse_move(CrymbleUI::Vec2.new(right + dx, panel.y + 300.0))
                renderer.render_frame(app)
                grow_y.call
                now = packing.call
                repacks += 1 if now != before
                before = now
                stale.call.should eq(0), "stale pixels in the chip area at dx=#{dx}"
                unpainted_chips.call.should eq(0), "chip(s) not painted at dx=#{dx} (a blank panel also has 0 stale pixels)"
            end
            app.handle_mouse_up(CrymbleUI::Vec2.new(right + steps.last, panel.y + 300.0))
            renderer.render_frame(app)
        end

        drag.call([-40.0, -90.0, -140.0, -190.0, -240.0, -290.0, -340.0, -390.0])
        drag.call([40.0, 90.0, 140.0, 190.0, 240.0, 290.0, 340.0, 390.0])

        # Non-vacuity: if no drag step ever changed the packing, the assertions above proved nothing.
        repacks.should be > 0
    end
end
