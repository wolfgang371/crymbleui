# Tutorial 02: Button
# ====================
# Buttons with click events.
#
# Key concepts:
# - button(label) { action } creates a clickable button
# - The block is executed when clicked
# - Buttons respond to mouse clicks and keyboard (Enter/Space when focused)
#
# Run with: shards build tutorial-02 && ./bin/tutorial-02

require "../src/crymble-ui"

class ButtonDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Button Demo", 400, 200) do
      button("Click me!") do
        puts "Button was clicked!"
      end
    end
  end
end

CrymbleUI.run(ButtonDemo.new)
