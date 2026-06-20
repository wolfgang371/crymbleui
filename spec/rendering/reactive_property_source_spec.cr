require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/text"
require "../../src/testing/test_renderer"

# reactive_property fields are tracked Sources. The getter is read in to_primitives, so it
# AUTO-CAPTURES: setting a DIFFERENT value re-renders with NO explicit mark_needs_render (the value edge
# can't be forgotten), while setting the SAME value is a no-op (the equality gate suppresses a spurious
# re-render). Verified through the user-visible pull decision (render_frame_if_needed), not internal state.
describe "reactive_property auto-capture + equality gate" do
  it "renders on a changed value, idles on an unchanged one — with no mark_needs_render" do
    window = CrymbleUI::Window.new("Test", 160, 60)
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    text = CrymbleUI::Text.new(text: "hello", id: "t")
    vstack.add_child(text)
    window.add_child(vstack)
    renderer = CrymbleUI::Testing::TestRenderer.new(160, 60)
    app = TestApp.new
    app.root_widget = window
    app.build_tree
    window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(160.0, 60.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Same value → the equality gate suppresses any re-render (the pull trigger does not fire).
    text.text = "hello"
    renderer.render_frame_if_needed(app).should be_false

    # Different value → to_primitives auto-captured `text`, so the Source.set marks the node stale and
    # the frame aggregate moves → a frame renders. No mark_needs_render is issued anywhere.
    text.text = "world"
    renderer.render_frame_if_needed(app).should be_true

    # And it settles back to idle once rendered.
    renderer.render_frame_if_needed(app).should be_false
  end

  it "auto-captures a nilable reactive_property (background_color) the same way" do
    window = CrymbleUI::Window.new("Test", 160, 60)
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    text = CrymbleUI::Text.new(text: "x", id: "t", background_color: CrymbleUI::Color.new(10, 20, 30))
    vstack.add_child(text)
    window.add_child(vstack)
    renderer = CrymbleUI::Testing::TestRenderer.new(160, 60)
    app = TestApp.new
    app.root_widget = window
    app.build_tree
    window.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(160.0, 60.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    text.background_color = CrymbleUI::Color.new(10, 20, 30) # same → no-op
    renderer.render_frame_if_needed(app).should be_false
    text.background_color = CrymbleUI::Color.new(99, 0, 0) # changed → renders
    renderer.render_frame_if_needed(app).should be_true
  end
end
