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

        # Visual properties — live theme color (nil = follow Theme.current; explicit wins)
        theme_property color, separator_color

        def initialize(
            id : String? = nil,
            color : Color? = nil
        )
            @color = color
            super(id: id)
        end

        # Override label for path_id generation
        def label : String?
            "separator"
        end

        # Measure separator. Width is MINIMAL at measure time so that layout
        # containers (grids, popups) don't size themselves around the
        # separator's preferred width — the separator visually stretches at
        # `perform_layout` time when the parent allocates a tight width.
        #
        # Previously this returned `constraints.max_width`, which broke
        # auto-sizing layouts: a parent's first measure (INFINITY constraints)
        # got 150 px while a second measure under tight constraints (e.g.
        # popup.perform_layout passing loose(available_width)) got the full
        # available width — making the natural width balloon between the two
        # passes and forcing RecursiveGrid#scale_to_fill to shrink ALL
        # columns proportionally. Concrete bug: cell-context-menu shortcut
        # column (e.g. "Ctrl+U") was scaled down ~15%, clipping the
        # rightmost glyph.
        def measure(constraints : BoxConstraints) : Size
            Size.new(0.0, SEPARATOR_HEIGHT)
        end

        # Layout separator — stretch to the allocated width (the parent has
        # decided how much room we get; fill it). Falls back to 150 px if the
        # parent gave an unbounded constraint, mirroring the pre-fix default.
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            width = constraints.max_width.finite? ? constraints.max_width : 150.0
            @bounds = Rect.new(position, Size.new(width, SEPARATOR_HEIGHT))
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
                fill_rect(line_rect, color)
            end
        end
    end
end
