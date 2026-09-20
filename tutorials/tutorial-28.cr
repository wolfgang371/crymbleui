# Tutorial 28: Tabs
# =================
# Putting several pages in one panel, with a tab strip on top.
#
# Key concepts:
# - tabs(id:, active:) wraps tab("Label") { ... } pages; the strip is drawn on top and the
#   active page fills the rest of the box.
# - Every page is BUILT, not just the visible one. The hidden pages keep their widgets in the
#   tree, so ids stay findable — and the keyboard shortcuts they declare stay registered and
#   keep firing. Press Ctrl+2 below while the first tab is forward: the counter on the second
#   page still changes, because shortcuts belong to the panel, not to whichever page happens
#   to be showing.
# - `active` survives a rebuild, so the tab the user picked is not reset by unrelated state
#   changes.
#
# Run with: shards build tutorial-28 && ./bin/tutorial-28

require "../src/crymble-ui"

include CrymbleUI

class Tutorial28App < CrymbleUI::App
  state ones : Int32 = 0
  state twos : Int32 = 0

  def build : CrymbleUI::Widget
    window("Tutorial 28: Tabs", 620, 420) do
      window_panel("Report", 20.0, 20.0, 560.0, 340.0, id: "report") do
        # Kept OUTSIDE the tabs on purpose: a strip of context that should stay readable
        # whichever page is forward.
        text("Both pages are live. Ctrl+1 and Ctrl+2 work from either one.")

        tabs(id: "views", active: 0) do
          tab("Summary") do
            text("Summary page")
            text("counted on this page: #{@ones}")
            button("Count here", "^1", id: "count_one") { self.ones += 1 }
          end

          tab("Details") do
            text("Details page")
            text("counted on this page: #{@twos}")
            button("Count there", "^2", id: "count_two") { self.twos += 1 }
          end
        end
      end
    end
  end
end

CrymbleUI.run(Tutorial28App.new)
