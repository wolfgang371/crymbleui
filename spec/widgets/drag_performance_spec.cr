require "../spec_helper"
require "../../src/widgets/drop_zone_box"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"

# DSL app that mimics the embrace VHTree layout:
# Many small DropZoneBox rows, each containing a Draggable widget.
# This reproduces the drag performance issue where crossing drop zone
# boundaries triggers expensive layer recollection.
class DragPerfApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Drag Perf Test", 400, 600) do
      vstack(padding: 5.0, spacing: 2.0) do
        # 30 drop zones with draggable content — matches typical VHTree size
        30.times do |i|
          drop_zone(accept_types: ["test_drag"], background_color: CrymbleUI::Color.new(230, 230, 230, 255),
                    id: "dz_#{i}") do
            draggable(data: TestDragData.new(i), id: "drag_#{i}") do
              text("Row #{i}", id: "row_text_#{i}")
            end
          end
        end
      end
    end
  end
end

class TestDragData < CrymbleUI::DragData
  getter index : Int32

  def initialize(@index : Int32)
  end

  def data_type : String
    "test_drag"
  end

  def display_text : String?
    "Row #{@index}"
  end
end

describe "Drag-and-drop performance" do
  it "layer recollection is bounded during drag across many drop zones" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 600)
    app = DragPerfApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Find a draggable widget to start drag from
    drag_source = app.find("drag_0")
    drag_source.should_not be_nil, "drag_0 widget should exist"

    source_abs = drag_source.not_nil!.absolute_bounds
    start_x = source_abs.x + source_abs.width / 2
    start_y = source_abs.y + source_abs.height / 2

    # Start drag: mouse_down + move past threshold
    renderer.mouse_down(start_x, start_y)
    renderer.mouse_move(start_x, start_y + 15.0)  # Past drag threshold
    renderer.render_frame(app)

    # Verify drag is active
    app.drag_manager.dragging?.should be_true, "Drag should be active after threshold"

    # Reset counters after drag setup
    CrymbleUI::LayerRenderer.reset_frame_counters

    # Simulate dragging across 20 drop zones (moving down ~20 rows)
    # Each row is ~22px high (text + spacing), so 20 rows ≈ 440px
    total_recollects = 0
    20.times do |step|
      y = start_y + 20.0 + step * 22.0  # Move through rows
      CrymbleUI::LayerRenderer.reset_frame_counters
      renderer.mouse_move(start_x, y)
      renderer.render_frame(app)
      total_recollects += CrymbleUI::LayerRenderer.frame_layer_recollect_count
    end

    # Key assertion: layer recollection should NOT happen on every target change.
    # Bug: each target change recreates highlight_layer → new object identity →
    # layers_need_recollect = true → full tree walk + sort on every drop zone crossing.
    # With 20 drag steps crossing ~20 drop zones, we'd get ~20 recollections.
    # Fixed: reusing highlight layer avoids identity changes → 0-1 recollections.
    # With highlight layer reuse + hide (not destroy), recollections should only happen
    # once: when the highlight layer is first created. After that, it's reused/hidden.
    # Before fix: 20 recollections (one per target change).
    # After fix: ≤2 (initial highlight creation + maybe 1 for ghost layer).
    total_recollects.should be <= 2,
      "Layer recollection fired #{total_recollects} times during 20 drag steps. " \
      "Expected ≤2 (highlight layer should be reused, not recreated on each target change)."
  end
end
