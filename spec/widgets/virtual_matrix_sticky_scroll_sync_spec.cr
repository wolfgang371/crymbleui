require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Sticky Header Scroll Sync Tests
#
# Verifies that sticky cell positions are updated correctly after scrollbar-style
# scroll (via ScrollView.scroll_offset=), not just mouse wheel scroll.

# Adapter with sticky row 0 and col 0
class StickySyncTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def initialize(@rows : Int32, @cols : Int32)
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    # Sticky: row 0 and col 0 scroll out LAST → sticky_count = 1 each
    {(1...@rows).to_a + [0], (1...@cols).to_a + [0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    TestVisibleCell.new("R#{row}C#{col}")
  end
end

describe "VirtualMatrix sticky header scroll sync", tags: "slow" do
  # The definitive test: mouse wheel and scrollbar scroll to the same offset
  # must produce identical sticky cell positions.
  it "scrollbar and mouse wheel produce identical sticky cell positions" do
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))

    # Helper to create and set up a matrix
    setup = ->{
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      adapter = StickySyncTestAdapter.new(50, 10)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "test")
      app.root_widget = matrix
      app.build_tree
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      {renderer, app, matrix}
    }

    target_scroll_y = 60.0

    # A: Mouse wheel path
    renderer_a, app_a, matrix_a = setup.call
    wheel_delta = CrymbleUI::Vec2.new(0.0, -(target_scroll_y / 30.0))
    click_point = CrymbleUI::Vec2.new(200.0, 150.0)
    matrix_a.on_mouse_wheel(wheel_delta, click_point)
    renderer_a.render_frame(app_a)

    # B: Scrollbar path
    renderer_b, app_b, matrix_b = setup.call
    sv_b = matrix_b.content_scroll_view.not_nil!
    sv_b.scroll_offset = CrymbleUI::Vec2.new(0.0, target_scroll_y)
    renderer_b.render_frame(app_b)

    # Sanity: both at same scroll offset
    matrix_a.scroll_offset.y.should be_close(target_scroll_y, 1.0)
    matrix_b.scroll_offset.y.should be_close(target_scroll_y, 1.0)

    # Compare sticky col cell positions (row 2, col 0 — scrolls vertically)
    cell_a = matrix_a.active_cells[{2, 0}]?
    cell_b = matrix_b.active_cells[{2, 0}]?
    cell_a.should_not be_nil, "Wheel: sticky col cell (2,0) should exist"
    cell_b.should_not be_nil, "Scrollbar: sticky col cell (2,0) should exist"

    cell_a.not_nil!.bounds.y.should be_close(cell_b.not_nil!.bounds.y, 1.0),
      "Sticky col cell Y should match: wheel=#{cell_a.not_nil!.bounds.y} vs " \
      "scrollbar=#{cell_b.not_nil!.bounds.y}"
  end

  it "sticky col cells reposition correctly after scrollbar vertical scroll" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new

    adapter = StickySyncTestAdapter.new(50, 10)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sticky_sync")

    app.root_widget = matrix
    app.build_tree

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
    matrix.layout(constraints, CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    # Use mouse wheel as reference for correct positions
    # (mouse wheel path calls update_visible_cells directly = known good)
    scroll_amount = 60.0
    wheel_delta = CrymbleUI::Vec2.new(0.0, -(scroll_amount / 30.0))
    click_point = CrymbleUI::Vec2.new(200.0, 150.0)
    matrix.on_mouse_wheel(wheel_delta, click_point)
    renderer.render_frame(app)

    # Record reference position from wheel scroll
    ref_cell = matrix.active_cells[{2, 0}]?
    ref_cell.should_not be_nil
    wheel_y = ref_cell.not_nil!.bounds.y

    # Now scroll back to 0 (reset)
    wheel_back = CrymbleUI::Vec2.new(0.0, (scroll_amount / 30.0))
    matrix.on_mouse_wheel(wheel_back, click_point)
    renderer.render_frame(app)

    # Verify reset
    matrix.scroll_offset.y.should be_close(0.0, 1.0)

    # Now scroll via scrollbar path to same position
    scroll_view = matrix.content_scroll_view.not_nil!
    scroll_view.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll_amount)
    renderer.render_frame(app)

    # Scrollbar path should produce same position as wheel
    bar_cell = matrix.active_cells[{2, 0}]?
    bar_cell.should_not be_nil
    bar_y = bar_cell.not_nil!.bounds.y

    bar_y.should be_close(wheel_y, 1.0),
      "Scrollbar Y (#{bar_y}) should match wheel Y (#{wheel_y}) " \
      "for same scroll offset (#{scroll_amount})"
  end

  it "sticky row cells reposition correctly after scrollbar horizontal scroll" do
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 300.0))

    setup = ->{
      renderer = CrymbleUI::Testing::TestRenderer.new(800, 300)
      app = TestApp.new
      adapter = StickySyncTestAdapter.new(20, 50)
      matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "test")
      app.root_widget = matrix
      app.build_tree
      matrix.layout(constraints, CrymbleUI::Vec2.zero)
      renderer.settle_rendering(app)
      {renderer, app, matrix}
    }

    hscroll = 80.0

    # Mouse wheel reference
    renderer_a, app_a, matrix_a = setup.call
    wheel_delta = CrymbleUI::Vec2.new(0.0, -(hscroll / 30.0))
    matrix_a.on_mouse_wheel(wheel_delta, CrymbleUI::Vec2.new(400.0, 150.0), shift: true)
    renderer_a.render_frame(app_a)

    # Scrollbar path
    renderer_b, app_b, matrix_b = setup.call
    sv_b = matrix_b.content_scroll_view.not_nil!
    sv_b.scroll_offset = CrymbleUI::Vec2.new(hscroll, 0.0)
    renderer_b.render_frame(app_b)

    # Both should be at same horizontal offset
    matrix_a.scroll_offset.x.should be_close(hscroll, 1.0)
    matrix_b.scroll_offset.x.should be_close(hscroll, 1.0)

    # Compare sticky row cell X positions
    cell_a = matrix_a.active_cells[{0, 2}]?
    cell_b = matrix_b.active_cells[{0, 2}]?
    cell_a.should_not be_nil
    cell_b.should_not be_nil

    cell_a.not_nil!.bounds.x.should be_close(cell_b.not_nil!.bounds.x, 1.0),
      "Sticky row cell X should match: wheel=#{cell_a.not_nil!.bounds.x} vs " \
      "scrollbar=#{cell_b.not_nil!.bounds.x}"
  end
end
