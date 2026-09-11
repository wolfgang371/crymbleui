require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# WHICH EDGE CLIPS A GROUP MUST NOT CHANGE HOW FAST ITS LABEL MOVES.
#
# Wolfgang, 2026-09-11, on the demo (images #105/#106): "mind r1a~19 and r1b~35 in first image,
# r1a~19 and r1b~38 in 2nd image — both compounds only partially visible in both images,
# nevertheless r1a having ruler speed and r1b half of it — this is a bug".
#
# Measured on his exact configuration: r1a, clipped at the TOP, moved -20px per 20px of scroll;
# r1b, clipped at the BOTTOM, moved -10px. Then r1a reached the band's leading edge and STOPPED
# DEAD, which is #99's "placed at the very top" all over again.
#
# The cause was the leading edge being held by the span's OVERFLOW rather than clamped to the band:
# with a modest overflow `lo` tracks the span's own bottom, so the label rides at the scroll's full
# speed until the allowance is spent and then jams against the edge. Both ends clamp now, once the
# span is taller than the band — a group you can see ALL of is still not held at its leading edge,
# because it is leaving and should leave with its rows (#93-#96).
private VP_W = 1400
private VP_H = 700

private def demo_matrix
  matrix = CrymbleUI::VirtualMatrix.new(ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10), id: "sym")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, VP_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.pre_render_flush
  matrix
end

private record Edge, text : String, top : Float64, clipped_top : Bool, clipped_bottom : Bool

private def edges(matrix) : Array(Edge)
  band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
  band_hi = matrix.bounds.height
  out = [] of Edge
  matrix.active_cells.each do |key, w|
    r = w.ink_region
    next unless r && r.compound
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    next unless prims.size == 1
    p = prims.first.as(CrymbleUI::DrawText)
    next if p.text.empty?
    content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_y = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
    lo = box_y + r.pos
    hi = lo + r.size
    next unless r.size > band_hi - band_lo # taller than the band: the regime he reported
    out << Edge.new(p.text, box_y + p.position.y, lo < band_lo - 0.5, hi > band_hi + 0.5)
  end
  out
end

describe "a group clipped at one edge" do
  it "moves at the same rate whichever edge clips it (#105/#106)" do
    matrix = demo_matrix
    prev = {} of String => Edge
    top_rates = [] of Float64
    bottom_rates = [] of Float64
    offenders = [] of String

    (200..600).step(20) do |sc|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, sc.to_f64)
      matrix.pre_render_flush
      edges(matrix).each do |e|
        was = prev[e.text]?
        prev[e.text] = e
        next unless was
        # EXACTLY ONE end clipped, and the same end as last frame — a label crossing between
        # regimes legitimately changes rate, and that frame is not what this measures.
        next unless e.clipped_top ^ e.clipped_bottom
        next unless was.clipped_top == e.clipped_top && was.clipped_bottom == e.clipped_bottom
        rate = (e.top - was.top).abs / 20.0
        (e.clipped_top ? top_rates : bottom_rates) << rate
        # Half the scroll: the slice has one moving end, so its centre moves at half that end's
        # rate. A WHOLE scroll means the label is tracking the span itself with no clamp; ZERO
        # means it has jammed against an edge. Both were r1a's behaviour before this was fixed.
        offenders << "scroll #{sc}: '#{e.text}' clipped at #{e.clipped_top ? "TOP" : "BOTTOM"} " \
                     "moved #{(e.top - was.top).round(1)}px for 20px" if (rate - 0.5).abs > 0.15
      end
    end

    t = top_rates.empty? ? 0.0 : top_rates.sum / top_rates.size
    b = bottom_rates.empty? ? 0.0 : bottom_rates.sum / bottom_rates.size
    puts "\n  [edge-symmetry] clipped at TOP: #{top_rates.size} samples, mean rate #{t.round(3)} | " \
         "clipped at BOTTOM: #{bottom_rates.size} samples, mean rate #{b.round(3)}"
    top_rates.size.should be > 8, "no group was ever clipped at the top — the fixture is wrong"
    bottom_rates.size.should be > 8, "no group was ever clipped at the bottom — the fixture is wrong"
    (t - b).abs.should be <= 0.1,
      "the two edges move a label at different rates: top #{t.round(3)}, bottom #{b.round(3)}"
    offenders.should be_empty,
      "a label did not move at half the scroll:\n  #{offenders.first(6).join("\n  ")}"
  end
end
