require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# ON_FILTER: a consumer learns the user is typing into the open list - every change of the typed filter,
# from its first character on, whichever way the list was opened. Each case names the mutation that turns
# it red.

# A new ComboBox each build (as a DSL app does), logging each filter change with the build that made it.
class FilterLogApp < CrymbleUI::App
  getter log = [] of {Int32, String}
  getter builds = 0

  def build : CrymbleUI::Widget
    @builds += 1
    build_no = @builds
    window = CrymbleUI::Window.new("Test", 400, 300)
    vstack = CrymbleUI::VStack.new
    combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, width: 200.0, id: "combo")
    combo.on_filter = ->(filter : String) { @log << {build_no, filter}; nil }
    vstack.add_child(combo)
    window.add_child(vstack)
    window
  end
end

private def filter_app : {FilterLogApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = FilterLogApp.new
  app.build_tree
  renderer.render_frame(app)
  {app, renderer}
end

private def combo(app) : CrymbleUI::ComboBox
  app.find("combo").as(CrymbleUI::ComboBox)
end

describe "ComboBox#on_filter" do
  # Typed on the closed box, the character opens the list and is its first filter character. Mutation: the
  # popup wired after the character went in - the first character is lost.
  it "hears the character that opens the list" do
    app, renderer = filter_app
    CrymbleUI::Widget.focus_manager.focus(combo(app))
    CrymbleUI::Widget.focus_manager.handle_text_input('B')
    renderer.render_frame(app)
    combo(app).popup_open?.should be_true # instrument
    app.log.should eq([{1, "B"}])
  end

  # Mutations: the popup not calling on_filter; the ComboBox not handing it on.
  it "hears nothing when the list merely opens, then each character typed" do
    app, renderer = filter_app
    combo(app).on_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    combo(app).popup_open?.should be_true # instrument
    app.log.should be_empty
    CrymbleUI::Widget.focus_manager.handle_text_input('A')
    CrymbleUI::Widget.focus_manager.handle_text_input('p')
    app.log.should eq([{1, "A"}, {1, "Ap"}])
  end

  # A rebuild moves the open list to the new box; the typing is then the new box's to report. Mutation: no
  # re-bind in copy_state_from - the old box's closure hears it.
  it "reports typing after a rebuild through the rebuilt box, and the rebuild itself not at all" do
    app, renderer = filter_app
    combo(app).on_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    app.rebuild
    renderer.render_frame(app)
    combo(app).popup_open?.should be_true # instrument: the list moved to the rebuilt box
    app.log.should be_empty
    CrymbleUI::Widget.focus_manager.handle_text_input('C')
    app.log.should eq([{2, "C"}])
  end
end
