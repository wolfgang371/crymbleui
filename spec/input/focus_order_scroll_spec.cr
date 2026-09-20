require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# Tab order and arrow-key navigation are VISUAL concepts: "the next one down" means the next one
# down ON THE SCREEN. Both were computed from `absolute_bounds`, the laid-out position, so once a
# ScrollView between the candidates was scrolled, the order stopped matching what the user sees —
# Tab jumping to a control far from the one that looks next, and Up landing on the wrong row.
# Widgets inside the SAME scrolled view all shift together, so the defect needs candidates on
# both sides of a scroll boundary, which is exactly embrace's Config tab plus the panel's own
# controls.
private def focus_fixture(scroll : Float64)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", 400, 300)
  root = CrymbleUI::VStack.new(spacing: 0.0)

  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, max_height: 150.0)
  inner = CrymbleUI::VStack.new(spacing: 0.0)
  12.times { |i| inner.add_child(CrymbleUI::Button.new("in#{i}", id: "in#{i}") { }) }
  sv.set_content(inner)
  root.add_child(sv)

  outside = CrymbleUI::Button.new("outside", id: "outside") { }
  root.add_child(outside)

  window.add_child(root)
  app.root_widget = window
  renderer.render_frame(app)
  sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll))
  renderer.render_frame(app)
  {app, window, sv, outside}
end

describe "focus order across a scroll boundary" do
  it "cycles in the order the user sees" do
    _app, window, sv, outside = focus_fixture(120.0)
    sv.scroll_offset.y.should be > 0.0 # instrument: really scrolled

    order = CrymbleUI::FocusCycler.new.collect_focusable_widgets(window)
    order.size.should be > 2

    painted = order.map { |w| w.viewport_bounds.y }
    # Reading order means monotonic DOWN THE SCREEN.
    painted.each_cons(2) { |pair| pair[1].should be >= pair[0] }

    # And the widget painted above `outside` must come before it.
    above = order.select { |w| w.viewport_bounds.y < outside.viewport_bounds.y }
    above.includes?(outside).should be_false
    above.empty?.should be_false
  end

  it "navigates up to the row painted above, not the one laid out above" do
    _app, window, _sv, outside = focus_fixture(120.0)
    focusables = CrymbleUI::FocusCycler.new.collect_focusable_widgets(window)

    target = CrymbleUI::FocusNavigator.new.find_neighbor(outside, focusables, :up)
    target.should_not be_nil
    picked = target.not_nil!

    # The property, without re-deriving the navigator's scoring: it is ABOVE on screen, and
    # nothing else lies between it and where we started. (A row clipped by the viewport is still
    # a legitimate target — focus scrolls it into view — so "visible" is not the test.)
    picked.viewport_bounds.y.should be < outside.viewport_bounds.y
    between = focusables.reject { |w| w == outside || w == picked }.select do |w|
      w.viewport_bounds.y > picked.viewport_bounds.y && w.viewport_bounds.y < outside.viewport_bounds.y
    end
    between.map(&.id).should eq([] of String?)

    # And it is NOT what laid-out order would have chosen: that row is elsewhere on screen.
    content_pick = focusables.reject { |w| w == outside }
      .select { |w| w.absolute_bounds.y < outside.absolute_bounds.y }
      .max_by { |w| w.absolute_bounds.y }
    picked.id.should_not eq(content_pick.not_nil!.id)
  end
end
