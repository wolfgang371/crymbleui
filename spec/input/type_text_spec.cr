require "../spec_helper"
require "../../src/testing/driver"

# Text typed from code as a user types it: each character to whatever holds the keyboard, through the one text path
# real keystrokes take. A character whose handling makes input wait for a rebuilt frame ends it - real input would
# wait, then land on a tree the caller never saw.

# A text input that asks for a rebuild blocking input on every character it is typed, and records them.
class TypeTextRebuilds < CrymbleUI::TextInput
  getter typed = [] of Char

  def initialize(@app : CrymbleUI::App)
    super(value: "", id: "rebuilds")
  end

  def on_text_input(char : Char)
    @typed << char
    @app.request_rebuild
    super
  end
end

private class TypeTextApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("W", 300, 200) { text_input(bind: CrymbleUI::Source(String).new(""), id: "name") }
  end
end

describe "FocusManager#type_text" do
  it "types into whatever holds the keyboard" do
    ui = CrymbleUI::Testing::Driver.new(TypeTextApp.new)
    ui.click "name"
    CrymbleUI::Widget.focus_manager.type_text("20261016 ", ui.app)
    ui.text("name").should eq("20261016 ")
  end

  # Mutation: drop the barrier check - all three characters reach the widget.
  it "ends at the input barrier - the rest is not typed" do
    app = TypeTextApp.new
    app.build_tree
    widget = TypeTextRebuilds.new(app)
    CrymbleUI::Widget.focus_manager.focus(widget)
    CrymbleUI::Widget.focus_manager.type_text("abc", app)
    widget.typed.should eq(['a'])
  end
end

describe "ShortcutFormat.to_display" do
  it "shows Ctrl+Period as Ctrl+. - the path a menu label takes" do
    {% unless flag?(:darwin) %}
      CrymbleUI::ShortcutFormat.to_display("Ctrl+Period").should eq("Ctrl+.")
    {% end %}
  end
end
