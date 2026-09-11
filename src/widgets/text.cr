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
                    fill_background(bounds, bg)
                end
                # Anchored as a BLOCK: measure_text reserves a slot per line now, and
                # anchoring that taller box by a single line's centring would leave a gap
                # above and hang the last line out of a box exactly tall enough to hold it.
                # Identical to vcentered_text_y for a single line, at every box height.
                text_y = vcentered_block_y(bounds.height - padding * 2, TextLines.count(text), font_scale, padding)
                # Say so where the label is cut, BEFORE the clip so the band sits behind the
                # glyphs — but ONLY when this Text paints its own background.
                #
                # With no background of its own a Text paints nothing and sits on whatever its
                # parent painted, which it cannot see. Deriving against the panel colour would
                # be asserting a backdrop rather than measuring one: embrace puts bare Texts
                # inside DropZoneBoxes filled with the field-class colours, none of which is
                # panel.background, so the floor would be computed against a colour that is
                # never on screen and the band could land below 3:1 — invisible, which is worse
                # than absent. A widget that cannot see its backdrop does not get to claim a
                # contrast floor, so it draws no marker.
                if bg = background_color
                    mark_clipped_text(
                        clipped_text_bands(Rect.new(padding, text_y, bounds.width - padding * 2, font_size),
                            0.0, measure_text(text, font_size).width),
                        on: bg)
                end
                # X-only clip to the text's own box. At the default padding of 0.0 the box IS
                # the bounds and this is a no-op; with padding it stops a long label running
                # into the gutter it reserved. Y stays unclipped — the glyphs may legitimately
                # overhang a box shorter than the font. The background above is outside it.
                clipped(Rect.new(padding, 0.0, bounds.width - padding * 2, bounds.height), within: Rect.new(0.0, 0.0, bounds.width, bounds.height)) do
                    draw_text(text, Vec2.new(padding, text_y), color, font_scale)
                end
            end
        end

        # Text is display-only (not clickable) - pass clicks through to layers below
        def hit_test(point : Vec2) : Widget?
            nil
        end
    end
end
