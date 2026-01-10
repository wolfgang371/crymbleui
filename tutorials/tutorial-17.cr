# Tutorial 17: Keyboard Shortcuts
# =================================
# Explicit shortcuts on widgets and built-in framework shortcuts.
#
# Key concepts:
# EXPLICIT (user-defined on widgets):
# - button(label, shortcut: "^S") { } for Ctrl+S
# - menu_item(label, shortcut: "^N") { } in menus
# - Format: "^X" = Ctrl+X (Cmd+X on Mac)
#
# BUILT-IN (always available):
# - Ctrl++/- or Ctrl+MouseWheel: zoom in/out
# - Ctrl+0: reset zoom to 100%
# - Ctrl+M: toggle maximize on focused panel
#
# Run with: shards build tutorial-17 && ./bin/tutorial-17

require "../src/crymble"

class ShortcutsDemo < CrymbleUI::App
  state message : String = "Try the shortcuts!"

  def build : CrymbleUI::Widget
    window("Shortcuts Demo", 550, 500) do
      menubar do
        menu("File") do
          menu_item("New", shortcut: "^N") { self.message = "New (Ctrl+N)" }
          menu_item("Save", shortcut: "^S") { self.message = "Save (Ctrl+S)" }
          separator
          menu_item("Quit", shortcut: "^Q") { quit }
        end
      end

      vstack(spacing: 15.0, padding: 20.0) do
        text("Shortcuts on menu items (see File menu)")

        text("---")
        text("Shortcuts on buttons:")

        hstack(spacing: 10.0) do
          button("Open", shortcut: "^O") do
            self.message = "Open (Ctrl+O)"
          end

          button("Print", shortcut: "^P") do
            self.message = "Print (Ctrl+P)"
          end
        end

        text("---")
        text("Built-in shortcuts (always available):")
        text("  Ctrl++/-  : Zoom in/out")
        text("  Ctrl+0    : Reset zoom to 100%")
        text("  Ctrl+M    : Maximize panel (see tutorial-12)")
        text("  Ctrl+MouseWheel : Zoom")

        spacer

        text(message, font_scale: 2)
      end
    end
  end
end

CrymbleUI.run(ShortcutsDemo.new)
