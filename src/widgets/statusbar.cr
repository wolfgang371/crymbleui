require "../core/widget"
require "../core/types"
require "../core/font_sizing"
require "../core/layer"
require "../core/layer_owner"
require "../dsl/primitive_builder"

module CrymbleUI
    # Forward declaration
    abstract class App
    end

    # StatusBar widget for displaying status information at the bottom of a window.
    #
    # ## Overview
    #
    # StatusBar is a generic widget with a text property. To make it dynamic (e.g., show hover text),
    # use the `on_hover_change` callback to wire up updates explicitly.
    #
    # ## Basic Usage
    #
    # ```crystal
    # # Static statusbar
    # statusbar("Ready", id: "status")
    # ```
    #
    # ## Dynamic Hover Text
    #
    # ```crystal
    # # Create statusbar and capture reference
    # status = statusbar("Ready", id: "status")
    #
    # # Wire up hover changes to update statusbar
    # on_hover_change do
    #   if widget = hovered_widget
    #     status.text = widget.user_data[:hover_text]? || "Ready"
    #   else
    #     status.text = "Ready"
    #   end
    # end
    # ```
    #
    # ## How It Works
    #
    # 1. **Hover changes** → `App.update_hover()` detects the change
    # 2. **Callback invoked** → `on_hover_change` block runs
    # 3. **Explicit update** → User code sets `status.text = ...`
    # 4. **Efficient render** → Setting `.text=` marks statusbar for render (not rebuild!)
    # 5. **Next frame** → StatusBar renders with new text
    #
    # ## User Data Pattern
    #
    # Store custom attributes on widgets using the `user_data` parameter:
    #
    # ```crystal
    # button("Save", id: "save", user_data: {:hover_text => "Save the current file"}) do
    #   save_file()
    # end
    # ```
    #
    # ## Benefits
    #
    # - **Generic widgets**: StatusBar and Button don't know about each other
    # - **Explicit wiring**: User code decides how widgets interact
    # - **Efficient**: Only statusbar re-renders when text changes (no rebuilds)
    # - **Flexible**: Easy to add custom hover behaviors
    # - **No framework coupling**: App's `on_hover_change` works with any widget
    #
    # ## Performance
    #
    # - **No flickering**: Text changes are render-only (no layout recalculation)
    # - **No rebuilds**: Widget tree stays intact on hover
    # - **Minimal CPU**: Callback only runs when hover actually changes
    # - **Smooth updates**: Instant response with zero rebuild overhead
    #
    class StatusBar < Widget
        include PrimitiveBuilder
        include LayerOwner

        # Rendering constants
        BORDER_HEIGHT = 1.0   # Top border thickness

        # @internal_layer provided by LayerOwner mixin
        # StatusBar renders on top with fixed high z_index (like MenuBar)
        STATUSBAR_Z_INDEX = 1000

        # Visual properties (reactive_property: Source-backed, auto-captures in to_primitives)
        reactive_property text : String

        # Font scale (relative sizing: 0 = base, +1 = larger, -1 = smaller)
        # Default -1 for compact statusbar text (~12.7pt)
        reactive_property font_scale : Int32 = -1, layout: true

        # Calculated font size (for internal use)
        def font_size : Float64
            FontSizing.calculate_size(font_scale)
        end

        # Visual properties
        theme_property text_color, statusbar_text
        theme_property background_color, statusbar_background
        theme_property border_color, statusbar_border
        reactive_property height : Float64, layout: true
        reactive_property padding : Float64, layout: true

        def initialize(
            text : String = "Ready",
            id : String? = nil,
            font_scale : Int32 = -1,
            text_color : Color? = nil,
            background_color : Color? = nil,
            border_color : Color? = nil,
            height : Float64 = 24.0,
            padding : Float64 = 5.0
        )
            @text = Source(String).new(text)
            @height = Source(Float64).new(height)
            @padding = Source(Float64).new(padding)
            @text_color = text_color
            @background_color = background_color
            @border_color = border_color
            @font_scale.set(font_scale)
            super(id: id)
        end

        # Override label for path_id generation
        def label : String?
            "statusbar"
        end

        # Measure statusbar size - auto-sized height based on font, flexible width
        def measure(constraints : BoxConstraints) : Size
            # Measure text to get proper height including SFML padding
            text_size = measure_text(text, font_size)

            # Auto-size height: text height + padding on top and bottom
            auto_height = text_size.height + (padding * 2)

            # Use explicit height if larger than auto-sized, otherwise use auto-sized
            height = self.height > auto_height ? self.height : auto_height

            # Take full available width
            width = constraints.max_width.finite? ? constraints.max_width : 400.0
            Size.new(width, height)
        end

        # Layout the statusbar at the given position
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)

            # Create layer only for Window statusbar (needs high z-index above content)
            if @parent.is_a?(Window) && @internal_layer.nil?
                @internal_layer = Layer.new("statusbar_#{id}", Rect.zero, z_index: STATUSBAR_Z_INDEX, owner_widget: self)
            end

            # Populate layer.widgets
            if layer = @internal_layer
                layer.widgets.clear
                layer.widgets << self
            end
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)

            # Calculate text position (left-aligned with padding)
            text_x = 0.0 + padding
            text_y = 0.0 + padding
            text_position = Vec2.new(text_x, text_y)

            # Border rect (top border)
            border_rect = Rect.new(0.0, 0.0, bounds.width, BORDER_HEIGHT)

            # Local bounds rect for background
            local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

            primitives do
                # Draw background
                fill_rect(local_bounds, background_color)

                # Draw top border
                fill_rect(border_rect, border_color)

                # Draw text (draw_text automatically handles SFML offset compensation)
                draw_text(text, text_position, text_color, font_scale)
            end
        end
    end
end
