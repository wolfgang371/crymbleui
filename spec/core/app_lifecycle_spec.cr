require "../spec_helper"
require "../../src/testing/driver"

# A clock: on_start starts the timer, build only describes the UI.
class LifecycleClockApp < CrymbleUI::App
  state ticks : Int32 = 0

  def on_start
    every(5.seconds) { self.ticks += 1 }
  end

  def build : CrymbleUI::Widget
    window("Clock", 300, 120) { text(ticks.to_s, id: "clock") }
  end
end

# Records what on_start saw: how often it ran, and whether the scheduler and the tree were there.
class LifecycleProbeApp < CrymbleUI::App
  getter starts = 0
  getter saw_scheduler = false
  getter saw_root = false

  def on_start
    @starts += 1
    @saw_scheduler = !CrymbleUI::Widget.scheduler?.nil?
    @saw_root = !root.nil?
  end

  def build : CrymbleUI::Widget
    window("Probe", 200, 100) { text("x") }
  end
end

# A one-shot timer, and a repeating one that is cancelled before it fires.
class LifecycleTimersApp < CrymbleUI::App
  getter once = 0
  getter repeated = 0

  def on_start
    after(1.second) { @once += 1 }
    every(1.second) { @repeated += 1 }.cancel
  end

  def build : CrymbleUI::Widget
    window("Timers", 200, 100) { text("x") }
  end
end

describe "App lifecycle" do
  # Mutation: the renderer never calls start - the clock stays at 0.
  it "a timer started in on_start drives the UI" do
    ui = CrymbleUI::Testing::Driver.new(LifecycleClockApp.new)
    ui.text("clock").should eq("0")
    ui.advance(4.0)
    ui.text("clock").should eq("0")
    ui.advance(1.0)
    ui.text("clock").should eq("1")
    ui.advance(5.0)
    ui.text("clock").should eq("2")
  end

  # Mutations: start before the tree is built; start on every frame or every rebuild.
  it "runs on_start once, with the scheduler installed and the tree built" do
    app = LifecycleProbeApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app.build_tree
    3.times { renderer.render_frame(app) }
    app.request_rebuild
    renderer.render_frame(app)
    app.starts.should eq(1)
    app.saw_scheduler.should be_true
    app.saw_root.should be_true
  end

  # Mutations: `after` repeats; Timer#cancel does nothing.
  it "fires an `after` timer once, and never a cancelled one" do
    app = LifecycleTimersApp.new
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.advance(1.0)
    ui.advance(1.0)
    ui.advance(1.0)
    app.once.should eq(1)
    app.repeated.should eq(0)
  end
end
