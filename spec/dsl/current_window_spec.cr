require "../spec_helper"

# A build can ask for the window it is building - an app placing panels at its first build, before there is a
# root, has a window to measure. A build that raised leaves none behind.
private class CurrentWindowApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  getter seen : CrymbleUI::Window? = nil
  property fail = false

  def build : CrymbleUI::Widget
    window("W", 300, 200, id: "w") do
      window_panel("P", 10.0, 10.0, 100.0, 80.0, id: "p") do
        @seen = current_window
        raise "a build that fails" if fail
        text("x")
      end
    end
  end
end

describe "current_window" do
  it "is the window the build is inside" do
    app = CurrentWindowApp.new
    app.build_tree
    app.seen.should_not be_nil
    app.seen.not_nil!.same?(app.root).should be_true
  end

  it "is nil outside a build" do
    app = CurrentWindowApp.new
    app.build_tree
    app.current_window.should be_nil
  end

  it "is nil again after a build that raised inside a panel inside the window" do
    app = CurrentWindowApp.new
    app.fail = true
    expect_raises(Exception, "a build that fails") { app.build_tree }
    app.current_window.should be_nil
  end
end
