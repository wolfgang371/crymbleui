# Tutorial 13: MenuBar
# =====================
# Application menus with dropdown items.
#
# Key concepts:
# - menubar { } creates the menu bar at window top
# - menu(label) { } creates a dropdown menu
# - menu_item(label) { action } for clickable items
# - separator for visual dividers between items
# - Menus open on click, close on click-outside
#
# Note: For keyboard shortcuts, see tutorial-17.
#
# Run with: shards build tutorial-13 && ./bin/tutorial-13

require "../src/crymble"

class MenuBarDemo < CrymbleUI::App
  state status : String = "Ready"

  def build : CrymbleUI::Widget
    window("MenuBar Demo", 500, 300) do
      menubar do
        menu("File") do
          menu_item("New") { self.status = "New file" }
          menu_item("Open") { self.status = "Open file" }
          menu_item("Save") { self.status = "Save file" }
          separator
          menu_item("Quit") { quit }
        end

        menu("Edit") do
          menu_item("Undo") { self.status = "Undo" }
          menu_item("Redo") { self.status = "Redo" }
          separator
          menu_item("Cut") { self.status = "Cut" }
          menu_item("Copy") { self.status = "Copy" }
          menu_item("Paste") { self.status = "Paste" }
        end

        menu("Help") do
          menu_item("About") { self.status = "About CrymbleUI" }
        end
      end

      vstack(padding: 20.0) do
        text("Status: #{status}")
        text("Click the menus above!")
      end
    end
  end
end

CrymbleUI.run(MenuBarDemo.new)
