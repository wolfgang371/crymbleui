require "../core/clipboard"

module CrymbleUI::Testing
  # In-memory clipboard for headless specs — no SFML, no display.
  #
  # ONE known divergence from SFMLClipboard, deliberate and worth remembering when
  # reading a spec that uses this fake: it can express ABSENCE. A fresh instance has
  # never been written to, so `text` is nil rather than "". That is what lets a spec
  # cover the absent-vs-empty distinction the real backend cannot yet produce.
  #
  # Non-ASCII behaves the same in both, so a spec may round-trip it here and trust
  # the result. (That was NOT true while the clipboard went through SFML's ANSI entry
  # points, which deleted every non-ASCII codepoint; the wrapper now uses the UTF-32
  # pair.)
  class TestClipboard < CrymbleUI::Clipboard
    @value : String? = nil

    def text : String?
      @value
    end

    def text=(value : String)
      @value = value
    end
  end
end
