require "../spec_helper"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

private class ResizeHarnessApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Host", 400, 300) { text("hello") }
  end
end

# SFML marks the root for layout in its Resized handler, so the next frame lays the window out at the new
# size; the headless resize must do the same, and at once, so the render-if-needed decision sees it too.
describe "TestRenderer#resize" do
  it "is a reason to render, and the window is laid out at the new size" do
    app = ResizeHarnessApp.new
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app.build_tree
    r.settle_rendering(app)
    r.render_frame_if_needed(app).should be_false
    r.resize(700, 300)
    r.render_frame_if_needed(app).should be_true
    app.root.not_nil!.bounds.width.should eq(700.0)
  end
end
