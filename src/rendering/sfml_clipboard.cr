require "../csfml3/wrapper"
require "../core/clipboard"

module CrymbleUI
  # Platform clipboard backed by SFML. `SF::Clipboard` talks to the OS clipboard
  # and needs a window/display, so this is only installed by the SFML renderer.
  class SFMLClipboard < Clipboard
    def string : String
      SF::Clipboard.string
    end

    def string=(value : String)
      SF::Clipboard.string = value
    end
  end
end
