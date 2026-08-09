require "../csfml3/wrapper"
require "../core/clipboard"

module CrymbleUI
  # Platform clipboard backed by SFML. `SF::Clipboard` talks to the OS clipboard
  # and needs a window/display, so this is only installed by the SFML renderer.
  class SFMLClipboard < Clipboard
    # ALWAYS non-nil today, despite the `String?` return type.
    #
    # CSFML documents `sfClipboard_getString` as "If the clipboard does not contain
    # string it returns an empty string", and SFML's implementation returns that same
    # empty string for THREE distinct states: no selection owner, a conversion that
    # timed out (~1s), and an owner genuinely holding "". They are one value here, so
    # this backend cannot honestly produce nil. It becomes reachable once the X11
    # selection reader lands and `XGetSelectionOwner` can tell them apart.
    #
    # Deliberately NOT mapping "" -> nil to fake the distinction: that would lie in
    # the other direction (a genuinely-empty copy reported as absent) and would have
    # to be unwound later.
    #
    # Non-ASCII round-trips correctly: the wrapper uses SFML's UTF-32 entry points,
    # and validates foreign codepoints as it decodes, so what arrives here is already
    # valid UTF-8 — nothing to re-check.
    def text : String?
      SF::Clipboard.string
    end

    def text=(value : String)
      SF::Clipboard.string = value
    end
  end
end
