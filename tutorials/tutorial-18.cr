# Tutorial 18: RecursiveGrid
# ============================
# 2D grid layout with array-based DSL.
#
# Key concepts:
# - recursive_grid { array_of_rows } where each row is array of widgets
# - Nested grids auto-span: cell with 2-row subgrid spans 2 rows
# - spacing: gap between cells
# - Great for forms and tabular layouts
#
# Syntax:
#   recursive_grid {
#     [
#       [widget, widget],     # Row 1
#       [widget, widget]      # Row 2
#     ]
#   }
#
# Run with: shards build tutorial-18 && ./bin/tutorial-18

require "../src/crymble-ui"

class RecursiveGridDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("RecursiveGrid Demo", 500, 350) do
      vstack(spacing: 20.0, padding: 20.0) do
        text("Simple 2x2 grid:")

        recursive_grid(spacing: 5.0) do
          [
            [button("A") { }, button("B") { }],
            [button("C") { }, button("D") { }]
          ]
        end

        text("Grid with nested subgrid (A spans 2 rows):")

        recursive_grid(spacing: 5.0) do
          [
            [button("A", padding: 20.0) { },
             recursive_grid(spacing: 3.0) {
               [
                 [button("B1") { }],
                 [button("B2") { }]
               ]
             }]
          ]
        end
      end
    end
  end
end

CrymbleUI.run(RecursiveGridDemo.new)
