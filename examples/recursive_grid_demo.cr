require "../src/crymble-ui"

# Cell data structure for the interactive grid
class Cell
  property text : String
  property is_subgrid : Bool
  property children : Array(Array(Cell))?

  def initialize(@text = "", @is_subgrid = false, @children = nil)
  end

  # Create a new cell with incremented counter
  def self.new_numbered : Cell
    @@counter ||= 0
    @@counter = @@counter.not_nil! + 1
    Cell.new(@@counter.to_s)
  end
end

# RecursiveGrid Demo Application
# Demonstrates:
# - Panel 1: Small static example showing spanning
# - Panel 2: Interactive grid with T/B/L/R/Sub buttons for on-the-fly editing
class RecursiveGridDemo < CrymbleUI::App
  # Red border color for edit mode
  EDIT_BORDER_COLOR = CrymbleUI::Color.new(200, 50, 50, 255)
  # Light blue background for edit-mode cells (makes spanning visible)
  EDIT_CELL_BACKGROUND = CrymbleUI::Color.new(200, 220, 240, 255)

  # State for interactive grid
  state grid_data : Array(Array(Cell)) = [[Cell.new("Hello")]]
  state edit_mode : Bool = true

  def build : CrymbleUI::Widget
    window("RecursiveGrid Demo", 900, 600) do
      hstack(id: "panels", spacing: 30.0) do
        # Panel 1: Static example
        vstack(id: "static_panel", spacing: 10.0) do
          text("Static Example", font_scale: 2, color: CrymbleUI::Color.new(0, 100, 180, 255))
          text("A spans 2 rows:", font_scale: -1)

          recursive_grid(spacing: 3.0) do
            [
              [button("A", padding: 15.0) { }, recursive_grid {
                [[button("B1", padding: 8.0) { }],
                 [button("B2", padding: 8.0) { }]]
              }]
            ]
          end
        end

        # Panel 2: Interactive grid
        vstack(id: "interactive_panel", spacing: 10.0) do
          text("Interactive Grid", font_scale: 2, color: CrymbleUI::Color.new(0, 100, 180, 255))

          checkbox("Edit mode", checked: edit_mode) do
            self.edit_mode = !edit_mode
          end

          if edit_mode
            text("T=Top B=Bottom L=Left R=Right Sub=Nest", font_scale: -3)
          end

          # Build the interactive grid from state
          build_interactive_grid
        end
      end
    end
  end

  # Build the interactive grid using recursive_grid DSL
  private def build_interactive_grid
    border = edit_mode ? EDIT_BORDER_COLOR : nil
    # cell_background_color auto-wraps cells in VStack with background for proper spanning
    recursive_grid(
      spacing: edit_mode ? 6.0 : 4.0,
      border_color: border,
      cell_background_color: EDIT_CELL_BACKGROUND
    ) do
      build_grid_content(grid_data)
    end
  end

  # Recursively build grid content from cell data
  private def build_grid_content(data : Array(Array(Cell))) : Array(Array(CrymbleUI::Widget))
    border = edit_mode ? EDIT_BORDER_COLOR : nil
    data.map_with_index do |row, ri|
      row.map_with_index do |cell, ci|
        if cell.is_subgrid && cell.children
          # Nested subgrid - also uses cell_background_color for consistent spanning
          grid = CrymbleUI::RecursiveGrid.new(
            content: build_grid_content(cell.children.not_nil!),
            spacing: edit_mode ? 6.0 : 4.0,
            cell_background_color: EDIT_CELL_BACKGROUND
          )
          grid.border_color = border if border
          grid
        else
          # Regular cell - RecursiveGrid auto-wraps in VStack with background
          build_cell_widget(cell, data, ri, ci)
        end
      end
    end
  end

  # Build a single cell widget (RecursiveGrid wraps this in VStack with background)
  private def build_cell_widget(cell : Cell, grid : Array(Array(Cell)), row : Int32, col : Int32) : CrymbleUI::Widget
    if edit_mode
      # Edit mode: VStack with edit buttons row + content
      CrymbleUI::VStack.new(spacing: 2.0).tap do |vs|
        # Edit buttons row
        hs = CrymbleUI::HStack.new(spacing: 1.0)
        hs.add_child(make_edit_btn("T") { insert_row_above(grid, row) })
        hs.add_child(make_edit_btn("B") { insert_row_below(grid, row) })
        hs.add_child(make_edit_btn("L") { insert_col_left(grid, col) })
        hs.add_child(make_edit_btn("R") { insert_col_right(grid, col) })
        hs.add_child(make_edit_btn("Sub") { make_subgrid(grid, row, col) })
        vs.add_child(hs)

        # Content button
        vs.add_child(CrymbleUI::Button.new(
          cell.text.empty? ? " " : cell.text,
          padding: 6.0
        ))
      end
    else
      # Non-edit mode: simple button (RecursiveGrid wraps in VStack with background)
      CrymbleUI::Button.new(cell.text.empty? ? " " : cell.text, padding: 10.0)
    end
  end

  # Helper to create small edit buttons
  private def make_edit_btn(label : String, &block : -> Nil) : CrymbleUI::Button
    CrymbleUI::Button.new(label, padding: 1.0, font_scale: -3, &block)
  end

  # Grid modification methods
  private def insert_row_above(grid : Array(Array(Cell)), row : Int32)
    new_row = Array.new(grid[0].size) { Cell.new_numbered }
    grid.insert(row, new_row)
    self.grid_data = grid_data  # Trigger rebuild
  end

  private def insert_row_below(grid : Array(Array(Cell)), row : Int32)
    new_row = Array.new(grid[0].size) { Cell.new_numbered }
    grid.insert(row + 1, new_row)
    self.grid_data = grid_data  # Trigger rebuild
  end

  private def insert_col_left(grid : Array(Array(Cell)), col : Int32)
    grid.each { |row| row.insert(col, Cell.new_numbered) }
    self.grid_data = grid_data  # Trigger rebuild
  end

  private def insert_col_right(grid : Array(Array(Cell)), col : Int32)
    grid.each { |row| row.insert(col + 1, Cell.new_numbered) }
    self.grid_data = grid_data  # Trigger rebuild
  end

  private def make_subgrid(grid : Array(Array(Cell)), row : Int32, col : Int32)
    cell = grid[row][col]
    cell.is_subgrid = true
    cell.children = [[Cell.new(cell.text)]]
    cell.text = ""
    self.grid_data = grid_data  # Trigger rebuild
  end
end

# Run the demo
CrymbleUI.run(RecursiveGridDemo.new)
