module CrymbleUI
  # Pure Crystal utility for shortcut string formatting
  # No SFML dependencies - just string manipulation for display purposes
  # Converts shortcuts like "^S" to platform-appropriate display "Ctrl+S" or "Cmd+S"
  module ShortcutFormat
    # Convert shortcut string to display format
    # Examples: "^S" → "Ctrl+S" (Win/Linux) or "Cmd+S" (Mac)
    #          "Ctrl+Alt+Delete" → "Ctrl+Alt+Delete"
    # Returns nil if input is nil, original string if parse fails
    def self.to_display(shortcut_str : String?) : String?
      return nil unless shortcut_str

      begin
        parse_and_format(shortcut_str)
      rescue
        shortcut_str  # Fallback to original on parse error
      end
    end

    # Parse shortcut string and format for display
    private def self.parse_and_format(shortcut_str : String) : String
      parts = shortcut_str.split("+").map(&.strip)

      ctrl = false
      alt = false
      shift = false
      system = false
      key_name : String? = nil

      parts.each do |part|
        case part.downcase
        when "ctrl"
          ctrl = true
        when "alt"
          alt = true
        when "shift"
          shift = true
        when "cmd", "command", "super", "win"
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

          # The remaining part is the key name
          key_name = format_key_name(part)
        end
      end

      raise "No key specified in shortcut '#{shortcut_str}'" unless key_name

      # Build display string with modifiers in platform order
      display_parts = [] of String

      {% if flag?(:darwin) %}
        display_parts << "Shift" if shift
        display_parts << "Ctrl" if ctrl
        display_parts << "Alt" if alt
        display_parts << "Cmd" if system
      {% else %}
        display_parts << "Ctrl" if ctrl
        display_parts << "Alt" if alt
        display_parts << "Shift" if shift
        display_parts << "Win" if system
      {% end %}

      display_parts << key_name

      display_parts.join("+")
    end

    # Format key name for display (capitalize, expand abbreviations)
    private def self.format_key_name(key_str : String) : String
      case key_str.downcase
      when "esc"
        "Escape"
      when "del"
        "Delete"
      when "return"
        "Enter"
      when "pageup"
        "PageUp"
      when "pagedown"
        "PageDown"
      else
        # Capitalize first letter for single char keys (s → S)
        # Keep multi-char keys as-is (Space, Enter, F1, etc.)
        key_str.size == 1 ? key_str.upcase : key_str.capitalize
      end
    end
  end
end
