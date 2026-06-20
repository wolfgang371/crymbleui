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
        reactive_property text : String
        theme_property color, text_default # live theme color (nil = follow Theme.current; explicit wins)
        reactive_property background_color : Color?
        reactive_property padding : Float64 = 0.0, layout: true

        def initialize(
            text : String,
            id : String? = nil,
            font_scale : Int32 = 0,
            color : ThemeColor? = nil,
            background_color : Color? = nil,
            padding : Float64 = 0.0
        )
            @text = Source(String).new(text)
            @background_color = Source(Color?).new(background_color)
            @padding = Source(Float64).new(padding)
            @color = color
            @font_scale.set(font_scale)
            super(id: id)
        end

        # Override label for path_id generation
        def label : String?
            text
        end

        # Measure the text size using proper text measurement
        def measure(constraints : BoxConstraints) : Size
            text_size = measure_text(text, font_size)
            width = text_size.width + padding * 2
            height = text_size.height + padding * 2

            # Constrain to box constraints
            constrained = constraints.constrain(Size.new(width, height))
            constrained
        end

        # Layout the text at the given position
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            {% if flag?(:DEBUG_TEXT) %}
                puts "[TEXT RENDER] '#{text}' #{path_id} bounds=(#{bounds.width.round(1)}x#{bounds.height.round(1)}) color=(#{color.r},#{color.g},#{color.b},#{color.a})"
            {% end %}

            primitives do
                if bg = background_color
                    fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), bg)
                end
                text_y = padding + (bounds.height - padding * 2 - font_size) / 2.0
                draw_text(text, Vec2.new(padding, text_y), color, font_scale)
            end
        end

        # Text is display-only (not clickable) - pass clicks through to layers below
        def hit_test(point : Vec2) : Widget?
            nil
        end
    end
end
