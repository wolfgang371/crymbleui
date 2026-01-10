require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"
require "../input/shortcut_format"

module CrymbleUI
    # MenuItem widget - item in a dropdown menu
    #
    # ## Usage
    #
    # ```crystal
    # menu_item("Copy", "Ctrl+C") { copy() }
    # menu_item("Dark Mode", checked: self.dark_mode) { toggle_dark_mode() }
    # ```
    #
    class MenuItem < Widget
        include PrimitiveBuilder
        include FontScalable

        # Layout constants
        LABEL_SHORTCUT_SPACING = 30.0  # Minimum gap between label and shortcut

        # Dynamic item height (scales with font zoom)
        def item_height : Float64
            FontSizing.calculate_size(@font_scale) + 10.0
        end

        # Dynamic check icon width (scales with font)
        def check_icon_width : Float64
            font_size * 1.15
        end

        # Dynamic checkmark size
        def checkmark_size : Float64
            font_size * 0.85
        end

        # Dynamic checkmark line thickness
        def checkmark_line_thickness : Float64
            font_size * 0.2
        end

        # Dynamic checkmark junction radius
        def checkmark_junction_radius : Float64
            font_size * 0.1
        end

        # Label and shortcut text
        @label : String
        @shortcut : String?  # Raw shortcut string (e.g., "^S", "Ctrl+N")
        @shortcut_display : String?  # Platform-specific display string (e.g., "Ctrl+S" on Linux, "Cmd+S" on Mac)

        def label_text : String
            @label
        end

        def label_text=(value : String)
            @label = value
            mark_needs_render
        end

        def shortcut : String?
            @shortcut
        end

        def shortcut=(value : String?)
            @shortcut = value
            @shortcut_display = ShortcutFormat.to_display(value)
            mark_needs_render
        end

        # Parse shortcut to display format (^S -> Ctrl+S on Linux, Cmd+S on Mac)

        # Checkable state
        @checked : Bool
        @checkable : Bool  # If true, this is a toggle item (keeps menu open on click)

        def checked : Bool
            @checked
        end

        def checked=(value : Bool)
            @checked = value
            mark_needs_render
        end

        def checkable : Bool
            @checkable
        end

        # Visual properties
        render_property text_color : Color
        render_property shortcut_color : Color
        render_property hover_color : Color
        layout_property padding : Float64
        layout_property min_width : Float64

        # Hover state
        @hovered : Bool = false

        # Click callback
        @on_click : Proc(Nil)?

        # Maximum label width among sibling items (for shortcut alignment)
        layout_property max_label_width : Float64 = 0.0

        def initialize(
            label : String,
            shortcut : String? = nil,
            checked : Bool? = nil,
            checkable : Bool = false,
            id : String? = nil,
            font_scale : Int32 = 0,
            @text_color : Color = Color.new(0, 0, 0, 255),
            @shortcut_color : Color = Color.new(100, 100, 100, 255),
            @hover_color : Color = Color.new(0, 120, 215, 255),
            @padding : Float64 = 8.0,
            @min_width : Float64 = 150.0,
            &block : -> Nil
        )
            @font_scale = font_scale
            super(id: id)
            @label = label
            @shortcut = shortcut
            @shortcut_display = ShortcutFormat.to_display(shortcut)
            @on_click = block
            # If checked is provided (not nil), this is a checkable item
            @checkable = checked.nil? ? checkable : true
            @checked = checked || false
        end

        # Constructor without block (for items that just toggle checked state)
        def initialize(
            label : String,
            shortcut : String? = nil,
            checked : Bool? = nil,
            checkable : Bool = false,
            id : String? = nil,
            font_scale : Int32 = 0,
            @text_color : Color = Color.new(0, 0, 0, 255),
            @shortcut_color : Color = Color.new(100, 100, 100, 255),
            @hover_color : Color = Color.new(0, 120, 215, 255),
            @padding : Float64 = 8.0,
            @min_width : Float64 = 150.0
        )
            @font_scale = font_scale
            super(id: id)
            @label = label
            @shortcut = shortcut
            @shortcut_display = ShortcutFormat.to_display(shortcut)
            @on_click = nil
            # If checked is provided (not nil), this is a checkable item
            @checkable = checked.nil? ? checkable : true
            @checked = checked || false
        end

        # Override label for path_id generation
        def label : String?
            "menuitem"
        end

        # Get the width of the label text (for alignment calculation)
        def label_width : Float64
            measure_text(@label, font_size).width
        end

        # Measure menu item size
        def measure(constraints : BoxConstraints) : Size
            # Width: check icon + label + minimum spacing + shortcut + padding
            check_width = check_icon_width

            # Use proper text measurement
            label_width = measure_text(@label, font_size).width

            # Minimum space between label and shortcut
            min_spacing = if @shortcut_display
                LABEL_SHORTCUT_SPACING
            else
                0.0
            end

            shortcut_width = if sc = @shortcut_display
                measure_text(sc, font_size).width
            else
                0.0
            end

            # Natural width needed
            natural_width = check_width + label_width + min_spacing + shortcut_width + @padding * 2

            # Constrain to box constraints (use full width when tight)
            size = Size.new(natural_width, item_height)
            constraints.constrain(size)
        end

        # Layout menu item
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)
        end

        # Trigger click callback - called by framework on mouse click
        def trigger_click
            # Execute callback
            @on_click.try &.call

            # Only close menu for non-checkable items
            # Checkable items (with checkmarks) should stay open for multi-toggle
            unless @checkable
                # Close parent menu via Popup's owner reference
                if popup = @parent
                    if popup.is_a?(Popup)
                        if menu = popup.as(Popup).owner
                            # Close the menu by triggering its toggle
                            menu.on_click
                        end
                    end
                end
            end
        end

        # Handle click - execute callback and close parent menu (unless checkable)
        # This is called when Menu closes via click (not used by mouse events)
        def on_click
            trigger_click
        end

        # Mouse enter - highlight item
        def on_mouse_enter
            @hovered = true
            mark_needs_render
        end

        # Mouse exit - remove highlight
        def on_mouse_exit
            @hovered = false
            mark_needs_render
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)

            # Determine text color based on hover state
            text_color = if @hovered
                Color.white
            else
                @text_color
            end

            # Get dynamic sizes
            height = item_height
            check_width = check_icon_width
            check_size = checkmark_size
            line_thickness = checkmark_line_thickness
            junction_radius = checkmark_junction_radius

            # Calculate text positions (widget-local coordinates)
            check_x = 0.0 + @padding
            check_y = 0.0 + (height - font_size) / 2.0

            label_x = 0.0 + @padding + check_width  # Leave space for checkmark
            label_y = 0.0 + (height - font_size) / 2.0

            # Local bounds rect for background
            local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

            primitives do
                # Draw hover background if hovered
                if @hovered
                    fill_rect(local_bounds, @hover_color)
                end

                # Draw checkmark if checked (geometric, like ImGui)
                if @checked
                    # Draw a checkmark as two line segments forming a "✓" shape
                    check_center_x = 0.0 + @padding + check_width / 2.0  # Center in check area
                    # Align vertically with text baseline
                    check_center_y = 0.0 + (height - font_size) / 2.0 + font_size * 0.6

                    # Short stroke going down-left
                    p1 = Vec2.new(check_center_x - check_size * 0.35, check_center_y - check_size * 0.1)
                    p2 = Vec2.new(check_center_x - check_size * 0.1, check_center_y + check_size * 0.25)

                    # Long stroke going up-right
                    p3 = Vec2.new(check_center_x - check_size * 0.1, check_center_y + check_size * 0.25)
                    p4 = Vec2.new(check_center_x + check_size * 0.4, check_center_y - check_size * 0.4)

                    draw_line(p1, p2, text_color, line_thickness)
                    draw_line(p3, p4, text_color, line_thickness)
                    # Fill junction with a circle for smooth connection
                    draw_circle(p2, junction_radius, text_color, fill: true)
                end

                # Draw label text
                draw_text(@label, Vec2.new(label_x, label_y), text_color, @font_scale)

                # Draw shortcut text (aligned at consistent column)
                if sc = @shortcut_display
                    # Position shortcut at a fixed column based on max label width
                    # This ensures all shortcuts in the menu start at the same x position
                    spacing = LABEL_SHORTCUT_SPACING
                    shortcut_x = if @max_label_width > 0.0
                        0.0 + @padding + check_width + @max_label_width + spacing
                    else
                        # Fallback to right-aligned if max_label_width not set
                        shortcut_width = measure_text(sc, font_size).width
                        0.0 + bounds.width - shortcut_width - @padding
                    end
                    shortcut_y = 0.0 + (height - font_size) / 2.0
                    shortcut_color = if @hovered
                        Color.white.with_alpha(200)
                    else
                        @shortcut_color
                    end
                    draw_text(sc, Vec2.new(shortcut_x, shortcut_y), shortcut_color, @font_scale)
                end
            end
        end
    end
end
