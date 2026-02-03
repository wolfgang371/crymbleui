require "../src/crymble-ui"

# Demo application showcasing checkbox features
class CheckboxDemo < CrymbleUI::App
    # Boolean checkboxes
    state auto_toggle : Bool = false
    state accept_terms : Bool = true

    # Tristate checkbox
    state select_all : CrymbleUI::CheckState = CrymbleUI::CheckState::Unchecked

    # Counter to show rebuild behavior
    state rebuild_count : Int32 = 0

    def build : CrymbleUI::Widget
        # Increment rebuild count to show rebuilds working
        @rebuild_count += 1

        window("Checkbox Demo", 600, 600) do
            vstack(spacing: 20.0) do
                cpu_monitor
                text("Checkbox Widget Demo", font_scale: 5)
                text("Rebuild count: #{@rebuild_count}", font_scale: 0)

                # Section: Auto-toggle with Macro
                text("Boolean Checkbox (Auto-toggle with Macro):", font_scale: 2)
                checkbox("Enable auto-toggle feature", bind: auto_toggle)

                # Section: Boolean Checkbox with Manual Control
                text("Boolean Checkbox (Manual Control):", font_scale: 2)
                checkbox("Accept terms and conditions", checked: self.accept_terms) do
                    self.accept_terms = !self.accept_terms
                end

                # Section: Tristate Checkbox
                text("Tristate Checkbox:", font_scale: 2)
                checkbox("Select all items", state: self.select_all) do
                    current = self.select_all
                    self.select_all = case current
                    when CrymbleUI::CheckState::Unchecked then CrymbleUI::CheckState::Checked
                    when CrymbleUI::CheckState::Checked then CrymbleUI::CheckState::Indeterminate
                    when CrymbleUI::CheckState::Indeterminate then CrymbleUI::CheckState::Unchecked
                    else CrymbleUI::CheckState::Unchecked
                    end
                end

                # Section: Current State Display
                text("Current State:", font_scale: 2)
                text("Auto-toggle: #{self.auto_toggle}", font_scale: 0)
                text("Accept terms: #{self.accept_terms}", font_scale: 0)
                text("Tristate state: #{self.select_all}", font_scale: 0)

                # Reset button
                button("Reset All") do
                    self.accept_terms = false
                    self.auto_toggle = false
                    self.select_all = CrymbleUI::CheckState::Unchecked
                end
            end
        end
    end
end

# Run the demo
CrymbleUI.run(CheckboxDemo.new)
