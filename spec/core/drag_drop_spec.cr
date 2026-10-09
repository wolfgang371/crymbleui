require "../spec_helper"
require "../../src/core/drag_types"
require "../../src/core/draggable"
require "../../src/core/drop_target"
require "../../src/core/drag_manager"

# Test draggable widget
class TestDraggableWidget < CrymbleUI::Widget
  include CrymbleUI::Draggable

  property drag_data_value : String

  def initialize(@drag_data_value : String = "test_data")
    super(id: nil)
  end

  def get_drag_data : CrymbleUI::DragData?
    CrymbleUI::TextDragData.new(@drag_data_value)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(100, 50))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# Test drop target widget
class TestDropTarget < CrymbleUI::Widget
  include CrymbleUI::DropTarget

  property accepted_types : Array(String)
  property dropped_data : CrymbleUI::DragData?
  property drop_position : CrymbleUI::Vec2?

  def initialize(@accepted_types : Array(String) = ["text"])
    super(id: nil)
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    @accepted_types.includes?(data.data_type)
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    @dropped_data = data
    @drop_position = position
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200, 100)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(200, 100))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A drop target that refuses by raising, as embrace's configurator does for a move it cannot make.
class RefusingDropTarget < TestDropTarget
  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
    raise "cannot move that here"
  end
end

# Simple concrete widget for testing (root container), laid out as a root always is - the drop
# search starts from a hit test, which needs the root's bounds.
class TestContainerWidget < CrymbleUI::Widget
  def initialize
    super(id: nil)
    @bounds = CrymbleUI::Rect.new(0, 0, 800, 600)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(800, 600)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(800, 600))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

