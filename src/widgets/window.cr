require "../dsl/primitive_builder"
require "../core/layer"

module CrymbleUI
    # Window widget - container that defines window properties
    # This is a declarative representation of the window, not the actual SFML window
    class Window < Widget
        include PrimitiveBuilder

        # Shared layout constant for content padding (same as WindowPanel)
        CONTENT_PADDING = 8.0

        property title : String
        property width : Int32
        property height : Int32

        # Root layer for non-layered widgets (text, buttons, etc.)
        getter root_layer : Layer?

        # Overlay registry for dynamic popups, tooltips, modals
        # Overlays are NOT part of DSL tree - they persist across rebuilds
        # and are auto-migrated during reconciliation
        @overlays : Array(Widget) = [] of Widget

        # Track overlay changes for layer recollection (popup added/removed)
        getter overlay_version : Int32 = 0

        def overlays : Array(Widget)
            @overlays
        end

        def initialize(@title : String, @width : Int32, @height : Int32, id : String? = nil)
            super(id: id)
            # Create root layer for content widgets (z-index 0, below panels)
            @root_layer = Layer.new("__window_content_#{id}", Rect.zero, z_index: 0, owner_widget: self)
        end

        # Add overlay (popup, tooltip, modal) - separate from DSL children
        def add_overlay(widget : Widget)
            widget.parent = self
            @overlays << widget
            @overlay_version += 1
            mark_needs_render  # NOT mark_needs_layout (avoids DSL rebuild)
        end

        # Remove overlay
        def remove_overlay(widget : Widget)
            @overlays.delete(widget)
            widget.parent = nil
            @overlay_version += 1
            mark_needs_render
        end

        # Notify overlays of click for click-outside-to-close behavior
        # Called by App on mouse_down events
        def notify_overlays_of_click(point : Vec2)
            @overlays.each do |overlay|
                # Check if click is outside overlay bounds
                if overlay.is_a?(Popup) && !overlay.bounds.contains_point(point)
                    overlay.on_click_outside
                end
            end
        end

        # Auto-migrate overlays during reconciliation
        def copy_state_from(old : Widget)
            super
            return unless old.is_a?(Window)
            old_window = old.as(Window)

            # Skip if same object (happens when TestApp returns same widget)
            return if old_window.same?(self)

            # Migrate all overlays from old Window to new Window
            # Orphaned overlays (from closed panels) are cleaned up AFTER
            # full reconciliation in App.cleanup_orphaned_overlays
            old_window.overlays.each do |overlay|
                overlay.parent = self
                @overlays << overlay
            end
            old_window.overlays.clear
        end

        # Remove orphaned ComboBoxPopup overlays (called after full reconciliation). An overlay is
        # parented directly to this Window (add_overlay sets overlay.parent = window), so once no
        # ComboBox references it any more it must be dropped from the Popup registry — otherwise
        # find_all_popups (registry.select(&.widget_in_tree?)) keeps returning it and it wrongly
        # blocks the cursor. UNREGISTER is sufficient for that (an unregistered popup can't be
        # selected regardless of widget_in_tree?), and it's the exact analogue of the old
        # @overlays-walk excluding it. We deliberately do NOT null overlay.parent: the popup may
        # still hold focus (its migrated TextInput), and find_window must keep reaching the live
        # window up the parent chain (combo_box_reconcile_focus_spec).
        def cleanup_orphaned_overlays
            @overlays.reject! do |overlay|
                if overlay.is_a?(ComboBoxPopup)
                    # Check if any ComboBox in the tree owns this popup
                    if combo_owns_popup?(self, overlay)
                        false
                    else
                        Popup.unregister(overlay.as(Popup))
                        true
                    end
                else
                    false
                end
            end
        end

        # Check if any ComboBox or MultiComboBox in the tree references this popup
        private def combo_owns_popup?(widget : Widget, popup : ComboBoxPopup) : Bool
            if widget.is_a?(ComboBox) && widget.popup_open?
                return true if widget.current_popup.same?(popup)
            elsif widget.is_a?(MultiComboBox) && widget.popup_open?
                return true if widget.current_popup.same?(popup)
            end
            widget.children.any? { |child| combo_owns_popup?(child, popup) }
        end

        def measure(constraints : BoxConstraints) : Size
            # Window always requests its specified size
            Size.new(@width.to_f64, @height.to_f64)
        end

        def perform_layout(constraints : BoxConstraints, position : Vec2)
            # Window always fills the ENTIRE available space (actual window size)
            # Use max_width/max_height from constraints to respect window resizing
            # @width/@height are only used for initial window creation
            width = constraints.max_width.finite? ? constraints.max_width : @width.to_f64
            height = constraints.max_height.finite? ? constraints.max_height : @height.to_f64
            @bounds = Rect.new(position.x, position.y, width, height)

            # Populate root layer with content widgets (not panels/menubar)
            if root = @root_layer
                root.widgets.clear
            end

            # Separate children into menubar, statusbar, layered widgets, and content
            menubar = children.find { |c| c.is_a?(MenuBar) }
            statusbar = children.find { |c| c.is_a?(StatusBar) }
            # Own-layer widgets (WindowPanel, LayerBox, Popup) declare a compositing z-boundary
            # and render in their own layers. Ask the capability polymorphically instead of the
            # `layer != nil` proxy — that proxy is FRAME-DEPENDENT now the owners create their
            # layer lazily (nil frame-1 → content, non-nil frame-2 → layered); compositing_z_index
            # is stable from construction. MenuBar/StatusBar don't declare it, so the select needs
            # no MenuBar/StatusBar exclusion (redundant); the reject DOES (they'd fall into content).
            layered = children.select { |c| c.responds_to?(:compositing_z_index) }
            # Content widgets render in root layer (exclude MenuBar/StatusBar — they own their layout)
            content = children.reject { |c| c.is_a?(MenuBar) || c.is_a?(StatusBar) || c.responds_to?(:compositing_z_index) }

            # Layout menubar at top if present (flush with window top, no padding above)
            content_y_offset = 0.0
            if mb = menubar
                menubar_constraints = BoxConstraints.tight(Size.new(width, mb.as(MenuBar).measure(constraints).height))
                # Pass relative position (relative to window, which is at 0,0)
                mb.layout(menubar_constraints, Vec2.new(0.0, 0.0))
                content_y_offset = mb.bounds.height
                # Add CONTENT_PADDING BELOW MenuBar (before content)
                content_y_offset += CONTENT_PADDING
            else
                # No MenuBar: add CONTENT_PADDING at top
                content_y_offset = CONTENT_PADDING
            end

            # Layout main content below menubar (with padding on all sides)
            # Always apply CONTENT_PADDING for consistent visual design
            content_x = CONTENT_PADDING
            content_width = width - (CONTENT_PADDING * 2)
            content_height = height - content_y_offset - CONTENT_PADDING  # Bottom padding

            # Layout statusbar at bottom if present (flush with window bottom, no padding below)
            if sb = statusbar
                statusbar_constraints = BoxConstraints.new(
                    min_width: width, max_width: width,
                    min_height: 0.0, max_height: content_height
                )
                sb_size = sb.measure(statusbar_constraints)
                # Position at bottom of window
                sb.layout(statusbar_constraints, Vec2.new(0.0, height - sb_size.height))
                # Reduce content area - keep padding between content and statusbar
                content_height = height - content_y_offset - sb_size.height - CONTENT_PADDING
            end

            # Stack content widgets vertically (auto-stack behavior)
            # Special case: single child fills full height (common case: vstack/hstack)
            if content.size == 1
                # Single child gets full available space
                child_constraints = BoxConstraints.tight(Size.new(content_width, content_height))
                content.first.layout(child_constraints, Vec2.new(content_x, content_y_offset))
            else
                # Multiple children auto-stack vertically
                current_y = content_y_offset
                content.each do |child|
                    child_constraints = BoxConstraints.new(
                        min_width: 0.0,  # Allow widgets their natural width
                        max_width: content_width,  # But constrain to window width
                        min_height: 0.0,
                        max_height: content_height - (current_y - content_y_offset)
                    )
                    child.layout(child_constraints, Vec2.new(content_x, current_y))
                    current_y += child.bounds.height
                end
            end

            # Add content widgets to root layer (statusbar has its own layer)
            if root = @root_layer
                content.each { |child| root.widgets << child }
            end

            # Layout layered widgets (WindowPanel, LayerBox, etc.)
            # Full window size - they position themselves
            layered_constraints = BoxConstraints.tight(Size.new(width, height))
            layered.each do |widget|
                widget.layout(layered_constraints, position)
                # Constrain position to panel area bounds (excludes menubar for maximized panels)
                if widget.responds_to?(:constrain_to_window_bounds)
                    widget.constrain_to_window_bounds(panel_area_bounds)
                end
            end

            # Layout overlays (popups, tooltips, modals)
            # Overlays position themselves - we just call layout to compute their bounds
            overlay_constraints = BoxConstraints.loose(Size.new(width, height))
            @overlays.each do |overlay|
                # Use overlay's current position (set by owner widget) or default to origin
                overlay_pos = overlay.bounds.position
                overlay.layout(overlay_constraints, overlay_pos)
            end
        end

        # Generate primitives for rendering - Window is just a container
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            # Window doesn't render anything - children render themselves
            [] of DrawPrimitive
        end

        # Override hit_test to respect z-ordering
        # Check overlays first (highest z-index), then children in reverse z-order
        def hit_test(point : Vec2) : Widget?
            return nil unless absolute_bounds.contains_point(point)

            # First check overlays (popups, tooltips, modals) - highest z-index first
            # Overlays are managed separately from DSL children
            overlay_popups = @overlays.select { |o| o.is_a?(Popup) }.map(&.as(Popup))
            overlay_popups.sort_by(&.z_index).reverse.each do |popup|
                if hit = popup.hit_test(point)
                    return hit
                end
            end

            # Also check legacy popups in widget tree (for backwards compatibility)
            # TODO: Remove once all popup users migrate to add_overlay
            tree_popups = find_all_popups.reject { |p| @overlays.includes?(p) }
            tree_popups.sort_by(&.z_index).reverse.each do |popup|
                if hit = popup.hit_test(point)
                    return hit
                end
            end

            # Then check children in reverse z-order (highest z-index first)
            sorted_children.reverse_each do |child|
                if hit = child.hit_test(point)
                    return hit
                end
            end

            # Return self if no child was hit
            self
        end

        # Collect all layers for rendering (root + panels + menubar + popups)
        # Returns layers sorted by z-index (ascending)
        def collect_all_layers : Array(Layer)
            # Use Layer registry for efficient O(k × d) lookup
            # Filters to only layers in the active widget tree, sorted by z_index
            Layer.active_layers(self).sort_by(&.z_index)
        end

        # Get children sorted by z_index (lowest to highest)
        # Content first, then panels, then MenuBar on top
        # (Popups are rendered separately - they're not direct Window children)
        def sorted_children : Array(Widget)
            menubar = children.select { |c| c.is_a?(MenuBar) }
            panels = children.select { |c| c.is_a?(WindowPanel) }.map(&.as(WindowPanel)).reject(&.closed)
            content = children.reject { |c| c.is_a?(MenuBar) || c.is_a?(WindowPanel) }

            # Content first (bottom), panels (sorted by z_index), MenuBar last (top)
            content + panels.sort_by(&.z_index) + menubar
        end

        # Get menubar child for direct compositing
        def menubar_child : Widget?
            children.find { |c| c.is_a?(MenuBar) }
        end

        # Get bounds for the panel area (excludes menubar at the top AND
        # statusbar at the bottom). Used for maximize / drag-constrain so
        # panels never cover either system surface. Without the statusbar
        # exclusion, maximizing a panel filled to the very bottom of the
        # window and the statusbar disappeared underneath.
        def panel_area_bounds : Rect
            menubar = children.find { |c| c.is_a?(MenuBar) }
            statusbar = children.find { |c| c.is_a?(StatusBar) }
            top = @bounds.y
            bottom = @bounds.y + @bounds.height
            top += menubar.bounds.height if menubar
            bottom -= statusbar.bounds.height if statusbar
            Rect.new(@bounds.x, top, @bounds.width, bottom - top)
        end

        # Expose root layer for widget state propagation
        # This allows child widgets to find and mark the root layer
        def layer : Layer?
            @root_layer
        end

        # Pull-based layer bounds: root layer = full window bounds
        def compute_bounds_for_layer(layer : Layer) : Rect
            @bounds
        end
    end
end
