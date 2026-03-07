require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

describe CrymbleUI::VirtualMatrix do
  describe "Layer Infrastructure" do
    it "creates VirtualMatrix with LayerOwner" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5)
      matrix.responds_to?(:layer).should be_true
      matrix.responds_to?(:on_ancestor_position_changed).should be_true
    end

    it "creates content layer with correct z-index" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "test_matrix")

      # Trigger layout to create layers
      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Should have content layer created
      matrix.content_layer.should_not be_nil

      # Content layer should have z_index > 0
      matrix.content_layer.not_nil!.z_index.should be >= 1
    end

    it "sets owner_widget on content layer" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "owner_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      matrix.content_layer.not_nil!.owner_widget.should eq(matrix)
    end

    it "inherits z_index from parent layer" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "z_inherit")

      # Create a parent with a layer at z=100
      parent_layer = CrymbleUI::Layer.new("parent", CrymbleUI::Rect.new(0, 0, 500, 400), z_index: 100)

      # Create a mock parent widget that has a layer
      parent = LayerBoxForTest.new(parent_layer, id: "parent_box")
      parent.add_child(matrix)

      app = TestApp.new
      app.root_widget = parent
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      parent.layout(constraints, CrymbleUI::Vec2.zero)

      # Matrix content layer should be based on parent's z_index (100)
      matrix.content_layer.not_nil!.z_index.should be >= 100
    end

    it "updates layer position on ancestor position changed" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "pos_change")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.new(50.0, 50.0))

      # Record initial position
      content_x = matrix.content_layer.not_nil!.bounds.x

      # Simulate ancestor drag
      delta = CrymbleUI::Vec2.new(10.0, 20.0)
      matrix.on_ancestor_position_changed(delta)

      # Content layer should have moved by delta
      matrix.content_layer.not_nil!.bounds.x.should eq(content_x + 10.0)
    end

    it "updates layer z-index on ancestor z-index changed" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "z_change")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Simulate bring-to-front (z-index changed to 500)
      matrix.on_ancestor_z_index_changed(500)

      # Content layer should now be based on 500
      matrix.content_layer.not_nil!.z_index.should be >= 500
    end

    it "layers are cleaned up when widget removed from tree" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "cleanup_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Layers should be in registry
      initial_count = CrymbleUI::Layer.registry_size

      # Remove matrix from tree (simulate rebuild without this widget)
      new_root = CrymbleUI::Text.new("Replacement")
      app.root_widget = new_root

      # Cleanup orphaned layers
      CrymbleUI::Layer.cleanup_orphaned_layers(new_root)

      # Registry should have fewer layers now
      CrymbleUI::Layer.registry_size.should be < initial_count
    end

    it "has ScrollView for scrollbar chrome" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 100, cols: 50, id: "scrollview_test")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.zero)

      # Should have content_scroll_view
      matrix.content_scroll_view.should_not be_nil
    end
  end
end

# Helper class for testing layer inheritance
class LayerBoxForTest < CrymbleUI::Widget
  include CrymbleUI::LayerOwner

  def initialize(@test_layer : CrymbleUI::Layer, id : String? = nil)
    super(id: id)
    @internal_layer = @test_layer
    @test_layer.owner_widget = self
  end

  def layer : CrymbleUI::Layer?
    @internal_layer
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width, constraints.max_height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
    @internal_layer.try { |l| l.bounds = @bounds }

    @children.each do |child|
      child_constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(@bounds.width, @bounds.height))
      child.layout(child_constraints, position)
    end
  end

  def add_child(child : CrymbleUI::Widget)
    child.parent = self
    @children << child
  end
end
