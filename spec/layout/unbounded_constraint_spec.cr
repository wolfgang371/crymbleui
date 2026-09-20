require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# An UNBOUNDED constraint must stay unbounded on the way down to children.
#
# A scrolling axis measures its content with `max = Float64::INFINITY` ("take what you need").
# The stacks derived the inner constraint with `(max - padding*2).clamp(0.0, Float64::MAX)` —
# and `INFINITY.clamp(0, MAX)` is MAX, a FINITE number. Every downstream guard that asks
# `finite?` then waves it through: a ScrollView offered a finite width takes all of it, so the
# outer content measured 1.79e308 wide, its buffer could not be sized, its layer never got a
# backend, and the whole view rendered NOTHING. Found by the scroll sweep, not by a report — a
# nested scroller inside a horizontally scrolling one is simply not in embrace yet.
class UnbCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder
  COL = CrymbleUI::Color.new(0, 255, 255, 255)

  def initialize
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(300.0, 40.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(300.0, 40.0))
  end

  def to_primitives(b : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, b.width, b.height), COL) }
  end
end

describe "unbounded constraints through a stack" do
  it "stays unbounded, so a nested scroller does not swallow the width" do
    vstack = CrymbleUI::VStack.new(spacing: 0.0)
    vstack.add_child(UnbCell.new)
    # A ScrollView takes all the width it is OFFERED. Offered a finite one it is entitled to;
    # the bug was offering it a finite one (MAX) where the answer was "unbounded".
    nested = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 60.0)
    inner_content = CrymbleUI::VStack.new(spacing: 0.0)
    inner_content.add_child(UnbCell.new)
    nested.set_content(inner_content)
    vstack.add_child(nested)

    measured = vstack.measure(CrymbleUI::BoxConstraints.new(
      min_width: 0.0, max_width: Float64::INFINITY,
      min_height: 0.0, max_height: Float64::INFINITY
    ))
    measured.width.finite?.should be_true
    measured.width.should be < 10_000.0
  end

  it "renders a ScrollView nested inside a horizontally scrolling ScrollView" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("t", 400, 300)

    outer = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal,
                                      max_height: 260.0, max_width: 200.0, id: "outer")
    content = CrymbleUI::VStack.new(spacing: 0.0)
    4.times { content.add_child(UnbCell.new) }
    inner = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical,
                                      max_height: 60.0, id: "inner")
    ic = CrymbleUI::VStack.new(spacing: 0.0)
    3.times { ic.add_child(UnbCell.new) }
    inner.set_content(ic)
    content.add_child(inner)
    outer.set_content(content)

    window.add_child(outer)
    app.root_widget = window
    renderer.render_frame(app)
    renderer.render_frame(app)

    outer.content_size.width.finite?.should be_true
    outer.content_size.width.should be < 10_000.0
    outer.layer.should_not be_nil
    outer.layer.not_nil!.backend.should_not be_nil

    painted = 0
    (0...renderer.backend.height).each do |y|
      (0...renderer.backend.width).each { |x| painted += 1 if renderer.backend.get_pixel(x, y) == UnbCell::COL }
    end
    painted.should be > 0
  end
end
