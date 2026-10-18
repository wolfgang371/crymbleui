require "../spec_helper"
require "../../src/testing/driver"
require "../../tutorials/tutorial-30"

describe ClockApp do
  it "shows the time and ticks every second" do
    time = Time.local(2026, 10, 10, 12, 0, 0)
    ui = CrymbleUI::Testing::Driver.new(ClockApp.new(-> { time }), 360, 160)
    ui.text("clock").should eq("12:00:00")

    time += 1.second
    ui.advance(1.0)
    ui.text("clock").should eq("12:00:01")
  end

  # What the user sees of it: the clock is as wide as the space it is given, centred there, and
  # follows the window when it is resized.
  it "draws the clock across the width it is given, and follows the window" do
    ui = CrymbleUI::Testing::Driver.new(ClockApp.new(-> { Time.local(2026, 10, 10, 12, 0, 0) }), 360, 160)
    {360, 520}.each do |width|
      ui.renderer.resize(width, 160)
      ui.app.root.not_nil!.mark_needs_layout
      ui.settle
      box = ui.find("clock_box").viewport_bounds
      clock = ui.find("clock").viewport_bounds
      clock.width.should be_close(box.width, 0.5) # a wide clock: the width binds
      clock.center.y.should be_close(box.center.y, 0.5)
      box.width.should be_close(width - CrymbleUI::Window::CONTENT_PADDING * 2, 0.5)
    end
  end
end
