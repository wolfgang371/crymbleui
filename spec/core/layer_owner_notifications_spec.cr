require "../spec_helper"

module CrymbleUI
  # Test widget that records notification calls
  class NotificationRecorder < Widget
    include LayerOwner

    getter position_changes : Array(Vec2) = [] of Vec2
    getter resize_starts : Int32 = 0
    getter resize_moves : Array({Float64, Float64}) = [] of {Float64, Float64}
    getter resize_ends : Int32 = 0
    getter z_index_changes : Array(Int32) = [] of Int32

    def initialize(id : String? = nil)
      super(id: id)
      @internal_layer = Layer.new("test_#{id}", Rect.zero, z_index: 100, owner_widget: self)
    end

    def on_ancestor_position_changed(delta : Vec2)
      @position_changes << delta
    end

    def on_ancestor_resize_start
      @resize_starts += 1
    end

    def on_ancestor_resize_move(dw : Float64, dh : Float64)
      @resize_moves << {dw, dh}
    end

    def on_ancestor_resize_end
      @resize_ends += 1
    end

    def on_ancestor_z_index_changed(base_z : Int32)
      @z_index_changes << base_z
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(100.0, 100.0)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position.x, position.y, 100.0, 100.0)
      sync_layer_bounds
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end

    def reset_recorders
      @position_changes.clear
      @resize_starts = 0
      @resize_moves.clear
      @resize_ends = 0
      @z_index_changes.clear
    end
  end

  # Simple container for testing notification broadcasting
  class NotificationBroadcaster < Widget
    def initialize(id : String? = nil)
      super(id: id)
    end

    # Expose broadcast methods for testing
    def broadcast_position_changed(delta : Vec2)
      notify_layer_owners_position_changed(delta)
    end

    def broadcast_resize_start
      notify_layer_owners_resize_start
    end

    def broadcast_resize_move(dw : Float64, dh : Float64)
      notify_layer_owners_resize_move(dw, dh)
    end

    def broadcast_resize_end
      notify_layer_owners_resize_end
    end

    def broadcast_z_index_changed(new_z : Int32)
      notify_layer_owners_z_index_changed(new_z)
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(200.0, 200.0)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position.x, position.y, 200.0, 200.0)
      current_y = position.y
      children.each do |child|
        child.layout(constraints, Vec2.new(position.x, current_y))
        current_y += child.bounds.height
      end
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end
  end
end

describe CrymbleUI::LayerOwner do
  describe "ancestor notification callbacks" do
    it "calls on_ancestor_position_changed on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      delta = CrymbleUI::Vec2.new(10.0, 20.0)
      broadcaster.broadcast_position_changed(delta)

      recorder.position_changes.size.should eq 1
      recorder.position_changes.first.x.should eq 10.0
      recorder.position_changes.first.y.should eq 20.0
    end

    it "calls on_ancestor_resize_start on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_resize_start

      recorder.resize_starts.should eq 1
    end

    it "calls on_ancestor_resize_move on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_resize_move(50.0, -30.0)

      recorder.resize_moves.size.should eq 1
      recorder.resize_moves.first.should eq({50.0, -30.0})
    end

    it "calls on_ancestor_resize_end on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_resize_end

      recorder.resize_ends.should eq 1
    end

    it "calls on_ancestor_z_index_changed on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_z_index_changed(500)

      recorder.z_index_changes.size.should eq 1
      recorder.z_index_changes.first.should eq 500
    end
  end

  describe "nested LayerOwner propagation" do
    it "notifies all nested LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")
      recorder1 = CrymbleUI::NotificationRecorder.new(id: "child1")
      recorder2 = CrymbleUI::NotificationRecorder.new(id: "child2")

      broadcaster.add_child(middle)
      middle.add_child(recorder1)
      broadcaster.add_child(recorder2)

      delta = CrymbleUI::Vec2.new(5.0, 10.0)
      broadcaster.broadcast_position_changed(delta)

      # Both recorders should receive the notification
      recorder1.position_changes.size.should eq 1
      recorder2.position_changes.size.should eq 1
    end

    it "propagates through non-LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")  # Not a LayerOwner
      recorder = CrymbleUI::NotificationRecorder.new(id: "nested")

      broadcaster.add_child(middle)
      middle.add_child(recorder)

      delta = CrymbleUI::Vec2.new(15.0, 25.0)
      broadcaster.broadcast_position_changed(delta)

      recorder.position_changes.size.should eq 1
      recorder.position_changes.first.x.should eq 15.0
    end
  end

  describe "resize flow" do
    it "supports complete resize lifecycle: start -> move(s) -> end" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      # Simulate resize
      broadcaster.broadcast_resize_start
      broadcaster.broadcast_resize_move(10.0, 20.0)
      broadcaster.broadcast_resize_move(20.0, 40.0)
      broadcaster.broadcast_resize_move(30.0, 60.0)
      broadcaster.broadcast_resize_end

      recorder.resize_starts.should eq 1
      recorder.resize_moves.size.should eq 3
      recorder.resize_moves[0].should eq({10.0, 20.0})
      recorder.resize_moves[1].should eq({20.0, 40.0})
      recorder.resize_moves[2].should eq({30.0, 60.0})
      recorder.resize_ends.should eq 1
    end
  end

  describe "non-LayerOwner widgets" do
    it "does not fail when subtree has no LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")  # Not a LayerOwner
      broadcaster.add_child(middle)

      # Should not raise
      broadcaster.broadcast_position_changed(CrymbleUI::Vec2.new(1.0, 2.0))
      broadcaster.broadcast_resize_start
      broadcaster.broadcast_resize_move(1.0, 2.0)
      broadcaster.broadcast_resize_end
      broadcaster.broadcast_z_index_changed(100)
    end
  end
end
