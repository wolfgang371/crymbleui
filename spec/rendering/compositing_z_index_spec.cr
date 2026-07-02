require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/core/layer_owner"
require "../../src/dsl/primitive_builder"

# The compositor orders layers by the NEAREST ancestor that
# declares a compositing z-boundary, asked POLYMORPHICALLY (responds_to?
# :compositing_z_index) — not by type-checking WindowPanel/LayerBox/Popup. So
# (1) overlapping panels still order by z_index, and (2) ANY widget that opts into
# the capability participates — impossible under the old is_a?(WindowPanel).

# A minimal custom layer-owning widget that declares compositing_z_index — a type
# the renderer never heard of. Under is_a?(WindowPanel/LayerBox/Popup) its layer
# would be treated as root (Int32::MIN) and composite BELOW panels.
class ZProbe < CrymbleUI::Widget
  include CrymbleUI::LayerOwner
  include CrymbleUI::PrimitiveBuilder

  def initialize(@px : Float64, @py : Float64, @pw : Float64, @ph : Float64,
                 @z : Int32, @fill : CrymbleUI::Color, id : String? = nil)
    super(id: id)
    @internal_layer = CrymbleUI::Layer.new("zprobe_#{id}", CrymbleUI::Rect.zero,
      z_index: @z, background_color: CrymbleUI::Color.new(0, 0, 0, 0), owner_widget: self)
  end

  def compositing_z_index : Int32
    @z
  end

  def compute_bounds_for_layer(layer : CrymbleUI::Layer) : CrymbleUI::Rect
    @bounds
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@pw, @ph)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(@px, @py, @pw, @ph)
    if l = @internal_layer
      l.z_index = @z
      l.widgets.clear
      l.widgets << self
    end
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill) }
  end
end

private def render(window) : CrymbleUI::Testing::TestRenderer
  r = CrymbleUI::Testing::TestRenderer.new(400, 400)
  app = TestApp.new
  app.root_widget = window
  app.build_tree
  window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 400.0)), CrymbleUI::Vec2.zero)
  r.settle_rendering(app)
  r
end

describe "compositing z-order" do
  it "overlapping WindowPanels order by z_index (behaviour-preserving)" do
    window = CrymbleUI::Window.new("Test", 400, 400)
    low = CrymbleUI::WindowPanel.new("low", 20.0, 20.0, 200.0, 200.0)
    low.background_color = CrymbleUI::Color.new(200, 0, 0, 255) # red
    low.z_index = 0
    high = CrymbleUI::WindowPanel.new("high", 120.0, 120.0, 200.0, 200.0)
    high.background_color = CrymbleUI::Color.new(0, 0, 200, 255) # blue
    high.z_index = 10
    window.add_child(low); window.add_child(high)
    r = render(window)
    # Overlap interior (both panels' content areas cover (180,180), below both title bars);
    # higher z = blue on top.
    p = r.backend.get_pixel(180, 180).not_nil!
    {p.r, p.g, p.b}.should eq({0, 0, 200})
  end

  it "a CUSTOM widget opting into compositing_z_index composites above a panel (inversion proof)" do
    window = CrymbleUI::Window.new("Test", 400, 400)
    panel = CrymbleUI::WindowPanel.new("p", 20.0, 20.0, 200.0, 200.0)
    panel.background_color = CrymbleUI::Color.new(0, 0, 200, 255) # blue
    panel.z_index = 10
    probe = ZProbe.new(120.0, 120.0, 150.0, 150.0, 9999, CrymbleUI::Color.new(0, 200, 0, 255), id: "probe") # green, z above the panel
    window.add_child(panel); window.add_child(probe)
    r = render(window)
    # At the overlap (180,180), the custom widget (z 9999) must be ON TOP — green, not the
    # panel's blue. Under is_a?(WindowPanel) the probe would be root (Int32::MIN) → BELOW → blue.
    p = r.backend.get_pixel(180, 180).not_nil!
    {p.r, p.g, p.b}.should eq({0, 200, 0})
  end
end
