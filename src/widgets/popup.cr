require "../core/widget"
require "../core/types"
require "../core/layer"
require "../core/layer_owner"
require "../dsl/primitive_builder"

module CrymbleUI
    # Forward declaration for Menu reference
    class Menu < Widget
    end

    # Popup widget - A floating container without chrome
    #
    # Similar to WindowPanel but simpler:
    # - No title bar, dragging, or resizing
    # - Absolute positioning
    # - Auto-sizes to content if width/height not specified
    # - Used for dropdowns, tooltips, context menus
    #
    # ## Usage
    #
    # ```crystal
    # popup(x: 100.0, y: 50.0, width: 200.0) do
    #   menu_item("Copy") { copy() }
    #   menu_item("Paste") { paste() }
    # end
    # ```
    class Popup < Widget
        include PrimitiveBuilder
        include LayerOwner

        # Layout constants
        MIN_AUTO_WIDTH = 120.0       # Minimum width when auto-sizing with no children
        BORDER_MARGIN = 1.0          # Margin for border stroke rendering
        MAX_CHILD_HEIGHT = 400.0     # Max height for child measurement

        layout_property width : Float64? = nil   # nil = auto-size to content
        layout_property height : Float64? = nil  # nil = auto-size to content

        # Position properties (for DSL-created popups)
        property target_x : Float64 = 0.0
        property target_y : Float64 = 0.0

        # Visual properties
        @background_color : Color
        @border_color : Color
        @padding : Float64

        def background_color : Color; @background_color end
        def background_color=(value : Color); @background_color = value; mark_needs_render end

        def border_color : Color; @border_color end
        def border_color=(value : Color); @border_color = value; mark_needs_render end

        def padding : Float64; @padding end
        def padding=(value : Float64); @padding = value; mark_needs_layout end

        # Z-ordering (higher = on top)
        property z_index : Int32

        # @internal_layer provided by LayerOwner mixin

        # Optional reference to owner Menu (for menu dropdowns)
        property owner : Menu?

        # Callback for click-outside-to-close behavior
        property on_click_outside_callback : Proc(Nil)?

        # Called when user clicks outside this popup's bounds
        def on_click_outside
            @on_click_outside_callback.try(&.call)
        end

        def initialize(
            @width : Float64? = nil,
            @height : Float64? = nil,
            @background_color : Color = Theme.current.popup_background,
            @border_color : Color = Theme.current.popup_border,
            @padding : Float64 = 0.0,
            @z_index : Int32 = 1000,  # High z-index for popups
            id : String? = nil
        )
            super(id: id)
            # Create internal layer (bounds will be set in layout)
            # Layer background should match popup background for correct selective rendering
            @internal_layer = Layer.new("popup_#{id}", Rect.zero, z_index: @z_index, background_color: @background_color, owner_widget: self)
        end

        # layer getter provided by LayerOwner mixin

        # Pull-based layer bounds: expand absolute_bounds by border margin
        def compute_bounds_for_layer(layer : Layer) : Rect
            abs = absolute_bounds
            Rect.new(
                abs.x - BORDER_MARGIN,
                abs.y - BORDER_MARGIN,
                abs.width + BORDER_MARGIN * 2,
                abs.height + BORDER_MARGIN * 2
            )
        end

        # Override label for path_id generation
        def label : String?
            "popup"
        end

        # Measure popup size - auto-size to children if width/height not specified
        def measure(constraints : BoxConstraints) : Size
            if @width && @height
                return Size.new(@width.not_nil!, @height.not_nil!)
            end

            # Start with 0 for auto-sizing
            max_width = 0.0
            total_height = 0.0

            # Measure children if we need to auto-size any dimension
            if !@width || !@height
                @children.each do |child|
                    # Give children unconstrained loose constraints to get their natural size
                    child_constraints = BoxConstraints.loose(Size.new(Float64::INFINITY, Float64::INFINITY))
                    child_size = child.measure(child_constraints)
                    max_width = [max_width, child_size.width].max if !@width
                    total_height += child_size.height if !@height
                end
            end

            # Apply minimum width only if no children and width not specified
            if !@width && max_width == 0.0
                max_width = MIN_AUTO_WIDTH
            end

            final_width = @width || (max_width + @padding * 2)
            final_height = @height || (total_height + @padding * 2)

            Size.new(final_width, final_height)
        end

        # Layout popup and children
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)

            # Use target_x/target_y for absolute positioning if set
            # Convert from absolute window coords to relative-to-parent coords
            actual_position = if @target_x != 0.0 || @target_y != 0.0
                # Calculate parent's absolute position to convert target to relative
                parent_abs = @parent.try(&.absolute_bounds.position) || Vec2.zero
                Vec2.new(@target_x - parent_abs.x, @target_y - parent_abs.y)
            else
                position
            end

            @bounds = Rect.new(actual_position, size)

            # Populate layer.widgets (popup first for background, then children)
            if layer = @internal_layer
                layer.widgets.clear
                layer.widgets << self  # Popup renders background first
            end

            # Layout children vertically inside popup
            # Use relative coordinates (relative to popup, not window)
            child_x = @padding
            child_y = @padding
            available_width = @bounds.width - (@padding * 2)

            @children.each do |child|
                child_size = child.measure(BoxConstraints.loose(Size.new(available_width, MAX_CHILD_HEIGHT)))
                child_constraints = BoxConstraints.tight(Size.new(available_width, child_size.height))
                child.layout(child_constraints, Vec2.new(child_x, child_y))
                child_y += child.bounds.height
            end

            # Don't add children to layer.widgets - they're already rendered recursively
            # when popup is rendered (see layer_renderer.cr render_widget_to_backend)
            # Adding them here causes double-rendering (visible as "bold" text)
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)

            # Local bounds rect
            local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

            primitives do
                # Draw background
                fill_rect(local_bounds, @background_color)

                # Draw border
                draw_rect(local_bounds, @border_color)
            end
        end

        # Popup content area (for clipping)
        def content_area : Rect
            abs = absolute_bounds
            Rect.new(
                abs.x + @padding,
                abs.y + @padding,
                @bounds.width - (@padding * 2),
                @bounds.height - (@padding * 2)
            )
        end

        # Override clip_children to clip to content area
        def clip_children : Rect?
            content_area
        end
    end
end
