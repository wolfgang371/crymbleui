require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"

module CrymbleUI
    # Separator widget - horizontal line in menus
    #
    # ## Usage
    #
    # ```crystal
    # menu("File") do
    #   menu_item("New") { new_file() }
    #   separator
    #   menu_item("Exit") { exit() }
    # end
    # ```
    #
    class Separator < Widget
        include PrimitiveBuilder

        # Fixed height for separator
        SEPARATOR_HEIGHT = 5.0

        # Line rendering constants
        LINE_MARGIN = 4.0      # Horizontal margin on each side
        LINE_THICKNESS = 1.0   # Line height in pixels

        # Visual properties
        render_property color : Color

        def initialize(
            id : String? = nil,
            @color : Color = Theme.current.separator_color
        )
            super(id: id)
        end

        # Override label for path_id generation
        def label : String?
            "separator"
        end

        # Measure separator - full width, fixed height
        def measure(constraints : BoxConstraints) : Size
            width = constraints.max_width.finite? ? constraints.max_width : 150.0
            Size.new(width, SEPARATOR_HEIGHT)
        end

        # Layout separator
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)

            # Only render if parent menu is open (dropdown visible)
            # Separators are children of Menu widgets and should only show in dropdown
            if parent = @parent
                if parent.is_a?(Menu)
                    return [] of DrawPrimitive unless parent.as(Menu).open?
                end
            end

            # Draw horizontal line centered vertically (widget-local coordinates)
            line_y = SEPARATOR_HEIGHT / 2.0
            line_rect = Rect.new(LINE_MARGIN, line_y, bounds.width - LINE_MARGIN * 2, LINE_THICKNESS)

            primitives do
                fill_rect(line_rect, @color)
            end
        end
    end
end
