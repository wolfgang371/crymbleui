require "../src/crymble-ui"

# Demo application showcasing checkbox features, including a tristate "Select all"
# that is a REAL union of the two boolean checkboxes above it.
class CheckboxDemo < CrymbleUI::App
    # Boolean checkboxes — the "items" the Select-all unions over.
    state auto_toggle : Bool = false
    state accept_terms : Bool = true

    # Counter to show rebuild behavior
    state rebuild_count : Int32 = 0

    # Tristate union of the two checkboxes above:
    #   none checked → Unchecked, all checked → Checked, some checked → Indeterminate.
    private def items_state : CrymbleUI::CheckState
        case [self.auto_toggle, self.accept_terms].count(true)
        when 0 then CrymbleUI::CheckState::Unchecked
        when 2 then CrymbleUI::CheckState::Checked
        else        CrymbleUI::CheckState::Indeterminate
        end
    end

    def build : CrymbleUI::Widget
        # Increment rebuild count to show rebuilds working
        @rebuild_count += 1

        window("Checkbox Demo", 600, 600) do
            vstack(spacing: 20.0) do
                cpu_monitor
                text("Checkbox Widget Demo", font_scale: 5)
                text("Rebuild count: #{@rebuild_count}", font_scale: 0)

                # Section: Auto-toggle over a plain state Bool (toggle: sugar)
                text("Boolean Checkbox (Auto-toggle with toggle:):", font_scale: 2)
                checkbox("Enable auto-toggle feature", toggle: auto_toggle)

                # Section: Boolean Checkbox with Manual Control
                text("Boolean Checkbox (Manual Control):", font_scale: 2)
                checkbox("Accept terms and conditions", checked: self.accept_terms) do
                    self.accept_terms = !self.accept_terms
                end

                # Section: Tristate "Select all" — a REAL union of the two boxes above.
                # It reflects their combined state, and on click sets BOTH
                # (toggle-all: clear if all are set, otherwise set all).
                text("Tristate \"Select all\" (union of the two above):", font_scale: 2)
                checkbox("Select all items", state: items_state) do
                    target = items_state != CrymbleUI::CheckState::Checked
                    self.auto_toggle = target
                    self.accept_terms = target
                end

                # Section: Current State Display
                text("Current State:", font_scale: 2)
                text("Auto-toggle: #{self.auto_toggle}", font_scale: 0)
                text("Accept terms: #{self.accept_terms}", font_scale: 0)
                text("Select all (union): #{items_state}", font_scale: 0)

                # Reset button
                button("Reset All") do
                    self.auto_toggle = false
                    self.accept_terms = false
                end
            end
        end
    end
end

# Run the demo
CrymbleUI.run(CheckboxDemo.new)
