# Tutorial 26: FlowLayout
# =======================
# Wrap-aware horizontal layout. Arranges children left-to-right and
# automatically wraps to the next row when they don't fit the available
# width. Think CSS flex-wrap, or a tag cloud that reflows on resize.
#
# Key concepts:
# - flow(hspacing:, vspacing:, padding:) { children } wraps children
#   adaptively based on container width
# - Resize the window and watch the rows re-pack — no manual chunking
#   or fixed column counts
# - hspacing controls gap between items on the same row
# - vspacing controls gap between rows
#
# Run with: shards build tutorial-26 && ./bin/tutorial-26

require "../src/crymble-ui"

include CrymbleUI

class Tutorial26App < CrymbleUI::App
  state check_count : Int32 = 0

  TAGS = %w(
    crystal ruby python rust go java c++ typescript javascript elixir haskell
    scala kotlin swift lua perl ocaml clojure racket zig nim
  )

  def build : CrymbleUI::Widget
    window("Tutorial 26: FlowLayout", 600, 400) do
      vstack(padding: 15.0, spacing: 12.0) do
        text("Resize the window — the tags below reflow automatically.", font_scale: 1)

        # Plain flow of buttons. No chunking, no max-per-row — the flow
        # measures each child against the available width and wraps as needed.
        flow(hspacing: 8.0, vspacing: 6.0) do
          TAGS.each do |tag|
            button(tag, padding: 4.0) { self.check_count += 1 }
          end
        end

        text("Clicks: #{check_count}", font_scale: -1)

        text("Mixed widths also wrap correctly:", font_scale: 1)
        flow(hspacing: 8.0, vspacing: 6.0) do
          [
            "short",
            "a somewhat longer chip",
            "tiny",
            "medium length",
            "an even longer one that takes a lot of width",
            "x",
            "another",
            "final entry"
          ].each do |s|
            button(s, padding: 4.0) { }
          end
        end
      end
    end
  end
end

CrymbleUI.run(Tutorial26App.new)
