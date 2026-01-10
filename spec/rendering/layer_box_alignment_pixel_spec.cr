require "../spec_helper"
require "../../src/testing/test_render_backend"
require "../../src/widgets/layer_box"
require "../../src/widgets/window"

# Pixel-level tests for LayerBox alignment
# Verifies actual rendered output, not just calculated positions

# Helper module for rendering
module LayerBoxPixelTestHelper
    # Render a LayerBox and its content to a backend
    def self.render_box_to_backend(box : CrymbleUI::LayerBox, backend : CrymbleUI::Testing::TestRenderBackend)
        # Render the box itself (background)
        primitives = box.get_primitives(box.bounds)
        primitives.each do |primitive|
            case primitive
            when CrymbleUI::FillRect
                # LayerBox primitives are widget-local (0,0), render to layer-local coords
                backend.fill_rect(primitive.bounds, primitive.color)
            end
        end

        # Render children
        box.children.each do |child|
            render_widget_recursive(child, backend, box.bounds.x, box.bounds.y)
        end
    end

    def self.render_layer_to_backend(layer : CrymbleUI::Layer, backend : CrymbleUI::Testing::TestRenderBackend)
        layer_offset_x = layer.bounds.x
        layer_offset_y = layer.bounds.y

        layer.widgets.each do |widget|
            render_widget_recursive(widget, backend, layer_offset_x, layer_offset_y)
        end
    end

    def self.render_widget_recursive(widget : CrymbleUI::Widget, backend : CrymbleUI::Testing::TestRenderBackend, offset_x : Float64, offset_y : Float64)
        return if widget.skip_render?

        widget_abs_x = widget.absolute_bounds.x
        widget_abs_y = widget.absolute_bounds.y

        primitives = widget.get_primitives(widget.bounds)
        primitives.each do |primitive|
            case primitive
            when CrymbleUI::FillRect
                abs_x = primitive.bounds.x + widget_abs_x
                abs_y = primitive.bounds.y + widget_abs_y
                local_bounds = CrymbleUI::Rect.new(
                    abs_x - offset_x,
                    abs_y - offset_y,
                    primitive.bounds.width,
                    primitive.bounds.height
                )
                backend.fill_rect(local_bounds, primitive.color)
            when CrymbleUI::DrawRect
                abs_x = primitive.bounds.x + widget_abs_x
                abs_y = primitive.bounds.y + widget_abs_y
                local_bounds = CrymbleUI::Rect.new(
                    abs_x - offset_x,
                    abs_y - offset_y,
                    primitive.bounds.width,
                    primitive.bounds.height
                )
                backend.draw_rect(local_bounds, primitive.color)
            end
        end

        widget.children.each do |child|
            render_widget_recursive(child, backend, offset_x, offset_y)
        end
    end
end

describe "LayerBox alignment pixel tests" do
    # Position calculation tests are in layer_box_alignment_spec.cr
    # This file focuses on actual pixel rendering verification

    describe "pixel rendering" do
        it "renders red background at layer-local coordinates" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)
            box.background_color = CrymbleUI::Color.new(255, 0, 0, 255)  # Red
            window.add_child(box)

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Create backend matching layer size (100x50)
            layer = box.layer.not_nil!
            backend = CrymbleUI::Testing::TestRenderBackend.new(100, 50)

            # Render box background
            LayerBoxPixelTestHelper.render_box_to_backend(box, backend)

            # In layer-local coords, pixel (0,0) should be red (box fills its layer)
            pixel = backend.get_pixel(0, 0)
            pixel.should eq(CrymbleUI::Color.new(255, 0, 0, 255))

            # Center pixel should also be red
            pixel_center = backend.get_pixel(50, 25)
            pixel_center.should eq(CrymbleUI::Color.new(255, 0, 0, 255))
        end
    end

    describe "auto-sized content rendering" do
        # Position tests for auto-sizing are in layer_box_alignment_spec.cr

        it "renders auto-sized box background correctly" do
            window = CrymbleUI::Window.new("Test", 800, 600)
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)
            box.background_color = CrymbleUI::Color.new(255, 128, 0, 255)  # Orange

            child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            box.add_child(child)
            window.add_child(box)

            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # After fix: layer should be 100x50
            layer = box.layer.not_nil!
            layer.bounds.width.should eq(100.0)
            layer.bounds.height.should eq(50.0)

            # Render to layer-sized backend
            backend = CrymbleUI::Testing::TestRenderBackend.new(100, 50)
            LayerBoxPixelTestHelper.render_box_to_backend(box, backend)

            # Pixel should be orange
            pixel = backend.get_pixel(10, 10)
            pixel.should eq(CrymbleUI::Color.new(255, 128, 0, 255))
        end
    end
end
