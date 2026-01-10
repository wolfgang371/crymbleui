# Tutorial 12: WindowPanel
# =========================
# Floating, draggable, resizable panels.
#
# Key concepts:
# - window_panel(title:, x:, y:, width:, height:) { content }
# - Drag by title bar, resize by edges/corners
# - Double-click title bar to maximize (or Ctrl+M)
# - closeable: true adds X button
# - z_index: controls stacking order
#
# Run with: shards build tutorial-12 && ./bin/tutorial-12

require "../src/crymble"

class WindowPanelDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("WindowPanel Demo", 600, 400) do
      window_panel(title: "Panel A", x: 20.0, y: 20.0, width: 200.0, height: 150.0) do
        vstack(padding: 10.0) do
          text("I'm Panel A")
          text("Drag my title bar!")
        end
      end

      window_panel(title: "Panel B", x: 250.0, y: 50.0, width: 200.0, height: 150.0,
                   closeable: true) do
        vstack(padding: 10.0) do
          text("I'm Panel B")
          text("I have a close button")
          button("Click me") { puts "Panel B button!" }
        end
      end

      window_panel(title: "Resizable", x: 100.0, y: 200.0, width: 250.0, height: 120.0,
                   resizable: true) do
        vstack(padding: 10.0) do
          text("Resize me from edges!")
        end
      end
    end
  end
end

CrymbleUI.run(WindowPanelDemo.new)
