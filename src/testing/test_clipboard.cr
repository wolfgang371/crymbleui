require "../core/clipboard"

module CrymbleUI::Testing
  # In-memory clipboard for headless specs — no SFML, no display.
  class TestClipboard < CrymbleUI::Clipboard
    @value = ""

    def string : String
      @value
    end

    def string=(value : String)
      @value = value
    end
  end
end
