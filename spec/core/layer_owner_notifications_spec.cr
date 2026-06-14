require "../spec_helper"

module CrymbleUI
  # Test widget that records notification calls
  class NotificationRecorder < Widget
    include LayerOwner

    getter resize_moves : Array({Float64, Float64, Float64, Float64}) = [] of {Float64, Float64, Float64, Float64}
    getter resize_ends : Int32 = 0
    getter z_index_changes : Array(Int32) = [] of Int32

    def initialize(id : String? = nil)
      super(id: id)
      @internal_layer = Layer.new("test_#{id}", Rect.zero, z_index: 100, owner_widget: self)
    end

    def on_ancestor_resize_move(dw : Float64, dh : Float64, dx : Float64 = 0.0, dy : Float64 = 0.0, clip_bounds : Rect? = nil)
      @resize_moves << {dw, dh, dx, dy}
      super  # Store @resize_clip_delta / @resize_clip_bounds via LayerOwner mixin
    end

    def on_ancestor_resize_end
      @resize_ends += 1
      super  # Clear @resize_clip_delta via LayerOwner mixin
    end

    def on_ancestor_z_index_changed(base_z : Int32)
      @z_index_changes << base_z
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(100.0, 100.0)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position.x, position.y, 100.0, 100.0)
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end

    def reset_recorders
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
    it "calls on_ancestor_resize_move on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_resize_move(50.0, -30.0)

      recorder.resize_moves.size.should eq 1
      recorder.resize_moves.first.should eq({50.0, -30.0, 0.0, 0.0})
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

  describe "pull-based bounds" do
    it "layer.bounds returns compute_bounds_for_layer result" do
      recorder = CrymbleUI::NotificationRecorder.new(id: "owner")
      recorder.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 100.0)),
                       CrymbleUI::Vec2.new(50.0, 60.0))
      layer = recorder.layer!

      # Layer bounds should match absolute_bounds (default compute_bounds_for_layer)
      layer.bounds.x.should eq 50.0
      layer.bounds.y.should eq 60.0
      layer.bounds.width.should eq 100.0
      layer.bounds.height.should eq 100.0
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

      broadcaster.broadcast_resize_move(5.0, 10.0)

      # Both recorders should receive the notification
      recorder1.resize_moves.size.should eq 1
      recorder2.resize_moves.size.should eq 1
    end

    it "propagates through non-LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")
      recorder = CrymbleUI::NotificationRecorder.new(id: "nested")

      broadcaster.add_child(middle)
      middle.add_child(recorder)

      broadcaster.broadcast_resize_move(15.0, 25.0)

      recorder.resize_moves.size.should eq 1
      recorder.resize_moves.first.should eq({15.0, 25.0, 0.0, 0.0})
    end
  end

  describe "resize flow" do
    it "supports complete resize lifecycle: move(s) -> end" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      # Simulate resize
      broadcaster.broadcast_resize_move(10.0, 20.0)
      broadcaster.broadcast_resize_move(20.0, 40.0)
      broadcaster.broadcast_resize_move(30.0, 60.0)
      broadcaster.broadcast_resize_end

      recorder.resize_moves.size.should eq 3
      recorder.resize_moves[0].should eq({10.0, 20.0, 0.0, 0.0})
      recorder.resize_moves[1].should eq({20.0, 40.0, 0.0, 0.0})
      recorder.resize_moves[2].should eq({30.0, 60.0, 0.0, 0.0})
      recorder.resize_ends.should eq 1
    end
  end

  describe "non-LayerOwner widgets" do
    it "does not fail when subtree has no LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")
      broadcaster.add_child(middle)

      # Should not raise
      broadcaster.broadcast_resize_move(1.0, 2.0)
      broadcaster.broadcast_resize_end
      broadcaster.broadcast_z_index_changed(100)
    end
  end
end
