require "../spec_helper"
require "../../src/widgets/layer_box.cr"
require "../../src/testing/test_renderer"

# Self-test for the -Dverify_bounds sibling-overlap re-layout check (layer_renderer's
# warn_sibling_overlaps). The release check runs only on a layer's FIRST render, which is how an
# overlap introduced by a LATER layout change reached a beta tester. Under the flag every re-LAYOUT
# re-checks it, as a warn + counter.
#
# Without this example the guard would be an unvalidated instrument: it currently reports nothing on
# the whole suite, and "silent" and "broken" look identical. Here a deliberate overlap must be seen.
{% if flag?(:verify_bounds) %}
  # Stacks its two children at the SAME position on demand — the overlap has to be introduced AFTER
  # the first render, since first-render overlaps are already caught (and raised) in release.
  class OverlappingStack < CrymbleUI::Widget
    property collapse = false

    def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
      CrymbleUI::Size.new(80.0, 48.0)
    end

    def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
      @bounds = CrymbleUI::Rect.new(position, measure(constraints))
      @children.each_with_index do |child, i|
        y = collapse ? 0.0 : (i * 24.0)
        child.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(80.0, 24.0)), CrymbleUI::Vec2.new(0.0, y))
      end
    end
  end

  describe "sibling-overlap guard (-Dverify_bounds)" do
    it "reports an overlap introduced by a re-layout, and stays silent while the layout is sane" do
      window = CrymbleUI::Window.new("T", 200, 120)
      box = CrymbleUI::LayerBox.new(x: 10.0, y: 10.0, width: 80.0, height: 48.0, z_index: 10, id: "box")
      stack = OverlappingStack.new(id: "stack")
      stack.add_child(CrymbleUI::Button.new("A") { })
      stack.add_child(CrymbleUI::Button.new("B") { })
      box.add_child(stack)
      window.add_child(box)
      renderer = CrymbleUI::Testing::TestRenderer.new(200, 120)
      app = TestApp.new
      app.root_widget = window
      app.build_tree
      renderer.settle_rendering(app)

      # A re-layout that keeps the children apart must not report anything.
      CrymbleUI::Widget.reset_sibling_overlap_warnings
      stack.mark_needs_layout
      renderer.render_frame(app)
      CrymbleUI::Widget.sibling_overlap_warnings.should eq(0)

      # …and one that stacks them must.
      CrymbleUI::Widget.reset_sibling_overlap_warnings
      stack.collapse = true
      stack.mark_needs_layout
      renderer.render_frame(app)
      CrymbleUI::Widget.sibling_overlap_warnings.should be > 0
    end
  end
{% end %}
