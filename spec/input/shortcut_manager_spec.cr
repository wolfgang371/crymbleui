require "../spec_helper"
require "../../src/input/shortcut_manager"
require "../../src/core/widget"

describe CrymbleUI::ShortcutManager do
    describe "#register and #handle_key_event" do
        it "triggers callback when shortcut is pressed" do
            manager = CrymbleUI::ShortcutManager.new
            callback_called = false

            # Register global shortcut
            manager.register("^S", CrymbleUI::ShortcutContext::Global, nil) do
                callback_called = true
            end

            # Simulate Ctrl+S key press
            event = SF::Event::KeyPressed.new
            {% if flag?(:darwin) %}
                event.system = true
                event.control = false
            {% else %}
                event.control = true
                event.system = false
            {% end %}
            event.alt = false
            event.shift = false
            event.code = SF::Keyboard::S

            # Handle the event
            handled = manager.handle_key_event(event, nil)

            handled.should be_true
            callback_called.should be_true
        end

        it "doesn't trigger callback for unregistered shortcut" do
            manager = CrymbleUI::ShortcutManager.new
            callback_called = false

            manager.register("^S", CrymbleUI::ShortcutContext::Global, nil) do
                callback_called = true
            end

            # Simulate Ctrl+N (not registered)
            event = SF::Event::KeyPressed.new
            {% if flag?(:darwin) %}
                event.system = true
            {% else %}
                event.control = true
            {% end %}
            event.alt = false
            event.shift = false
            event.code = SF::Keyboard::N

            handled = manager.handle_key_event(event, nil)

            handled.should be_false
            callback_called.should be_false
        end

        it "panel shortcuts override global shortcuts" do
            manager = CrymbleUI::ShortcutManager.new
            global_called = false
            panel_called = false

            # Register global ^F
            manager.register("^F", CrymbleUI::ShortcutContext::Global, nil) do
                global_called = true
            end

            # Register panel ^F (should override)
            panel = TestWidget.new(id: "test_panel")
            manager.register("^F", CrymbleUI::ShortcutContext::Panel, panel.path_id) do
                panel_called = true
            end

            # Simulate Ctrl+F with panel active
            event = SF::Event::KeyPressed.new
            {% if flag?(:darwin) %}
                event.system = true
                event.control = false
            {% else %}
                event.control = true
                event.system = false
            {% end %}
            event.alt = false
            event.shift = false
            event.code = SF::Keyboard::F

            handled = manager.handle_key_event(event, panel)

            handled.should be_true
            panel_called.should be_true
            global_called.should be_false  # Panel shortcut overrides global
        end

        it "falls back to global when panel doesn't have shortcut" do
            manager = CrymbleUI::ShortcutManager.new
            global_called = false

            # Only register global ^S
            manager.register("^S", CrymbleUI::ShortcutContext::Global, nil) do
                global_called = true
            end

            # Simulate Ctrl+S with a panel active (but panel doesn't have ^S)
            event = SF::Event::KeyPressed.new
            {% if flag?(:darwin) %}
                event.system = true
            {% else %}
                event.control = true
            {% end %}
            event.alt = false
            event.shift = false
            event.code = SF::Keyboard::S

            panel = TestWidget.new(id: "test_panel")
            handled = manager.handle_key_event(event, panel)

            handled.should be_true
            global_called.should be_true
        end
    end

    describe "conflict detection" do
        it "detects duplicate global shortcuts" do
            manager = CrymbleUI::ShortcutManager.new

            # Register first ^S
            result1 = manager.register("^S", CrymbleUI::ShortcutContext::Global, nil) { }
            result1.should be_true

            # Register duplicate ^S (should detect conflict and return false)
            # Disable warnings to avoid test noise
            CrymbleUI::Widget.enable_warnings = false
            result2 = manager.register("^S", CrymbleUI::ShortcutContext::Global, nil) { }
            CrymbleUI::Widget.enable_warnings = true

            result2.should be_false  # Conflict detected
        end
    end
end
