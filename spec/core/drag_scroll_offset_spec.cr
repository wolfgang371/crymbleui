require "../spec_helper"
require "../../src/testing/test_renderer"

# A row of the shape the user actually drags: an entry inside a SCROLLED panel
# (the embrace field list lives in one since the config became scrollable).
class ScrolledDragRow < CrymbleUI::Widget
  include CrymbleUI::Draggable

  ROW_HEIGHT = 50.0

  def initialize(@label : String)
    super(id: nil)
  end

  def get_drag_data : CrymbleUI::DragData?
    CrymbleUI::TextDragData.new(@label)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, ROW_HEIGHT)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(constraints.max_width, ROW_HEIGHT))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

class ScrolledDropRow < CrymbleUI::Widget
  include CrymbleUI::DropTarget

  ROW_HEIGHT = 50.0

  getter dropped : CrymbleUI::DragData? = nil

  def initialize
    super(id: nil)
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    data.data_type == "text"
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @dropped = data
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, ROW_HEIGHT)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(constraints.max_width, ROW_HEIGHT))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Builds a scrolled panel: 12 rows of 50px inside a 300px viewport, the drag row
# at index `drag_at` and a drop row at index `drop_at`, scrolled down by `scroll`.
private def scrolled_panel(scroll : Float64, drag_at : Int32 = 6, drop_at : Int32 = 8)
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  window = CrymbleUI::Window.new("Test", 400, 300)

  scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
  vstack = CrymbleUI::VStack.new(spacing: 0.0)
  drag_row = ScrolledDragRow.new("Time")
  drop_row = ScrolledDropRow.new
  12.times do |i|
    case i
    when drag_at then vstack.add_child(drag_row)
    when drop_at then vstack.add_child(drop_row)
    else              vstack.add_child(ScrolledDragRow.new("row#{i}"))
    end
  end
  scroll_view.set_content(vstack)

  window.add_child(scroll_view)
  app.root_widget = window
  renderer.render_frame(app)

  scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll))
  renderer.render_frame(app)

  {window, scroll_view, drag_row, drop_row}
end

# The drag ghost and the drop highlight are drawn in WINDOW coordinates, but a widget
# inside a ScrollView keeps its LAID-OUT (content) bounds — the layer composites shifted
# by scroll_offset. Anything that meets the cursor must convert, or it is displaced by
# exactly the scroll amount.
describe "drag inside a scrolled ScrollView" do
  it "keeps the ghost under the cursor" do
    scroll = 150.0
    window, _sv, drag_row, _drop = scrolled_panel(scroll)

    # Where the row is PAINTED, and where inside it the user grabs.
    visual_y = drag_row.absolute_bounds.y - scroll
    grab = CrymbleUI::Vec2.new(40.0, visual_y + 10.0)

    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(drag_row, grab)
    cursor = CrymbleUI::Vec2.new(grab.x, grab.y + 20.0)
    manager.update_drag(cursor, window)

    manager.state.active?.should be_true
    ghost = manager.ghost_layer.should_not be_nil
    # The ghost sticks to the cursor: it keeps the grab offset, nothing else.
    ghost.bounds.y.should be_close(cursor.y - 10.0, 0.5)
    ghost.bounds.x.should be_close(cursor.x - (grab.x - drag_row.absolute_bounds.x), 0.5)
  end

  it "finds and highlights the drop row the cursor is actually over" do
    scroll = 150.0
    window, _sv, drag_row, drop_row = scrolled_panel(scroll)

    visual_y = drag_row.absolute_bounds.y - scroll
    grab = CrymbleUI::Vec2.new(40.0, visual_y + 10.0)

    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(drag_row, grab)
    # Like a real mouse: the threshold move activates the drag, the next one hovers a target.
    manager.update_drag(CrymbleUI::Vec2.new(grab.x, grab.y + 10.0), window)

    drop_visual_y = drop_row.absolute_bounds.y - scroll
    over_drop = CrymbleUI::Vec2.new(40.0, drop_visual_y + 25.0)
    manager.update_drag(over_drop, window)

    manager.state.current_target.should eq(drop_row)
    highlight = manager.highlight_layer.should_not be_nil
    highlight.bounds.y.should be_close(drop_visual_y, 0.5)
  end

  # Control: unscrolled, the two spaces coincide and nothing may shift.
  it "is exact when nothing is scrolled" do
    window, _sv, drag_row, _drop = scrolled_panel(0.0)

    grab = CrymbleUI::Vec2.new(40.0, drag_row.absolute_bounds.y + 10.0)
    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(drag_row, grab)
    cursor = CrymbleUI::Vec2.new(grab.x, grab.y + 20.0)
    manager.update_drag(cursor, window)

    ghost = manager.ghost_layer.should_not be_nil
    ghost.bounds.y.should be_close(cursor.y - 10.0, 0.5)
  end
end
