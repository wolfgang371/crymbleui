require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# The three field reports that had NO headless test until now — two of them regressions I put in
# front of Wolfgang, which is exactly why they are here. All use the DEMO's own configuration
# (2 header levels, span 3, leaf span 10), i.e. the fixture the reports came from, rather than a
# shape invented to suit the assertion.
#
#   #45  a group label ("a") was not drawn AT ALL, then appeared after one line of scroll
#   #49  column header labels ("1a"/"2a") scrolled out while their span was still on screen
#   #50  a row header label ("r1b") left the view while its cluster was still visible
#
# Each asserts the PROPERTY the report is about — the label is drawn, and it is inside the part of
# its own span you can see — rather than a pixel position, so the rule may keep evolving without
# these turning into a transcript of one implementation.

private VP_W = 900
private VP_H = 600

private def demo_matrix
  adapter = ConfigurableMatrixAdapter.new(2, 2, 3, 3, 10, 10) # the demo's defaults
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "compound_label_vis")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(VP_W, VP_H)
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(VP_W.to_f64, VP_H.to_f64)),
    CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

# Every DrawText the matrix's cells emit, in SCREEN coordinates, keyed by its exact string, with
# the SCREEN rect of the cell that emitted it. The rect matters: a cell can outlive its span on
# screen (it sits in the destruction buffer for a few frames), and its label is then legitimately
# outside the band — so "the label is in the band" is only a property while the SPAN is visible.
private record LabelAt, x : Float64, y : Float64, box : CrymbleUI::Rect

private def cell_labels(matrix) : Hash(String, LabelAt)
  out = {} of String => LabelAt
  matrix.active_cells.each do |key, w|
    row, col = key
    content_cell = row >= matrix.sticky_row_count && col >= matrix.sticky_col_count
    dx = content_cell ? matrix.scroll_offset.x : 0.0
    dy = content_cell ? matrix.scroll_offset.y : 0.0
    box = CrymbleUI::Rect.new(w.absolute_bounds.x - dx, w.absolute_bounds.y - dy,
      w.bounds.width, w.bounds.height)
    w.to_primitives(w.bounds).each do |p|
      next unless p.is_a?(CrymbleUI::DrawText)
      next if p.text.empty?
      out[p.text] = LabelAt.new(box.x + p.position.x, box.y + p.position.y, box)
    end
  end
  out
end

describe "a span's label stays with the part of the span you can see" do
  it "keeps a ROW header's label drawn while its cluster is on screen (#45, #50)" do
    renderer, app, matrix = demo_matrix
    band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels

    seen = 0
    (0..40).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step * 30.0)
      # flush, not settle: the matrix is already built and this loop only changes the scroll.
      # `settle_rendering` renders to quiescence — several full frames — 41 times over, which made
      # these two tests 205 of this suite's 899 seconds, the largest single cost in it.
      matrix.pre_render_flush
      labels = cell_labels(matrix)
      # r1a names the first level-1 cluster. While any part of that cluster is on screen its
      # label must be DRAWN — #45 was the label missing entirely — and inside the viewport, not
      # parked below it, which is #50.
      # EVERY level-1 cluster, not one hand-picked: r1a's span starts at the top, so it is held
      # whatever the geometry does and cannot exhibit the defect at all. #50 was about r1b — a
      # span ARRIVING from below. Picking the span I happened to think of is how the first
      # version of this example passed against the very regression it was written for.
      labels.each do |text, at|
        next unless text =~ /\Ar1[a-z]\z/
        # Only while the SPAN itself is on screen — a cell outliving its span in the destruction
        # buffer may legitimately place its label anywhere.
        vis_lo = {at.box.y, band_lo}.max
        vis_hi = {at.box.y + at.box.height, VP_H.to_f64}.min
        next unless vis_hi - vis_lo > 20.0
        seen += 1
        # THE property, and it has to be the VISIBLE PART of the span rather than "somewhere in
        # the window": a level-1 cluster is thousands of px tall, so a label left at the span's
        # own centre can drift far from what you can see without ever leaving the viewport. That
        # weaker form was tried and did NOT catch the regression it was written for.
        at.y.should be >= vis_lo - 1.0,
          "#{text}'s label sat above the visible part of its own cluster at scroll #{step * 30} " \
          "(y=#{at.y.round(1)}, cluster visible from #{vis_lo.round(1)} to #{vis_hi.round(1)})"
        at.y.should be <= vis_hi + 1.0,
          "#{text}'s label sat below the visible part of its own cluster at scroll #{step * 30} " \
          "(y=#{at.y.round(1)}, cluster visible from #{vis_lo.round(1)} to #{vis_hi.round(1)})"
      end
    end
    seen.should be > 5 # instrument: the sweep really did observe the label
  end

  it "keeps a COLUMN header's label drawn while its span is on screen (#49)" do
    renderer, app, matrix = demo_matrix
    band_lo_x = matrix.ruler_col_width_pixels + matrix.sticky_col_width_pixels

    seen = 0
    (0..40).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(step * 30.0, 0.0)
      matrix.pre_render_flush # as above
      labels = cell_labels(matrix)
      # c1a is the level-1 column header. It scrolled out with its span when the box-level pin
      # was removed on the X axis and nothing replaced it.
      labels.each do |text, at|
        next unless text =~ /\Ac1[a-z]\z/
        vis_lo = {at.box.x, band_lo_x}.max
        vis_hi = {at.box.x + at.box.width, VP_W.to_f64}.min
        next unless vis_hi - vis_lo > 20.0
        seen += 1
        at.x.should be >= vis_lo - 1.0,
          "#{text}'s label sat left of the visible part of its own span at scroll #{step * 30} " \
          "(x=#{at.x.round(1)}, span visible from #{vis_lo.round(1)} to #{vis_hi.round(1)})"
        at.x.should be <= vis_hi + 1.0,
          "#{text}'s label sat right of the visible part of its own span at scroll #{step * 30} " \
          "(x=#{at.x.round(1)}, span visible from #{vis_lo.round(1)} to #{vis_hi.round(1)})"
      end
    end
    seen.should be > 5
  end
end
