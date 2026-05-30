require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/testing/test_renderer"

# Test adapter that tracks cell_move calls
class CellDragTestAdapter
    include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

    getter move_calls = [] of {Tuple(Int32, Int32), Tuple(Int32, Int32)}

    def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
        CrymbleUI::Text.new("R#{row}C#{col}")
    end

    def cell_has_content?(row : Int32, col : Int32) : Bool
        true
    end

    def cell_move(from_row : Int32, from_col : Int32, to_row : Int32, to_col : Int32) : Tuple(Int32, Int32)
        @move_calls << { {from_row, from_col}, {to_row, to_col} }
        {to_row, to_col}
    end

    def cell_get_name(row : Int32, col : Int32) : String
        "R#{row}C#{col}"
    end

    def get_scrollorder : {Array(Int32), Array(Int32)}
        {(0...10).to_a, (0...5).to_a}
    end

    def get_sizes : {Array(Float64), Array(Float64)}
        {Array.new(10, 1.0), Array.new(5, 3.0)}
    end
end

describe "VirtualMatrix cell drag-and-drop" do
    it "is a Draggable and DropTarget" do
        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "traits_test")

        matrix.is_a?(CrymbleUI::Draggable).should be_true
        matrix.is_a?(CrymbleUI::DropTarget).should be_true
    end

    it "returns drag data after mouse down on a cell" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = TestApp.new

        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "data_test")
        app.root_widget = matrix
        app.build_tree

        constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)

        # Click on a cell (past ruler area)
        cell_point = CrymbleUI::Vec2.new(80.0, 50.0)
        matrix.on_mouse_down(cell_point)

        data = matrix.get_drag_data
        data.should_not be_nil
    end

    it "calls adapter.cell_move on successful drag-drop" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = TestApp.new

        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "drop_test")
        app.root_widget = matrix
        app.build_tree

        constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)

        # Mouse down on source cell
        source = CrymbleUI::Vec2.new(80.0, 50.0)
        renderer.mouse_down(source.x, source.y)

        # Drag tracking should have started
        app.drag_manager.state.phase.should_not eq(CrymbleUI::DragPhase::Idle)

        # drag_source_cell should be set
        matrix.@drag_source_cell.should_not be_nil

        # Move past drag threshold (5px)
        renderer.mouse_move(80.0, 56.0)

        # Drag should be active now
        app.drag_manager.dragging?.should be_true

        # Move to target position (updates drop target)
        renderer.mouse_move(80.0, 150.0)

        # Release on target
        renderer.mouse_up(80.0, 150.0)

        # cell_move should have been called
        adapter.move_calls.size.should eq(1)
    end

    it "stamps drag_owner_key into the drag data" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = TestApp.new

        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "owner_key_test")
        matrix.drag_owner_key = "shape-A"
        app.root_widget = matrix
        app.build_tree

        constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)

        matrix.on_mouse_down(CrymbleUI::Vec2.new(80.0, 50.0))
        data = matrix.get_drag_data
        data.should be_a(CrymbleUI::CellDragData)
        data.as(CrymbleUI::CellDragData).owner_key.should eq("shape-A")
    end

    it "delegates a cross-owner drop to cross_drop_handler instead of cell_move" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = TestApp.new

        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "cross_drop_test")
        matrix.drag_owner_key = "shape-A"
        captured = nil.as({CrymbleUI::CellDragData, Int32, Int32}?)
        matrix.cross_drop_handler = ->(d : CrymbleUI::CellDragData, tr : Int32, tc : Int32) {
            captured = {d, tr, tc}
            nil
        }
        app.root_widget = matrix
        app.build_tree

        constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)

        # A drop whose payload originates from a DIFFERENT owner.
        foreign = CrymbleUI::CellDragData.new(0, 0, "R0C0", owner_key: "shape-B")
        matrix.on_drop(foreign, CrymbleUI::Vec2.new(80.0, 150.0))

        captured.should_not be_nil
        captured.not_nil![0].should eq(foreign)
        adapter.move_calls.should be_empty
    end

    it "treats a same-owner drop as a native intra-shape cell_move" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = TestApp.new

        adapter = CellDragTestAdapter.new
        matrix = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "same_owner_test")
        matrix.drag_owner_key = "shape-A"
        handler_called = false
        matrix.cross_drop_handler = ->(d : CrymbleUI::CellDragData, tr : Int32, tc : Int32) {
            handler_called = true
            nil
        }
        app.root_widget = matrix
        app.build_tree

        constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
        matrix.layout(constraints, CrymbleUI::Vec2.zero)
        renderer.render_frame(app)

        same = CrymbleUI::CellDragData.new(0, 0, "R0C0", owner_key: "shape-A")
        matrix.on_drop(same, CrymbleUI::Vec2.new(80.0, 150.0))

        handler_called.should be_false
        adapter.move_calls.size.should eq(1)
    end
end
