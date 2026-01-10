require "../core/widget"
require "../core/types"
require "../core/layer"
require "../core/layer_owner"
require "../dsl/primitive_builder"

module CrymbleUI
    # MenuBar widget - horizontal container for Menu items
    # This is chrome (fixed at top), not a regular child widget
    #
    # ## Usage
    #
    # ```crystal
    # window("My App", 800, 600) do
    #   menubar do
    #     menu("File") do
    #       menu_item("New", "Ctrl+N") { new_file() }
    #       menu_item("Open", "Ctrl+O") { open_file() }
    #     end
    #     menu("Edit") do
    #       menu_item("Cut", "Ctrl+X") { cut() }
    #     end
    #   end
    # end
    # ```
    #
    class MenuBar < Widget
        include PrimitiveBuilder
        include LayerOwner

        # Border width at bottom of menubar
        BORDER_WIDTH = 1.0

        # Dynamic menubar height (scales with font zoom)
        def menubar_height : Float64
            FontSizing.calculate_size(0) + 14.0
        end

        # Visual properties
        render_property background_color : Color
        render_property border_color : Color

        # Menu system state - tracks if any menu is open (enables hover-to-open)
        # Using reconcile_property for automatic state preservation across rebuilds
        reconcile_property menu_system_active : Bool = false

        # @internal_layer provided by LayerOwner mixin
        # MenuBar always renders on top with fixed high z_index
        MENUBAR_Z_INDEX = 1000  # Fixed high z_index to render above all panels (same as Popups)

        # Activate menu system (called when any menu opens)
        def activate_menu_system
            @menu_system_active = true
        end

        # Deactivate menu system (called when all menus close)
        def deactivate_menu_system
            @menu_system_active = false
        end

        # No manual copy_state_from needed - reconcile_property handles it automatically!

        def initialize(
            id : String? = nil,
            @background_color : Color = Color.new(250, 250, 250, 255),
            @border_color : Color = Color.new(200, 200, 200, 255)
        )
            super(id: id)
            # Layer will be created conditionally in layout() based on parent context
            # - Window menubar: needs own layer (high z-index to render above panels)
            # - Panel menubar: uses parent panel's layer (part of panel chrome)
            @internal_layer = nil
        end

        # layer getter and can_skip_layout? provided by LayerOwner mixin

        # Override label for path_id generation
        def label : String?
            "menubar"
        end

        # Measure menubar - dynamic height, full width
        def measure(constraints : BoxConstraints) : Size
            width = constraints.max_width.finite? ? constraints.max_width : 800.0
            Size.new(width, menubar_height)
        end

        # Layout menubar and its menu items horizontally
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)

            # Create layer only for Window menubar (needs high z-index above panels)
            # Panel menubar uses parent panel's layer (part of panel chrome)
            if @parent.is_a?(Window) && @internal_layer.nil?
                @internal_layer = Layer.new("menubar_#{id}", Rect.zero, z_index: MENUBAR_Z_INDEX, owner_widget: self)
            end

            # Update internal layer bounds if we have our own layer (Window menubar only)
            if layer = @internal_layer
                abs_bounds = absolute_bounds
                layer.bounds = abs_bounds

                # Populate layer.widgets (menubar first for background, then menu children)
                layer.widgets.clear
                layer.widgets << self  # MenuBar renders background first
            end

            # Layout menu items horizontally
            x_offset = 0.0
            height = menubar_height
            @children.each do |child|
                # Each menu gets loose constraints (they size themselves)
                child_constraints = BoxConstraints.loose(Size.new(
                    constraints.max_width - x_offset,
                    height
                ))

                child_size = child.measure(child_constraints)
                # Pass relative position (relative to menubar)
                child_position = Vec2.new(x_offset, 0.0)
                child.layout(child_constraints, child_position)

                x_offset += child_size.width
            end

            # Don't add children to layer.widgets - they're already rendered recursively
            # when menubar is rendered (see layer_renderer.cr render_widget_to_backend)
            # Adding them here causes double-rendering (visible as "bold" text)
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)

            primitives do
                # Use bounds.width for background (correctly set to panel width by Content.layout)
                # MenuBar bounds are updated during panel resize, so this extends properly
                menubar_width = bounds.width

                # Draw background in empty space after last menu (non-overlapping)
                if @children.any?
                    last_menu_end = @children.map { |c| c.bounds.x + c.bounds.width }.max
                    # Fill from end of last menu to menubar edge
                    empty_width = menubar_width - last_menu_end
                    if empty_width > 0
                        # last_menu_end is already in widget-local coordinates (child.bounds.x is relative to parent)
                        bg_rect = Rect.new(last_menu_end, 0.0, empty_width, bounds.height - BORDER_WIDTH)
                        fill_rect(bg_rect, @background_color)
                    end
                else
                    # No menus - draw full background to menubar width
                    bg_rect = Rect.new(0.0, 0.0, menubar_width, bounds.height - BORDER_WIDTH)
                    fill_rect(bg_rect, @background_color)
                end

                # Draw bottom border to menubar width
                border_rect = Rect.new(0.0, 0.0 + bounds.height - BORDER_WIDTH, menubar_width, BORDER_WIDTH)
                fill_rect(border_rect, @border_color)
            end
        end
    end
end
