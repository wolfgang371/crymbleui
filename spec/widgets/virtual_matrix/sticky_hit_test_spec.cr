require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Adapter with sticky headers (row 0 and col 0 are sticky via scroll_order)
class StickyHitTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # Sticky: row 0 and col 0 scroll out LAST
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("#{row},#{col}")
  end
end

describe "VirtualMatrix sticky header hit-testing" do
  # Cell pixel sizes with defaults:
  #   row_height_pixels = GRID_SPACING(3) + DEFAULT_ROW_HEIGHT(1.0) * frame_height(20) = 23px
  #   col_width_pixels  = GRID_SPACING(3) + DEFAULT_COLUMN_WIDTH(5.0) * frame_height(20) = 103px
  # Sticky row 0 occupies screen y=[0, 23). Sticky col 0 occupies screen x=[0, 103).

  it "clicking sticky row header selects header row, not hidden content" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyHitTestAdapter.new(50, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_hit_row")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll down 200px (~8 content rows slide under sticky row 0)
    # Use reactive_property (… layout: true) setter which calls mark_needs_layout
    matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, 200.0)
    if layer = matrix.content_layer
      layer.scroll_offset = matrix.scroll_offset
    end
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Click at (200, 10) — x in content area, y within sticky row 0's 23px band
    click_at(app, 200.0, 10.0)

    # Should select row 0 (the sticky header), NOT ~row 9 (hidden content)
    matrix.cursor_rc[0].should eq(0),
      "Expected cursor at row 0 (sticky header), got row #{matrix.cursor_rc[0]}"
  end

  it "clicking sticky col header selects header col, not hidden content" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyHitTestAdapter.new(50, 20)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_hit_col")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll right 300px (~3 content cols slide under sticky col 0)
    matrix.scroll_offset = CrymbleUI::Vec2.new(300.0, 0.0)
    if layer = matrix.content_layer
      layer.scroll_offset = matrix.scroll_offset
    end
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Click at (50, 100) — x within sticky col 0's 103px band, y in content area
    click_at(app, 50.0, 100.0)

    # Should select col 0 (the sticky header), NOT ~col 3 (hidden content)
    matrix.cursor_rc[1].should eq(0),
      "Expected cursor at col 0 (sticky header), got col #{matrix.cursor_rc[1]}"
  end

  it "clicking sticky corner selects (0,0)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickyHitTestAdapter.new(50, 20)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_hit_corner")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Scroll both 200px down + 300px right
    matrix.scroll_offset = CrymbleUI::Vec2.new(300.0, 200.0)
    if layer = matrix.content_layer
      layer.scroll_offset = matrix.scroll_offset
    end
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    # Click at (50, 10) — both x and y within sticky bands
    click_at(app, 50.0, 10.0)

    # Should select (0, 0) — the sticky corner
    matrix.cursor_rc.should eq({0, 0}),
      "Expected cursor at (0,0) (sticky corner), got #{matrix.cursor_rc}"
  end
end
