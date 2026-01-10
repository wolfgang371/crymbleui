require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"
require "./popup"

module CrymbleUI
    # Menu widget - top-level menu item in MenuBar that opens a dropdown
    #
    # ## Usage
    #
    # ```crystal
    # menu("File") do
    #   menu_item("New", "Ctrl+N") { new_file() }
    #   menu_item("Open", "Ctrl+O") { open_file() }
    # end
    # ```
    #
    class Menu < Widget
        include PrimitiveBuilder
        include FontScalable

        # Layout constants
        DEFAULT_BORDER_COLOR = Color.new(200, 200, 200, 255)

        # Dynamic default height (fallback when not constrained by menubar)
        def default_height : Float64
            FontSizing.calculate_size(@font_scale) + 14.0
        end

        # Menu label
        @label : String
        def label_text : String
            @label
        end

        def label_text=(value : String)
            @label = value
            mark_needs_render
        end

        # Visual properties
        render_property text_color : Color
        render_property background_color : Color
        render_property hover_color : Color
        layout_property padding : Float64

        # State (managed internally)
        @open : Bool = false
        @hovered : Bool = false

        # Preserve menu items across open/close cycles
        @menu_items : Array(Widget) = [] of Widget

        # Reference to current popup (if open) - NOT a child, just a reference for closing
        @current_popup : Popup? = nil

        def open? : Bool; @open end

        def initialize(
            label : String,
            id : String? = nil,
            font_scale : Int32 = 0,
            @text_color : Color = Color.new(0, 0, 0, 255),
            @background_color : Color = Color.new(250, 250, 250, 255),
            @hover_color : Color = Color.new(230, 230, 230, 255),
            @padding : Float64 = 10.0
        )
            @font_scale = font_scale
            super(id: id)
            @label = label
        end

        # Override label for path_id generation
        def label : String?
            "menu"
        end

        # Measure menu size based on text width
        def measure(constraints : BoxConstraints) : Size
            # Use proper text measurement (pure geometry query, no rendering)
            text_width = measure_text(@label, font_size).width
            width = text_width + @padding * 2
            height = constraints.max_height.finite? ? constraints.max_height : default_height
            Size.new(width, height)
        end

        # Layout menu and dropdown popup
        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)

            # Capture menu items on first layout (from DSL build)
            if @menu_items.empty? && @children.any?
                @menu_items = @children.dup
                @children.clear
            end

            # If open, ensure popup exists
            if @open && !@current_popup
                open_dropdown
            elsif !@open && @current_popup
                close_dropdown
            end

            # Layout popup if it exists (update its position in case menu moved)
            if popup = @current_popup
                # Calculate absolute position for popup
                abs_bounds = absolute_bounds
                popup_position = Vec2.new(abs_bounds.x, abs_bounds.y + abs_bounds.height)

                # Re-layout popup at new position
                if window = find_window
                    window_constraints = BoxConstraints.tight(Size.new(window.bounds.width, window.bounds.height))
                    popup.layout(window_constraints, popup_position)
                end
            end
        end

        # Handle click - toggle menu and close siblings
        def on_click
            # Close ALL other open menus (in all MenuBars - window and panels)
            # and deactivate all other MenuBars
            if window = find_window
                all_menus = window.find_all { |w| w.is_a?(Menu) }
                all_menus.each do |menu|
                    if menu.is_a?(Menu) && menu != self && menu.open?
                        menu.close
                    end
                end

                # Deactivate all MenuBars except our own
                all_menubars = window.find_all { |w| w.is_a?(MenuBar) }
                all_menubars.each do |mb|
                    if mb.is_a?(MenuBar) && mb != @parent
                        mb.deactivate_menu_system
                    end
                end
            end

            # Toggle this menu
            @open = !@open

            # Directly add/remove popup without triggering rebuild
            if @open
                open_dropdown
                # Activate THIS menu system (enables hover-to-open)
                if menubar = @parent
                    if menubar.is_a?(MenuBar)
                        menubar.activate_menu_system
                    end
                end
            else
                close_dropdown
                # Deactivate menu system when closing via click
                if menubar = @parent
                    if menubar.is_a?(MenuBar)
                        menubar.deactivate_menu_system
                    end
                end
            end
        end

        # Open dropdown by creating Popup
        private def open_dropdown
            return if @menu_items.empty?

            # Calculate max label width for shortcut alignment
            max_label_width = 0.0
            @menu_items.each do |item|
                if item.is_a?(MenuItem)
                    label_width = item.as(MenuItem).label_width
                    max_label_width = [max_label_width, label_width].max
                end
            end

            # Set max label width on all MenuItems for alignment
            @menu_items.each do |item|
                if item.is_a?(MenuItem)
                    item.as(MenuItem).max_label_width = max_label_width
                end
            end

            # Create popup below menu label
            popup = Popup.new(
                width: nil,  # Auto-size to content
                height: nil,
                padding: 0.0
            )

            # Set owner menu reference (for closing when items are clicked)
            popup.owner = self

            # Add preserved menu items to popup
            @menu_items.each do |item|
                popup.add_child(item)
            end

            # Add popup to window as overlay (persists across DSL rebuilds)
            if window = find_window
                # Calculate absolute position for popup
                abs_bounds = absolute_bounds
                popup_position = Vec2.new(abs_bounds.x, abs_bounds.y + abs_bounds.height)

                # Add popup as overlay (auto-migrated during reconciliation)
                window.add_overlay(popup)

                # Layout popup at calculated position
                window_constraints = BoxConstraints.tight(Size.new(window.bounds.width, window.bounds.height))
                popup.layout(window_constraints, popup_position)

                # Store reference so we can close it later
                @current_popup = popup
            end

            mark_needs_render
        end

        # Close dropdown by removing Popup from window overlays
        private def close_dropdown
            # Remove popup from window overlays
            if popup = @current_popup
                if window = find_window
                    window.remove_overlay(popup)
                end
            end

            @current_popup = nil
            mark_needs_render
        end

        # Close this menu (called by framework when clicking outside)
        def close
            if @open
                @open = false
                close_dropdown
            end
        end

        # Copy state from old widget during reconciliation
        # Menu is SPECIAL: we must recreate popup with NEW menu items from DSL
        # (Menu items hold checkable state, so we can't reuse old popup)
        def copy_state_from(old_widget : Widget)
            # First, auto-copy all @[Reconcile] annotated properties (render/layout properties)
            auto_copy_reconcile_properties(old_widget)

            return unless old_widget.is_a?(Menu)
            old_menu = old_widget.as(Menu)

            # If old menu was open, close its popup and reopen with NEW menu items
            if old_menu.open?
                # Remove old popup from NEW window's overlay registry
                # (Window.copy_state_from already migrated it from old window)
                if old_popup = old_menu.@current_popup
                    if window = find_window  # Use NEW menu's window
                        window.remove_overlay(old_popup)
                    end
                end

                # Open with NEW menu items (from this DSL rebuild)
                @open = true
                open_dropdown
            end
        end

        # For compatibility with App.close_all_menus
        def trigger_toggle
            close
        end

        # Mouse enter - highlight menu and auto-open if menu system is active
        def on_mouse_enter
            @hovered = true
            mark_needs_render

            # Auto-open if menu system is active (hover-to-open after first click)
            if menubar = @parent
                if menubar.is_a?(MenuBar) && menubar.menu_system_active && !@open
                    # Close sibling menus
                    menubar.children.each do |sibling|
                        if sibling.is_a?(Menu) && sibling != self && sibling.open?
                            sibling.close
                        end
                    end

                    # Open this menu
                    @open = true
                    open_dropdown
                end
            end
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

            # Determine background color based on hover/open state
            bg_color = (@hovered || @open) ? @hover_color : @background_color

            # Background rect (leave space at bottom for menubar border)
            bg_rect = Rect.new(0.0, 0.0, bounds.width, bounds.height - MenuBar::BORDER_WIDTH)

            # Border rect (bottom border, 1px high)
            border_rect = Rect.new(0.0, 0.0 + bounds.height - MenuBar::BORDER_WIDTH, bounds.width, MenuBar::BORDER_WIDTH)

            # Get border color from parent MenuBar if possible
            border_color = DEFAULT_BORDER_COLOR
            if mb = @parent
                if mb.is_a?(MenuBar)
                    border_color = mb.as(MenuBar).border_color
                end
            end

            # Text position (centered)
            text_x = 0.0 + @padding
            text_y = 0.0 + (bounds.height - font_size) / 2.0
            text_position = Vec2.new(text_x, text_y)

            primitives do
                # Draw background
                fill_rect(bg_rect, bg_color)

                # Draw bottom border
                fill_rect(border_rect, border_color)

                # Draw label text
                draw_text(@label, text_position, @text_color, @font_scale)
            end
        end
    end
end
