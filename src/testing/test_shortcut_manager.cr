require "./test_shortcut"

module CrymbleUI
  module Testing
    # Stub shortcut manager for headless testing (no SFML dependency)
    # Provides same interface as real ShortcutManager but doesn't handle actual shortcuts
    # Headless tests don't test keyboard input - this is just for API compatibility
    class TestShortcutManager
      # Register a shortcut (no-op in headless mode)
      def register_shortcut(shortcut : TestShortcut, &block : -> Nil)
        # Stub - do nothing
      end

      # Register a shortcut with widget (no-op in headless mode)
      def register_shortcut(shortcut : TestShortcut, widget : Widget, &block : -> Nil)
        # Stub - do nothing
      end

      # Unregister shortcuts for a widget (no-op in headless mode)
      def unregister_widget(widget : Widget)
        # Stub - do nothing
      end

      # Handle key press (no-op in headless mode - no keyboard events)
      def handle_key_press(ctrl : Bool, alt : Bool, shift : Bool, system : Bool, key : TestKey)
        # Stub - do nothing
      end

      # Check for conflicts (no-op in headless mode)
      def check_conflicts : Array(String)
        [] of String
      end
    end
  end
end
