require "../spec_helper"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"

# cached_primitives keyed on a summed revision
# (content_rev + theme_rev + zoom_rev + layout_rev) instead of `needs_render? || @cached_primitives.nil?`.
#
# A widget that reads Theme.current LIVE in to_primitives must regenerate its
# cached primitives after a theme swap — even though Theme.set issues NO mark_needs_render. Fails
# with the stale `needs_render? || nil` key (it keeps the old primitives); passes once the cache's
# validity key includes theme_rev and Theme.set bumps it.

# Reads the theme LIVE (no construction-time snapshot). Default cache_policy
# is Dynamic, so this exercises the exact `needs_render? || nil` branch the re-keying targets.
private class LiveThemeWidget < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(50.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
      CrymbleUI::Theme.current.button_background)] of CrymbleUI::DrawPrimitive
  end
end

private def fill_color(prims : Array(CrymbleUI::DrawPrimitive)) : CrymbleUI::Color
  prims[0].as(CrymbleUI::FillRect).color
end

describe "cached_primitives keyed on theme_rev" do
  it "regenerates cached primitives on a theme swap without explicit invalidation" do
    begin
      CrymbleUI::Theme.set(:light)
      light = CrymbleUI::Theme.current.button_background

      window = CrymbleUI::Window.new("Test", 120, 80)
      vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
      widget = LiveThemeWidget.new(id: "lt")
      vstack.add_child(widget)
      window.add_child(vstack)
      renderer = CrymbleUI::Testing::TestRenderer.new(120, 80)
      app = TestApp.new
      app.root_widget = window
      app.build_tree
      window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(120.0, 80.0)), CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)

      # Precondition: the widget is clean (rendered, node valid) and its primitives cache holds the light color.
      widget.needs_render?.should be_false
      fill_color(widget.get_primitives(widget.bounds)).should eq light

      # Swap the theme. Theme.set issues NO mark_needs_render (no @state PUSH). The widget's primitives
      # node AUTO-CAPTURED Theme.current during its last recompute, so the theme Source bump marks the
      # node value-stale — the PULL path detects the change with no explicit invalidation.
      CrymbleUI::Theme.set(:dark)
      dark = CrymbleUI::Theme.current.button_background
      dark.should_not eq light            # precondition: the two themes actually differ
      # needs_render? is now node-derived (node stale?), so the auto-captured theme edge
      # correctly reports render-needed — without a single mark_needs_render. (Previously this read false
      # because the @state push flag was the proxy; the node is the precise, unforgettable signal now.)
      widget.needs_render?.should be_true

      # The primitives cache MUST now reflect the dark theme.
      fill_color(widget.get_primitives(widget.bounds)).should eq dark
    ensure
      CrymbleUI::Theme.set(:light) # restore the global theme for other specs
    end
  end
end
