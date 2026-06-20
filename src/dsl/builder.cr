require "../core/widget"
require "../core/drag_types"
require "../widgets/text"
require "../widgets/button"
require "../widgets/window"
require "../widgets/window_panel"
require "../widgets/layer_box"
require "../widgets/popup"
require "../widgets/statusbar"
require "../widgets/image"
require "../widgets/checkbox"
require "../widgets/menubar"
require "../widgets/menu"
require "../widgets/menu_item"
require "../widgets/separator"
require "../widgets/cpu_monitor"
require "../widgets/text_input"
require "../widgets/draggable_box"
require "../widgets/drop_zone_box"
require "../layout/vstack"
require "../layout/hstack"
require "../layout/flow"
require "../widgets/scroll_view"
require "../widgets/expanded"
require "../widgets/combo_box_item"
require "../widgets/combo_box"
require "../widgets/multi_combo_box"
require "../layout/recursive_grid"
require "../widgets/border_box"
require "../widgets/tree_node"

module CrymbleUI
    module DSL
        # DSL builder methods for declarative UI construction
        #
        # Usage:
        #   def build : Widget
        #     vstack(spacing: 10.0) do
        #       text("Hello World")
        #       button("Click me") { @count += 1 }
        #     end
        #   end
        module BuilderMethods
            @container_stack : Array(Widget)?

            # Auto-initialize container stack for widgets using DSL in their build method
            private def ensure_container_stack
                if @container_stack.nil? && self.is_a?(Widget)
                    @container_stack = [self.as(Widget)] of Widget
                end
            end

            # Create a vertical stack container with children defined in block
            #
            # Example:
            #   vstack(id: "main", spacing: 10.0, padding: 5.0) do
            #     text("Title")
            #     button("Click") { action }
            #   end
            def vstack(id : String? = nil, spacing : Float64 = 10.0, padding : Float64 = 0.0, background_color : Color? = nil, &block)
                ensure_container_stack
                stack = VStack.new(id: id, spacing: spacing, padding: padding, background_color: background_color)
                # Add to parent container if we're inside one
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(stack)
                end
                with_container(stack, &block)
                stack
            end

            # Create a horizontal stack container with children defined in block
            #
            # Example:
            #   hstack(id: "row", spacing: 5.0, padding: 8.0, background_color: Color.new(100, 150, 200, 255)) do
            #     text("Name:")
            #     button("Edit") { action }
            #   end
            def hstack(id : String? = nil, spacing : Float64 = 10.0, padding : Float64 = 0.0, background_color : Color? = nil, &block)
                ensure_container_stack
                stack = HStack.new(id: id, spacing: spacing, padding: padding, background_color: background_color)
                # Add to parent container if we're inside one
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(stack)
                end
                with_container(stack, &block)
                stack
            end

            # Create a flow layout — arranges children left-to-right, wrapping
            # to a new row when the next child would exceed the available width.
            # Like CSS flex-wrap. Adaptive to container width (resize-aware).
            #
            # Example:
            #   flow(hspacing: 8.0, vspacing: 4.0) do
            #     tags.each { |t| button(t) { ... } }   # wraps gracefully
            #   end
            def flow(id : String? = nil, hspacing : Float64 = 8.0, vspacing : Float64 = 4.0,
                     padding : Float64 = 0.0, background_color : Color? = nil, &block)
                ensure_container_stack
                layout = FlowLayout.new(id: id, hspacing: hspacing, vspacing: vspacing,
                                        padding: padding, background_color: background_color)
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(layout)
                end
                with_container(layout, &block)
                layout
            end

            # Create a scrollable view container
            #
            # ScrollView takes a single child widget (typically a VStack or HStack)
            #
            # Example:
            #   scroll_view(direction: ScrollDirection::Vertical) do
            #     vstack(spacing: 5.0) do
            #       # Many children that overflow viewport
            #       20.times { |i| button("Button #{i}") { } }
            #     end
            #   end
            # Sugar over VirtualMatrix for a small static tabular view
            # without writing a MatrixAdapter. Optional header row, optional
            # sticky leading rows / columns, cells are any Widget.
            #
            # Example:
            #   matrix(max_height: 200.0, sticky_row_count: 1, id: "summary") do |m|
            #     m.header "Name", "Value"
            #     rows.each do |entry|
            #       m.row do |r|
            #         r << text(entry.name)
            #         r << text(entry.value.to_s)
            #       end
            #     end
            #   end
            def matrix(id : String? = nil,
                       sticky_row_count : Int32 = 0,
                       sticky_col_count : Int32 = 0,
                       max_height : Float64? = nil,
                       max_width : Float64? = nil,
                       &block : SimpleMatrixBuilder ->)
                ensure_container_stack
                builder = SimpleMatrixBuilder.new
                block.call(builder)
                # Header row counts against sticky_row_count if set; sticky
                # defaults to "at least the header rows" so headers stay
                # visible when scrolling.
                effective_sticky_rows = {sticky_row_count, builder.header_count}.max
                adapter = SimpleMatrixAdapter.new(
                  rows: builder.rows,
                  sticky_row_count: effective_sticky_rows,
                  sticky_col_count: sticky_col_count,
                  header_row_count: builder.header_count,
                )
                vm = VirtualMatrix.new(adapter: adapter, id: id)
                # Sugar defaults for the "embedded small table" use case:
                # - shrink_to_content: don't take over the parent's space
                # - show_rulers: false — `m.header` supplies headers
                # - interactive_cells: false — cell widgets (Checkbox,
                #   Button, ...) get direct clicks; no cursor navigation
                #   or cell-highlight overlay.
                vm.shrink_to_content = true
                vm.show_rulers = false
                vm.interactive_cells = false
                vm.max_height = max_height if max_height
                current_container.add_child(vm)
                vm
            end

            def scroll_view(id : String? = nil, direction : ScrollDirection = ScrollDirection::Vertical,
                            spacing : Float64 = 0.0, padding : Float64 = 0.0,
                            max_height : Float64? = nil, max_width : Float64? = nil, &block)
                ensure_container_stack
                scroll = ScrollView.new(direction: direction, max_height: max_height, max_width: max_width, id: id)
                # Add to parent container if we're inside one
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(scroll)
                end
                # Execute block with scroll_view as container
                with_container(scroll, &block)
                # Set content: single child directly, multiple children auto-wrapped
                if scroll.children.size == 1
                    scroll.set_content(scroll.children.first)
                elsif scroll.children.size > 1
                    # Auto-wrap multiple children: VStack for vertical, HStack for horizontal
                    # Both direction requires explicit layout (no auto-wrap)
                    wrapper = case direction
                    when ScrollDirection::Vertical
                        VStack.new(spacing: spacing, padding: padding)
                    when ScrollDirection::Horizontal
                        HStack.new(spacing: spacing, padding: padding)
                    else
                        nil  # Both: no auto-wrap, use first child only
                    end

                    if wrapper
                        scroll.children.each { |child| wrapper.add_child(child) }
                        scroll.children.clear
                        scroll.set_content(wrapper)
                    else
                        # Both direction: just use first child, warn user
                        scroll.set_content(scroll.children.first)
                    end
                end
                scroll
            end

            # Create a list box with selectable items
            #
            # Example:
            #   combo_box(items: ["Apple", "Banana", "Cherry"]) do |index, value|
            #     puts "Selected: #{value} at index #{index}"
            #   end
            def combo_box(
                items : Array(String) = [] of String,
                selected : Int32 = 0,
                width : Float64? = nil,
                id : String? = nil,
                text_background_color : Color? = nil,
                text_background_colors : Array(Color)? = nil,
                &block : Int32, String -> Nil
            )
                ensure_container_stack
                widget = ComboBox.new(
                    items: items,
                    selected: selected,
                    width: width,
                    id: id,
                    text_background_color: text_background_color,
                    text_background_colors: text_background_colors,
                    &block
                )
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(widget)
                end
                widget
            end

            # Create a combo box without callback
            def combo_box(
                items : Array(String) = [] of String,
                selected : Int32 = 0,
                width : Float64? = nil,
                id : String? = nil,
                text_background_color : Color? = nil,
                text_background_colors : Array(Color)? = nil
            )
                ensure_container_stack
                widget = ComboBox.new(
                    items: items,
                    selected: selected,
                    width: width,
                    id: id,
                    text_background_color: text_background_color,
                    text_background_colors: text_background_colors
                )
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(widget)
                end
                widget
            end

            # Multi-select combo box — `selected` is a Set(Int32).
            # `selected` is REQUIRED (no default) so a bare `combo_box(items: …)`
            # stays unambiguously the Int32 path.
            # The block receives the COMPLETE new selection `(Set(Int32))` after any
            # change (toggle / select-all / body select-one) — just store it.
            def combo_box(
                items : Array(String),
                selected : Set(Int32),
                width : Float64? = nil,
                id : String? = nil,
                summary : (Set(Int32) -> String)? = nil,
                &block : Set(Int32) -> Nil
            )
                ensure_container_stack
                widget = MultiComboBox.new(
                    items: items,
                    selected: selected,
                    width: width,
                    id: id,
                    summary: summary,
                    &block
                )
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(widget)
                end
                widget
            end

            # Multi-select combo box without callback
            def combo_box(
                items : Array(String),
                selected : Set(Int32),
                width : Float64? = nil,
                id : String? = nil,
                summary : (Set(Int32) -> String)? = nil
            )
                ensure_container_stack
                widget = MultiComboBox.new(
                    items: items,
                    selected: selected,
                    width: width,
                    id: id,
                    summary: summary
                )
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(widget)
                end
                widget
            end

            # Create an expanded wrapper that fills remaining space in HStack/VStack
            #
            # Example:
            #   hstack do
            #     text("Label")
            #     expanded { text_input(id: "main") }  # Fills remaining width
            #   end
            def expanded(id : String? = nil, fill_area : Bool = false, flex : Int32 = 1, fit : Symbol = :tight, &block)
                exp = Expanded.new(id: id, fill_area: fill_area, flex: flex, fit: fit)
                current_container.add_child(exp)
                with_container(exp, &block)
                exp
            end

            # Create a spacer that fills remaining space
            #
            # Spacer is just an empty Expanded - it takes up remaining space
            # without containing any visible content.
            #
            # Usage:
            #   hstack do
            #     text("Left")
            #     spacer              # Pushes right content to edge
            #     text("Right")
            #   end
            def spacer(flex : Int32 = 1)
                exp = Expanded.new(flex: flex)
                current_container.add_child(exp)
                exp
            end

            # Create a flexible container that allocates space but doesn't force child to fill
            #
            # Like Expanded, but child uses its natural size within the allocated space.
            # This is sugar for expanded(fit: :loose)
            #
            # Usage:
            #   hstack do
            #     flexible { button("OK") }  # Gets space, button stays natural size
            #     expanded { content }       # Gets space AND fills it
            #   end
            def flexible(id : String? = nil, flex : Int32 = 1, &block)
                expanded(id: id, flex: flex, fit: :loose, &block)
            end

            # Create a recursive grid layout with automatic cell spanning
            #
            # Cells can contain widgets OR nested RecursiveGrids.
            # Nested grids automatically cause sibling cells to span.
            #
            # Example:
            #   recursive_grid(spacing: 5.0) do
            #     [
            #       [button("A") { }, button("B") { }],
            #       [button("C") { }, recursive_grid {
            #         [[button("D1") { }],
            #          [button("D2") { }]]
            #       }]
            #     ]
            #   end
            #   # Result: A and C span 2 rows because nested grid has 2 rows
            def recursive_grid(
                id : String? = nil,
                spacing : Float64 = 0.0,
                border_color : Color? = nil,
                cell_background_color : Color? = nil,
                &block
            )
                ctx = GridContentContext.new
                content = with ctx yield
                grid = RecursiveGrid.new(content: content, id: id, spacing: spacing, cell_background_color: cell_background_color)
                grid.border_color = border_color
                current_container.add_child(grid)
                grid
            end

            # Create a window with title, size and content defined in block
            #
            # Example:
            #   window("My App", 800, 600) do
            #     vstack do
            #       text("Hello")
            #     end
            #   end
            def window(title : String, width : Int32, height : Int32, id : String? = nil, &block)
                win = Window.new(title, width, height, id: id)
                # Build content inside window context
                # All widgets created in the block will be added as children via add_child()
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(win)
                yield  # Don't capture result - widgets are added via add_child()
                @container_stack.not_nil!.pop
                win
            end

            # Create a text widget and add it to the current container
            #
            # Example:
            #   text("Hello", id: "greeting", font_scale: 2)
            def text(
                content : String,
                id : String? = nil,
                font_scale : Int32 = 0,
                color : Color? = nil
            )
                widget = Text.new(content, id: id, font_scale: font_scale, color: color)
                current_container.add_child(widget)
                widget
            end

            # Create a button widget and add it to the current container
            #
            # Example:
            #   button("Click me", id: "btn") { @count += 1 }
            #   button("Save", id: "save", user_data: {:hover_text => "Save file"}) { save() }
            def button(
                label : String,
                shortcut : String? = nil,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                text_align : TextAlign = TextAlign::Center,
                padding : Float64 = 10.0,
                user_data : Hash(Symbol, String)? = nil,
                &block : -> Nil
            )
                widget = Button.new(
                    label,
                    shortcut: shortcut,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    text_align: text_align,
                    padding: padding,
                    &block
                )
                widget.user_data = user_data if user_data
                current_container.add_child(widget)

                # Register shortcut if provided
                if shortcut
                    register_shortcut(shortcut, &block)
                end

                widget
            end

            # Create a statusbar widget
            #
            # Example:
            #   statusbar("Ready", id: "status")
            #
            # To make it dynamic, use on_hover_change callback:
            #   status = statusbar("Ready", id: "status")
            #   on_hover_change do
            #     if widget = hovered_widget
            #       status.text = widget.user_data["hover_text"]? || "Ready"
            #     else
            #       status.text = "Ready"
            #     end
            #   end
            def statusbar(
                text : String = "Ready",
                id : String? = nil,
                font_scale : Int32 = -1,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                height : Float64 = 24.0,
                padding : Float64 = 5.0
            )
                widget = StatusBar.new(
                    text: text,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    height: height,
                    padding: padding
                )
                current_container.add_child(widget)
                widget
            end

            # Image from a disk path (loaded at render time, relative to CWD).
            def image(path : String, id : String? = nil, tint : Color = Color.white,
                      width : Float64? = nil, height : Float64? = nil)
                image(ImageSource.new(path), id: id, tint: tint, width: width, height: height)
            end

            # Image from a compile-time-embedded source (`embed_image`) — CWD-independent.
            def image(source : ImageSource, id : String? = nil, tint : Color = Color.white,
                      width : Float64? = nil, height : Float64? = nil)
                widget = Image.new(source, id: id, tint: tint, width: width, height: height)
                current_container.add_child(widget)
                widget
            end

            # Create a boolean checkbox widget with manual control
            #
            # Example:
            #   state accepted : Bool = false
            #   checkbox("Accept terms", checked: self.accepted) do
            #     self.accepted = !self.accepted
            #   end
            def checkbox(
                label : String,
                checked : Bool,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                box_scale : Int32 = 0,
                box_color : Color? = nil,
                check_color : Color? = nil,
                spacing : Float64 = 8.0,
                &block : -> Nil
            )
                widget = Checkbox.new(
                    label,
                    checked: checked,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    box_scale: box_scale,
                    box_color: box_color,
                    check_color: check_color,
                    spacing: spacing,
                    &block
                )
                current_container.add_child(widget)
                widget
            end

            # Create a tristate checkbox widget with manual control
            #
            # Example:
            #   state select_all : CheckState = CheckState::Unchecked
            #   checkbox("Select all", state: self.select_all) do
            #     self.select_all = case self.select_all
            #     when CheckState::Unchecked then CheckState::Checked
            #     when CheckState::Checked then CheckState::Indeterminate
            #     when CheckState::Indeterminate then CheckState::Unchecked
            #     end
            #   end
            def checkbox(
                label : String,
                state : CheckState,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                box_scale : Int32 = 0,
                box_color : Color? = nil,
                check_color : Color? = nil,
                spacing : Float64 = 8.0,
                &block : -> Nil
            )
                widget = Checkbox.new(
                    label,
                    check_state: state,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    box_scale: box_scale,
                    box_color: box_color,
                    check_color: check_color,
                    spacing: spacing,
                    &block
                )
                current_container.add_child(widget)
                widget
            end

            # Macro for auto-toggle boolean checkbox (no block needed)
            #
            # Example:
            #   state accepted : Bool = false
            #   checkbox("Accept terms", bind: accepted)
            #
            # Expands to:
            #   checkbox("Accept terms", checked: self.accepted) do
            #     self.accepted = !self.accepted
            #   end
            macro checkbox(label, bind var_name, **options)
                checkbox({{label}}, checked: self.{{var_name.id}}, {{options.double_splat}}) do
                    self.{{var_name.id}} = !self.{{var_name.id}}
                end
            end

            # Create a text input widget for single-line text entry
            #
            # Example:
            #   text_input(placeholder: "Username") { |v| @username = v }
            #   text_input(id: "email", width: 200.0, value: @email) { |v| @email = v }
            #   text_input(value: @name, user_data: {:hover_text => "Enter your name"}) { |v| @name = v }
            def text_input(
                value : String = "",
                id : String? = nil,
                width : Float64? = nil,
                placeholder : String = "",
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                focused_border_color : Color? = nil,
                placeholder_color : Color? = nil,
                padding : Float64 = 4.0,
                mode : TextInputMode = TextInputMode::FullEdit,
                user_data : Hash(Symbol, String)? = nil,
                &block : String -> Nil
            )
                widget = TextInput.new(
                    value: value,
                    id: id,
                    width: width,
                    placeholder: placeholder,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    focused_border_color: focused_border_color,
                    placeholder_color: placeholder_color,
                    padding: padding,
                    mode: mode,
                    &block
                )
                widget.user_data = user_data if user_data
                current_container.add_child(widget)
                widget
            end

            # Create a text input widget with event callback
            # Events: Change, Submit (Enter), Cancel (Escape), Blur, ArrowUp, ArrowDown
            #
            # Example:
            #   text_input(value: name, on_event: ->(val : String, ev : TextInputEvent) {
            #     self.name = val if ev.change?
            #     self.submitted = val if ev.submit?
            #   })
            def text_input(
                value : String = "",
                id : String? = nil,
                width : Float64? = nil,
                placeholder : String = "",
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                focused_border_color : Color? = nil,
                placeholder_color : Color? = nil,
                padding : Float64 = 4.0,
                mode : TextInputMode = TextInputMode::FullEdit,
                user_data : Hash(Symbol, String)? = nil,
                on_event : Proc(String, TextInputEvent, Nil)? = nil
            )
                widget = TextInput.new(
                    value: value,
                    id: id,
                    width: width,
                    placeholder: placeholder,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    focused_border_color: focused_border_color,
                    placeholder_color: placeholder_color,
                    padding: padding,
                    mode: mode
                )
                widget.on_event = on_event
                widget.user_data = user_data if user_data
                current_container.add_child(widget)
                widget
            end

            # Create a text input widget without callback
            def text_input(
                value : String = "",
                id : String? = nil,
                width : Float64? = nil,
                placeholder : String = "",
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                focused_border_color : Color? = nil,
                placeholder_color : Color? = nil,
                padding : Float64 = 4.0,
                mode : TextInputMode = TextInputMode::FullEdit,
                user_data : Hash(Symbol, String)? = nil
            )
                widget = TextInput.new(
                    value: value,
                    id: id,
                    width: width,
                    placeholder: placeholder,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    focused_border_color: focused_border_color,
                    placeholder_color: placeholder_color,
                    padding: padding,
                    mode: mode
                )
                widget.user_data = user_data if user_data
                current_container.add_child(widget)
                widget
            end

            # Create a CPU monitor widget that displays process CPU usage
            #
            # Example:
            #   cpu_monitor
            #   cpu_monitor(font_scale: 3)
            #   cpu_monitor(font_scale: 3, text_color: Color.new(255, 0, 0, 255))
            def cpu_monitor(id : String? = nil, font_scale : Int32 = 0, text_color : Color = Theme.current.text_default)
                widget = CPUMonitor.new(id: id, font_scale: font_scale, text_color: text_color)
                current_container.add_child(widget)
                widget
            end

            # Create a floating window panel with content defined in block
            #
            # Example:
            #   window_panel("Tools", x: 50.0, y: 50.0, width: 200.0, height: 150.0, z_index: 1, closeable: true) do
            #     vstack do
            #       text("Panel content")
            #     end
            #   end
            def window_panel(
                title : String,
                x : Float64,
                y : Float64,
                width : Float64,
                height : Float64,
                z_index : Int32 = 0,
                closeable : Bool = true,
                draggable : Bool = true,
                resizable : Bool = true,
                id : String? = nil,
                &block
            )
                # Auto-assign z_index based on panel order if using default (0)
                # This ensures the last panel created is topmost
                auto_z_index = z_index
                if auto_z_index == 0  # Using default value
                    existing_panels = current_container.children.count { |c| c.is_a?(WindowPanel) }
                    auto_z_index = existing_panels
                end

                panel = WindowPanel.new(title, x, y, width, height, z_index: auto_z_index, closeable: closeable, draggable: draggable, resizable: resizable, id: id)
                # Add panel to current container (usually Window)
                current_container.add_child(panel)
                # Build content inside panel context
                # Widgets created in block will be added as children via add_child()
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(panel)
                yield  # Don't capture result - widgets are added via add_child()
                @container_stack.not_nil!.pop
                panel
            end

            # Create a layer box with its own rendering layer
            #
            # Examples:
            #   # Full-window overlay with auto z-index
            #   layer { cpu_monitor }  # z=1, covers full window
            #   layer { text("Overlay 2") }  # z=2, auto-increment
            #
            #   # Explicit positioning
            #   layer(x: 50.0, y: 50.0, width: 200.0, height: 100.0) do
            #     cpu_monitor
            #   end
            def layer(
                x : Float64? = nil,
                y : Float64? = nil,
                width : Float64? = nil,
                height : Float64? = nil,
                z_index : Int32 = 0,  # 0 = auto-increment
                background_color : Color = Color.new(0, 0, 0, 0),  # Fully transparent by default
                id : String? = nil,
                &block
            )
                # Auto-increment z_index (start at 1, above root layer)
                auto_z = z_index
                if auto_z == 0
                    existing = current_container.children.count { |c| c.is_a?(LayerBox) }
                    auto_z = existing + 1
                end

                # Default to full window size if dimensions not specified
                w = width
                h = height
                x_pos = x
                y_pos = y

                # Try to get window dimensions if parameters not specified
                if w.nil? || h.nil?
                    if current_container.is_a?(Window)
                        window = current_container.as(Window)
                        # Apply CONTENT_PADDING to match regular content area (unless explicit dimensions given)
                        # This makes user layers align with the content instead of window edges
                        content_padding = Window::CONTENT_PADDING
                        w ||= window.width.to_f64 - (content_padding * 2)
                        h ||= window.height.to_f64 - (content_padding * 2)
                        x_pos ||= content_padding
                        y_pos ||= content_padding
                    else
                        # Fallback if not in Window context
                        w ||= 400.0
                        h ||= 300.0
                        x_pos ||= 0.0
                        y_pos ||= 0.0
                    end
                end

                # Ensure all values are non-nil
                x_pos ||= 0.0
                y_pos ||= 0.0

                box = LayerBox.new(x_pos, y_pos, w, h, z_index: auto_z, id: id)
                box.background_color = background_color
                # Add to current container (usually Window)
                current_container.add_child(box)
                # Build content inside layer context
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(box)
                yield
                @container_stack.not_nil!.pop
                box
            end

            # Create an aligned layer box that auto-positions based on alignment
            #
            # Examples:
            #   # Top-right overlay with 10px margin
            #   aligned_layer(align: Alignment::TopRight, margin: 10.0) do
            #     cpu_monitor
            #   end
            #
            #   # Bottom-center status bar, 50% width
            #   aligned_layer(
            #       align: Alignment::BottomCenter,
            #       width: Percent.of(50),
            #       height: 30.0,
            #       margin: 20.0
            #   ) do
            #     text("Status: Ready")
            #   end
            def aligned_layer(
                align : Alignment,
                width : SizeSpec = nil,
                height : SizeSpec = nil,
                margin : Float64 = 0.0,
                z_index : Int32 = 0,
                background_color : Color = Color.new(0, 0, 0, 0),
                id : String? = nil,
                &block
            )
                # Auto-increment z_index (start at 1, above root layer)
                auto_z = z_index
                if auto_z == 0
                    existing = current_container.children.count { |c| c.is_a?(LayerBox) }
                    auto_z = existing + 1
                end

                # Resolve initial pixel dimensions from specs for LayerBox constructor
                initial_width = case width
                                when Float64 then width
                                else nil
                                end
                initial_height = case height
                                 when Float64 then height
                                 else nil
                                 end

                box = LayerBox.new(
                    0.0, 0.0,  # Initial position (will be calculated by constrain_to_window_bounds)
                    initial_width, initial_height,
                    z_index: auto_z,
                    id: id,
                    alignment: align,
                    width_spec: width,
                    height_spec: height,
                    margin: margin
                )
                box.background_color = background_color

                # Add to current container (usually Window)
                current_container.add_child(box)

                # Build content inside layer context
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(box)
                yield
                @container_stack.not_nil!.pop
                box
            end

            # Create a popup overlay at a specific position
            #
            # Popups are floating containers without chrome (no title bar/drag/resize).
            # Useful for dialogs, tooltips, context menus.
            #
            # Example:
            #   if show_popup
            #     popup(x: 100.0, y: 50.0, padding: 15.0) do
            #       text("Popup content")
            #       button("Close") { self.show_popup = false }
            #     end
            #   end
            def popup(
                x : Float64,
                y : Float64,
                width : Float64? = nil,
                height : Float64? = nil,
                padding : Float64 = 10.0,
                background_color : Color? = nil,
                border_color : Color? = nil,
                z_index : Int32 = 1000,
                id : String? = nil,
                &block
            )
                popup_widget = Popup.new(
                    width: width,
                    height: height,
                    padding: padding,
                    background_color: background_color,
                    border_color: border_color,
                    z_index: z_index,
                    id: id
                )

                # Store target position
                popup_widget.target_x = x
                popup_widget.target_y = y

                # Build content inside popup context
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(popup_widget)
                yield
                @container_stack.not_nil!.pop

                # Add popup as regular child (NOT overlay)
                # Overlays persist across rebuilds, but DSL popups should
                # disappear when their condition becomes false
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(popup_widget)
                end

                popup_widget
            end

            # Create a menubar with menus defined in block
            #
            # Example:
            #   menubar do
            #     menu("File") do
            #       menu_item("New", "Ctrl+N") { new_file() }
            #     end
            #   end
            def menubar(id : String? = nil, &block)
                bar = MenuBar.new(id: id)
                # Add to parent container
                current_container.add_child(bar)
                with_container(bar, &block)
                bar
            end

            # Create a menu with menu items defined in block
            #
            # Example:
            #   menu("File") do
            #     menu_item("New", "Ctrl+N") { new_file() }
            #   end
            def menu(label : String, id : String? = nil, &block)
                m = Menu.new(label, id: id)
                current_container.add_child(m)
                with_container(m, &block)
                m
            end

            # Create a menu item with optional shortcut and checkable state
            #
            # Example:
            #   menu_item("Copy", "Ctrl+C") { copy() }
            #   menu_item("Dark Mode", checked: self.dark_mode) { toggle_dark_mode() }
            def menu_item(
                label : String,
                shortcut : String? = nil,
                checked : Bool? = nil,
                checkable : Bool = false,
                check_state : CheckState? = nil,
                tristate : Bool = false,
                id : String? = nil,
                &block : -> Nil
            )
                item = MenuItem.new(label, shortcut, checked, checkable, check_state, tristate, id: id, &block)
                current_container.add_child(item)

                # Register shortcut if provided
                if shortcut
                    register_shortcut(shortcut, &block)
                end

                item
            end

            # Create a menu item without block (for items that just exist)
            def menu_item(
                label : String,
                shortcut : String? = nil,
                checked : Bool? = nil,
                checkable : Bool = false,
                check_state : CheckState? = nil,
                tristate : Bool = false,
                id : String? = nil
            )
                item = MenuItem.new(label, shortcut, checked, checkable, check_state, tristate, id: id)
                current_container.add_child(item)
                # Note: No shortcut registration for menu items without action blocks
                item
            end

            # Create a separator in a menu
            #
            # Example:
            #   separator
            def separator(id : String? = nil)
                sep = Separator.new(id: id)
                current_container.add_child(sep)
                sep
            end

            # Create a draggable container that wraps content
            #
            # Example:
            #   draggable(data: TextDragData.new("Task A")) do
            #     hstack(padding: 8.0, background_color: blue) do
            #       text("Task A")
            #     end
            #   end
            def draggable(data : DragData?, id : String? = nil, &block)
                box = DraggableBox.new(data, id: id)
                current_container.add_child(box)
                with_container(box, &block)
                box
            end

            # Create a drop zone container with content block
            # Background changes from background_color to hover_color when dragging over
            #
            # Example:
            #   drop_zone(accept_types: ["text"], on_drop: ->(d : DragData, p : Vec2) { puts d }) do
            #     vstack(padding: 8.0) { text("Drop here") }
            #   end
            def drop_zone(
                accept_types : Array(String),
                on_drop : Proc(DragData, Vec2, Nil)? = nil,
                background_color : ThemeColor? = Theme.ref(&.dropzone_background), # live; pass nil for no bg
                hover_color : ThemeColor? = nil,
                id : String? = nil,
                &block
            )
                box = DropZoneBox.new(accept_types, on_drop, background_color, hover_color, id: id)
                current_container.add_child(box)
                with_container(box, &block)
                box
            end

            # Add an arbitrary widget to the current container
            #
            # Example:
            #   widget(MyCustomWidget.new("data"))
            def widget(w : Widget)
                current_container.add_child(w)
                w
            end

            # Execute block with the given container as the current context
            # Widgets created in the block are automatically added to this container
            private def with_container(container : Widget)
                @container_stack ||= [] of Widget
                @container_stack.not_nil!.push(container)
                yield
                @container_stack.not_nil!.pop
            end

            # Get the current container (the innermost vstack in nested blocks)
            private def current_container : Widget
                ensure_container_stack
                stack = @container_stack
                raise "No container context - widgets must be created inside vstack { } block" if stack.nil? || stack.empty?
                stack.last
            end

            # Find the current WindowPanel in the container stack (for panel-specific shortcuts)
            private def find_current_panel : WindowPanel?
                return nil unless stack = @container_stack
                stack.reverse_each do |widget|
                    return widget.as(WindowPanel) if widget.is_a?(WindowPanel)
                end
                nil
            end

            def tree_node(
                header : String,
                expanded : Bool = false,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                indicator_color : Color? = nil,
                &block
            )
                ensure_container_stack
                widget = TreeNode.new(
                    header,
                    expanded: expanded,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    indicator_color: indicator_color
                )
                if @container_stack && !@container_stack.not_nil!.empty?
                    @container_stack.not_nil!.last.add_child(widget)
                end
                with_container(widget, &block)
                widget
            end

            # Register a keyboard shortcut with the ShortcutManager
            # Note: ShortcutManager is initialized by the renderer, so this will be called
            # during rebuild after the renderer is running. During initial build, shortcuts
            # are registered when the renderer calls build_tree again.
            private def register_shortcut(shortcut_str : String?, &block : -> Nil)
                return unless shortcut_str

                # Check if ShortcutManager is initialized (it won't be during first build)
                # Shortcuts will be registered on the first rebuild after renderer starts
                begin
                    manager = Widget.shortcut_manager
                rescue
                    return  # ShortcutManager not initialized yet, skip registration
                end

                # Determine context: Panel (inside a WindowPanel) or Global (root-level)
                if panel = find_current_panel
                    # Inside a panel — panel-scoped (even if inside that panel's menubar)
                    manager.register(shortcut_str, ShortcutContext::Panel, panel.path_id, &block)
                else
                    # Root-level (including root menubar) — global
                    manager.register(shortcut_str, ShortcutContext::Global, nil, &block)
                end
            end
        end

        # Context for building grid content without auto-adding widgets to containers
        # Used with `with` to evaluate recursive_grid blocks
        class GridContentContext
            # Create a text widget (returns without adding to container)
            def text(
                content : String,
                id : String? = nil,
                font_scale : Int32 = 0,
                color : Color? = nil
            ) : Widget
                Text.new(content, id: id, font_scale: font_scale, color: color)
            end

            # Create a button widget (returns without adding to container)
            def button(
                label : String,
                shortcut : String? = nil,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                background_color : Color? = nil,
                border_color : Color? = nil,
                text_align : TextAlign = TextAlign::Center,
                padding : Float64 = 10.0,
                user_data : Hash(Symbol, String)? = nil,
                &block : -> Nil
            ) : Widget
                widget = Button.new(
                    label,
                    shortcut: shortcut,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    background_color: background_color,
                    border_color: border_color,
                    text_align: text_align,
                    padding: padding,
                    &block
                )
                widget.user_data = user_data if user_data
                widget
            end

            # Create a checkbox widget (returns without adding to container)
            def checkbox(
                label : String,
                checked : Bool,
                id : String? = nil,
                font_scale : Int32 = 0,
                text_color : Color? = nil,
                box_scale : Int32 = 0,
                box_color : Color? = nil,
                check_color : Color? = nil,
                spacing : Float64 = 8.0,
                &block : -> Nil
            ) : Widget
                Checkbox.new(
                    label,
                    checked: checked,
                    id: id,
                    font_scale: font_scale,
                    text_color: text_color,
                    box_scale: box_scale,
                    box_color: box_color,
                    check_color: check_color,
                    spacing: spacing,
                    &block
                )
            end

            # Create a vstack (returns without adding to container)
            def vstack(id : String? = nil, spacing : Float64 = 10.0, padding : Float64 = 0.0, background_color : Color? = nil, &block) : Widget
                stack = VStack.new(id: id, spacing: spacing, padding: padding, background_color: background_color)
                # Execute block with stack as container, collecting children
                collector = ChildCollector.new
                with collector yield
                collector.children.each { |child| stack.add_child(child) }
                stack
            end

            # Create an hstack (returns without adding to container)
            def hstack(id : String? = nil, spacing : Float64 = 10.0, padding : Float64 = 0.0, background_color : Color? = nil, &block) : Widget
                stack = HStack.new(id: id, spacing: spacing, padding: padding, background_color: background_color)
                collector = ChildCollector.new
                with collector yield
                collector.children.each { |child| stack.add_child(child) }
                stack
            end

            # Create a nested recursive_grid (returns without adding to container)
            def recursive_grid(
                id : String? = nil,
                spacing : Float64 = 0.0,
                border_color : Color? = nil,
                cell_background_color : Color? = nil,
                &block
            ) : Widget
                ctx = GridContentContext.new
                content = with ctx yield
                grid = RecursiveGrid.new(content: content, id: id, spacing: spacing, cell_background_color: cell_background_color)
                grid.border_color = border_color
                grid
            end
        end

        # Helper to collect child widgets from a block
        class ChildCollector
            getter children : Array(Widget) = [] of Widget

            def text(content : String, **opts) : Widget
                widget = Text.new(content, **opts)
                @children << widget
                widget
            end

            def button(label : String, **opts, &block : -> Nil) : Widget
                widget = Button.new(label, **opts, &block)
                @children << widget
                widget
            end
        end
    end

    # Auto-include DSL methods in all widgets for nested widget construction
    abstract class Widget
        include DSL::BuilderMethods

        # Override in subclasses to build children using DSL methods
        # DSL methods auto-setup container stack when called from a Widget
        def build
            # Empty default - override in subclasses
        end
    end
end
