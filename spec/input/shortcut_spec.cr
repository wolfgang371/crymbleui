require "../spec_helper"
require "../../src/input/shortcut"

describe CrymbleUI::Shortcut do
    describe ".parse" do
        it "parses ^N as Ctrl+N on Linux" do
            shortcut = CrymbleUI::Shortcut.parse("^N")

            {% if flag?(:darwin) %}
                shortcut.system.should be_true
                shortcut.ctrl.should be_false
            {% else %}
                shortcut.ctrl.should be_true
                shortcut.system.should be_false
            {% end %}

            shortcut.alt.should be_false
            shortcut.shift.should be_false
            shortcut.key.should eq(SF::Keyboard::N)
        end

        it "parses explicit Ctrl+S" do
            shortcut = CrymbleUI::Shortcut.parse("Ctrl+S")

            shortcut.ctrl.should be_true
            shortcut.alt.should be_false
            shortcut.shift.should be_false
            shortcut.system.should be_false
            shortcut.key.should eq(SF::Keyboard::S)
        end

        it "parses Alt+F4" do
            shortcut = CrymbleUI::Shortcut.parse("Alt+F4")

            shortcut.ctrl.should be_false
            shortcut.alt.should be_true
            shortcut.shift.should be_false
            shortcut.system.should be_false
            shortcut.key.should eq(SF::Keyboard::F4)
        end

        it "parses Shift+^T" do
            shortcut = CrymbleUI::Shortcut.parse("Shift+^T")

            {% if flag?(:darwin) %}
                shortcut.system.should be_true
            {% else %}
                shortcut.ctrl.should be_true
            {% end %}

            shortcut.shift.should be_true
            shortcut.alt.should be_false
            shortcut.key.should eq(SF::Keyboard::T)
        end
    end

    # Punctuation keys by their character or name.
    describe ".parse punctuation" do
        it "parses Ctrl+. and Ctrl+Period as the period key" do
            CrymbleUI::Shortcut.parse("Ctrl+.").key.should eq(SF::Keyboard::Period)
            CrymbleUI::Shortcut.parse("Ctrl+Period").key.should eq(SF::Keyboard::Period)
            CrymbleUI::Shortcut.parse("Ctrl+.").ctrl.should be_true
        end

        it "parses Ctrl+, and Ctrl+Comma as the comma key" do
            CrymbleUI::Shortcut.parse("Ctrl+,").key.should eq(SF::Keyboard::Comma)
            CrymbleUI::Shortcut.parse("Ctrl+Comma").key.should eq(SF::Keyboard::Comma)
        end

        it "displays Ctrl+. as Ctrl+." do
            {% unless flag?(:darwin) %}
                CrymbleUI::Shortcut.parse("Ctrl+.").to_display_string.should eq("Ctrl+.")
            {% end %}
        end
    end

    describe "#to_display_string" do
        it "displays ^N as Ctrl+N on Linux" do
            shortcut = CrymbleUI::Shortcut.parse("^N")
            display = shortcut.to_display_string

            {% if flag?(:darwin) %}
                display.should eq("Cmd+N")
            {% else %}
                display.should eq("Ctrl+N")
            {% end %}
        end

        it "displays Alt+F4 correctly" do
            shortcut = CrymbleUI::Shortcut.parse("Alt+F4")
            display = shortcut.to_display_string

            {% if flag?(:darwin) %}
                display.should eq("Alt+F4")
            {% else %}
                display.should eq("Alt+F4")
            {% end %}
        end
    end

    describe "#matches?" do
        it "matches KeyPressed event with correct modifiers" do
            shortcut = CrymbleUI::Shortcut.parse("^S")

            # Create a mock key event
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
            event.code = SF::Keyboard::S

            shortcut.matches?(event).should be_true
        end

        it "doesn't match with wrong key" do
            shortcut = CrymbleUI::Shortcut.parse("^S")

            event = SF::Event::KeyPressedEvent.new
            {% if flag?(:darwin) %}
                event.system = true
            {% else %}
                event.control = true
            {% end %}
            event.alt = false
            event.shift = false
            event.code = SF::Keyboard::N  # Wrong key

            shortcut.matches?(event).should be_false
        end

        it "doesn't match with wrong modifiers" do
            shortcut = CrymbleUI::Shortcut.parse("^S")

            event = SF::Event::KeyPressedEvent.new
            event.control = false  # Missing Ctrl
            event.alt = false
            event.shift = false
            event.system = false
            event.code = SF::Keyboard::S

            shortcut.matches?(event).should be_false
        end
    end
end