describe CrymbleUI::DragManager do
  describe "drag state" do
    it "starts in idle state" do
      manager = CrymbleUI::DragManager.new
      manager.state.phase.should eq(CrymbleUI::DragPhase::Idle)
      manager.dragging?.should be_false
    end

    it "enters pending state on begin_drag_tracking" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      manager.state.phase.should eq(CrymbleUI::DragPhase::Pending)
      manager.state.source_widget.should eq(widget)
    end

    it "ignores non-draggable widgets" do
      manager = CrymbleUI::DragManager.new
      widget = TestContainerWidget.new

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      manager.state.phase.should eq(CrymbleUI::DragPhase::Idle)
    end
  end

  describe "drag threshold" do
    it "stays pending below threshold" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      # Create a root widget for hit testing
      root = TestContainerWidget.new

      # Move less than threshold (5 pixels)
      manager.update_drag(CrymbleUI::Vec2.new(22, 22), root)

      manager.state.phase.should eq(CrymbleUI::DragPhase::Pending)
      manager.dragging?.should be_false
    end

    it "becomes active after passing threshold" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      root = TestContainerWidget.new

      # Move more than threshold (5 pixels)
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)

      manager.state.phase.should eq(CrymbleUI::DragPhase::Active)
      manager.dragging?.should be_true
      manager.state.data.should_not be_nil
    end
  end

  describe "ghost layer" do
    it "creates ghost layer when drag becomes active" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      root = TestContainerWidget.new
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)

      manager.ghost_layer.should_not be_nil
      ghost = manager.ghost_layer.not_nil!
      ghost.id.should eq("drag_ghost")
      ghost.z_index.should eq(CrymbleUI::DragManager::GHOST_Z_INDEX)
    end

    it "clears ghost layer on end_drag" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      root = TestContainerWidget.new
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)
      manager.ghost_layer.should_not be_nil

      manager.end_drag(CrymbleUI::Vec2.new(100, 100))

      manager.ghost_layer.should be_nil
      manager.dragging?.should be_false
    end
  end

  describe "drop target detection" do
    it "detects valid drop target" do
      manager = CrymbleUI::DragManager.new

      # Create draggable
      draggable = TestDraggableWidget.new("hello")
      draggable.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      # Create drop target
      target = TestDropTarget.new(["text"])
      target.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(200, 200)
      )

      # Create root with both widgets
      root = TestContainerWidget.new
      root.add_child(draggable)
      root.add_child(target)

      # Start drag
      manager.begin_drag_tracking(draggable, CrymbleUI::Vec2.new(20, 20))
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)  # Pass threshold

      # Move over target
      manager.update_drag(CrymbleUI::Vec2.new(250, 250), root)

      manager.state.current_target.should eq(target)
      target.drag_hover?.should be_true
    end

    it "completes drop on valid target" do
      manager = CrymbleUI::DragManager.new

      # Create draggable
      draggable = TestDraggableWidget.new("hello")
      draggable.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      # Create drop target
      target = TestDropTarget.new(["text"])
      target.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(200, 200)
      )

      # Create root
      root = TestContainerWidget.new
      root.add_child(draggable)
      root.add_child(target)

      # Perform drag
      manager.begin_drag_tracking(draggable, CrymbleUI::Vec2.new(20, 20))
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)  # Pass threshold
      manager.update_drag(CrymbleUI::Vec2.new(250, 250), root)  # Over target

      # Release
      drop_pos = CrymbleUI::Vec2.new(250, 250)
      manager.end_drag(drop_pos)

      # Verify drop occurred
      target.dropped_data.should_not be_nil
      data = target.dropped_data.as(CrymbleUI::TextDragData)
      data.text.should eq("hello")
      target.drop_position.should eq(drop_pos)
    end

    it "ends the drag even when the target refuses by raising in on_drop" do
      manager = CrymbleUI::DragManager.new
      draggable = TestDraggableWidget.new("hello")
      draggable.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)), CrymbleUI::Vec2.new(10, 10))
      target = RefusingDropTarget.new
      target.perform_layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)), CrymbleUI::Vec2.new(200, 200))
      root = TestContainerWidget.new
      root.add_child(draggable)
      root.add_child(target)
      manager.begin_drag_tracking(draggable, CrymbleUI::Vec2.new(20, 20))
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)
      manager.update_drag(CrymbleUI::Vec2.new(250, 250), root)
      manager.state.active?.should be_true # control: the drag is live and over the target
      expect_raises(Exception, "cannot move that here") { manager.end_drag(CrymbleUI::Vec2.new(250, 250)) }
      manager.state.phase.idle?.should be_true # else the next drag cannot start
    end

    it "rejects incompatible data types" do
      manager = CrymbleUI::DragManager.new

      # Create draggable with "text" type
      draggable = TestDraggableWidget.new("hello")
      draggable.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      # Create drop target that only accepts "image" type
      target = TestDropTarget.new(["image"])
      target.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(200, 200)
      )

      # Create root
      root = TestContainerWidget.new
      root.add_child(draggable)
      root.add_child(target)

      # Perform drag
      manager.begin_drag_tracking(draggable, CrymbleUI::Vec2.new(20, 20))
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)
      manager.update_drag(CrymbleUI::Vec2.new(250, 250), root)

      # Target should not be detected as valid
      manager.state.current_target.should be_nil
      target.drag_hover?.should be_false
    end
  end

  describe "drag cancellation" do
    it "cancels drag on cancel_drag" do
      manager = CrymbleUI::DragManager.new
      widget = TestDraggableWidget.new
      widget.perform_layout(
        CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800, 600)),
        CrymbleUI::Vec2.new(10, 10)
      )

      manager.begin_drag_tracking(widget, CrymbleUI::Vec2.new(20, 20))

      root = TestContainerWidget.new
      manager.update_drag(CrymbleUI::Vec2.new(30, 30), root)  # Activate
      manager.dragging?.should be_true

      manager.cancel_drag

      manager.dragging?.should be_false
      manager.state.phase.should eq(CrymbleUI::DragPhase::Idle)
      manager.ghost_layer.should be_nil
    end
  end
end

