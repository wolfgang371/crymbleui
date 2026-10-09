require "../spec_helper"
require "../../src/widgets/virtual_matrix"

# AN EXAMPLE'S APP IS RELEASED BEFORE THE NEXT. Nothing else releases a discarded app: its widgets stay registered
# with the global zoom and theme Sources, and a grid's overlays and rulers (standing on its layers, not in any
# @children) hold the grid - so every example's trees, layers and frame buffers stayed reachable, and the suite grew
# to the machine's memory limit. TestRenderer records every app it renders while armed (spec_helper arms it) and
# releases them all, the way a rebuild releases a discarded tree. Read on the zoom Source's dependents: every
# widget's pull node that read the zoom is one.

class RarAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], (1...6).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row}:#{col}")
  end
end

class RarApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(CrymbleUI::VirtualMatrix.new(RarAdapter.new, id: "g")) }
  end
end

private def rar_rendered : {RarApp, CrymbleUI::Testing::TestRenderer}
  app = RarApp.new
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  renderer.settle_rendering(app)
  {app, renderer}
end

private def rar_dependents : Int32
  CrymbleUI::FontSizing.zoom_source_dependent_count
end

# The app the wiring example leaves behind, for the example after it.
class RarLeftBehind
  class_property app : RarApp? = nil
end

describe "an example's app is released" do
  it "records an app it renders once, however many frames" do
    app, renderer = rar_rendered
    3.times { renderer.render_frame(app) }
    apps = CrymbleUI::Testing::TestRenderer.rendered_apps.not_nil!
    apps.count(&.same?(app)).should eq(1)
  end

  it "releases what a rendered grid registered, overlays and rulers included, and empties the list" do
    before = rar_dependents
    rar_rendered
    (rar_dependents > before).should be_true # instrument: the grid's widgets registered with the zoom
    CrymbleUI::Testing::TestRenderer.release_rendered_apps
    rar_dependents.should eq(before)
    CrymbleUI::Testing::TestRenderer.rendered_apps.not_nil!.should be_empty
  end

  it "records nothing while unarmed" do
    armed = CrymbleUI::Testing::TestRenderer.rendered_apps
    CrymbleUI::Testing::TestRenderer.rendered_apps = nil
    begin
      rar_rendered
      CrymbleUI::Testing::TestRenderer.rendered_apps.should be_nil
    ensure
      CrymbleUI::Testing::TestRenderer.rendered_apps = armed
    end
  end

  # The wiring (spec_helper's before_each), across two examples in order.
  it "leaves an app behind" do
    app, _renderer = rar_rendered
    app.root.not_nil!.children.should_not be_empty # instrument
    RarLeftBehind.app = app
  end

  it "finds it released when the next example begins" do
    left = RarLeftBehind.app || fail "run it with the example above (definition order): that one leaves the app behind"
    RarLeftBehind.app = nil # not pinned for the rest of the run
    left.root.not_nil!.children.should be_empty
  end
end
