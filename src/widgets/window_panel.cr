require "../core/widget"
require "../core/types"
require "../core/layer"
require "../core/layer_owner"
require "../core/font_sizing"
require "../dsl/primitive_builder"

module CrymbleUI
    # Resize edge/corner enum
    enum ResizeEdge
        None
        Top
        Bottom
        Left
        Right
        TopLeft
        TopRight
        BottomLeft
        BottomRight
    end

    # Panel interaction mode
    enum InteractionMode
        Idle       # Not being interacted with
        Dragging   # Being dragged by title bar
        Resizing   # Being resized by edge/corner
    end

    # WindowPanel widget - A floating panel within the main window
    # V2: Draggable, resizable, closeable, z-ordered
    class WindowPanel < Widget
        include PrimitiveBuilder
        include LayerOwner

        # Pull-based layer bounds: panel bounds = self-positioned Rect(@x, @y, @width, @height)
        def compute_bounds_for_layer(layer : Layer) : Rect
            Rect.new(@x, @y, @width, @height)
        end

        # Minimum visible area to keep panel accessible (prevents dragging completely off-screen)
        MIN_VISIBLE_MARGIN = 50.0

        @title : String
        def title : String
            @title
        end
        def title=(value : String)
            @title = value
            mark_needs_render
        end

        # Override label to return title for unique path_id
        # This ensures find_by_path can distinguish between panels after rebuild
        def label : String?
            @title
        end

        reconcile_property x : Float64
        reconcile_property y : Float64
        reconcile_property width : Float64
        reconcile_property height : Float64

        # Z-ordering for overlapping panels (higher = on top)
        reconcile_property z_index : Int32

        # Close button support
        property closeable : Bool
        reconcile_property closed : Bool = false

        # Close callback - invoked when panel is closed (via close button or programmatic close)
        @on_closed_callback : Proc(Nil)?

        # Maximize state
        reconcile_property maximized : Bool = false
        reconcile_property pre_maximize_bounds : Rect = Rect.zero

        # Double-click detection for title bar maximize
        DOUBLE_CLICK_THRESHOLD_MS = 300
        @last_title_click_time : Time::Instant = Time.instant
        @last_title_click_point : Vec2 = Vec2.new(0.0, 0.0)

        # Track last hit position for close button detection
        @last_hit_point : Vec2?

        # Interaction support
        property draggable : Bool
        property resizable : Bool

        # Right-click on the title-bar area. Set by the application; the
        # internal Chrome widget dispatches to this handler instead of
        # bubbling up the generic on_right_click_handler. Keeps
        # body-area right-clicks (which inner widgets like VirtualMatrix
        # claim for cell context menus) cleanly separated from
        # title-bar gestures — no coordinate gating needed by callers.
        property on_title_bar_right_click_handler : Proc(Vec2, Nil)? = nil

        # Optional widget placed at the leading edge of the title bar
        # (left of the title text). Sized + positioned by Chrome to fit
        # the title bar height, vertically centered. hit_test routes
        # mouse events to this widget BEFORE the panel-drag fallback —
        # so a Draggable widget here acts as a drag handle without
        # moving the whole panel. The title text shifts right so it
        # doesn't overlap.
        @title_bar_leading : Widget? = nil

        def title_bar_leading : Widget?
            @title_bar_leading
        end

        def title_bar_leading=(w : Widget?) : Widget?
            if old = @title_bar_leading
                @chrome.children.delete(old)
                old.parent = nil
            end
            @title_bar_leading = w
            if w
                w.parent = @chrome
                @chrome.children << w
            end
            mark_needs_layout
            w
        end

        @[Reconcile]
        @interaction_mode : InteractionMode = InteractionMode::Idle

        # Dragging state
        @[Reconcile]
        @drag_offset : Vec2 = Vec2.new(0.0, 0.0)
        # Track panel position when children were last laid out (for drag offset calculation)
        @children_layout_position : Vec2 = Vec2.new(0.0, 0.0)

        # Resizing state - reconciled to preserve resize across DSL rebuilds
        @[Reconcile]
        @resize_edge : ResizeEdge = ResizeEdge::None
        @[Reconcile]
        @resize_start_pos : Vec2 = Vec2.new(0.0, 0.0)
        @[Reconcile]
        @resize_start_bounds : Rect = Rect.zero

        # Visual properties - reconcile: true to preserve user color changes
        render_property title_bar_color : Color = Theme.current.panel_title_bar
        render_property title_text_color : Color = Theme.current.panel_title_text
        render_property border_color : Color = Theme.current.panel_border
        render_property background_color : Color = Theme.current.panel_background
        # Title font scale (relative sizing: 0 = base, +1 = larger, -1 = smaller)
        # Note: Uses layout_property because title_bar_height depends on font_scale
        layout_property title_font_scale : Int32 = 0

        # Calculated title font size (for internal use)
        def title_font_size : Float64
            FontSizing.calculate_size(@title_font_scale)
        end

        # Title bar and close button brightness multiplier
        CLOSE_BUTTON_BRIGHTNESS = 1.2

        # Dynamic title bar height (scales with font zoom)
        def title_bar_height : Float64
            (FontSizing.calculate_size(@title_font_scale) + 16.0).round
        end

        # Dynamic close button size (proportional to title bar)
        def close_button_size : Float64
            title_bar_height * 0.65
        end

        # Dynamic close button padding
        def close_button_padding : Float64
            title_bar_height * 0.15
        end

        # Dynamic close button X padding (inside the button)
        def close_button_x_padding : Float64
            close_button_size * 0.25
        end

        # Dynamic close button X line width (also used for maximize button icon)
        def close_button_x_width : Float64
            close_button_size * 0.08
        end

        # Dynamic title text padding
        def title_text_padding : Float64
            title_bar_height * 0.25
        end
        # Title bar colors (dynamic - must follow theme changes)

        # Resize handle constants
        RESIZE_HANDLE_SIZE = 8.0  # Hit area for edge/corner resize

        # Content padding (spacing between panel edges and content)
        CONTENT_PADDING = 8.0  # Padding around panel content area

        # Texture cache constants (over-allocation to reduce reallocations during resize)
        CACHE_BUFFER_FACTOR = 0.2  # 20% extra capacity
        CACHE_MIN_BUFFER = 50.0    # Minimum buffer in pixels

        # Inner class: Panel chrome (title bar, close button)
        # Flex widget - width varies with panel width, always re-renders on panel resize
        class Chrome < Widget
            include PrimitiveBuilder

            def initialize(id : String? = nil)
                super(id: id)
            end

            # Get parent panel (chrome is always child of WindowPanel)
            private def panel : WindowPanel
                @parent.as(WindowPanel)
            end

            def measure(constraints : BoxConstraints) : Size
                # Chrome height scales with font, width matches panel
                Size.new(panel.width, panel.title_bar_height)
            end

            def perform_layout(constraints : BoxConstraints, position : Vec2)
                # Chrome bounds = title bar area only (non-overlapping with content!)
                @bounds = Rect.new(position, Size.new(panel.width, panel.title_bar_height))

                # Lay out the optional leading widget (e.g., a drag handle):
                # square, sized to match the close button, vertically centred,
                # with the same edge padding the close button uses.
                if leading = panel.title_bar_leading
                    side = panel.close_button_size
                    pad = panel.close_button_padding
                    lx = position.x + pad
                    ly = position.y + (panel.title_bar_height - side) / 2.0
                    leading.layout(BoxConstraints.tight(Size.new(side, side)), Vec2.new(lx, ly))
                end
            end

            # Render title bar chrome
            def to_primitives(bounds : Rect) : Array(DrawPrimitive)
                return [] of DrawPrimitive if panel.closed

                # Determine active color: use custom title_bar_color if set, else theme active/inactive
                active_color = if panel.title_bar_color != Theme.current.panel_title_bar
                    panel.title_bar_color  # Custom color (e.g., warning dialogs)
                elsif panel.topmost?
                    Theme.current.panel_title_bar_active
                else
                    Theme.current.panel_title_bar_inactive
                end

                # Get dynamic sizes
                title_height = panel.title_bar_height
                btn_size = panel.close_button_size
                btn_padding = panel.close_button_padding
                btn_x_padding = panel.close_button_x_padding
                btn_x_width = panel.close_button_x_width

                # Title bar rects in widget-local coordinates
                title_bar = Rect.new(0.0, 0.0, panel.width, title_height)
                title_bar_border = Rect.new(0.0, title_height - 1, panel.width, 1.0)

                # Title text position — shift past the leading widget if present.
                # leading.bounds is Chrome-relative (parent-relative @bounds),
                # which is the same coord system text_x lives in. Renderer adds
                # Chrome's absolute offset when drawing.
                text_x = panel.title_text_padding
                if leading = panel.title_bar_leading
                    lb = leading.bounds
                    text_x = lb.x + lb.width + panel.title_text_padding
                end
                text_y = (title_height - panel.title_font_size) / 2.0
                text_position = Vec2.new(text_x, text_y)

                primitives do
                    # Draw title bar background
                    fill_rect(title_bar, active_color)

                    # Draw title bar bottom border
                    fill_rect(title_bar_border, panel.border_color)

                    # Draw title text
                    draw_text(panel.title, text_position, panel.title_text_color, panel.title_font_scale)

                    # Draw maximize button (left of close button)
                    max_btn_x = panel.width - (btn_size * 2) - (btn_padding * 2)
                    max_btn_y = (title_height - btn_size) / 2.0
                    max_btn = Rect.new(max_btn_x, max_btn_y, btn_size, btn_size)

                    # Button background
                    btn_bg = active_color * CLOSE_BUTTON_BRIGHTNESS
                    fill_rect(max_btn, btn_bg)
                    draw_rect(max_btn, panel.border_color, 1.0)

                    # Draw icon: single rect for maximize, two overlapping rects for restore
                    if panel.maximized
                        # Restore icon: two overlapping rectangles
                        inner_padding = btn_x_padding * 1.2
                        small_size = btn_size - (inner_padding * 2)
                        offset = small_size * 0.25

                        # Back rectangle (upper-right)
                        draw_rect(Rect.new(max_btn.x + inner_padding + offset, max_btn.y + inner_padding,
                                  small_size - offset, small_size - offset), panel.title_text_color, btn_x_width)
                        # Front rectangle (lower-left)
                        draw_rect(Rect.new(max_btn.x + inner_padding, max_btn.y + inner_padding + offset,
                                  small_size - offset, small_size - offset), panel.title_text_color, btn_x_width)
                    else
                        # Maximize icon: single rectangle
                        draw_rect(Rect.new(max_btn.x + btn_x_padding, max_btn.y + btn_x_padding,
                                  btn_size - (btn_x_padding * 2), btn_size - (btn_x_padding * 2)),
                                  panel.title_text_color, btn_x_width)
                    end

                    # Draw close button if closeable
                    if panel.closeable
                        # Close button rect (relative to chrome bounds, which are already at panel top)
                        close_btn_x = panel.width - btn_size - btn_padding
                        close_btn_y = (title_height - btn_size) / 2.0
                        close_btn = Rect.new(close_btn_x, close_btn_y, btn_size, btn_size)

                        # Button background
                        fill_rect(close_btn, btn_bg)
                        draw_rect(close_btn, panel.border_color, 1.0)

                        # Draw X
                        x1 = close_btn.x + btn_x_padding
                        y1 = close_btn.y + btn_x_padding
                        x2 = close_btn.x + close_btn.width - btn_x_padding
                        y2 = close_btn.y + close_btn.height - btn_x_padding

                        draw_line(Vec2.new(x1, y1), Vec2.new(x2, y2), panel.title_text_color, btn_x_width)
                        draw_line(Vec2.new(x2, y1), Vec2.new(x1, y2), panel.title_text_color, btn_x_width)
                    end
                end
            end

            # Override hit_test to handle maximize button, close button, and title bar dragging
            def hit_test(point : Vec2) : Widget?
                return nil unless absolute_bounds.contains_point(point)

                btn_size = panel.close_button_size
                btn_padding = panel.close_button_padding

                # Check maximize button (left of close button)
                max_btn_x = panel.x + panel.width - (btn_size * 2) - (btn_padding * 2)
                max_btn_y = panel.y + (panel.title_bar_height - btn_size) / 2.0
                max_btn_rect = Rect.new(max_btn_x, max_btn_y, btn_size, btn_size)

                if max_btn_rect.contains_point(point)
                    return panel  # Panel handles maximize button click
                end

                # Check close button (if closeable)
                if panel.closeable
                    close_btn_x = panel.x + panel.width - btn_size - btn_padding
                    close_btn_y = panel.y + (panel.title_bar_height - btn_size) / 2.0
                    close_btn_rect = Rect.new(close_btn_x, close_btn_y, btn_size, btn_size)

                    if close_btn_rect.contains_point(point)
                        return panel  # Panel handles close button click
                    end
                end

                # Optional leading widget (e.g., drag handle): claims hits in
                # its bounds before the panel-drag fallback below, so dragging
                # the icon doesn't move the panel.
                if leading = panel.title_bar_leading
                    if leading.absolute_bounds.contains_point(point)
                        if hit = leading.hit_test(point)
                            return hit
                        end
                    end
                end

                # Title bar hit - check for drag
                if panel.draggable
                    return panel  # Panel handles dragging
                end

                self
            end
        end

        # Inner class: Panel content container
        # Contains user-added widgets, uses selective rendering
        class Content < Widget
            def initialize(id : String? = nil)
                super(id: id)
            end

            # Get parent panel
            private def panel : WindowPanel
                @parent.as(WindowPanel)
            end

            def measure(constraints : BoxConstraints) : Size
                # Content fills panel minus title bar and padding
                width = panel.width - (CONTENT_PADDING * 2)
                height = panel.height - panel.title_bar_height - (CONTENT_PADDING * 2)
                Size.new(width, height)
            end

            # Content computes its own position internally (below title bar + padding)
            # based on panel.title_bar_height and MenuBar presence.
            #
            # Can't use layout skip optimization because:
            # - WindowPanel passes Vec2.zero as position (Content ignores it)
            # - Base layout() skip path does: @bounds = Rect.new(position, @bounds.size)
            # - This would set Content bounds to (0,0,...) instead of (CONTENT_PADDING, title_bar_height+...)
            # - Causing Chrome and Content to overlap, triggering sibling overlap invariant
            #
            # This is an architectural mismatch: base layout() assumes position from parent,
            # but Content is a "self-positioning" widget that computes its own position.
            protected def can_skip_layout?(constraints : BoxConstraints) : Bool
              false
            end

            def perform_layout(constraints : BoxConstraints, position : Vec2)
                # Separate menubar from other content (like Window does)
                menubar = @children.find { |c| c.is_a?(MenuBar) }
                content = @children.reject { |c| c.is_a?(MenuBar) }

                # Content area positioning depends on whether MenuBar exists
                content_x = CONTENT_PADDING
                title_height = panel.title_bar_height
                if menubar
                    # With MenuBar: ContentArea starts at title_bar_height (no padding above MenuBar)
                    content_y = title_height
                else
                    # Without MenuBar: ContentArea starts at title_bar_height + CONTENT_PADDING
                    content_y = title_height + CONTENT_PADDING
                end
                @bounds = Rect.new(Vec2.new(content_x, content_y), measure(constraints))

                # Track current Y offset for stacking widgets vertically
                current_y = 0.0

                # Layout menubar at top (if present)
                # MenuBar spans full panel width (edge-to-edge) and is flush with title bar
                if mb = menubar
                    menubar_constraints = BoxConstraints.new(
                        min_width: panel.width,
                        max_width: panel.width,
                        min_height: 0.0,
                        max_height: @bounds.height
                    )
                    # MenuBar positioned at negative offset to span full width (edge-to-edge)
                    mb.layout(menubar_constraints, Vec2.new(-CONTENT_PADDING, current_y))
                    current_y += mb.bounds.height
                    # Add CONTENT_PADDING BELOW MenuBar (before content)
                    current_y += CONTENT_PADDING
                end

                # Layout content widgets below menubar, stacking vertically
                content_height = @bounds.height - current_y
                content.each do |child|
                    # Each widget gets remaining height, positioned at current_y
                    child_constraints = BoxConstraints.new(
                        min_width: @bounds.width,
                        max_width: @bounds.width,
                        min_height: 0.0,
                        max_height: content_height
                    )
                    child.layout(child_constraints, Vec2.new(0.0, current_y))
                    # Stack vertically - next widget goes below this one
                    current_y += child.bounds.height
                    content_height = @bounds.height - current_y
                end
            end

            # Pure container - no visual content
            def to_primitives(bounds : Rect) : Array(DrawPrimitive)
                [] of DrawPrimitive
            end
        end

        # @internal_layer provided by LayerOwner mixin

        # Chrome and content widgets (implementation detail - users don't see this split)
        @chrome : Chrome
        @content : Content

        def initialize(
            @title : String,
            @x : Float64,
            @y : Float64,
            @width : Float64,
            @height : Float64,
            @z_index : Int32 = 0,
            @closeable : Bool = true,
            @draggable : Bool = true,
            @resizable : Bool = true,
            id : String? = nil
        )
            super(id: id)
            # Initialize layout position to match initial panel position
            @children_layout_position = Vec2.new(@x, @y)

            # Create chrome and content widgets
            @chrome = Chrome.new("#{id}_chrome")
            @content = Content.new("#{id}_content")

            # Add chrome and content as internal children (not exposed to users)
            # Set parent relationship manually
            @chrome.parent = self
            @content.parent = self
            @children << @chrome  # Chrome first (renders first)
            @children << @content  # Content second

            # Create internal layer with panel background color (bounds will be set in layout)
            # Background color used for buffer clearing instead of rendering as primitive
            # Must be created after all ivars initialized (Crystal requirement)
            @internal_layer = Layer.new("panel_#{id}", Rect.zero, z_index: @z_index, background_color: @background_color, owner_widget: self)
        end

        # layer getter provided by LayerOwner mixin

        def measure(constraints : BoxConstraints) : Size
            # Panel has fixed size
            Size.new(@width, @height)
        end

        def perform_layout(constraints : BoxConstraints, position : Vec2)
            # Panel is positioned absolutely at @x, @y
            # (ignoring position parameter - panels float)
            @bounds = Rect.new(@x, @y, @width, @height)

            # Update internal layer
            if layer = @internal_layer
                # Sync layer z_index with panel z_index (important after reconciliation)
                layer.z_index = @z_index
                # Sync layer background color with current theme (important after theme switch)
                layer.background_color = @background_color

                # Populate layer.widgets with chrome and content (NOT panel self!)
                # Chrome first (renders first for correct background capture order)
                layer.widgets.clear
                layer.widgets << @chrome
                layer.widgets << @content
            end

            # Layout chrome (title bar area)
            chrome_constraints = BoxConstraints.tight(Size.new(@width, title_bar_height))
            @chrome.layout(chrome_constraints, Vec2.zero)

            # Layout content (below title bar with padding)
            # Content widget handles its own children layout (computes its own position)
            content_constraints = BoxConstraints.tight(Size.new(@width, @height))
            @content.layout(content_constraints, Vec2.zero)

            # Track position when layout happened (for drag offset calculation)
            @children_layout_position = Vec2.new(@x, @y)
        end

        # Override add_child to redirect user children to content widget
        # Users don't know about chrome/content split - they just add to panel
        def add_child(child : Widget)
            @content.add_child(child)  # Redirect to content
        end

        # Polymorphic rendering control - skip rendering if closed
        def skip_render? : Bool
            @closed
        end

        # Constrain panel position to stay within window bounds
        # Called when window is resized to prevent panels from being lost off-screen
        def constrain_to_window_bounds(window_bounds : Rect)
            # If maximized, fill the new window bounds
            if @maximized
                if @x != window_bounds.x || @y != window_bounds.y ||
                   @width != window_bounds.width || @height != window_bounds.height
                    @x = window_bounds.x
                    @y = window_bounds.y
                    @width = window_bounds.width
                    @height = window_bounds.height
                    @bounds = Rect.new(@x, @y, @width, @height)
                    # Re-flow children NOW. Window.perform_layout already
                    # called panel.layout earlier in this pass, using the
                    # pre-resize @width/@height — so the chrome and the
                    # content widgets are still positioned for the old
                    # size. mark_needs_layout alone defers the fix to
                    # whichever future pass picks it up, leaving stale
                    # content in the meantime (visible as a maximized
                    # panel-border with old-size content inside).
                    perform_layout(
                        BoxConstraints.tight(Size.new(@width, @height)),
                        Vec2.new(@x, @y)
                    )
                end
                return
            end

            # Allow dragging left edge up to (width - MIN_VISIBLE_MARGIN) off-screen
            min_x = window_bounds.x - @width + MIN_VISIBLE_MARGIN
            max_x = window_bounds.x + window_bounds.width - MIN_VISIBLE_MARGIN
            # Top edge must stay within window (can't go above window)
            min_y = window_bounds.y
            max_y = window_bounds.y + window_bounds.height - title_bar_height

            new_x = @x.clamp(min_x, max_x)
            new_y = @y.clamp(min_y, max_y)

            # Only update if position changed
            if new_x != @x || new_y != @y
                delta = Vec2.new(new_x - @x, new_y - @y)
                @x = new_x
                @y = new_y
                @bounds = Rect.new(@x, @y, @width, @height)
                # Pull-based: layer.bounds will auto-update from compute_bounds_for_layer
            end
        end

        # Get the content area rect for clipping
        def content_area : Rect
            Rect.new(
                @x,
                @y + title_bar_height,
                @width,
                @height - title_bar_height
            )
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        # WindowPanel is now a pure container - Chrome and Content handle rendering
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            [] of DrawPrimitive
        end

        # Override hit_test to handle close button, resize edges, and skip when closed
        def hit_test(point : Vec2) : Widget?
            return nil if @closed
            return nil unless absolute_bounds.contains_point(point)

            # Store hit point for on_click to use
            @last_hit_point = point

            # Check if close button was clicked
            if @closeable && close_button_rect.contains_point(point)
                return self  # Return self so on_click gets called for close button
            end

            # Check if we're over a resize edge/corner - intercept before children
            # Skip when maximized (no resize allowed, let window handle edge events)
            if @resizable && !@maximized && get_resize_edge(point) != ResizeEdge::None
                return self  # Return self so on_mouse_down gets called for resize
            end

            # Check children first (front to back)
            @children.reverse_each do |child|
                if hit = child.hit_test(point)
                    return hit
                end
            end

            # Return self if no child was hit (clicking on panel itself)
            self
        end

        # Handle clicks on panel (close button or bring to front)
        def on_click
            if @last_hit_point
                hit_point = @last_hit_point.not_nil!
                # Check maximize button first (left of close button)
                if maximize_button_rect.contains_point(hit_point)
                    toggle_maximize
                    return
                end
                # Check if close button was clicked
                if @closeable && close_button_rect.contains_point(hit_point)
                    close
                    return
                end
            end
            # Note: Panel is already brought to front in on_mouse_down
        end

        # Mouse down - start drag or resize
        def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
            return if @closed

            # Bring this panel to front
            bring_to_front

            # Title-bar right-click → dedicated handler. Routed here
            # rather than via the generic `on_right_click_handler`
            # bubble (super below) so application code can attach to
            # title-bar gestures without coordinate-gating body
            # right-clicks that inner widgets (VirtualMatrix etc.)
            # should claim.
            if button == MouseButton::Right
                if (h = @on_title_bar_right_click_handler) &&
                   Rect.new(@x, @y, @width, title_bar_height).contains_point(point)
                    h.call(point)
                    return
                end
            end

            # Also call super to handle any parent panel (nested panels)
            super(point, button)

            # Check for resize edge/corner first (blocked when maximized)
            if @resizable && !@maximized
                edge = get_resize_edge(point)
                if edge != ResizeEdge::None
                    @interaction_mode = InteractionMode::Resizing
                    @resize_edge = edge
                    @resize_start_pos = point
                    @resize_start_bounds = Rect.new(@x, @y, @width, @height)
                    return
                end
            end

            # Check if click is on title bar (for dragging or double-click maximize)
            title_bar = Rect.new(@x, @y, @width, title_bar_height)
            if title_bar.contains_point(point)
                # Don't process if clicking close button
                if @closeable && close_button_rect.contains_point(point)
                    return
                end

                # Don't process if clicking maximize button
                if maximize_button_rect.contains_point(point)
                    return
                end

                # Check for double-click to toggle maximize
                now = Time.instant
                diff = @last_title_click_point - point
                distance = Math.sqrt(diff.x * diff.x + diff.y * diff.y)
                if (now - @last_title_click_time).total_milliseconds < DOUBLE_CLICK_THRESHOLD_MS &&
                   distance < 10.0
                    toggle_maximize
                    @last_title_click_time = Time.instant  # Reset to prevent triple-click
                    return
                end
                @last_title_click_time = now
                @last_title_click_point = point

                # Start dragging (blocked when maximized)
                if @draggable && !@maximized
                    @interaction_mode = InteractionMode::Dragging
                    @drag_offset = Vec2.new(point.x - @x, point.y - @y)

                    # Trigger render to remove panel from main cache
                    mark_needs_render
                end
            end
        end

        # Mouse move - update position if dragging, or size if resizing
        def on_mouse_move(point : Vec2)
            if @interaction_mode == InteractionMode::Dragging
                # Update position
                new_x = point.x - @drag_offset.x
                new_y = point.y - @drag_offset.y

                # Constrain to window bounds (keep MIN_VISIBLE_MARGIN visible)
                if window = find_window
                    window_bounds = window.bounds
                    # Allow dragging left edge up to (width - MIN_VISIBLE_MARGIN) off-screen
                    min_x = window_bounds.x - @width + MIN_VISIBLE_MARGIN
                    max_x = window_bounds.x + window_bounds.width - MIN_VISIBLE_MARGIN
                    # Top edge must stay within window (can't drag above window)
                    min_y = window_bounds.y
                    max_y = window_bounds.y + window_bounds.height - title_bar_height

                    @x = new_x.clamp(min_x, max_x)
                    @y = new_y.clamp(min_y, max_y)
                else
                    @x = new_x
                    @y = new_y
                end

                # Calculate drag delta
                drag_delta = Vec2.new(@x - @bounds.x, @y - @bounds.y)

                # Update bounds
                @bounds = Rect.new(@x, @y, @width, @height)

                # NOTE: No layout_children needed during drag!
                # Children absolute positions will be updated in on_mouse_up
                # During drag, hit testing is not needed (mouse is held down)

                # NOTE: No mark_needs_render needed during drag!
                # Pull-based: layer.bounds auto-updates from compute_bounds_for_layer
                # This achieves O(1) drag performance - zero re-renders!
            elsif @interaction_mode == InteractionMode::Resizing
                # Calculate deltas
                dx = point.x - @resize_start_pos.x
                dy = point.y - @resize_start_pos.y

                # Update size/position based on resize edge
                case @resize_edge
                when ResizeEdge::Right
                    @width = (@resize_start_bounds.width + dx).clamp(100.0, Float64::MAX)
                when ResizeEdge::Bottom
                    @height = (@resize_start_bounds.height + dy).clamp(100.0, Float64::MAX)
                when ResizeEdge::Left
                    new_width = (@resize_start_bounds.width - dx).clamp(100.0, Float64::MAX)
                    @x = @resize_start_bounds.x + (@resize_start_bounds.width - new_width)
                    @width = new_width
                when ResizeEdge::Top
                    new_height = (@resize_start_bounds.height - dy).clamp(100.0, Float64::MAX)
                    @y = @resize_start_bounds.y + (@resize_start_bounds.height - new_height)
                    @height = new_height
                when ResizeEdge::BottomRight
                    @width = (@resize_start_bounds.width + dx).clamp(100.0, Float64::MAX)
                    @height = (@resize_start_bounds.height + dy).clamp(100.0, Float64::MAX)
                when ResizeEdge::BottomLeft
                    new_width = (@resize_start_bounds.width - dx).clamp(100.0, Float64::MAX)
                    @x = @resize_start_bounds.x + (@resize_start_bounds.width - new_width)
                    @width = new_width
                    @height = (@resize_start_bounds.height + dy).clamp(100.0, Float64::MAX)
                when ResizeEdge::TopRight
                    @width = (@resize_start_bounds.width + dx).clamp(100.0, Float64::MAX)
                    new_height = (@resize_start_bounds.height - dy).clamp(100.0, Float64::MAX)
                    @y = @resize_start_bounds.y + (@resize_start_bounds.height - new_height)
                    @height = new_height
                when ResizeEdge::TopLeft
                    new_width = (@resize_start_bounds.width - dx).clamp(100.0, Float64::MAX)
                    new_height = (@resize_start_bounds.height - dy).clamp(100.0, Float64::MAX)
                    @x = @resize_start_bounds.x + (@resize_start_bounds.width - new_width)
                    @y = @resize_start_bounds.y + (@resize_start_bounds.height - new_height)
                    @width = new_width
                    @height = new_height
                end

                # Update bounds
                @bounds = Rect.new(@x, @y, @width, @height)
                # Pull-based: layer.bounds auto-updates from compute_bounds_for_layer

                # Update Chrome bounds directly (flex widget - width changed)
                @chrome.bounds = Rect.new(0.0, 0.0, @width, title_bar_height)
                # Invalidate background - old cached background doesn't cover new width
                @chrome.background_backend = nil
                @chrome.mark_needs_render

                # Update Content bounds directly (position stays same, size changes)
                content_x = CONTENT_PADDING
                content_y = if @content.children.any? { |c| c.is_a?(MenuBar) }
                  title_bar_height  # MenuBar: no padding above
                else
                  title_bar_height + CONTENT_PADDING  # No MenuBar: add padding
                end
                content_width = @width - (CONTENT_PADDING * 2)
                content_height = @height - title_bar_height - (CONTENT_PADDING * 2)
                @content.bounds = Rect.new(content_x, content_y, content_width, content_height)

                # Layout MenuBar with new panel width (edge-to-edge, must extend)
                # Don't layout all Content children - too expensive at 60fps
                menubar = @content.children.find { |c| c.is_a?(MenuBar) }
                if mb = menubar
                    # MenuBar gets full panel width, flexible height
                    menubar_constraints = BoxConstraints.new(
                        min_width: @width,
                        max_width: @width,
                        min_height: 0.0,
                        max_height: @height - title_bar_height
                    )
                    # Position at negative offset to account for Content padding
                    mb.layout(menubar_constraints, Vec2.new(-CONTENT_PADDING, mb.bounds.y))
                    # Invalidate background - old cached background doesn't cover new width
                    mb.background_backend = nil
                    mb.mark_needs_render
                    # Also mark Menu children dirty so their text labels render during resize
                    mb.children.each(&.mark_needs_render)
                end

                # Notify layer owners of resize (uses cumulative delta from start)
                delta_width = @width - @resize_start_bounds.width
                delta_height = @height - @resize_start_bounds.height
                delta_x = @x - @resize_start_bounds.x
                delta_y = @y - @resize_start_bounds.y
                @content.notify_layer_owners_resize_move(delta_width, delta_height, delta_x, delta_y)
            end
        end

        # Mouse up - stop dragging or resizing
        def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
            was_dragging = @interaction_mode == InteractionMode::Dragging
            was_resizing = @interaction_mode == InteractionMode::Resizing

            # Notify layer owners that resize ended (cleanup state)
            if was_resizing
              @content.notify_layer_owners_resize_end
            end

            # Update children positions/sizes after drag or resize
            if was_dragging || was_resizing
                layout_children
            end

            @interaction_mode = InteractionMode::Idle
            @resize_edge = ResizeEdge::None

            # After interaction ends, trigger FULL layout to rebuild panel cache
            # (mark_needs_layout instead of mark_needs_render to force cache rebuild)
            if was_dragging || was_resizing
                mark_needs_layout
            end

            # Note: No special handling needed after resize - selective rendering
            # with drag_offset_since_layout (in layer_renderer.cr) handles ghost pixels
            # during resize without triggering full layout or performance issues
        end

        # Set callback invoked when panel is closed
        def on_closed(&block : -> Nil)
            @on_closed_callback = block
        end

        # Close this panel (hides it)
        def close
            if callback = @on_closed_callback
                callback.call
            else
                @closed = true
                mark_needs_layout
                # Trigger app rebuild to update dynamic content (e.g., panel counts)
                Widget.app?.try(&.request_rebuild)
            end
        end

        # Open/show this panel
        def open
            @closed = false
            mark_needs_layout
            # Trigger app rebuild to update dynamic content (e.g., panel counts)
            Widget.app?.try(&.request_rebuild)
        end

        # Toggle panel open/closed
        def toggle
            @closed = !@closed
            mark_needs_layout
            # Trigger app rebuild to update dynamic content (e.g., panel counts)
            Widget.app?.try(&.request_rebuild)
        end

        # Maximize panel to fill window bounds
        def maximize(window_bounds : Rect)
            return if @maximized

            # Store current bounds for restore
            @pre_maximize_bounds = Rect.new(@x, @y, @width, @height)

            # Set to window bounds
            @x = window_bounds.x
            @y = window_bounds.y
            @width = window_bounds.width
            @height = window_bounds.height
            @maximized = true

            # Update bounds and trigger layout
            @bounds = Rect.new(@x, @y, @width, @height)
            mark_needs_layout
        end

        # Restore panel to pre-maximize bounds
        def restore
            return unless @maximized

            @x = @pre_maximize_bounds.x
            @y = @pre_maximize_bounds.y
            @width = @pre_maximize_bounds.width
            @height = @pre_maximize_bounds.height
            @maximized = false

            # Update bounds and trigger layout
            @bounds = Rect.new(@x, @y, @width, @height)
            mark_needs_layout
        end

        # Toggle maximize/restore state
        def toggle_maximize
            if @maximized
                restore
            else
                # Need panel area bounds (excludes menubar) - find via parent chain
                if window = find_window
                    maximize(window.panel_area_bounds)
                end
            end
        end

        # Bring this panel to the front (highest z-index)
        def bring_to_front
            return unless parent = @parent

            # Get all WindowPanel siblings
            panels = parent.children
                .select { |child| child.is_a?(WindowPanel) }
                .map(&.as(WindowPanel))

            max_z = panels.map(&.z_index).max? || 0

            # Find the old topmost panel (if any) to mark it for re-render
            old_topmost = panels.find { |p| p != self && p.z_index == max_z }

            # Use +10 gap to ensure front panel's base z > back panel's child layers
            # (ScrollView uses +1 for content layer, +2 for scrollbar layer)
            new_z = max_z + 10
            if @z_index != new_z
                @z_index = new_z
                # Update layer z_index to match panel z_index (keeps visual z-order in sync with hit-test z-order)
                if layer = @internal_layer
                    layer.z_index = new_z
                end
                # Mark for render (z-order changed, need to re-render)
                mark_needs_render

                # Propagate z-index to child ScrollView layers
                # Fixes: scrollbar bleeding between overlapping panels (Issue D)
                # Fixes: blank content after click (Issue A+B)
                propagate_to_scrollviews(new_z)

                # Mark old topmost panel for re-render so it updates its title color from active to inactive
                # Also update its ScrollView z-indices so its scrollbar doesn't bleed through
                if old_topmost
                    old_topmost.mark_needs_render
                    old_topmost.propagate_to_scrollviews(old_topmost.z_index)
                end
            end
        end

        # Propagate z-index change to child layer owners (ScrollView, etc.)
        # Called when panel is brought to front (or when another panel takes front)
        protected def propagate_to_scrollviews(new_z : Int32)
          @content.notify_layer_owners_z_index_changed(new_z)
        end

        # Override mark_needs_render to also mark Chrome child
        # This ensures titlebar color updates immediately when z-order changes
        def mark_needs_render
            super  # Mark self for render
            @chrome.mark_needs_render if @chrome  # Also mark Chrome (titlebar) for re-render
        end

        # Get the rectangle for the close button
        private def close_button_rect : Rect
            # Position close button in top-right corner of title bar
            btn_size = close_button_size
            btn_padding = close_button_padding
            btn_x = @x + @width - btn_size - btn_padding
            btn_y = @y + (title_bar_height - btn_size) / 2.0
            Rect.new(btn_x, btn_y, btn_size, btn_size)
        end

        # Get the rectangle for the maximize button (left of close button)
        private def maximize_button_rect : Rect
            btn_size = close_button_size
            btn_padding = close_button_padding
            btn_x = @x + @width - (btn_size * 2) - (btn_padding * 2)
            btn_y = @y + (title_bar_height - btn_size) / 2.0
            Rect.new(btn_x, btn_y, btn_size, btn_size)
        end

        # Detect which resize edge/corner is at the given point
        def get_resize_edge(point : Vec2) : ResizeEdge
            return ResizeEdge::None unless @resizable

            # Check if point is inside panel area (using @x, @y, @width, @height)
            return ResizeEdge::None if point.x < @x || point.x > @x + @width
            return ResizeEdge::None if point.y < @y || point.y > @y + @height

            # Check if point is near panel edges (inside the panel)
            # Distance from each edge (positive values mean inside the panel)
            dist_left = point.x - @x
            dist_right = (@x + @width) - point.x
            dist_top = point.y - @y
            dist_bottom = (@y + @height) - point.y

            near_left = dist_left < RESIZE_HANDLE_SIZE && dist_left >= 0
            near_right = dist_right < RESIZE_HANDLE_SIZE && dist_right >= 0
            near_top = dist_top < RESIZE_HANDLE_SIZE && dist_top >= 0
            near_bottom = dist_bottom < RESIZE_HANDLE_SIZE && dist_bottom >= 0

            # Check corners first (priority over edges)
            return ResizeEdge::TopLeft if near_top && near_left
            return ResizeEdge::TopRight if near_top && near_right
            return ResizeEdge::BottomLeft if near_bottom && near_left
            return ResizeEdge::BottomRight if near_bottom && near_right

            # Check edges
            return ResizeEdge::Top if near_top
            return ResizeEdge::Bottom if near_bottom
            return ResizeEdge::Left if near_left
            return ResizeEdge::Right if near_right

            ResizeEdge::None
        end

        # Programmatic movement API (for testing and animation)
        # Moves panel to absolute position and updates child positions
        def move_to(new_x : Float64, new_y : Float64)
            @x = new_x
            @y = new_y
            @bounds = Rect.new(@x, @y, @width, @height)
            layout_children
            mark_needs_render
        end

        # Moves panel by relative offset and updates child positions
        def move_by(dx : Float64, dy : Float64)
            move_to(@x + dx, @y + dy)
        end

        # Re-layout children within the panel (must match perform_layout logic)
        private def layout_children
            # Layout chrome (title bar area)
            chrome_constraints = BoxConstraints.tight(Size.new(@width, title_bar_height))
            @chrome.layout(chrome_constraints, Vec2.zero)

            # Layout content (Content computes its own position based on menubar presence)
            content_constraints = BoxConstraints.tight(Size.new(@width, @height))
            @content.layout(content_constraints, Vec2.zero)

            # Track position when layout happened
            @children_layout_position = Vec2.new(@x, @y)
        end

        # Get drag offset since last layout (for selective rendering during drag)
        def drag_offset_since_layout : Vec2
            Vec2.new(@x - @children_layout_position.x, @y - @children_layout_position.y)
        end

        # Check if panel is being dragged
        def dragging? : Bool
            @interaction_mode == InteractionMode::Dragging
        end

        # Check if panel is being resized
        def resizing? : Bool
            @interaction_mode == InteractionMode::Resizing
        end

        # Debug getters for resize state (to diagnose reconciliation issues)
        def resize_start_bounds : Rect
            @resize_start_bounds
        end

        def resize_edge : ResizeEdge
            @resize_edge
        end

        def resize_start_pos : Vec2
            @resize_start_pos
        end

        # Check if this panel is topmost (highest z_index) among siblings
        def topmost? : Bool
            return true unless parent = @parent

            # Get all WindowPanel siblings (including self)
            panels = parent.children
                .select { |child| child.is_a?(WindowPanel) && !child.as(WindowPanel).closed }
                .map(&.as(WindowPanel))

            return true if panels.empty?

            max_z = panels.map(&.z_index).max
            @z_index == max_z
        end

        # Propagate render invalidation up to root (so renderer knows to redraw)
        private def propagate_render_invalidation
            current : Widget? = self
            while current
                current.mark_needs_render
                current = current.parent
            end
        end

        # Concise inspect for readable spec output (prevents 80MB dumps)
        def inspect(io : IO)
            io << "WindowPanel(id=#{@id.inspect}, \"#{@title}\", x=#{@x}, y=#{@y}, w=#{@width}, h=#{@height}, z=#{@z_index})"
        end
    end
end