describe CrymbleUI::DragData do
  describe CrymbleUI::TextDragData do
    it "has correct data type" do
      data = CrymbleUI::TextDragData.new("hello")
      data.data_type.should eq("text")
      data.text.should eq("hello")
      data.display_text.should eq("hello")
    end
  end

  describe CrymbleUI::WidgetDragData do
    it "has correct data type" do
      widget = TestContainerWidget.new
      data = CrymbleUI::WidgetDragData.new(widget, source_index: 3)
      data.data_type.should eq("widget")
      data.widget.should eq(widget)
      data.source_index.should eq(3)
    end
  end
end

describe CrymbleUI::DragState do
  it "calculates threshold correctly" do
    state = CrymbleUI::DragState.new
    state.start_position = CrymbleUI::Vec2.new(10, 10)

    # Less than 5 pixels
    state.passed_threshold?(CrymbleUI::Vec2.new(12, 12)).should be_false

    # Exactly 5 pixels
    state.passed_threshold?(CrymbleUI::Vec2.new(14, 13)).should be_true

    # More than 5 pixels
    state.passed_threshold?(CrymbleUI::Vec2.new(20, 20)).should be_true
  end
end

# A drag source that logs its hooks and offers what it is given.
private class HookedDraggable < CrymbleUI::Widget
  include CrymbleUI::Draggable
  getter log = [] of String
  property offer : CrymbleUI::DragData?

  def initialize(@offer : CrymbleUI::DragData? = nil, id : String = "src")
    super(id: id)
  end

  def get_drag_data : CrymbleUI::DragData?
    @offer
  end

  def on_drag_start(data : CrymbleUI::DragData)
    @log << "start"
  end

  def on_drag_end(data : CrymbleUI::DragData, dropped : Bool)
    @log << "end"
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(100, 50))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private def rooted(*children : CrymbleUI::Widget) : CrymbleUI::Widget
  root = CrymbleUI::VStack.new(id: "root")
  children.each { |c| root.add_child(c) }
  root
end

# A rebuild replaces the source of a drag still PENDING: the payload is the gesture's, taken from the source
# that was pressed (DragManager#rebind). Each case names the mutation that turns it red.
describe "DragManager: a rebuild during a pending drag" do
  # Mutation: cancel_drag calls on_drag_end for a pending drag - it never announced itself.
  it "cancels a pending drag holding a payload without a drag end" do
    old = HookedDraggable.new(CrymbleUI::TextDragData.new("x"))
    rooted(old)
    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(old, CrymbleUI::Vec2.new(20, 20))
    fresh = HookedDraggable.new # the rebuilt instance offers nothing
    manager.rebind { |w| w.same?(old) ? fresh : nil } # the rebuild replaced the pressed one with `fresh`
    manager.state.source_widget.same?(fresh).should be_true # instrument: the source was replaced
    manager.payload.as(CrymbleUI::TextDragData).text.should eq("x") # the pressed one's payload
    manager.cancel_drag
    fresh.log.should be_empty
    old.log.should be_empty
  end

  # Mutation: take the payload after the re-find (still from the old source) - its widget is not re-pointed.
  it "re-points a widget payload at the rebuilt widget" do
    old = HookedDraggable.new
    old.offer = CrymbleUI::WidgetDragData.new(old)
    rooted(old)
    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(old, CrymbleUI::Vec2.new(20, 20))
    fresh = HookedDraggable.new
    manager.rebind { |w| w.same?(old) ? fresh : nil } # the rebuild replaced the pressed one with `fresh`
    manager.payload.as(CrymbleUI::WidgetDragData).widget.same?(fresh).should be_true
  end

  # Mutation: drag_onto continuing any pending drag - it continues only the one pressed on this source.
  it "refuses to drag another source while one is pending" do
    a = HookedDraggable.new(CrymbleUI::TextDragData.new("a"), id: "a")
    b = HookedDraggable.new(CrymbleUI::TextDragData.new("b"), id: "b")
    target = TestDropTarget.new
    rooted(a, b, target)
    manager = CrymbleUI::DragManager.new
    manager.begin_drag_tracking(a, CrymbleUI::Vec2.new(20, 20))
    expect_raises(Exception, /in progress/) { manager.drag_onto(b, target, CrymbleUI::Vec2.new(20, 120)) }
  end
end
