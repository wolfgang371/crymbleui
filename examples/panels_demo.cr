require "../src/crymble"

# Window Panels Demo (V2)
# Demonstrates:
# - Multiple floating panels within a window
# - Draggable panels (drag title bar to move)
# - Resizable panels (drag edges/corners to resize)
# - Closeable panels (X button in title bar)
# - Z-ordering (click panel to bring to front)
# - Panel content layout adapts to resize
class PanelsDemo < CrymbleUI::App
    state click_count : Int32 = 0

    # Count open (non-closed) panels in current widget tree
    def open_panel_count : Int32
        return 3 unless r = @root  # Default to 3 if no root yet (initial build)
        panels = r.find_all { |w| w.is_a?(CrymbleUI::WindowPanel) }.map(&.as(CrymbleUI::WindowPanel))
        panels.count { |p| !p.closed }
    end

    def build : CrymbleUI::Widget
        window("CrymbleUI - Window Panels Demo", 800, 600) do
            # CPU monitor overlay in top-right corner (high z_index to stay on top of panels)
            aligned_layer(align: CrymbleUI::Alignment::TopRight, margin: 10.0, z_index: 100) do
                cpu_monitor
            end

            # Main content area
            vstack(id: "main_content", spacing: 10.0) do
                text(
                    "Window Panels Demo (V2)",
                    id: "title",
                    font_scale: 5,
                    color: CrymbleUI::Color.new(0, 100, 180, 255)
                )

                text(
                    "Try the interactive features:",
                    id: "subtitle",
                    font_scale: 1
                )

                text(
                    "• Drag title bar to move panels",
                    font_scale: -1
                )

                text(
                    "• Drag edges/corners to resize panels",
                    font_scale: -1
                )

                text(
                    "• Click X button to close panels",
                    font_scale: -1
                )

                text(
                    "• Click any panel to bring it to front",
                    font_scale: -1
                )

                text(
                    "Click count: #{@click_count}",
                    id: "counter",
                    font_scale: 1
                )
            end

            # Floating panel 1 - Tools
            window_panel("Tools", x: 50.0, y: 100.0, width: 200.0, height: 150.0, id: "tools_panel") do
                vstack(spacing: 5.0) do
                    text("Tool Panel", font_scale: -1)

                    button("Increment", font_scale: -1, padding: 5.0) {
                        self.click_count += 1
                    }

                    button("Decrement", font_scale: -1, padding: 5.0) {
                        self.click_count -= 1
                    }

                    button("Reset",
                        font_scale: -1,
                        padding: 5.0,
                        background_color: CrymbleUI::Color.new(180, 0, 0, 255),
                        border_color: CrymbleUI::Color.new(140, 0, 0, 255)
                    ) {
                        self.click_count = 0
                    }
                end
            end

            # Floating panel 2 - Inspector
            window_panel("Inspector", x: 550.0, y: 100.0, width: 220.0, height: 200.0, id: "inspector_panel") do
                vstack(spacing: 5.0) do
                    text("Inspector Panel", font_scale: -1)

                    text("Count: #{@click_count}", font_scale: -2)
                    text("Even: #{@click_count.even?}", font_scale: -2)
                    text("Odd: #{@click_count.odd?}", font_scale: -2)
                    text("Positive: #{@click_count > 0}", font_scale: -2)
                    text("Negative: #{@click_count < 0}", font_scale: -2)
                end
            end

            # Floating panel 3 - Info
            window_panel("Info", x: 300.0, y: 350.0, width: 200.0, height: 120.0, id: "info_panel") do
                vstack(spacing: 5.0) do
                    text("Info Panel", font_scale: -1)
                    text("Version: 1.0", font_scale: -2)
                    text("Open Panels: #{open_panel_count}", font_scale: -2)
                    text("Framework: CrymbleUI", font_scale: -2)
                end
            end
        end
    end
end

# Run the demo
puts "Starting Window Panels Demo (V2)..."
puts "Features:"
puts "  • Drag panels by title bar"
puts "  • Resize panels by edges/corners"
puts "  • Close panels with X button"
puts "  • Click panels to bring to front (z-ordering)"
puts ""

CrymbleUI.run(PanelsDemo.new)
