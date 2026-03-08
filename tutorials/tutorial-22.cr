# Tutorial 22: VirtualMatrix with Sticky Headers
# ================================================
# Grouped hierarchical headers: level 0 spans 4, level 1 spans 2 data cells.
# Run with: shards build tutorial-22 && ./bin/tutorial-22

require "../src/crymble-ui"
include CrymbleUI
include CrymbleUI::Widgets::VirtualMatrix

class TutorialAdapter
  include MatrixAdapter

  @total_rows : Int32
  @total_cols : Int32
  @data : Hash(Tuple(Int32, Int32), String)
  property on_button_click : Proc(Nil) = ->{ }

  def initialize(@data_rows : Int32, @data_cols : Int32)
    @total_rows = 2 + @data_rows
    @total_cols = 2 + @data_cols
    @data = Hash(Tuple(Int32, Int32), String).new { |h, k| h[k] = default_value(k[0], k[1]) }
  end
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...@total_rows).to_a + [1, 0], (2...@total_cols).to_a + [1, 0]}
  end
  def get_sizes : {Array(Float64), Array(Float64)}
    {Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 }, Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    if row < 2 && col < 2
      { {row, 0}, {row, 1} }
    elsif col < 2 && row >= 2
      span = col == 0 ? 4 : 2
      start = 2 + ((row - 2) // span) * span
      { {start, col}, {start + span - 1, col} }
    elsif row < 2 && col >= 2
      span = row == 0 ? 4 : 2
      start = 2 + ((col - 2) // span) * span
      { {row, start}, {row, start + span - 1} }
    else
      { {row, col}, {row, col} }
    end
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    white = Color.new(255, 255, 255, 255)
    return Text.new(@data[{row, col}], background_color: white, padding: 4.0) if row < 2 && col < 2
    return Text.new(@data[{row, col}], color: Color.new(60, 90, 180, 255), background_color: white, padding: 4.0) if col < 2
    return Text.new(@data[{row, col}], color: Color.new(180, 100, 40, 255), background_color: white, padding: 4.0) if row < 2
    return Checkbox.new("Check", background_color: white) if row == 10 && col == 5
    return Button.new("Click") { @on_button_click.call } if row == 11 && col == 5
    TextInput.new(value: @data[{row, col}], mode: TextInputMode::QuickEntry) { |v| @data[{row, col}] = v }
  end

  private def default_value(row : Int32, col : Int32) : String
    return "" if row < 2 && col < 2
    return "r#{col + 1}#{idx_letter((row - 2) // (col == 0 ? 4 : 2))}" if col < 2
    return "c#{row + 1}#{idx_letter((col - 2) // (row == 0 ? 4 : 2))}" if row < 2
    "(#{row - 2},#{col - 2})"
  end

  private def idx_letter(i : Int32) : String; r = "a"; i.times { r = r.succ }; r; end
end

class Tutorial22App < CrymbleUI::App
  state grid_size : Int32 = 100
  state checked : Bool = false
  @adapter : TutorialAdapter?
  @prev_size : Int32?

  def build : CrymbleUI::Widget
    if @prev_size != grid_size
      @prev_size = grid_size
      @adapter = TutorialAdapter.new(grid_size, grid_size)
    end
    adapter = @adapter.not_nil!
    adapter.on_button_click = ->{ self.checked = !checked }

    window("Tutorial 22: VirtualMatrix + Sticky Headers", 900, 600) do
      aligned_layer(align: Alignment::TopRight, margin: 10.0, z_index: 100) { cpu_monitor }
      vstack(padding: 10.0, spacing: 5.0) do
        text("Grid: #{grid_size}×#{grid_size} data cells, 2 sticky row + 2 sticky col headers")
        hstack(spacing: 10.0) do
          [100, 1000, 10000].each { |s| button("#{s}²") { self.grid_size = s } }
          checkbox("Toggled by grid button", checked: checked) { }
        end
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "matrix",
            content_background_color: Color.new(200, 200, 205, 255),
            cursor_highlight_delta: -40))
        end
      end
    end
  end
end

CrymbleUI.run(Tutorial22App.new)
