require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/scroll_view"
require "../../src/layout/vstack"

# A CHILD THAT SHRINKS ON BOTH AXES MUST NOT LEAVE ITS OLD SELF BEHIND.
#
# Wolfgang, 2026-09-17, narrowing the About dialog: after a few drags the panel showed the logo's
# footer text stamped four times at four different sizes, with the paragraph below drawn over
# itself. Ghosts, not distortion — stale pixels where the picture used to be.
#
# It appeared the moment Image#measure began preserving its declared aspect ratio, and that is a
# giveaway rather than a cause: before, a narrowing box changed the image's WIDTH only, so every
# repaint covered the same rows and whatever fails to clear vacated area was never asked to. Scaling
# both axes together makes a child give back height as well, which is the case with no coverage.
#
# Modelled with a SOLID-COLOUR widget rather than a real Image, deliberately and at a cost worth
# stating: an ImageSource with no bytes paints nothing in the test backend, so a spec built on one
# could report clean while proving nothing. What is reproduced here is the mechanism — a child
# vacating area on both axes inside a viewport_cache ScrollView — and solid fills keep the cv
# comparison free of anti-aliasing jitter. It does NOT exercise the image decode path.
#
# Under -Dcache_validation the validator re-renders each viewport-cache content layer from scratch
# and compares it pixel-by-pixel with the cached buffer, so spec_helper fails the example on any
# divergence. No spec in that gate had a child that shrinks on both axes, which is why it never fired.
private class AspectCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  COLOR = CrymbleUI::Color.new(200, 60, 60, 255)

  def initialize(@asked : Float64, id : String? = nil)
    super(id: id)
  end

  # The same rule Image#measure now follows: one factor for both axes, never enlarging.
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    scale = {constraints.max_width / @asked, constraints.max_height / @asked, 1.0}.min
    scale = 1.0 unless scale.finite?
    CrymbleUI::Size.new(@asked * scale, @asked * scale)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), COLOR)
    end
  end
end

private class PlainCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  COLOR = CrymbleUI::Color.new(45, 50, 55, 255)

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new({constraints.max_width, 400.0}.min, 24.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), COLOR)
    end
  end
end

describe "a child shrinking on both axes inside a ScrollView (cv)" do
  it "leaves no ghost of its previous size when the panel is narrowed in steps" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1200, 900)
    panel = CrymbleUI::WindowPanel.new("About", 40.0, 40.0, 700.0, 620.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    stack = CrymbleUI::VStack.new(spacing: 5.0, padding: 10.0)
    stack.add_child(AspectCell.new(560.0, id: "logo"))
    8.times { stack.add_child(PlainCell.new) }
    sv.set_content(stack)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    logo = app.find("logo").not_nil!
    trail = [] of String
    trail << "start #{logo.bounds.width.round(1)}x#{logo.bounds.height.round(1)}"

    [560.0, 470.0, 380.0, 300.0, 240.0].each do |w|
      panel.width = w
      panel.mark_needs_layout
      app.request_rebuild
      renderer.settle_rendering(app)
      logo = app.find("logo").not_nil!
      trail << "#{w.round.to_i}->#{logo.bounds.width.round(1)}x#{logo.bounds.height.round(1)}"
    end

    # Instrument check: it really did give back area on BOTH axes, which is the precondition. A
    # clean cv verdict over a child that never shrank would prove nothing at all.
    f = trail.first.split(" ").last.split("x").map(&.to_f)
    l = trail.last.split("->").last.split("x").map(&.to_f)
    l[0].should be < f[0], "width never shrank: #{trail}"
    l[1].should be < f[1], "height never shrank: #{trail}"
  end
end
