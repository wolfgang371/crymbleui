require "../src/crymble"

# StatusBar Demo - Block-based dynamic text updates
# StatusBar accepts a block that computes text, checks for changes, and only re-renders if needed
class StatusBarApp < CrymbleUI::App
    state clicks : Int32 = 0

    def build : CrymbleUI::Widget
        window("StatusBar Demo - Hover over buttons!", 600, 400) do
            # Main content area
            vstack(spacing: 15.0, padding: 10.0) do
                cpu_monitor
                text("StatusBar Demo", font_scale: 5)
                text("Hover over buttons to see messages in the status bar", font_scale: 0)
                text("Clicks: #{clicks}", font_scale: 2)

                # Set user_data on buttons for statusbar to read
                button("Increment Counter", user_data: {:hover_text => "Click to increment the counter"}) do
                    self.clicks += 1
                end

                button("Decrement Counter", user_data: {:hover_text => "Click to decrement the counter"}) do
                    self.clicks -= 1
                end

                button("Reset Counter", user_data: {:hover_text => "Click to reset the counter to zero"}) do
                    self.clicks = 0
                end
            end

            # StatusBar as direct child of window (positioned at bottom automatically)
            status = statusbar("Ready", font_scale: 5)

            # Wire up hover changes to update statusbar
            on_hover_change do
                text = hovered_widget.try { |w| w.user_data[:hover_text]? }
                status.text = text || "Ready"
            end
        end
    end
end

# Run the demo
CrymbleUI.run(StatusBarApp.new)
