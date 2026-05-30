require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/testing/test_renderer"

# Reproduction for: maximizing a window panel does not update the
# VirtualMatrix inside it. The panel's blue border shows the new
# (maximized) bounds, but the cells (and matrix viewport) stay at
# their pre-maximize size, leaving stale empty space inside the
# panel.

class MaximizeMatrixApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        window("Test", 1000, 800) do
            window_panel(title: "Shape", x: 50.0, y: 50.0,
                         width: 300.0, height: 250.0, id: "panel") do
                vstack(spacing: 0.0, padding: 0.0) do
                    expanded do
                        widget(CrymbleUI::VirtualMatrix.new(rows: 50, cols: 10, id: "vm"))
                    end
                end
            end
        end
    end
end

describe "WindowPanel maximize — content propagation" do
    it "VirtualMatrix inside a maximized panel grows to fill new bounds" do
        renderer = CrymbleUI::Testing::TestRenderer.new(1000, 800)
        app = MaximizeMatrixApp.new
        app.build_tree
        renderer.settle_rendering(app)

        panel = app.find("panel").as(CrymbleUI::WindowPanel)
        vm    = app.find("vm").as(CrymbleUI::VirtualMatrix)

        # Sanity: VM bounded by panel's content area before maximize.
        small_width  = vm.absolute_bounds.width
        small_height = vm.absolute_bounds.height
        small_width.should  be > 0.0
        small_height.should be > 0.0

        # Maximize to a region much larger than the initial panel.
        big_bounds = CrymbleUI::Rect.new(0.0, 0.0, 1000.0, 800.0)
        panel.maximize(big_bounds)
        renderer.settle_rendering(app)

        # Re-find in case reconciliation replaced instances.
        panel = app.find("panel").as(CrymbleUI::WindowPanel)
        vm    = app.find("vm").as(CrymbleUI::VirtualMatrix)

        # Panel's own bounds reflect the maximize.
        panel.absolute_bounds.width.should  eq(1000.0)
        panel.absolute_bounds.height.should eq(800.0)

        # KEY ASSERTION: VirtualMatrix grew with the panel.
        big_w = vm.absolute_bounds.width
        big_h = vm.absolute_bounds.height
        big_w.should  be > small_width
        big_h.should be > small_height
    end

    it "VirtualMatrix shrinks back when the panel is restored" do
        renderer = CrymbleUI::Testing::TestRenderer.new(1000, 800)
        app = MaximizeMatrixApp.new
        app.build_tree
        renderer.settle_rendering(app)

        panel = app.find("panel").as(CrymbleUI::WindowPanel)
        vm    = app.find("vm").as(CrymbleUI::VirtualMatrix)
        small_width  = vm.absolute_bounds.width
        small_height = vm.absolute_bounds.height

        panel.maximize(CrymbleUI::Rect.new(0.0, 0.0, 1000.0, 800.0))
        renderer.settle_rendering(app)

        panel = app.find("panel").as(CrymbleUI::WindowPanel)
        panel.restore
        renderer.settle_rendering(app)

        panel = app.find("panel").as(CrymbleUI::WindowPanel)
        vm    = app.find("vm").as(CrymbleUI::VirtualMatrix)
        vm.absolute_bounds.width.should  eq(small_width)
        vm.absolute_bounds.height.should eq(small_height)
    end

    it "subsequent window resize after maximize stretches the matrix" do
        # User flow: maximize the panel, then maximize the app window.
        # constrain_to_window_bounds should pull the maximized panel to
        # the new window bounds AND re-flow the children. Built directly
        # (no DSL) so app rebuild doesn't reset the window size between
        # frames.
        window = CrymbleUI::Window.new("Test", 1000, 800)
        panel = CrymbleUI::WindowPanel.new("Shape", 50.0, 50.0, 300.0, 250.0, id: "panel")
        vm = CrymbleUI::VirtualMatrix.new(rows: 50, cols: 10, id: "vm")
        # Mirror the DSL structure: panel → vstack → expanded → vm.
        vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
        expanded = CrymbleUI::Expanded.new
        expanded.add_child(vm)
        vstack.add_child(expanded)
        panel.add_child(vstack)
        window.add_child(panel)

        # Initial layout at 1000x800.
        window.layout(
            CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1000.0, 800.0)),
            CrymbleUI::Vec2.zero
        )

        # Maximize the panel to the current window bounds.
        panel.maximize(CrymbleUI::Rect.new(0.0, 0.0, 1000.0, 800.0))
        # Re-run layout so the maximize takes effect through the cascade.
        window.layout(
            CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1000.0, 800.0)),
            CrymbleUI::Vec2.zero
        )
        small_vm_w = vm.absolute_bounds.width
        small_vm_h = vm.absolute_bounds.height

        # Simulate the app window being maximized — Window gets new
        # constraints. constrain_to_window_bounds should pull the
        # maximized panel to the new bounds and re-flow children.
        window.layout(
            CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(1600.0, 1200.0)),
            CrymbleUI::Vec2.zero
        )

        # Panel should fill the new window bounds.
        panel.absolute_bounds.width.should  eq(1600.0)
        panel.absolute_bounds.height.should eq(1200.0)

        # VM should grow with the panel. Without the fix, the layout
        # cascade on the panel happened BEFORE constrain_to_window_bounds
        # resized it — so VM bounds stay at the pre-resize size.
        vm.absolute_bounds.width.should  be > small_vm_w
        vm.absolute_bounds.height.should be > small_vm_h
    end
end
