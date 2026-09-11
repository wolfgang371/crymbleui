require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Field report 2026-09-05 (image #37): a group header scrolling IN from the bottom "gets scrolled in
# oddly — the other way round like vruler 5 or 5/c2 5". Measured across a full sweep: while the
# group enters, its label moves 42px per 84px of scroll — HALF content speed — while the ruler
# number for the same row moves the full 84. `compound_axis` clamps the box at the viewport BOTTOM,
# so the box grows from below and its centre lags behind the content it belongs to.
#
# Pinning belongs to the LEADING edge only. A span arriving from the trailing edge rides in like
# every other cell; once its top reaches the sticky boundary it pins, and the half-speed drift on
# the way OUT is the sticky behaviour that was asked for in the first place.
class EnteringGroupAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @group : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...@rows).to_a, [2, 1, 0]}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    return { {row, col}, {row, col} } unless col == 0
    lo = (row // @group) * @group
    { {lo, 0}, {lo + @group - 1, 0} }
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: col == 0 ? "g#{row // @group}" : "#{row},#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

private def entering_matrix
  renderer = CrymbleUI::Testing::TestRenderer.new(500, 200)
  matrix = CrymbleUI::VirtualMatrix.new(EnteringGroupAdapter.new(24, 4), id: "entering_group")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(500.0, 200.0)), CrymbleUI::Vec2.zero)
  renderer.settle_rendering(app)
  {renderer, app, matrix}
end

private def label_y(matrix, key) : Float64?
  cell = matrix.active_cells[key]?
  return nil unless cell
  tp = cell.to_primitives(cell.absolute_bounds).select(CrymbleUI::DrawText).first?
  tp ? cell.bounds.y + tp.position.y : nil
end

describe "a group header entering from the trailing edge" do
  it "shows its label as soon as any of the group is on screen" do
    # HISTORY, because this example used to assert the opposite and the change was deliberate.
    #
    # An arriving group rides in at CONTENT SPEED — 12px of label per 12px of scroll —
    # because arriving at half speed looked wrong (field report #37, "scrolled in oddly"). The
    # cost was that a cluster taller than the viewport showed several rows with NO label at all,
    # since a label centred in the whole span only appears once the span's midpoint arrives. That
    # is what was reported on 2026-09-06 as "r1b is scrolling out albeit the cluster is still
    # visible!!".
    #
    # Both cannot hold. While a span arrives, its visible part is [span_top, viewport_bottom]:
    # the near edge moves with the rows, the far edge does not, so anything centred in that window
    # moves at HALF the span's speed. Wolfgang chose visibility over arrival speed (2026-09-07):
    # "we can live w/o content-speed arrival".
    #
    # So this now asserts what was bought: the label is on screen as soon as its group is, and it
    # tracks its rows monotonically rather than freezing or jumping backwards.
    renderer, app, matrix = entering_matrix
    band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
    band_hi = matrix.bounds.height

    previous = nil.as(Float64?)
    samples = 0
    (1..8).each do |step|
      scroll = step * 12.0
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll)
      renderer.settle_rendering(app)
      cell = matrix.active_cells[{8, 0}]?
      next unless cell
      break if cell.bounds.y <= band_lo # only while the span is still ARRIVING
      y = label_y(matrix, {8, 0})
      next unless y

      # Visible at all — the property the arrival speed was traded for.
      y.should be >= band_lo - 1.0, "the label was placed above the band at scroll #{scroll}"
      y.should be <= band_hi, "the label was still off screen at scroll #{scroll} (y=#{y.round(1)}) " \
                              "while its group was already on screen"
      if prev = previous
        samples += 1
        moved = prev - y
        moved.should be >= -0.5, "the label moved BACKWARDS at scroll #{scroll} (#{moved.round(1)}px)"
        moved.should be <= 12.5, "the label outran its own rows at scroll #{scroll} (#{moved.round(1)}px)"
      end
      previous = y
    end
    samples.should be > 2 # instrument: the sweep really did observe the arriving phase
  end

  it "holds its label in the visible part of the span, then lets its own end push it out" do
    # The report was that the group label SCROLLED OUT with the first row while the rest of
    # its cluster was still on screen. What it asked for is that the label stay with the part of
    # the cluster you can see. That property is preserved here; what changed is the mechanism.
    #
    # Until 2026-09-06 the box itself was pinned and clipped to the visible slice by
    # StickyMath.compound_axis, and the label rode along inside it — which is where the "half
    # speed" figure came from: it was the midpoint of a shrinking box, an artefact of the
    # mechanism rather than something the report asked for. The box now keeps its natural span
    # and the LABEL is placed by the shared rule (docs/ARCHITECTURE.md, "Where content sits in a
    # band"), the same one that places a ruler number and a row header — which is what stops a
    # group label and the rank cell beside it disagreeing, and removes the 1-3px jump the old
    # box pin made when it engaged (field report 2026-09-06 (a)).
    #
    # So this asserts the PROPERTY, not the pixel: while the span covers the band the label stays
    # inside what you can see, and once the span's own end arrives it is pushed out rather than
    # outliving its cluster.
    renderer, app, matrix = entering_matrix
    band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
    band_hi = matrix.bounds.height

    samples = 0
    (17..24).each do |step|
      matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, step * 12.0)
      renderer.settle_rendering(app)
      cell = matrix.active_cells[{8, 0}]?
      next unless cell
      y = label_y(matrix, {8, 0})
      next unless y

      # The span's own visible extent, in the same frame as the label.
      top = cell.bounds.y
      vis_lo = {top, band_lo}.max
      vis_hi = {top + cell.bounds.height, band_hi}.min
      next unless vis_hi - vis_lo > 20.0

      samples += 1
      y.should be >= vis_lo - 1.0,
        "the label sat above the visible part of its own span at scroll #{step * 12} " \
        "(y=#{y.round(1)}, span visible #{vis_lo.round(1)}..#{vis_hi.round(1)})"
      y.should be <= vis_hi + 1.0,
        "the label outlived its cluster at scroll #{step * 12} " \
        "(y=#{y.round(1)}, span visible #{vis_lo.round(1)}..#{vis_hi.round(1)})"
    end
    samples.should be > 2 # instrument: the sweep really did observe the covering phase
  end
end
