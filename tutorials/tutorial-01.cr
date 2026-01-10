# Tutorial 01: Hello World
# =========================
# The simplest CrymbleUI application.
#
# Key concepts:
# - Every app extends CrymbleUI::App
# - build() returns the widget tree (must return a Window)
# - CrymbleUI.run() starts the event loop
#
# Run with: shards build tutorial-01 && ./bin/tutorial-01

require "../src/crymble"

class HelloWorld < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Hello World", 400, 200) do
      text("Hello, CrymbleUI!")
    end
  end
end

CrymbleUI.run(HelloWorld.new)
