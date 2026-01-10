require "crsfml"

module CrymbleUI
    # Represents a keyboard shortcut
    # Supports portable syntax like "^S" (Ctrl/Cmd based on platform)
    # and explicit modifiers like "Ctrl+S", "Alt+F4", "Shift+^N"
    struct Shortcut
        getter ctrl : Bool
        getter alt : Bool
        getter shift : Bool
        getter system : Bool  # Cmd on Mac, Win key on Windows
        getter key : SF::Keyboard::Key

        def initialize(@ctrl : Bool, @alt : Bool, @shift : Bool, @system : Bool, @key : SF::Keyboard::Key)
        end

        # Parse shortcut string like "^S", "Ctrl+N", "Shift+Alt+F"
        def self.parse(shortcut_str : String) : Shortcut
            parts = shortcut_str.split("+").map(&.strip)

            ctrl = false
            alt = false
            shift = false
            system = false
            key : SF::Keyboard::Key? = nil

            parts.each do |part|
                case part.downcase
                when "ctrl"
                    ctrl = true
                when "alt"
                    alt = true
                when "shift"
                    shift = true
                when "cmd", "command", "super"
                    system = true
                else
                    # Check for ^ prefix (platform-agnostic primary modifier)
                    if part.starts_with?("^")
                        # ^ means Ctrl on Win/Linux, Cmd on Mac
                        {% if flag?(:darwin) %}
                            system = true
                        {% else %}
                            ctrl = true
                        {% end %}
                        part = part[1..]  # Remove ^
                    end

                    # Parse the key
                    key = parse_key(part)
                end
            end

            raise "No key specified in shortcut '#{shortcut_str}'" unless key

            Shortcut.new(ctrl, alt, shift, system, key)
        end

        # Parse key name to SF::Keyboard::Key
        private def self.parse_key(key_str : String) : SF::Keyboard::Key
            # Single letter keys
            if key_str.size == 1
                char = key_str[0].upcase
                if char >= 'A' && char <= 'Z'
                    return SF::Keyboard::Key.from_value(char.ord - 'A'.ord)
                elsif char >= '0' && char <= '9'
                    # Numbers (Num0 = 26 in SFML enum)
                    return SF::Keyboard::Key.from_value(26 + (char.ord - '0'.ord))
                end
            end

            # Special keys
            case key_str.downcase
            when "space"
                SF::Keyboard::Space
            when "return", "enter"
                SF::Keyboard::Enter
            when "escape", "esc"
                SF::Keyboard::Escape
            when "tab"
                SF::Keyboard::Tab
            when "backspace"
                SF::Keyboard::Backspace
            when "delete", "del"
                SF::Keyboard::Delete
            when "left"
                SF::Keyboard::Left
            when "right"
                SF::Keyboard::Right
            when "up"
                SF::Keyboard::Up
            when "down"
                SF::Keyboard::Down
            when "pageup"
                SF::Keyboard::PageUp
            when "pagedown"
                SF::Keyboard::PageDown
            when "home"
                SF::Keyboard::Home
            when "end"
                SF::Keyboard::End
            when "insert"
                SF::Keyboard::Insert
            # Function keys
            when "f1"
                SF::Keyboard::F1
            when "f2"
                SF::Keyboard::F2
            when "f3"
                SF::Keyboard::F3
            when "f4"
                SF::Keyboard::F4
            when "f5"
                SF::Keyboard::F5
            when "f6"
                SF::Keyboard::F6
            when "f7"
                SF::Keyboard::F7
            when "f8"
                SF::Keyboard::F8
            when "f9"
                SF::Keyboard::F9
            when "f10"
                SF::Keyboard::F10
            when "f11"
                SF::Keyboard::F11
            when "f12"
                SF::Keyboard::F12
            else
                raise "Unknown key '#{key_str}' in shortcut"
            end
        end

        # Check if this shortcut matches a key event
        def matches?(event : SF::Event::KeyEvent) : Bool
            return false unless event.code == @key
            return false if event.control != @ctrl
            return false if event.alt != @alt
            return false if event.shift != @shift
            return false if event.system != @system
            true
        end

        # Format shortcut for display (platform-specific)
        def to_display_string : String
            parts = [] of String

            # Add modifiers in standard order
            {% if flag?(:darwin) %}
                parts << "Shift" if @shift
                parts << "Ctrl" if @ctrl
                parts << "Alt" if @alt
                parts << "Cmd" if @system
            {% else %}
                parts << "Ctrl" if @ctrl
                parts << "Alt" if @alt
                parts << "Shift" if @shift
                parts << "Win" if @system
            {% end %}

            # Add key name
            parts << key_to_string(@key)

            parts.join("+")
        end

        # Convert key to readable string
        private def key_to_string(key : SF::Keyboard::Key) : String
            # Letters A-Z
            if key.value >= 0 && key.value <= 25
                return ('A'.ord + key.value).chr.to_s
            end

            # Numbers 0-9
            if key.value >= 26 && key.value <= 35
                return ('0'.ord + (key.value - 26)).chr.to_s
            end

            # Special keys
            case key
            when SF::Keyboard::Space
                "Space"
            when SF::Keyboard::Enter
                "Enter"
            when SF::Keyboard::Escape
                "Esc"
            when SF::Keyboard::Tab
                "Tab"
            when SF::Keyboard::Backspace
                "Backspace"
            when SF::Keyboard::Delete
                "Del"
            when SF::Keyboard::Left
                "Left"
            when SF::Keyboard::Right
                "Right"
            when SF::Keyboard::Up
                "Up"
            when SF::Keyboard::Down
                "Down"
            when SF::Keyboard::PageUp
                "PgUp"
            when SF::Keyboard::PageDown
                "PgDn"
            when SF::Keyboard::Home
                "Home"
            when SF::Keyboard::End
                "End"
            when SF::Keyboard::Insert
                "Ins"
            when SF::Keyboard::F1
                "F1"
            when SF::Keyboard::F2
                "F2"
            when SF::Keyboard::F3
                "F3"
            when SF::Keyboard::F4
                "F4"
            when SF::Keyboard::F5
                "F5"
            when SF::Keyboard::F6
                "F6"
            when SF::Keyboard::F7
                "F7"
            when SF::Keyboard::F8
                "F8"
            when SF::Keyboard::F9
                "F9"
            when SF::Keyboard::F10
                "F10"
            when SF::Keyboard::F11
                "F11"
            when SF::Keyboard::F12
                "F12"
            else
                "?"
            end
        end

        # Generate hash for use in Hash keys
        def hash
            {@ctrl, @alt, @shift, @system, @key}.hash
        end

        # Equality check
        def ==(other : Shortcut) : Bool
            @ctrl == other.ctrl &&
            @alt == other.alt &&
            @shift == other.shift &&
            @system == other.system &&
            @key == other.key
        end

        # Parse shortcut string and return display string, or original string on error
        # Convenience method for widgets that display shortcuts
        def self.to_display(shortcut_str : String?) : String?
            return nil unless shortcut_str
            begin
                parse(shortcut_str).to_display_string
            rescue ex
                shortcut_str  # Fallback to original on parse error
            end
        end
    end
end
