require "../src/crymble"

# Demo application showcasing TextInput widget
class TextInputDemo < CrymbleUI::App
    # Form fields
    state username : String = ""
    state email : String = ""
    state message : String = "Hello, World!"

    # Track submissions
    state submitted : Bool = false

    def build : CrymbleUI::Widget
        window("TextInput Demo", 500, 600) do
            vstack(spacing: 15.0) do
                cpu_monitor
                text("TextInput Widget Demo", font_scale: 5)

                # Username field (QuickEntry mode for grid-like navigation)
                text("Username:", font_scale: 0)
                text_input(
                    value: self.username,
                    placeholder: "Enter username...",
                    width: 300.0,
                    mode: CrymbleUI::TextInputMode::QuickEntry
                ) { |v| self.username = v }

                # Email field
                text("Email:", font_scale: 0)
                text_input(
                    value: self.email,
                    placeholder: "your@email.com",
                    width: 300.0,
                    mode: CrymbleUI::TextInputMode::QuickEntry
                ) { |v| self.email = v }

                # Pre-filled field
                text("Message:", font_scale: 0)
                text_input(
                    value: self.message,
                    width: 300.0,
                    mode: CrymbleUI::TextInputMode::QuickEntry
                ) { |v| self.message = v }

                # Submit button
                button("Submit") do
                    self.submitted = true
                end

                # Show current values
                text("Current Values:", font_scale: 2)
                text("Username: '#{self.username}'", font_scale: -1)
                text("Email: '#{self.email}'", font_scale: -1)
                text("Message: '#{self.message}'", font_scale: -1)

                if self.submitted
                    text("Form submitted!", font_scale: 0, color: CrymbleUI::Color.new(0, 150, 0, 255))
                end

                # Reset button
                button("Reset") do
                    self.username = ""
                    self.email = ""
                    self.message = "Hello, World!"
                    self.submitted = false
                end
            end
        end
    end
end

# Run the demo
CrymbleUI.run(TextInputDemo.new)
