require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/widgets/scroll_view"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/core/layer"
require "../../src/dsl/builder"

# Regression test: dragging a WindowPanel containing a VirtualMatrix must not
# misalign content_layer vs ScrollView layers.
#
# ROOT CAUSE: VirtualMatrix.on_ancestor_position_changed explicitly propagated
# to its ScrollView child, but widget.cr's notify_layer_owners_position_changed
# broadcast ALSO walked into VirtualMatrix's children and hit ScrollView again.
# Result: ScrollView layers moved 2× the drag delta while content_layer moved 1×.

class PanelDragMatrixApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Drag Test", 800, 600) do
      window_panel("Matrix Panel", 50.0, 50.0, 400.0, 300.0, id: "drag_panel") do
        widget(CrymbleUI::VirtualMatrix.new(rows: 5, cols: 3, id: "drag_matrix"))
      end
    end
  end
end

describe "VirtualMatrix panel drag layer alignment" do
  it "content_layer and ScrollView layer move by same delta during drag" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = PanelDragMatrixApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("drag_matrix").as(CrymbleUI::VirtualMatrix)
    scroll_view = matrix.children.find { |c| c.is_a?(CrymbleUI::ScrollView) }.as(CrymbleUI::ScrollView)

    # Both VirtualMatrix content_layer and ScrollView's layer must exist after layout
    vm_layer = matrix.content_layer.not_nil!
    sv_layer = scroll_view.layer.not_nil!

    # Record layer positions before drag
    vm_before_x = vm_layer.bounds.x
    vm_before_y = vm_layer.bounds.y
    sv_before_x = sv_layer.bounds.x
    sv_before_y = sv_layer.bounds.y

    panel = app.find("drag_panel").as(CrymbleUI::WindowPanel)
    panel_abs = panel.absolute_bounds
    drag_start_x = panel_abs.x + panel_abs.width / 2
    drag_start_y = panel_abs.y + 10.0 # In the titlebar

    drag_delta_x = 50.0
    drag_delta_y = 30.0

    # Simulate drag: mouse_down on titlebar, move, render
    renderer.mouse_down(drag_start_x, drag_start_y)
    renderer.render_frame(app)
    renderer.mouse_move(drag_start_x + drag_delta_x, drag_start_y + drag_delta_y)
    renderer.render_frame(app)

    # Layers persist across rebuilds — measure deltas on the SAME layer objects
    vm_dx = vm_layer.bounds.x - vm_before_x
    vm_dy = vm_layer.bounds.y - vm_before_y
    sv_dx = sv_layer.bounds.x - sv_before_x
    sv_dy = sv_layer.bounds.y - sv_before_y

    # All layers must move by the SAME delta (no double-notification)
    sv_dx.should be_close(vm_dx, 0.5)
    sv_dy.should be_close(vm_dy, 0.5)

    # Sanity: something actually moved
    vm_dx.abs.should be > 1.0

    # Release drag
    renderer.mouse_up(drag_start_x + drag_delta_x, drag_start_y + drag_delta_y)
    renderer.render_frame(app)
  end
end
