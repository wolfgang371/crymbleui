module CrymbleUI
  # Abstract clipboard interface.
  #
  # Decouples widgets from the platform clipboard so they can run headless:
  # SFML's `SF::Clipboard` needs a window/X11 connection, which doesn't exist on a
  # headless CI runner. Renderers install a platform implementation (SFMLClipboard);
  # specs install an in-memory stub (Testing::TestClipboard). Mirrors the Font /
  # ShortcutManager injectable-global pattern on Widget.
  abstract class Clipboard
    abstract def string : String
    abstract def string=(value : String)
  end
end
