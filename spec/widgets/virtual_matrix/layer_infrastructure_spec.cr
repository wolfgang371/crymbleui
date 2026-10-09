require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"

describe CrymbleUI::VirtualMatrix do
  describe "Layer Infrastructure" do
    it "creates VirtualMatrix with LayerOwner" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5)
      matrix.responds_to?(:layer).should be_true
      matrix.responds_to?(:compute_bounds_for_layer).should be_true
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

    it "layer bounds follow widget position via pull-based compute" do
      matrix = CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "pull_bounds")

      app = TestApp.new
      app.root_widget = matrix
      app.build_tree

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
      matrix.layout(constraints, CrymbleUI::Vec2.new(50.0, 50.0))

      # Content layer bounds should reflect widget's absolute position
      matrix.content_layer.not_nil!.bounds.x.should eq(50.0)
      matrix.content_layer.not_nil!.bounds.y.should eq(50.0)

      # Re-layout at different position - bounds should auto-update
      matrix.layout(constraints, CrymbleUI::Vec2.new(100.0, 75.0))
      matrix.content_layer.not_nil!.bounds.x.should eq(100.0)
      matrix.content_layer.not_nil!.bounds.y.should eq(75.0)
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
