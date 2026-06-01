require "../spec_helper"
require "../../src/crymble-ui"

# Test app with keyboard shortcuts
class ShortcutTestApp < CrymbleUI::App
    state count : Int32 = 0

    def build : CrymbleUI::Widget
        window("Shortcut Test", 400, 300) do
            vstack do
                text("Count: #{@count}")

                # Button with shortcut
                button("Increment", "^I") do
                    self.count += 1
                end
            end
        end
    end
end

describe "Keyboard Shortcut Integration" do
    it "triggers state change when shortcut is pressed" do
        app = ShortcutTestApp.new
        # Headless: drive a real ShortcutManager directly instead of opening an
        # SFMLRenderer. SFMLRenderer.new would open a real window (X11 on Linux) and
        # replace the global Widget.font with an SFML font — the latter skews every
        # headless layout spec that runs afterward. This mirrors what
        # SFMLRenderer#initialize does for shortcuts: set the global manager, then
        # build so the DSL registers the button's "^I" into it.
        shortcut_manager = CrymbleUI::ShortcutManager.new
        CrymbleUI::Widget.shortcut_manager = shortcut_manager

        # Set up app
        CrymbleUI::Widget.app = app
        app.build_tree

        # Check initial state
        app.@count.should eq(0)

        # Simulate Ctrl+I key press
        event = SF::Event::KeyPressedEvent.new
        {% if flag?(:darwin) %}
            event.system = true
            event.control = false
        {% else %}
            event.control = true
            event.system = false
        {% end %}
        event.alt = false
        event.shift = false
        event.code = SF::Keyboard::I

        # Handle the shortcut
        handled = shortcut_manager.handle_key_event(event, nil)

        # Verify shortcut was handled
        handled.should be_true

        # Verify state changed
        app.@count.should eq(1)

        # Verify rebuild was triggered (root should need layout/render)
        app.root.try(&.needs_render?).should be_true
    end
end
