require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
    # Text widget for displaying text
    class Text < Widget
        include PrimitiveBuilder
        include FontScalable

        # Visual properties
        render_property text : String
        render_property color : Color

        def initialize(
            @text : String,
            id : String? = nil,
            font_scale : Int32 = 0,
            @color : Color = Color.new(0, 0, 0, 255)
        )
            @font_scale = font_scale
            super(id: id)
        end

        # Override label for path_id generation
        def label : String?
            @text
        end

        # Measure the text size using proper text measurement
        def measure(constraints : BoxConstraints) : Size
            text_size = measure_text(@text, font_size)
            width = text_size.width
            height = text_size.height

            # Constrain to box constraints
            constrained = constraints.constrain(Size.new(width, height))
            constrained
        end

        # Layout the text at the given position
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            new_bounds = Rect.new(position, size)

            # Check if size changed (requires re-rendering)
            # Position-only changes don't require re-render (widget-local coords)
            old_bounds = @bounds
            size_changed = old_bounds.nil? || (old_bounds.width != new_bounds.width || old_bounds.height != new_bounds.height)

            {% if flag?(:DEBUG_TEXT) %}
                pos_changed = old_bounds && (old_bounds.x != new_bounds.x || old_bounds.y != new_bounds.y)
                puts "[TEXT LAYOUT] '#{@text}' #{path_id} pos=(#{new_bounds.x.round(1)},#{new_bounds.y.round(1)}) size=(#{new_bounds.width.round(1)}x#{new_bounds.height.round(1)}) size_changed=#{size_changed} pos_changed=#{pos_changed}"
            {% end %}

            @bounds = new_bounds

            if size_changed
                mark_needs_render
            end
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            {% if flag?(:DEBUG_TEXT) %}
                puts "[TEXT RENDER] '#{@text}' #{path_id} bounds=(#{bounds.width.round(1)}x#{bounds.height.round(1)}) color=(#{@color.r},#{@color.g},#{@color.b},#{@color.a})"
            {% end %}

            primitives do
                draw_text(@text, Vec2.zero, @color, @font_scale)
            end
        end

        # Text is display-only (not clickable) - pass clicks through to layers below
        def hit_test(point : Vec2) : Widget?
            nil
        end
    end
end
