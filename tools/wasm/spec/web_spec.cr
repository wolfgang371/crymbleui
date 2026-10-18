# The web flavour's own wasm-side spec (spec.sh runs it under Node; the page's imports are stubs that raise).
#   - the event round trip: crymble.js's event and key tables (CRYMBLE_JS_TABLES, dumped from the module by spec.sh)
#     name the same CSFML values crymble-ui decodes, and WebRenderer.event rebuilds every field of every kind
#   - the notices this flavour reports to an app's About
require "spec"
require "json"
require "../../../src/crymble-ui"

JS = JSON.parse({{ read_file(env("CRYMBLE_JS_TABLES")) }})

# DOM KeyboardEvent.code -> the CSFML key it must arrive as
KEY_NAMES = {
  "KeyA" => "A", "KeyZ" => "Z", "Digit0" => "Num0", "Digit9" => "Num9", "Escape" => "Escape",
  "ControlLeft" => "LControl", "ShiftRight" => "RShift", "AltRight" => "RAlt", "MetaLeft" => "LSystem",
  "ContextMenu" => "Menu", "BracketLeft" => "LBracket", "Quote" => "Apostrophe", "Backquote" => "Grave",
  "Minus" => "Hyphen", "Equal" => "Equal", "Space" => "Space", "Enter" => "Enter", "Backspace" => "Backspace",
  "Tab" => "Tab", "PageUp" => "PageUp", "Delete" => "Delete", "NumpadAdd" => "Add", "NumpadDivide" => "Divide",
  "ArrowLeft" => "Left", "ArrowDown" => "Down", "Numpad0" => "Numpad0", "Numpad9" => "Numpad9", "F1" => "F1",
  "F12" => "F12", "F15" => "F15", "Pause" => "Pause", "NumpadEnter" => "Enter",
}

describe "the event round trip (crymble.js -> WebRenderer.event)" do
  it "uses CSFML's event type values" do
    JS["EV"].as_h.each do |name, value|
      LibCSFML::EventType.parse(name).value.should eq(value.as_i), "EV.#{name}"
    end
  end

  it "maps DOM key codes to CSFML's key codes" do
    KEY_NAMES.each do |code, name|
      JS["KEYS"][code].as_i.should eq(LibCSFML::KeyCode.parse(name).value), code
    end
  end

  it "rebuilds every field of every kind" do
    ev = ->(name : String) { LibCSFML::EventType.new(JS["EV"][name].as_i) }
    e = CrymbleUI::WebRenderer.event(ev.call("Resized"), 640, 480, 0, 0.0, 0)
    {e.type, e.size.size.x, e.size.size.y}.should eq({LibCSFML::EventType::Resized, 640, 480})
    e = CrymbleUI::WebRenderer.event(ev.call("TextEntered"), 0x1F600, 0, 0, 0.0, 0)
    {e.type, e.text.unicode}.should eq({LibCSFML::EventType::TextEntered, 0x1F600})
    {1 => :alt, 2 => :control, 4 => :shift, 8 => :system, 15 => :all, 0 => :none}.each do |mods, which|
      e = CrymbleUI::WebRenderer.event(ev.call("KeyPressed"), LibCSFML::KeyCode::F5.value, 0, 0, 0.0, mods)
      k = e.key
      {k.type, k.code, k.alt, k.control, k.shift, k.system}.should eq({LibCSFML::EventType::KeyPressed, LibCSFML::KeyCode::F5,
        mods.bit(0) == 1, mods.bit(1) == 1, mods.bit(2) == 1, mods.bit(3) == 1}), which.to_s
    end
    e = CrymbleUI::WebRenderer.event(ev.call("KeyReleased"), LibCSFML::KeyCode::Z.value, 0, 0, 0.0, 2)
    {e.type, e.key.code, e.key.control}.should eq({LibCSFML::EventType::KeyReleased, LibCSFML::KeyCode::Z, true})
    e = CrymbleUI::WebRenderer.event(ev.call("MouseMoved"), -3, 1200, 0, 0.0, 0)
    {e.type, e.mouse_move.position.x, e.mouse_move.position.y}.should eq({LibCSFML::EventType::MouseMoved, -3, 1200})
    {"MouseButtonPressed", "MouseButtonReleased"}.each do |kind|
      e = CrymbleUI::WebRenderer.event(ev.call(kind), LibCSFML::MouseButton::Right.value, 17, 23, 0.0, 0)
      b = e.mouse_button
      {b.type, b.button, b.position.x, b.position.y}.should eq({LibCSFML::EventType.parse(kind), LibCSFML::MouseButton::Right, 17, 23})
    end
    e = CrymbleUI::WebRenderer.event(ev.call("MouseWheelScrolled"), LibCSFML::MouseWheel::Horizontal.value, 5, 6, -0.25, 0)
    w = e.mouse_wheel_scroll
    {w.type, w.wheel, w.delta, w.position.x, w.position.y}.should eq({LibCSFML::EventType::MouseWheelScrolled,
      LibCSFML::MouseWheel::Horizontal, -0.25_f32, 5, 6})
    {"Closed", "FocusLost", "FocusGained", "MouseEntered", "MouseLeft"}.each do |kind|
      CrymbleUI::WebRenderer.event(ev.call(kind), 0, 0, 0, 0.0, 0).type.should eq(LibCSFML::EventType.parse(kind))
    end
  end
end

describe "CrymbleUI.backend_notices (web flavour)" do
  it "names the web backend and what the module links, the font's attribution, and the NOTICES file" do
    notices = CrymbleUI.backend_notices
    notices.first.should contain("web backend")
    notices.none?(&.includes?("SFML")).should be_true
    notices.should contain(CrymbleUI::EmbeddedFont::ATTRIBUTION.first)
    notices.last.should contain("NOTICES")
  end
end
