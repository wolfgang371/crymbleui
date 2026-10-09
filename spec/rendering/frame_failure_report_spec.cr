require "../spec_helper"
require "../../src/testing/test_renderer"

# A FRAME THAT RAISES REACHES THE USER. The renderer recovers from it (graceful degradation) - and tells the app's
# on_event_exception (embrace: the status bar) at the first failing frame of a run, once more when the run reaches
# its 10th, never on every frame; the window title says so while the run lasts. A frame that completes ends the run.
# A failing frame does not trigger the next one, so each is driven here with an explicit render_frame.

class FfrBomb < CrymbleUI::Widget
  class_property armed = false

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    raise "boom" if FfrBomb.armed
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height),
      CrymbleUI::Color.new(90, 90, 200, 255)).as(CrymbleUI::DrawPrimitive)]
  end
end

class FfrApp < CrymbleUI::App
  getter bomb = FfrBomb.new
  getter status = CrymbleUI::Text.new("ok")

  def build : CrymbleUI::Widget
    CrymbleUI::Window.new("Ledger", 300, 200).tap do |window|
      window.add_child(@bomb)
      window.add_child(@status)
    end
  end
end

private def ffr_app(reports : Array(String)?) : {FfrApp, CrymbleUI::Testing::TestRenderer}
  FfrBomb.armed = false
  app = FfrApp.new
  # As embrace's: the message goes into a widget, whose mark must trigger the frame that paints it
  app.on_event_exception = ->(msg : String) { reports.try(&.<< msg); app.status.text = msg; nil } if reports
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(300, 200)
  renderer.settle_rendering(app)
  {app, renderer}
end

# One failing frame: the bomb armed, its cache invalidated, one frame.
private def ffr_fail(app : FfrApp, renderer) : Nil
  FfrBomb.armed = true
  app.bomb.mark_needs_render
  renderer.render_frame(app)
end

describe "a frame that raises" do
  after_each { FfrBomb.armed = false }

  it "is reported at the first failing frame of a run and at its 10th, never else" do
    reports = [] of String
    app, renderer = ffr_app(reports)
    swallowed = CrymbleUI::Testing::TestRenderer.frame_exceptions_swallowed
    21.times { ffr_fail(app, renderer) }
    reports.should eq(["Display error: boom", "Display error keeps recurring: boom - please save your work"])
    (CrymbleUI::Testing::TestRenderer.frame_exceptions_swallowed - swallowed).should eq(21) # each one recovered
  end

  it "is reported after the frame is stamped, so the report's own change is painted next" do
    app, renderer = ffr_app([] of String)
    ffr_fail(app, renderer)
    app.status.text.should eq("Display error: boom") # instrument: the handler wrote it
    FfrBomb.armed = false
    renderer.render_frame_if_needed(app).should be_true
  end

  it "starts a new run after a frame that completes, and marks the title only while a run lasts" do
    reports = [] of String
    app, renderer = ffr_app(reports)
    renderer.applied_title.should eq("Ledger")
    ffr_fail(app, renderer)
    renderer.applied_title.should eq("Ledger - display error")
    FfrBomb.armed = false
    app.bomb.mark_needs_render
    renderer.render_frame(app) # completes
    renderer.applied_title.should eq("Ledger")
    ffr_fail(app, renderer)
    reports.should eq(["Display error: boom", "Display error: boom"])
  end

  it "reports nothing, and raises nothing, when the app has no handler" do
    app, renderer = ffr_app(nil)
    3.times { ffr_fail(app, renderer) }
    renderer.applied_title.should eq("Ledger - display error")
  end
end
