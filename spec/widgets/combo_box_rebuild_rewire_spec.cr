require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# A REBUILD WHILE THE LIST IS OPEN moves the popup to the rebuilt box; every callback the popup calls must
# reach THAT box - one that still reaches the old box acts on a discarded tree. Each case names the mutation
# that turns it red.

# A focus scope (as a grid is) that records the keys handed back to it.
class KeyScope < CrymbleUI::VStack
  getter keys = [] of SF::Keyboard::Key

  def is_focus_scope? : Bool
    true
  end

  def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
    @keys << key
    true
  end
end

# A new box each build (as a DSL app does), inside a focus scope; the box offers "(custom...)".
class RewireApp < CrymbleUI::App
  getter custom_requests = [] of {Int32, String}
  getter builds = 0

  def build : CrymbleUI::Widget
    @builds += 1
    build_no = @builds
    window = CrymbleUI::Window.new("Test", 400, 300, id: "window")
    scope = KeyScope.new(id: "scope")
    combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], width: 200.0, id: "combo", allow_custom: true) { |_i, _v| }
    combo.on_custom_requested = ->(prefill : String) { @custom_requests << {build_no, prefill}; nil }
    scope.add_child(combo)
    window.add_child(scope)
    window
  end
end

private def rewire_app : {RewireApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = RewireApp.new
  app.build_tree
  renderer.render_frame(app)
  {app, renderer}
end

private def combo(app) : CrymbleUI::ComboBox
  app.find("combo").as(CrymbleUI::ComboBox)
end

describe "ComboBox: a rebuild while the list is open" do
  # Mutations: copy_state_from not calling wire_popup; wire_popup omitting on_custom_requested. Before, the
  # old box's collapse disposed the popup but could not take it out of the LIVE window, and the new box
  # stayed open.
  it "asks the rebuilt box's host for a custom value, and closes the list there" do
    app, renderer = rewire_app
    combo(app).on_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    app.rebuild
    renderer.render_frame(app)
    popup = combo(app).current_popup.not_nil! # instrument: the list moved to the rebuilt box
    fm = CrymbleUI::Widget.focus_manager
    "zz".each_char { |ch| fm.handle_text_input(ch) } # no item matches: "(custom...)" is the highlighted row
    popup.text_input.on_key_down(SF::Keyboard::Key::Enter, false, false)
    renderer.render_frame(app)
    app.custom_requests.should eq([{2, "zz"}])
    combo(app).popup_open?.should be_false
    app.find("window").as(CrymbleUI::Window).overlays.includes?(popup).should be_false
  end

  # Typed on the closed box, the list's arrows hand the key back to the scope around the box. Mutation:
  # copy_state_from not calling wire_popup - the old box's closure hands it to the discarded scope.
  it "hands an arrow back to the rebuilt scope in type-to-filter mode" do
    app, renderer = rewire_app
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(combo(app))
    fm.handle_text_input('B') # opens the list, type-to-filter
    renderer.render_frame(app)
    old_scope = app.find("scope").as(KeyScope)
    app.rebuild
    renderer.render_frame(app)
    new_scope = app.find("scope").as(KeyScope)
    new_scope.same?(old_scope).should be_false # instrument: the scope was rebuilt
    combo(app).current_popup.not_nil!.text_input.on_key_down(SF::Keyboard::Key::Down, false, false)
    new_scope.keys.should eq([SF::Keyboard::Key::Down])
    old_scope.keys.should be_empty
  end
end
