require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Blit-shift slot bookkeeping at FRACTIONAL layer bounds — the band where the old
# term-wise ties-even slot math diverged from the render stamp's difference-first
# flooring (they agree at whole coords, which is why the integer-bounds blit-shift
# specs never caught it). The matrix sits inside a fractional-padding wrapper so its
# content layer lands at fractional bounds; a scroll past cache_extent then triggers
# real blit-shift recenters whose slot keys must classify every cell correctly —
# wrong keys mis-shift slots onto stale pixels (wrong cell data) or spuriously
# dispose cells.
#
# Also pins the negative-fractional cull band behaviorally: after scrolling to a
# mid-cell offset the top row straddles the layer edge at negative-fractional
# layer-local y; the DISPOSITION oracle (never pixels — the retained-pixel law)
# asserts the straddling cell still renders.

class FractionalBoundsMatrixApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 1400, 900) do
      # Fractional padding → the matrix and its content layer sit at fractional bounds;
      # expanded so the matrix fills the window (a loose vstack would collapse it to
      # its minimal height and the wheel events would miss it).
      vstack(padding: 10.3) do
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(rows: 100, cols: 20, id: "frac_grid"))
        end
      end
    end
  end
end

private def frac_setup
  renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
  app = FractionalBoundsMatrixApp.new
  app.build_tree
  renderer.settle_rendering(app)
  matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
  {renderer, app, matrix}
end

describe "VirtualMatrix blit-shift at fractional layer bounds", tags: "slow" do
  it "layer bounds are genuinely fractional (fixture sanity)" do
    _renderer, _app, matrix = frac_setup
    layer = matrix.content_layer.not_nil!
    (layer.bounds.y % 1.0).should_not eq(0.0)
  end

  it "preserves correct cell data across a blit-shift scroll and round-trip" do
    renderer, app, matrix = frac_setup
    layer = matrix.content_layer.not_nil!
    initial_origin = layer.buffer_origin
    center = CrymbleUI::Vec2.new(700.0, 450.0)

    # Scroll well past cache_extent → real blit-shift recenters at fractional bounds.
    12.times do
      matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)

    matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
    matrix.scroll_offset.y.should be > 150.0 # the wheel really scrolled the matrix
    matrix.content_layer.not_nil!.buffer_origin.should_not eq(initial_origin) # recenter happened

    # Every active cell's text must match its content coordinates (default adapter
    # paints "row,col") — a mis-shifted slot would show a stale neighbor's text.
    wrong = [] of String
    matrix.active_cells.each do |(row, col), w|
      if t = w.as?(CrymbleUI::Text)
        wrong << "#{row},#{col}=#{t.text}" unless t.text == "#{row},#{col}"
      end
    end
    wrong.should be_empty

    # Round-trip back to the top: another recenter, same integrity.
    10.times do
      matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
      matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
      renderer.render_frame(app)
    end
    renderer.settle_rendering(app)
    matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
    wrong2 = [] of String
    matrix.active_cells.each do |(row, col), w|
      if t = w.as?(CrymbleUI::Text)
        wrong2 << "#{row},#{col}=#{t.text}" unless t.text == "#{row},#{col}"
      end
    end
    wrong2.should be_empty
  end

  it "preserves correct cell data across a column-resize blit-shift at fractional bounds" do
    renderer, app, matrix = frac_setup
    abs = matrix.absolute_bounds
    # Column 0's right border in the ruler strip (ruler_col_w 40 + col_w 103 at zoom 1.0),
    # in ABSOLUTE coords — the matrix itself sits at fractional bounds.
    border = CrymbleUI::Vec2.new(abs.x + 143.0, abs.y + 10.0)
    app.handle_mouse_down(border)
    app.handle_mouse_move(CrymbleUI::Vec2.new(border.x + 40.0, border.y))
    renderer.render_frame(app)
    app.handle_mouse_up(CrymbleUI::Vec2.new(border.x + 40.0, border.y))
    renderer.settle_rendering(app)

    matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
    matrix.get_col_width(0).should be > 5.0 # the drag really widened col 0 (default 5.0)
    wrong = [] of String
    matrix.active_cells.each do |(row, col), w|
      if t = w.as?(CrymbleUI::Text)
        wrong << "#{row},#{col}=#{t.text}" unless t.text == "#{row},#{col}"
      end
    end
    wrong.should be_empty # a mis-classified resize slot would surface a stale neighbor
  end

  it "renders a cell straddling the top edge at negative-fractional layer-local y (disposition)" do
    renderer, app, matrix = frac_setup
    center = CrymbleUI::Vec2.new(700.0, 450.0)
    # Scroll to a mid-cell offset: the top visible row straddles the viewport top.
    matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
    renderer.settle_rendering(app)

    matrix = app.find("frac_grid").as(CrymbleUI::VirtualMatrix)
    # Force a fresh render of all cells so dispositions are recorded THIS frame.
    matrix.content_layer.not_nil!.mark_needs_clear_and_render
    renderer.render_frame(app)

    # The TOP edge is the band under test; restrict to columns fully visible
    # horizontally (the rightmost partially-clipped column is a separate,
    # pre-existing right-edge concern outside this spec's contract).
    top_row = matrix.active_cells.keys.map(&.[0]).min
    top_cells = matrix.active_cells.select { |k, _| k[0] == top_row && k[1] < 10 }.values
    top_cells.should_not be_empty
    rendered = top_cells.count { |c| !renderer.widget_disposition(c).nil? }
    rendered.should eq(top_cells.size)
  end
end
