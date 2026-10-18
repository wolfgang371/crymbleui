require "../spec_helper"

# KeyboardDispatch::BUILT_INS names the chords KeyboardDispatch handles in code (a host lists them next to an app's
# registered shortcuts - the web flavour's page, when it names the shortcuts a browser keeps). A chord added to the
# list without a handler, or a handler renamed, must fail here: each listed chord, delivered through the real
# keyboard path, is consumed before the focused widget sees it.

private class KeyRecorder < CrymbleUI::Widget
  getter keys = [] of String

  def initialize(id : String)
    super(id: id)
  end

  def focusable? : Bool
    true
  end

  def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
    @keys << "#{control ? "Ctrl+" : ""}#{shift ? "Shift+" : ""}#{key}"
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(50, 20)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class BuiltinsApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Built-ins", 400, 300) do
      vstack { widget(KeyRecorder.new("rec")) }
    end
  end
end

# What the focused widget received for `chord`, delivered as a key press through KeyboardDispatch.
private def received(chord : String) : Array(String)
  shortcut = CrymbleUI::Shortcut.parse(chord)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = BuiltinsApp.new
  app.build_tree
  renderer.render_frame(app)
  recorder = app.find("rec").not_nil!.as(KeyRecorder)
  CrymbleUI::Widget.focus_manager.focus(recorder)
  renderer.deliver(app, [CrymbleUI::Testing::Keys.pressed(shortcut.key, control: shortcut.ctrl, shift: shortcut.shift)])
  recorder.keys
ensure
  CrymbleUI::FontSizing.reset_zoom # Ctrl+0 is one of them
end

describe "KeyboardDispatch::BUILT_INS" do
  it "lists only chords KeyboardDispatch consumes itself: none reaches the focused widget" do
    CrymbleUI::KeyboardDispatch::BUILT_INS.each do |chord|
      received(chord).should be_empty, "#{chord} is listed as built in but reached the focused widget"
    end
  end

  it "is checked by a probe that does see a chord which is not built in (the instrument)" do
    received("Ctrl+K").should eq ["Ctrl+K"]
  end
end
