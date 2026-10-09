require "../spec_helper"

module CrymbleUI
  # Test widget that records notification calls
  class NotificationRecorder < Widget
    include LayerOwner

    getter raises = 0

    def initialize(id : String? = nil)
      super(id: id)
      @internal_layer = Layer.new("test_#{id}", Rect.zero, z_index: 100, owner_widget: self)
    end

    def on_ancestor_raised
      @raises += 1
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
  end

  # Simple container for testing notification broadcasting
  class NotificationBroadcaster < Widget
    def initialize(id : String? = nil)
      super(id: id)
    end

    def broadcast_raised
      notify_layer_owners_raised
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
  describe "ancestor raised notification" do
    it "calls on_ancestor_raised on LayerOwner descendants" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      recorder = CrymbleUI::NotificationRecorder.new(id: "child")
      broadcaster.add_child(recorder)

      broadcaster.broadcast_raised

      recorder.raises.should eq 1
    end
  end

  describe "pull-based bounds" do
    it "layer.bounds returns compute_bounds_for_layer result (== absolute_bounds)" do
      recorder = CrymbleUI::NotificationRecorder.new(id: "owner")
      recorder.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 100.0)),
                       CrymbleUI::Vec2.new(50.0, 60.0))
      layer = recorder.layer!

      layer.bounds.x.should eq 50.0
      layer.bounds.y.should eq 60.0
      layer.bounds.width.should eq 100.0
      layer.bounds.height.should eq 100.0
    end
  end

  describe "nested LayerOwner propagation" do
    it "notifies all nested LayerOwner widgets (through non-LayerOwner intermediates)" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      middle = CrymbleUI::NotificationBroadcaster.new(id: "middle")
      recorder1 = CrymbleUI::NotificationRecorder.new(id: "child1")
      recorder2 = CrymbleUI::NotificationRecorder.new(id: "child2")

      broadcaster.add_child(middle)
      middle.add_child(recorder1)   # nested under a non-LayerOwner intermediate
      broadcaster.add_child(recorder2)

      broadcaster.broadcast_raised

      recorder1.raises.should eq 1
      recorder2.raises.should eq 1
    end

    it "does not fail when the subtree has no LayerOwner widgets" do
      broadcaster = CrymbleUI::NotificationBroadcaster.new(id: "parent")
      broadcaster.add_child(CrymbleUI::NotificationBroadcaster.new(id: "middle"))
      broadcaster.broadcast_raised # should not raise
    end
  end
end
