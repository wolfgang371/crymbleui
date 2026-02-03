require "../src/crymble-ui"

# Hello World Counter Application
# Demonstrates:
# - Declarative UI with build()
# - Reactive state with `state` macro
# - Button callbacks (automatic rebuild on state change)
# - VStack layout
# - Text widgets
class HelloWorld < CrymbleUI::App
    # State macro automatically triggers rebuild when count changes
    state count : Int32 = 0

    def build : CrymbleUI::Widget
        # Declarative UI with DSL - much cleaner than manual widget creation!
        window("Hello World - CrymbleUI", 400, 300) do
            vstack(id: "container", spacing: 10.0) do
                cpu_monitor(font_scale: 3)

                # Title text
                text(
                    "Hello, CrymbleUI!",
                    id: "title",
                    font_scale: 5,
                    color: CrymbleUI::Color.new(0, 100, 180, 255)
                )

                # Counter display
                text(
                    "Count: #{count}",
                    id: "counter_text",
                    font_scale: 3
                )

                # Increment button - no manual rebuild needed!
                button("Increment") {
                    self.count += 1  # Must use self.count to trigger setter
                }

                # Decrement button
                button("Decrement") {
                    self.count -= 1  # Must use self.count to trigger setter
                }

                # Reset button with custom colors
                button(
                    "Reset",
                    id: "reset_btn",
                    background_color: CrymbleUI::Color.new(180, 0, 0, 255),
                    border_color: CrymbleUI::Color.new(140, 0, 0, 255)
                ) {
                    self.count = 0  # Must use self.count to trigger setter
                }
            end
        end
    end
end

# Run the Hello World application - window config is now declarative!
CrymbleUI.run(HelloWorld.new)
