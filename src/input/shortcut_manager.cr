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

        # Panel: the panel itself -> (shortcut -> handler). Keyed by the INSTANCE (Widget defines no ==/hash,
        # so a Hash compares widgets by identity): two panels with the same path - no id, the same title -
        # are still two panels. Registration and dispatch both see the live tree's instances: every rebuild
        # clears the shortcuts and its build registers them on the widgets that become the live tree.
        @panel_shortcuts : Hash(Widget, Hash(Shortcut, Proc(Nil)))

        def initialize
            @global_shortcuts = {} of Shortcut => Proc(Nil)
            @panel_shortcuts = {} of Widget => Hash(Shortcut, Proc(Nil))
        end

        # Register a shortcut with its handler
        # context: Global or Panel
        # panel: the panel (a WindowPanel) for Panel context, nil for Global
        # Returns true if registered, false if conflicted (but still registers)
        def register(shortcut_str : String, context : ShortcutContext, panel : Widget?, &block : -> Nil) : Bool
            shortcut = Shortcut.parse(shortcut_str)

            case context
            when ShortcutContext::Global
                return register_global(shortcut, shortcut_str, &block)
            when ShortcutContext::Panel
                raise "Panel context requires the panel" unless panel
                return register_panel(shortcut, shortcut_str, panel, &block)
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
        private def register_panel(shortcut : Shortcut, shortcut_str : String, panel : Widget, &block : -> Nil) : Bool
            # Get or create panel shortcut map
            panel_map = @panel_shortcuts[panel]? || Hash(Shortcut, Proc(Nil)).new
            @panel_shortcuts[panel] = panel_map

            if panel_map.has_key?(shortcut)
                if Widget.enable_warnings
                    STDERR.puts "WARNING: Duplicate panel shortcut '#{shortcut_str}' in panel '#{panel.path_id}'"
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
            dispatch(shortcut, active_panel)
        end

        # Fire a registered shortcut by the string it was registered with, exactly as a key press
        # would — same lookup, same order, same handler. Headless tests have no key events, so
        # without this a panel shortcut can only be proven to REGISTER, never to do anything. `panel` must
        # be the live one (found after the last rebuild): the rebuild registered on its replacement.
        def trigger(shortcut_str : String, panel : Widget? = nil) : Bool
            dispatch(Shortcut.parse(shortcut_str), panel)
        end

        # The active panel wins over global, so a dialog's Escape does not reach the app's.
        private def dispatch(shortcut : Shortcut, panel : Widget?) : Bool
            if panel && (panel_map = @panel_shortcuts[panel]?)
                if handler = panel_map[shortcut]?
                    handler.call
                    return true
                end
            end

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
    end
end
