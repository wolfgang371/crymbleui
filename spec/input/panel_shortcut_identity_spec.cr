require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# A PANEL'S SHORTCUTS ARE ITS OWN. Two panels without ids and with the same title have the same path; the
# shortcuts they register must still reach only their own handlers. Mutation: key panel shortcuts by
# path_id - the second registration replaces the first, and either panel's key runs the second's handler.

class SameTitleDialogs < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods
  getter fired = [] of Int32

  def build : CrymbleUI::Widget
    window("t", 600, 300) do
      [10.0, 300.0].each_with_index do |x, i|
        window_panel("Dialog", x: x, y: 10.0, width: 200.0, height: 100.0) do
          register_shortcut("Escape") { @fired << i }
          text("body #{i}")
        end
      end
    end
  end
end

private def dialogs : {SameTitleDialogs, CrymbleUI::Testing::TestRenderer, Array(CrymbleUI::WindowPanel)}
  app = SameTitleDialogs.new
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 300) # installs the manager before the build
  app.build_tree
  renderer.settle_rendering(app)
  panels = app.root.not_nil!.children.compact_map(&.as?(CrymbleUI::WindowPanel))
  panels.map(&.path_id).uniq.size.should eq(1) # instrument: the two share one path
  {app, renderer, panels}
end

describe "panel shortcuts of two same-path panels" do
  it "run the handler of the panel in front, through real key input" do
    {0, 1}.each do |front|
      app, renderer, panels = dialogs
      panels[front].bring_to_front
      renderer.settle_rendering(app)
      renderer.deliver(app, CrymbleUI::Testing::Keys.tap(SF::Keyboard::Key::Escape))
      app.fired.should eq([front])
    end
  end

  it "fire for the panel named in trigger" do
    app, _renderer, panels = dialogs
    CrymbleUI::Widget.shortcut_manager.trigger("Escape", panels[0]).should be_true
    CrymbleUI::Widget.shortcut_manager.trigger("Escape", panels[1]).should be_true
    app.fired.should eq([0, 1])
  end
end
