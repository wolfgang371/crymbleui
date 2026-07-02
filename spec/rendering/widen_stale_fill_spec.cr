require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/expanded"
require "../../src/widgets/window"

# FAITHFUL reproduction of the live "white strip at the right edge of an Expanded HStack on
# window widen" bug (docs/BUGFIXING.md "stale primitive cache → white lines" class).
#
# The earlier spec used TWO renderers (narrow then a FRESH wide one) — a fresh renderer
# first-renders the inner hstack at the wide size, so nothing is ever stale. This drives ONE
# renderer across a real resize (render narrow → resize → render wide), so the inner hstack's
# fill_rect cached at the narrow width is reused on its grown widget_backend. If the primitive
# cache is not invalidated on the widen, the right-edge strip composites as the window background.

private def build_demo2
  inner2 = CrymbleUI::HStack.new(
    id: "inner2", padding: 10.0,
    background_color: CrymbleUI::Color.new(80, 80, 120, 255))
  inner2.add_child(CrymbleUI::Text.new("Expanded 2 (50%)", font_scale: 1,
    color: CrymbleUI::Color.new(200, 200, 255, 255)))
  exp2 = CrymbleUI::Expanded.new
  exp2.add_child(inner2)

  inner1 = CrymbleUI::HStack.new(
    padding: 10.0, background_color: CrymbleUI::Color.new(120, 80, 80, 255))
  inner1.add_child(CrymbleUI::Text.new("Expanded 1 (50%)", font_scale: 1))
  exp1 = CrymbleUI::Expanded.new
  exp1.add_child(inner1)

  outer = CrymbleUI::HStack.new(
    spacing: 10.0, padding: 10.0,
    background_color: CrymbleUI::Color.new(60, 60, 70, 255))
  outer.add_child(CrymbleUI::Text.new("Start", font_scale: 1))
  outer.add_child(exp1)
  outer.add_child(exp2)
  outer.add_child(CrymbleUI::Text.new("End", font_scale: 1))

  window = CrymbleUI::Window.new("Test", 600, 200)
  window.add_child(outer)
  app = TestApp.new
  app.root_widget = window
  {app, inner2}
end

private def right_edge_pixel(renderer, widget)
  b = widget.absolute_bounds
  col = (b.x + b.width).to_i - 1
  row = (b.y + b.height / 2.0).to_i
  {renderer.backend.get_pixel(col, row), col, row, b}
end

describe "Expanded HStack widen — stale fill (one renderer, real resize)" do
  it "single widen 600→900 keeps the right edge purple (no stale-fill white strip)" do
    app, inner2 = build_demo2
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 200)
    renderer.settle_rendering(app)

    # Real resize: same renderer, lay out + render at the new size, reusing backends.
    renderer.resize(900, 200)
    app.root.not_nil!.mark_needs_layout
    renderer.render_frame(app)

    inner2.absolute_bounds.width.should be > 350.0 # sanity: it expanded
    pixel, col, row, b = right_edge_pixel(renderer, inner2)
    purple = CrymbleUI::Color.new(80, 80, 120, 255)
    pixel.should eq(purple),
      "right edge (#{col},#{row}) should be purple #{purple.inspect}, got #{pixel.inspect}; abs=#{b.inspect}"
  end

  it "incremental widen sweep (drag-like) keeps the right edge purple at every step" do
    app, inner2 = build_demo2
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 200)
    renderer.settle_rendering(app)

    purple = CrymbleUI::Color.new(80, 80, 120, 255)
    max_strip = 0
    (610..900).step(5) do |w|
      renderer.resize(w, 200)
      app.root.not_nil!.mark_needs_layout
      renderer.render_frame(app)
      b = inner2.absolute_bounds
      row = (b.y + b.height / 2.0).to_i
      right = (b.x + b.width).to_i - 1
      # scan inward from the right edge: how many consecutive non-purple px (the strip width)?
      strip = 0
      while strip < 40
        break if renderer.backend.get_pixel(right - strip, row) == purple
        strip += 1
      end
      if strip > 0
        max_strip = Math.max(max_strip, strip)
        px = renderer.backend.get_pixel(right, row)
        puts "  width=#{w}: inner2 w=#{b.width.round(2)} x=#{b.x.round(2)} → #{strip}px strip, edge px=#{px.inspect}"
      end
    end
    puts "  MAX STRIP = #{max_strip}px"
    max_strip.should eq(0), "stale-fill white strip up to #{max_strip}px wide appeared during the widen sweep"
  end
end
