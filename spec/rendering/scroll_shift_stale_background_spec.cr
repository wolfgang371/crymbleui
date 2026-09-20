require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A RecursiveGrid inside a ScrollView must keep its cell backgrounds across a buffer recenter.
#
# Wolfgang, 2026-09-20: "I think the recgrid issue was always there wrt scrolling — just crymbleui
# nor embrace had it in a scrollable area before." embrace's Config tab is the first place a
# RecursiveGrid lives inside a ScrollView (the field list's mirror grid, and the history changes
# table), and that is where the garbling appears: after scrolling, rectangles of the panel
# background sit INSIDE the grid's coloured cells until a full repaint.
#
# Measured off the field screenshots: +8441 background pixels against -3074 green and -2179 brown,
# the largest hole 58x53 over one cell. The scroll layer's own background is TRANSPARENT
# (#00000000), so a hole is simply buffer nobody painted, with the panel showing through.
private class GridScrollApp < CrymbleUI::App
  CELL = CrymbleUI::Color.new(30, 160, 60, 255)

  def build : CrymbleUI::Widget
    window("GridScroll", 400, 300) do
      window_panel("P", 0.0, 0.0, 400.0, 300.0, id: "panel") do
        scroll_view(id: "sv") do
          # The field list's shape, which is where the field reports land: grids NESTED inside
          # grids, with drop zones inside those. The one-shot dump from the app showed a three-deep
          # stack (RecursiveGrid / DropZoneBox / Text) at one rectangle, entirely unpainted after a
          # recenter, none of them dirty and two of them holding no texture at all.
          # ALIGNED WITH THE SFML CASE (docs/BUGFIXING.md (b) — use the SFML test to find and close
          # the gap between the execution models). What has to match is not "taller than the
          # viewport" but the RECENTER CONDITION: the content must out-reach the buffer at its
          # initial origin, or no shift ever happens and the case cannot occur.
          #   SFML:     content 782, viewport 618, buffer 818, origin -100 -> reach 718 < 782  -> recenters
          #   headless: buffer 454, origin -100 -> reach 354, so the content must exceed that.
          # With 30 grids (content 1380) the scroll ran through many recenters and ended past every
          # painted cell; with 7 (content 210) it could not scroll at all.
          14.times do |g|
            recursive_grid(id: "outer_#{g}", spacing: 2.0, cell_background_color: CELL) do
              (0...2).map do |r|
                [
                  text("g#{g}r#{r}").as(CrymbleUI::Widget),
                  recursive_grid(spacing: 1.0, cell_background_color: CELL) do
                    [[text("inner").as(CrymbleUI::Widget)]]
                  end.as(CrymbleUI::Widget),
                ]
              end
            end
          end
        end
      end
    end
  end
end

describe "RecursiveGrid inside a ScrollView" do
  # The regression test for invariant (h2). Written as a FAILING spec against the live defect
  # first (docs/BUGFIXING.md: a failing test before a fix), after the SFML autotest reproduced it
  # (core/spec/autotest/config_tab_scroll_garble_autotest.cr: 3043 background pixels enclosed by
  # cell colour on the third leg, 0 when clean).
  #
  # The oracle is the one that worked there, not the ones that lied: count the CELL COLOUR in the
  # layer buffer at the SAME scroll offset, before and after the round trip. Emptiness/alpha was
  # tried twice and is unusable — a blank cell is legitimately empty, and the reading stops being
  # trustworthy once the buffer recenters.
  #
  # Mechanism under test: a widget captures "the pixels beneath me" where the widget that paints
  # them has not painted this pass, memorizes transparency, and restores it over its parent's cell
  # colour on every later re-render. Without the fix this reads 3420 -> 1190; with it, unchanged.
  #
  # The fixture's proportions are load-bearing. What must hold is the RECENTER CONDITION — the
  # content has to out-reach the buffer at its initial origin — not merely "taller than the
  # viewport": 30 grids scrolled through many recenters and ended past every painted cell (read 0),
  # 7 grids could not scroll at all (read 0), and only 14 reproduces. The SFML case this mirrors:
  # content 782 in a 618 viewport with an 818 buffer at origin -100, i.e. reach 718 < 782.
  it "does not lose cell colour across a scroll round trip" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = GridScrollApp.new
    CrymbleUI::Widget.app = app
    app.build_tree
    renderer.settle_rendering(app)

    sv = app.find("sv").not_nil!.as(CrymbleUI::ScrollView)
    layer = sv.layer.not_nil!
    backend = layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)
    # Room to scroll; that a RECENTER happens is asserted below via buffer_origin, which is the
    # real condition. (Demanding 2x here contradicted the SFML geometry being matched: 782 in 618.)
    (sv.content_size.height > sv.bounds.height * 1.1).should be_true

    cell_pixels = ->{
      n = 0
      y = 0
      while y < backend.height
        x = 0
        while x < backend.width
          n += 1 if backend.get_pixel(x, y) == GridScrollApp::CELL
          x += 2
        end
        y += 2
      end
      n
    }

    centre = CrymbleUI::Vec2.new(sv.absolute_bounds.x + 20.0, sv.absolute_bounds.y + 20.0)
    scroll = ->(dir : Float64, n : Int32) {
      n.times { app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, dir), centre); renderer.render_frame(app) }
    }

    origin_before = layer.buffer_origin.y
    # The field gesture. NO request_rebuild: it marks the layer NeedsLayout, takes the
    # clear-and-repaint branch, and the recenter case never happens.
    scroll.call(-3.0, 8)
    after_first_descent = cell_pixels.call
    after_first_descent.should be > 0 # instrument: the cells are painted at this offset
    offset_at_bottom = layer.scroll_offset.y

    scroll.call(3.0, 8)
    scroll.call(-3.0, 8)
    layer.buffer_origin.y.should_not eq(origin_before)   # instrument: the buffer really recentered
    layer.scroll_offset.y.should eq(offset_at_bottom)    # instrument: same offset as the first read

    # Same offset, same content: the cell colour must still be there.
    cell_pixels.call.should be >= (after_first_descent * 9 // 10)
  end
end
