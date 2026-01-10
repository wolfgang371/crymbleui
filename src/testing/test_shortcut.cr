module CrymbleUI
  module Testing
    # Stub keyboard key enum for headless testing (no SFML dependency)
    # Real shortcuts use SF::Keyboard::Key but headless tests don't support keyboard input
    enum TestKey
      Unknown
      A
      B
      C
      S  # Common shortcuts: Save, etc.
      N  # New
      Escape
      Space
      Enter
    end

    # Stub shortcut for headless testing (no SFML dependency)
    # Provides same interface as real Shortcut but doesn't require SF::Keyboard::Key
    struct TestShortcut
      getter ctrl : Bool
      getter alt : Bool
      getter shift : Bool
      getter system : Bool
      getter key : TestKey

      def initialize(@ctrl : Bool, @alt : Bool, @shift : Bool, @system : Bool, @key : TestKey)
      end

      # Stub parse - always returns Unknown key
      # Real shortcut parsing not needed in headless tests
      def self.parse(shortcut_str : String) : TestShortcut
        new(false, false, false, false, TestKey::Unknown)
      end

      def to_s(io : IO)
        modifiers = [] of String
        modifiers << "Ctrl" if @ctrl
        modifiers << "Alt" if @alt
        modifiers << "Shift" if @shift
        modifiers << "Sys" if @system
        io << modifiers.join("+")
        io << "+" unless modifiers.empty?
        io << @key.to_s
      end
    end
  end
end
