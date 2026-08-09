module CrymbleUI
  # Abstract clipboard interface.
  #
  # Decouples widgets from the platform clipboard so they can run headless:
  # SFML's `SF::Clipboard` needs a window/X11 connection, which doesn't exist on a
  # headless CI runner. Renderers install a platform implementation (SFMLClipboard);
  # specs install an in-memory stub (Testing::TestClipboard). Mirrors the Font /
  # ShortcutManager injectable-global pattern on Widget.
  abstract class Clipboard
    # The clipboard's text, or nil when there is NOTHING on the clipboard — which is
    # a different state from an empty string having been copied. A caller that must
    # tell "nothing to paste" from "an empty value was copied" needs that difference;
    # a plain `String` accessor cannot express it.
    #
    # There is deliberately NO provenance here — no "who wrote this" tag. The
    # clipboard carries text and nothing else, so a consumer that copies structured
    # data (a spreadsheet-style grid, say) and then pastes it into a text field gets
    # that text. That is the user's own doing, and not something the library polices.
    #
    # NOTE: `SFMLClipboard` cannot return nil yet — see the honesty note there. Until
    # the X11 selection reader lands, nil is reachable only from `TestClipboard`.
    abstract def text : String?

    # Absence is deliberately readable but NOT settable: there is no portable "clear
    # the clipboard" (X11 has no such operation — you relinquish ownership instead),
    # so a caller returns to "nothing copied" by installing a fresh instance rather
    # than by assigning nil. That is why the spec harness REPLACES the clipboard per
    # example instead of resetting it.
    abstract def text=(value : String)
  end
end
