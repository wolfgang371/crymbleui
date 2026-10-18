require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A fitted's layer under the dual renderer: the cached buffer (per-widget textures, selective re-renders) must
# equal the immediate-mode ground truth at fractional factors and across factor changes. Flat colours only, so
# no anti-aliasing can differ between the two. Both paths go through the same scaling of the primitives; what
# cv adds is that the cached path's re-captured backgrounds and the immediate path's painter order agree.
#
# Built by tools/cv-coherency.sh with -Dcache_validation AND -Dverify_bounds: no sibling overlap and no
# containment warning either - a child larger than its fitted (factor < 1) is drawn scaled, not escaping it.
# Counters stay out (cv's second render per frame inflates them).

FITCV_RED   = CrymbleUI::Color.new(200, 40, 40, 255)
FITCV_BLUE  = CrymbleUI::Color.new(40, 40, 200, 255)
FITCV_GREEN = CrymbleUI::Color.new(40, 160, 40, 255)

class FitCvSwatch < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@w : Float64, @h : Float64, @color : CrymbleUI::Color)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@w, @h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(@w, @h))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives { fill_background(bounds, @color) }
  end
end

class FitCvApp < CrymbleUI::App
  def initialize(@wide : Bool = false)
    super()
  end

  def build : CrymbleUI::Widget
    window("cv", 300, 300) do
      fitted(id: "f") do
        hstack(spacing: 0.0) do
          widget(FitCvSwatch.new(@wide ? 333.0 : 33.0, 40.0, FITCV_RED))
          vstack(padding: 3.0, spacing: 0.0, background_color: FITCV_GREEN) do
            widget(FitCvSwatch.new(27.0, 17.0, FITCV_BLUE))
            text("ok")
          end
          widget(FitCvSwatch.new(33.0, 40.0, FITCV_BLUE))
        end
      end
    end
  end
end

private def fitcv_run(app : CrymbleUI::App, w : Int32, h : Int32) : CrymbleUI::Testing::TestRenderer
  renderer = CrymbleUI::Testing::TestRenderer.new(w, h)
  app.build_tree
  renderer.render_frame(app)
  app.find("f").not_nil!.layer.not_nil!.cv_validate = true
  renderer.settle_rendering(app)
  renderer
end

private def fitcv_resize(app : CrymbleUI::App, renderer : CrymbleUI::Testing::TestRenderer, w : Int32, h : Int32) : Nil
  renderer.resize(w, h)
  app.root.not_nil!.mark_needs_layout
  renderer.settle_rendering(app)
end

{% if flag?(:cache_validation) %}
  describe "fitted under the dual renderer" do
    it "keeps the cached layer equal to the ground truth at fractional factors, across factor changes" do
      CrymbleUI::Widget.reset_sibling_overlap_warnings
      CrymbleUI::Widget.reset_containment_warnings
      app = FitCvApp.new
      r = fitcv_run(app, 274, 400)
      [{301, 400}, {263, 400}, {274, 157}, {388, 131}, {274, 400}].each do |(w, h)|
        fitcv_resize(app, r, w, h)
        CrymbleUI::CacheValidation.assert_no_failures!
      end
      r.exceptions_caught.should eq(0)
      {% if flag?(:verify_bounds) %}
        CrymbleUI::Widget.sibling_overlap_warnings.should eq(0)
        CrymbleUI::Widget.containment_warnings.should eq(0)
      {% end %}
    end

    it "draws a child wider than its box scaled down, inside it" do
      CrymbleUI::Widget.reset_sibling_overlap_warnings
      CrymbleUI::Widget.reset_containment_warnings
      app = FitCvApp.new(wide: true)
      r = fitcv_run(app, 274, 400)
      fitted = app.find("f").not_nil!
      (fitted.children.first.bounds.width > fitted.bounds.width).should be_true # coverage: factor < 1
      fitcv_resize(app, r, 251, 400)
      CrymbleUI::CacheValidation.assert_no_failures!
      r.exceptions_caught.should eq(0)
      {% if flag?(:verify_bounds) %}
        CrymbleUI::Widget.sibling_overlap_warnings.should eq(0)
        CrymbleUI::Widget.containment_warnings.should eq(0)
      {% end %}
    end
  end
{% end %}
