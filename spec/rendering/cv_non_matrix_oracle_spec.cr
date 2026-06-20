require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/layer_box"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/rendering/cache_validation"

# The non-matrix synthetic-pixel oracle. The immediate-mode
# validator auto-covers viewport_cache content layers but is BLIND to non-matrix overlay/window
# layers (combo popups, menus, buttons). A NON-scrolling layer
# has scroll_offset=0, so the immediate path positions correctly; opting it in via Layer#cv_validate
# lets the validator catch a stale-cache there too. This proves the mechanism works.
{% if flag?(:cache_validation) %}
  # Synthetic, solid-color (no AA jitter), can silently change its to_primitives() output without
  # invalidating its cache — the exact stale-cache shape, on a non-matrix layer.
  class NonMatrixStaleWidget < CrymbleUI::Widget
    @stale = false

    def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
      CrymbleUI::Size.new(80.0, 24.0)
    end

    def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
      @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
      color = @stale ? CrymbleUI::Color.new(0, 200, 0, 255) : CrymbleUI::Color.new(200, 0, 0, 255)
      [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), color)] of CrymbleUI::DrawPrimitive
    end

    def go_stale! # change output WITHOUT mark_needs_render / invalidate — the bug
      @stale = true
    end
  end

  describe "non-matrix cv oracle (Layer#cv_validate)" do
    before_each { CrymbleUI::CacheValidation.suite_gate = false } # this is a validator self-test

    it "catches a stale cache on an opted-in NON-matrix layer" do
      # LayerBox is the generic overlay layer-owner — the SAME non-viewport_cache layer kind that
      # combo popups / menus use. Host the synthetic widget there.
      window = CrymbleUI::Window.new("Test", 200, 120)
      box = CrymbleUI::LayerBox.new(x: 10.0, y: 10.0, width: 80.0, height: 48.0, z_index: 10, id: "box")
      widget = NonMatrixStaleWidget.new(id: "synthetic")
      sibling = NonMatrixStaleWidget.new(id: "sibling") # stays fresh; dirtying it forces a layer render
      box.add_child(widget)
      box.add_child(sibling)
      window.add_child(box)
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 120)
      app = TestApp.new
      app.root_widget = window
      app.build_tree
      window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 120.0)), CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app) # widget cached in its widget_backend; layer clean

      # Opt the box's (non-matrix, non-viewport_cache) overlay layer into validation.
      layer = box.layer
      layer.should_not be_nil
      layer.not_nil!.viewport_cache.should be_false # confirm this is NOT a matrix content layer
      layer.not_nil!.cv_validate = true

      CrymbleUI::CacheValidation.clear_failures!
      CrymbleUI::CacheValidation.enable(:immediate_mode)

      # Clean frame — the (cached) buffer matches a fresh immediate render.
      renderer.render_frame(app)
      CrymbleUI::CacheValidation.failures.should be_empty

      # Silently go stale (output changes, cache NOT invalidated). The widget stays clean, so the
      # fast path keeps its stale (red) pixels in the buffer. Dirty the SIBLING to force the layer
      # to re-render (the stale widget itself is never re-rendered) — exactly the matrix stale test's
      # trick. Now the buffer (stale red) diverges from the fresh immediate render (green) → the
      # validator MUST flag it. Without the cv_validate opt-in this layer would be invisible to it.
      widget.go_stale!
      box.layer.not_nil!.mark_needs_render(sibling)
      renderer.render_frame(app)
      CrymbleUI::CacheValidation.failures.should_not be_empty
    end
  end
{% end %}
