require "../src/crymble-ui"

# Simple Overlay Demo - Two Layers
# Root Layer (z=0): Window auto-stacks content
# Overlay Layer (z=1): Full-window semi-transparent overlay
class OverlayDemo < CrymbleUI::App
    def build : CrymbleUI::Widget
        window("Overlay Demo", 400, 300) do
            # Root layer: auto-stacks vertically (no explicit vstack needed!)
            button("Button 1") { puts "Button 1!" }
            hstack do
                button("Button 2") { puts "Button 2!" }
                button("Button 3") { puts "Button 3!" }
            end

            # Overlay layer: zero-config full-window overlay with bright text
            layer do
                text("=== OVERLAY LAYER ===", font_scale: 5)
                cpu_monitor(font_scale: 3)
                button("Button 4") { puts "Button 4!" }
            end
        end
    end
end

CrymbleUI.run(OverlayDemo.new)
