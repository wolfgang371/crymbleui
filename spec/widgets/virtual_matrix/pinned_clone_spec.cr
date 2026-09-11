require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# A PINNED CLONE: a cell whose BOX is no longer its span, because the sticky machinery holds the box
# still while the group scrolls away. The rule treats it specially — it is the only cell floored at
# the band — and until 2026-09-11 exactly one example touched the case (`placement_boxes` B1), at
# the LEADING edge only. The regime matrix named the other half as a gap.
#
# Measured first, so this is not a fixture built for a situation that never happens: over 400px of
# scroll, the demo shape yields 243 pinned samples, 100 of them with the span running past the FAR
# edge as well.
private VP_W = 600
private VP_H = 300

private def pinned_matrix(config)
  matrix = CrymbleUI::VirtualMatrix.new(ConfigurableMatrixAdapter.new(*config), id: "pinned")
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

private def line_height
  size = CrymbleUI::FontSizing.calculate_size(0)
  (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
end

describe "a pinned clone, whose box is not its span" do
  it "keeps its label inside its own BOX at both edges, not only the leading one" do
    # Ink outside the box is not drawn at all (layer_renderer.cr:1667), so a label placed out there
    # is simply shaved. B1 caught this at the leading edge — 2, then 4, then 6px of overhang,
    # growing with the scroll — when the leading-edge floor was briefly dropped. This asks the same
    # of the far edge, which nothing did.
    outside = [] of String
    at_far = 0
    at_lead = 0

    [{2, 2, 3, 3, 10, 10}, {2, 2, 6, 6, 8, 8}].each do |config|
      matrix = pinned_matrix(config)
      (0..400).step(4) do |sc|
        matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, sc.to_f64)
        matrix.pre_render_flush
        band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
        band_hi = matrix.bounds.height
        matrix.active_cells.each do |key, w|
          r = w.ink_region
          next unless r
          next unless r.pinned # the matrix's own answer, not a guess from the geometry
          prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
          next unless prims.size == 1
          p = prims.first.as(CrymbleUI::DrawText)
          next if p.text.empty?
          content = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
          box_y = w.absolute_bounds.y - (content ? matrix.scroll_offset.y : 0.0)
          ink = box_y + p.position.y
          span_lo = box_y + r.pos
          at_lead += 1 if span_lo < band_lo - 0.5
          at_far += 1 if span_lo + r.size > band_hi + 0.5
          # inside its own box, with a pixel of grid tolerance
          next if ink >= box_y - 1.0 && ink + line_height <= box_y + w.bounds.height + 1.0
          outside << "#{key} '#{p.text}' ink #{ink.round(1)} against box #{box_y.round(1)}.." \
                     "#{(box_y + w.bounds.height).round(1)} at scroll #{sc}"
        end
      end
    end

    puts "\n  [pinned] samples at the leading edge #{at_lead}, past the far edge #{at_far}; " \
         "placed outside their box: #{outside.size}"
    at_far.should be > 50, "no pinned clone ever reached the far edge — the fixture is wrong"
    outside.should be_empty,
      "a pinned clone's label was placed where it cannot be drawn:\n  #{outside.first(6).join("\n  ")}"
  end

  # A second example asserted "its label stays on screen while its span covers the band". It is NOT
  # here, because it could not be made to fail: with the far-edge clamp removed, with the box bounds
  # removed, and with the pinned floor removed, it stayed green all three times. Given its own
  # filter — only boxes that are themselves inside the band — "the ink is in the band" follows from
  # "the ink is in the box", which is the example above. A guard that cannot fail is not a guard.
  #
  # The example above IS live: disabling `confine` puts 9 pinned labels outside their box.
end
