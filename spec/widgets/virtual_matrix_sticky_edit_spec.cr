require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/input/focus_cycler"

# Tests that editing a sticky (header) cell in VirtualMatrix correctly marks
# the sticky layer dirty, not the content layer. This is a regression test
# for a bug where header cell edits were invisible until a full rebuild.

# Reuse the sticky adapter pattern from virtual_matrix_sticky_ghosting_spec.cr
class StickyEditTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  @data : Hash({Int32, Int32}, String)

  def initialize(@rows : Int32, @cols : Int32)
    @data = Hash({Int32, Int32}, String).new
  end

  # Sticky: row 0 scrolls out LAST, col 0 scrolls out LAST
  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_data(row : Int32, col : Int32) : String
    @data[{row, col}]? || "R#{row}C#{col}"
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(
      value: cell_data(row, col),
      mode: CrymbleUI::TextInputMode::QuickEntry
    )
  end

  # For write-back from TextInput widgets
  def cell_write(row : Int32, col : Int32, value : String)
    @data[{row, col}] = value
  end
end

describe "VirtualMatrix sticky header cell editing" do
  it "typing in a sticky corner cell marks the sticky corner layer dirty" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyEditTestAdapter.new(20, 5)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_edit")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Focus the matrix — cursor starts at {0, 0} which is a sticky corner cell
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    matrix.cursor_rc.should eq({0, 0})

    # Get layer references
    content_layer = matrix.content_layer.not_nil!
    sv = matrix.content_scroll_view.not_nil!
    sticky_corner_layer = sv.sticky_corner_layer.not_nil!

    # Settle after focus change
    renderer.settle_rendering(app)

    # Verify cell {0,0} is proxy-focused
    cell_00 = matrix.active_cells[{0, 0}]?
    cell_00.should_not be_nil
    cell_00 = cell_00.not_nil!

    # Clear render states
    content_layer.clear_render_state
    sticky_corner_layer.clear_render_state

    # Type a character
    fm.handle_text_input('X')

    # The sticky corner layer should be dirty — this is the bug
    sticky_corner_layer.needs_render?.should be_true,
      "Expected sticky_corner_layer to be marked dirty after typing, " \
      "but it was clean. The cell's mark_needs_render propagated to the wrong layer."

    # The cell should be in the sticky corner layer's dirty widgets, not content layer's
    sticky_corner_layer.dirty_widgets.should contain(cell_00),
      "Expected cell {0,0} in sticky_corner_layer.dirty_widgets"
  end

  it "sticky header cell pixels change after typing" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyEditTestAdapter.new(20, 5)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_pixel")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Focus at {0,0} (sticky corner)
    fm = CrymbleUI::Widget.focus_manager
    fm.focus(matrix)
    renderer.settle_rendering(app)

    # Read pixels from sticky corner layer before edit
    sv = matrix.content_scroll_view.not_nil!
    sticky_corner_layer = sv.sticky_corner_layer.not_nil!
    raw_backend = sticky_corner_layer.backend
    raw_backend.should_not be_nil, "sticky_corner_layer should have a backend after rendering"
    backend = raw_backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    before_pixels = [] of CrymbleUI::Color
    cell_00 = matrix.active_cells[{0, 0}].not_nil!
    abs_bounds = cell_00.absolute_bounds
    layer_bounds = sticky_corner_layer.bounds
    # Convert to layer-local coordinates
    local_x_start = abs_bounds.x.to_i - layer_bounds.x.to_i
    local_y_start = abs_bounds.y.to_i - layer_bounds.y.to_i
    local_x_end = local_x_start + [abs_bounds.width.to_i, 40].min
    local_y_end = local_y_start + [abs_bounds.height.to_i, 30].min
    # Sample a grid of pixels across the cell area (layer-local coords)
    (local_y_start...local_y_end).each do |y|
      (local_x_start...local_x_end).each do |x|
        px = backend.get_pixel(x, y)
        before_pixels << px if px
      end
    end

    before_pixels.should_not be_empty, "Should have sampled some pixels before edit"

    # Verify cell value before edit
    cell_00.as(CrymbleUI::TextInput).value.should eq("R0C0")

    # Type a character to change cell content
    fm.handle_text_input('Z')

    # Verify cell value changed
    cell_00.as(CrymbleUI::TextInput).value.should_not eq("R0C0"),
      "TextInput value didn't change after typing"

    renderer.settle_rendering(app)

    # Re-get backend (may have been recreated)
    backend_after = sticky_corner_layer.backend.not_nil!.as(CrymbleUI::Testing::TestRenderBackend)

    # Read pixels after — they should differ
    after_pixels = [] of CrymbleUI::Color
    (local_y_start...local_y_end).each do |y|
      (local_x_start...local_x_end).each do |x|
        px = backend_after.get_pixel(x, y)
        after_pixels << px if px
      end
    end

    after_pixels.should_not eq(before_pixels),
      "Expected sticky corner cell pixels to change after typing, but they didn't. " \
      "The edit was not visually applied to the sticky layer."
  end
end
