require "./shortcut"
require "../core/widget"

module CrymbleUI
    # Context for shortcut activation
    enum ShortcutContext
        Global      # MenuBar, always active
        Panel       # Active panel only
        Widget      # Focused widget only (future)
    end

    # Manages keyboard shortcuts and dispatches them to handlers
    class ShortcutManager
        # Shortcuts by context
        # Global: shortcut -> handler
        @global_shortcuts : Hash(Shortcut, Proc(Nil))

        # Panel: panel_path -> (shortcut -> handler)
        @panel_shortcuts : Hash(String, Hash(Shortcut, Proc(Nil)))

        def initialize
            @global_shortcuts = {} of Shortcut => Proc(Nil)
            @panel_shortcuts = {} of String => Hash(Shortcut, Proc(Nil))
        end

        # Register a shortcut with its handler
        # context: Global or Panel
        # context_id: panel path_id for Panel context, nil for Global
        # Returns true if registered, false if conflicted (but still registers)
        def register(shortcut_str : String, context : ShortcutContext, context_id : String?, &block : -> Nil) : Bool
            shortcut = Shortcut.parse(shortcut_str)

            case context
            when ShortcutContext::Global
                return register_global(shortcut, shortcut_str, &block)
            when ShortcutContext::Panel
                raise "Panel context requires context_id (panel path_id)" unless context_id
                return register_panel(shortcut, shortcut_str, context_id, &block)
            when ShortcutContext::Widget
                # Not implemented yet
                raise "Widget context not implemented yet"
            else
                false  # Should never reach here
            end
        end

        # Register global shortcut (MenuBar, etc.)
        private def register_global(shortcut : Shortcut, shortcut_str : String, &block : -> Nil) : Bool
            if @global_shortcuts.has_key?(shortcut)
                if Widget.enable_warnings
                    STDERR.puts "WARNING: Duplicate global shortcut '#{shortcut_str}'"
                    STDERR.puts "  Previous handler will be replaced."
                end
                @global_shortcuts[shortcut] = block
                return false  # Conflict
            end

            @global_shortcuts[shortcut] = block
            true
        end

        # Register panel-specific shortcut
        private def register_panel(shortcut : Shortcut, shortcut_str : String, panel_id : String, &block : -> Nil) : Bool
            # Get or create panel shortcut map
            panel_map = @panel_shortcuts[panel_id]? || Hash(Shortcut, Proc(Nil)).new
            @panel_shortcuts[panel_id] = panel_map

            if panel_map.has_key?(shortcut)
                if Widget.enable_warnings
                    STDERR.puts "WARNING: Duplicate panel shortcut '#{shortcut_str}' in panel '#{panel_id}'"
                    STDERR.puts "  Previous handler will be replaced."
                end
                panel_map[shortcut] = block
                return false  # Conflict
            end

            panel_map[shortcut] = block
            true
        end

        # Handle key press event
        # Returns true if shortcut was handled
        def handle_key_event(event : SF::Event::KeyEvent, active_panel : Widget?) : Bool
            shortcut = Shortcut.new(
                event.control,
                event.alt,
                event.shift,
                event.system,
                event.code
            )

            # 1. Try active panel shortcuts first (if panel active)
            if active_panel
                panel_id = active_panel.path_id
                if panel_map = @panel_shortcuts[panel_id]?
                    if handler = panel_map[shortcut]?
                        handler.call
                        return true
                    end
                end
            end

            # 2. Try global shortcuts
            if handler = @global_shortcuts[shortcut]?
                handler.call
                return true
            end

            false  # Not handled
        end

        # Clear all shortcuts (useful for testing)
        def clear
            @global_shortcuts.clear
            @panel_shortcuts.clear
        end

        # Clear shortcuts for specific panel
        def clear_panel(panel_id : String)
            @panel_shortcuts.delete(panel_id)
        end
    end
end
