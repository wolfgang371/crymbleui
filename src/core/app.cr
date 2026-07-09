require "./widget"
require "./drag_manager"
require "./overlay"
require "../dsl/builder"

module CrymbleUI
  # Base class for Crystal UI applications
  # Users extend this and implement build() to create their UI
  abstract class App
    include DSL::BuilderMethods

    # Root widget of the application
    getter root : Widget?

    # Callback for exceptions during event handling (set by app for statusbar warnings)
    property on_event_exception : Proc(String, Nil)? = nil

    # Instrumentation: Track rebuild calls (for testing)
    @@rebuild_count : Int32 = 0

    def self.rebuild_count : Int32
      @@rebuild_count
    end

    def self.reset_rebuild_count
      @@rebuild_count = 0
    end

    def self.class_var_increment_rebuild_count
      @@rebuild_count += 1
    end

    # Hover tracking (which widget is currently under the mouse)
    # Rebuild flag: explicitly set when DSL tree needs to be rebuilt.
    # Separate from mark_needs_layout which only affects geometry.
    @needs_rebuild : Bool = false

    # Cheap-rebuild staleness: set at the end of rebuild(), consumed by the renderer AFTER prepare_layout
    # (once layer.widgets is repopulated) to run the per-layer content-staleness assessment
    # (LayerRenderer#assess_rebuild_staleness). One-shot; replaces the old unconditional post-rebuild
    # blanket clear so an unchanged layer keeps its carried buffer instead of full-re-rendering.
    property rebuild_needs_assessment : Bool = false

    # Request a DSL rebuild on the next frame.
    # Call this when app state changes require build() to produce a new widget tree.
    def request_rebuild
      @needs_rebuild = true
      @root.try &.mark_needs_layout  # layout needed after rebuild
    end

    def needs_rebuild? : Bool
      @needs_rebuild
    end

    @hovered_widget : Widget? = nil
    @last_mouse_position : Vec2? = nil

    # Get the currently hovered widget (ImGui-style API)
    def hovered_widget : Widget?
      @hovered_widget
    end

    # Check if a specific widget is currently hovered (ImGui-style API)
    def is_widget_hovered?(widget : Widget) : Bool
      @hovered_widget == widget
    end

    # Callback invoked when hover state changes
    @hover_change_callback : Proc(Nil)? = nil

    # Set callback to be invoked when hover state changes
    # Typically called in build() to wire up hover-dependent UI updates
    def on_hover_change(&block : -> Nil)
      @hover_change_callback = block
    end

    # Callback invoked when close is requested (X button, Alt+F4, etc.)
    @close_callback : Proc(Nil)? = nil

    # Set close callback - context-aware:
    # Inside a window_panel block: sets panel's on_closed callback
    # Otherwise: sets App's window close callback
    #
    # Example (App-level):
    #   on_closed do
    #     save_data()
    #     self.quit  # Actually close the window
    #   end
    #
    # Example (panel-level):
    #   window_panel("My Panel", ...) do
    #     on_closed { handle_panel_close }
    #   end
    def on_closed(&block : -> Nil)
      # Check if we're inside a window_panel DSL block
      if (stack = @container_stack) && !stack.empty?
        container = stack.last
        if container.is_a?(WindowPanel)
          container.on_closed(&block)
          return
        end
      end
      @close_callback = block
    end

    # Internal: Handle close request from window manager
    def handle_close_request
      if callback = @close_callback
        callback.call
      else
        # No callback set - default behavior is to quit immediately
        quit
      end
    end

    # Mouse drag tracking
    @mouse_down : Bool = false
    @mouse_down_widget : Widget? = nil

    # Drag-and-drop manager
    @drag_manager : DragManager = DragManager.new

    # Get the drag manager (for layer rendering)
    def drag_manager : DragManager
      @drag_manager
    end

    # Cached topmost panel (for rendering optimization)
    @topmost_panel : WindowPanel? = nil

    # Callback to quit the application (set by renderer)
    @quit_callback : Proc(Nil)? = nil
    @needs_composite_only : Bool = false

    def initialize
      @root = nil
    end

    # Request compositor-only frame (no layer render needed).
    # Use for visibility toggles (opacity changes) that don't change content.
    def request_composite
      @needs_composite_only = true
    end

    def needs_composite_only? : Bool
      res = @needs_composite_only
      @needs_composite_only = false
      res
    end

    # Request application quit (closes the window)
    # Call this from menu items or shortcuts to exit the app
    def quit
      @quit_callback.try &.call
    end

    # Set quit callback (called by renderer)
    def quit_callback=(callback : Proc(Nil))
      @quit_callback = callback
    end

    # Override in subclasses to set a custom window background color.
    # Returns nil to use Theme.current.app_background (the default).
    def app_background_color : Color?
      nil
    end

    # Overlay primitives drawn directly to the window after all layers
    # Override in subclasses for splash screens, overlays, etc.
    # Receives window dimensions; primitives use absolute screen coordinates
    def overlay_primitives(window_width : Float64, window_height : Float64) : Array(DrawPrimitive)?
      nil
    end

    # State property macro - automatically triggers rebuild when changed
    # Usage: state count : Int32 = 0
    # This generates a property with a custom setter that calls rebuild
    #
    # Provides automatic UI updates when state changes.
    #
    # Example:
    #   class MyApp < CrymbleUI::App
    #     state count : Int32 = 0
    #
    #     def build
    #       button("Increment") { @count += 1 }  # Auto-rebuilds!
    #     end
    #   end
    macro state(declaration)
            {% if declaration.is_a?(TypeDeclaration) %}
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                {% else %}
                    @{{declaration.var}} : {{declaration.type}}
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}} = value
                    # Request rebuild — app state changed, DSL tree needs updating
                    request_rebuild
                end
            {% end %}
        end

    # FUTURE: Observable Objects Pattern (Option 2)
    #
    # For more complex state management with nested objects, we may want
    # to implement an Observable pattern.
    #
    # Concept:
    #   class UserData
    #     include Observable
    #     published property name : String = ""
    #     published property age : Int32 = 0
    #   end
    #
    #   class MyApp < CrymbleUI::App
    #     observe user_data : UserData = UserData.new
    #
    #     def build
    #       text(@user_data.name)  # Auto-rebuilds when name changes
    #     end
    #   end
    #
    # This would require:
    # - Observable module with published macro
    # - observe macro in App that subscribes to object changes
    # - Change notification system
    #
    # For now, the `state` macro handles simple properties well enough.
    # We'll add this if/when we need nested object tracking.

    # Build the application UI (abstract - users implement this)
    # Should return the root widget
    abstract def build : Widget

    # Build and set the widget tree
    def build_tree
      # Clear shortcuts before rebuilding to avoid duplicates
      # Shortcuts will be re-registered as widgets are created
      begin
        Widget.shortcut_manager.clear
      rescue
        # ShortcutManager not initialized yet (first build before renderer)
      end

      @root = build()
    end

    # Find widget by ID in the widget tree
    def find(id : String) : Widget?
      @root.try &.find_by_id(id)
    end

    # Find widget by path ID
    def find_by_path(path : String) : Widget?
      @root.try &.find_by_path(path)
    end

    # Find all widgets matching condition
    def find_all(&block : Widget -> Bool) : Array(Widget)
      if r = @root
        r.find_all(&block)
      else
        [] of Widget
      end
    end

    # Trigger rebuild of widget tree with reconciliation
    def rebuild
      {% if flag?(:DEBUG_RENDER) %}
        puts "\n[REBUILD TRIGGERED - Layer objects will be recreated!]"
        # Print callstack to see what triggered rebuild
        begin
          raise Exception.new
        rescue ex
          ex.backtrace.each_with_index do |line, i|
            break if i >= 10 # Limit to 10 lines
            puts "  #{line}"
          end
        end
      {% end %}

      # Use explicit class reference to avoid subclass variable shadowing
      CrymbleUI::App.class_var_increment_rebuild_count

      # Clear shortcuts before rebuilding to avoid duplicates
      # Shortcuts will be re-registered as widgets are created
      begin
        Widget.shortcut_manager.clear
      rescue
        # ShortcutManager not initialized yet (shouldn't happen in rebuild, but be safe)
      end

      old_root = @root

      # Collect old panel IDs before rebuild (to detect new panels after reconciliation)
      old_panel_ids = Set(String).new
      if old_root
        old_root.children.each do |child|
          if child.is_a?(WindowPanel) && (id = child.id)
            old_panel_ids << id
          end
        end
      end

      # Save mouse_down_widget's path ID before rebuild (for re-finding after reconciliation)
      # this is crucial for e.g. scrollbar scrolling!
      mouse_down_widget_path_id = @mouse_down_widget.try(&.path_id)

      # Build new tree
      new_root = build()

      # Reconcile old and new trees
      if old_root
        reconcile(old_root, new_root)
      end

      # Bring new (unreconciled) panels to front so they appear on top
      unless old_panel_ids.empty?
        new_root.children.each do |child|
          if child.is_a?(WindowPanel)
            id = child.id
            if id.nil? || !old_panel_ids.includes?(id)
              child.bring_to_front
            end
          end
        end
      end

      @root = new_root

      # Clear hovered widget - it points to old tree now
      # Will be re-detected on next layout+update_hover or mouse move
      @hovered_widget = nil

      # Reconcile keyboard focus to the new tree. A reconciled widget already had
      # focus transferred in reconcile() above; but a widget that was REMOVED
      # (e.g. a closed dialog) leaves focus dangling on an orphan that keeps
      # eating key events (a stale TextInput swallows Alt+Left so the panel
      # shortcut never fires). Mirrors the @hovered_widget reset.
      Widget.focus_manager?.try &.reconcile_focus(new_root)

      # Update mouse_down_widget to point to corresponding widget in new tree
      # Critical for dragging to continue working after rebuild (e.g., ScrollView scrollbar dragging)
      if mouse_down_widget_path_id
        @mouse_down_widget = new_root.find_by_path(mouse_down_widget_path_id)
      end

      # Update drag state widget references to point to new tree nodes
      # Without this, mid-drag rebuilds leave source_widget/current_target pointing at dead nodes
      @drag_manager.state.update_widget_references(new_root)

      # Clean up orphaned layers from the registry
      # Old layers from the old widget tree are no longer reachable - remove them
      # This prevents @@all_layers from growing unboundedly with each rebuild
      Layer.cleanup_orphaned_layers(new_root)

      # Same cleanup for the WindowPanel/Popup topmost-lookup registries (mirrors Layer's).
      # Old panel/popup instances from the discarded old_root are no longer reachable — drop
      # them so @@all_panels/@@all_popups don't grow unboundedly across rebuilds.
      WindowPanel.cleanup_orphaned(new_root)
      Popup.cleanup_orphaned(new_root)

      # Clean up orphaned widgets from active layers.
      # Reconciled layers may retain widgets from the old tree that weren't
      # @[Reconcile]d — new widgets get appended, old ones accumulate.
      Layer.cleanup_orphaned_widgets(new_root)

      # Validate reconciliation integrity (debug mode only).
      # Catches orphaned references that would cause rendering bugs.
      {% if flag?(:DEBUG_INVARIANTS) %}
        validate_reconciliation(new_root)
      {% end %}

      # After a rebuild a layer MAY have stale pixels from old widgets at positions no longer covered
      # (ghost artifacts) — but a layer whose content is UNCHANGED does not, and clearing it wastes a
      # full re-render (the v2 rebuild cost). So the decision is per-layer + deferred: overlay layers
      # (cursor — CachePolicy::Never) refresh here (their widgets are already final); every other layer
      # is assessed for content-staleness AFTER prepare_layout repopulates layer.widgets, in the
      # renderer (LayerRenderer#assess_rebuild_staleness, gated on @rebuild_needs_assessment + did_layout).
      Layer.active_layers(new_root).each do |layer|
        if layer.skip_rebuild_clear
          layer.mark_needs_render(layer.widgets.first) if layer.widgets.first?
        end
      end
      @rebuild_needs_assessment = true

      # Clean up orphaned overlays (e.g., ComboBoxPopup from closed panels)
      # Must happen AFTER reconciliation so ComboBoxes have their popup references
      if new_root.is_a?(Window)
        new_root.cleanup_orphaned_overlays
      end

      @needs_rebuild = false
    end

    {% if flag?(:DEBUG_INVARIANTS) %}
      private def validate_reconciliation(root : Widget)
        Layer.active_layers(root).each do |layer|
          # Check 1: layer owner reachable from root
          unless layer.in_tree?(root)
            STDERR.puts "[INVARIANT] Layer '#{layer.id}' owner_widget not in tree after rebuild!"
          end
          # Check 2: all layer.widgets reachable from root
          layer.widgets.each do |w|
            unless w.widget_in_tree?(root)
              STDERR.puts "[INVARIANT] Widget #{w.class.name.split("::").last}##{w.id} in layer '#{layer.id}' not in tree after rebuild!"
            end
          end
        end
      end
    {% end %}

    # Re-detect hover after layout changes
    # Call this after rebuild+layout to restore hover state
    def redetect_hover
      if pos = @last_mouse_position
        if root = @root
          update_hover(pos)
        end
      end
    end

    # Reconcile old and new widget trees
    # Reuses widget instances where possible to preserve state (positions, etc.)
    private def reconcile(old_widget : Widget, new_widget : Widget)
      {% if flag?(:DEBUG_RENDER) %}
        puts "[RECONCILE] old=#{old_widget.class.name.split("::").last}##{old_widget.path_id} vs new=#{new_widget.class.name.split("::").last}##{new_widget.path_id}"
      {% end %}

      # If same type, copy state from old to new
      # This works both for widgets with matching IDs and widgets matched by position
      if old_widget.class == new_widget.class
        # If both have IDs, they must match
        if old_widget.id && new_widget.id
          if old_widget.id == new_widget.id
            {% if flag?(:DEBUG_RENDER) %}
              puts "[RECONCILE] Same class + matching IDs -> copying state"
            {% end %}
            copy_widget_state(old_widget, new_widget)
          else
            {% if flag?(:DEBUG_RENDER) %}
              puts "[RECONCILE] Same class but IDs differ (old=#{old_widget.id}, new=#{new_widget.id}) -> NOT copying"
            {% end %}
          end
        else
          # No IDs (or one has ID) - matched by position, still copy state
          {% if flag?(:DEBUG_RENDER) %}
            puts "[RECONCILE] Same class, no matching IDs -> copying state by position"
          {% end %}
          copy_widget_state(old_widget, new_widget)
        end
      else
        {% if flag?(:DEBUG_RENDER) %}
          puts "[RECONCILE] Different classes -> NOT copying state"
        {% end %}
      end

      # Reconcile children
      reconcile_children(old_widget, new_widget)
    end

    # Reconcile children of two widgets
    private def reconcile_children(old_parent : Widget, new_parent : Widget)
      old_children = old_parent.children
      new_children = new_parent.children

      # Build map of old children by ID
      old_by_id = {} of String => Widget
      old_children.each do |child|
        if id = child.id
          old_by_id[id] = child
        end
      end

      # Match new children with old children
      new_children.each_with_index do |new_child, index|
        if id = new_child.id
          # Try to find by ID first
          if old_child = old_by_id[id]?
            reconcile(old_child, new_child)
          end
        elsif index < old_children.size
          # No ID - try to match by position if same type
          old_child = old_children[index]
          if old_child.class == new_child.class
            reconcile(old_child, new_child)
          end
        end
      end
    end

    # Copy state from old widget to new widget (preserves positions, etc.)
    private def copy_widget_state(old : Widget, new : Widget)
      {% if flag?(:DEBUG_RENDER) %}
        puts "[COPY_WIDGET_STATE] Copying from #{old.class.name.split("::").last}##{old.path_id} to #{new.class.name.split("::").last}##{new.path_id}"
      {% end %}

      # Copy bounds (preserves position/size)
      new.bounds = old.bounds

      # Let widget copy its own state (virtual method)
      {% if flag?(:DEBUG_RENDER) %}
        puts "[COPY_WIDGET_STATE] About to call copy_state_from..."
      {% end %}
      new.copy_state_from(old)
      {% if flag?(:DEBUG_RENDER) %}
        puts "[COPY_WIDGET_STATE] Done calling copy_state_from"
      {% end %}
    end

    # Update hover state based on what's under the mouse
    # Returns true if hover changed (needs redraw), false otherwise
    def update_hover(point : Vec2) : Bool
      return false unless root = @root

      # Store mouse position for rebuild hover re-detection
      @last_mouse_position = point

      # Find widget under mouse
      current_hover = root.hit_test(point)

      {% if flag?(:DEBUG_HOVER) %}
        # DEBUG: Log hover detection
        if current_hover
          bounds = current_hover.absolute_bounds
          puts "[HOVER] Point (#{point.x.round(1)}, #{point.y.round(1)}) -> #{current_hover.class.name} bounds=(#{bounds.x.round(1)}, #{bounds.y.round(1)}, #{bounds.width.round(1)}x#{bounds.height.round(1)})"
        end
      {% end %}

      # Check if hover changed
      hover_changed = (current_hover != @hovered_widget)
      if hover_changed
        @hovered_widget.try &.on_mouse_exit
        @hovered_widget = current_hover
        current_hover.try &.on_mouse_enter
      end

      # Always fire hover callback (position-dependent widgets like VirtualMatrix
      # need updates on every move, not just widget changes)
      @hover_change_callback.try &.call

      hover_changed
    end

    # Handle mouse down events
    def handle_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
      return unless root = @root

      # Notify window of click for popup click-outside-to-close
      # This happens BEFORE hit_test so popups can close before new interaction
      if root.is_a?(Window)
        root.notify_overlays_of_click(point)
      end

      @mouse_down = true
      if widget = root.hit_test(point)
        @mouse_down_widget = widget

        # A click outside every overlay surface dismisses the open menus.
        unless is_inside_overlay_surface?(widget)
          close_all_menus(root)
        end

        # Start drag tracking if widget or an ancestor is Draggable
        if draggable = find_draggable_ancestor(widget)
          @drag_manager.begin_drag_tracking(draggable, point)
        end

        widget.on_mouse_down(point, button)

        # Cancel drag tracking if widget claimed the click for its own purpose
        # (e.g., VirtualMatrix resize — drag tracking would intercept mouse_move)
        if @drag_manager.state.pending? && widget.suppresses_drag?
          @drag_manager.cancel_drag
        end
        # Rebuild only if explicitly requested (not for layout-only changes)
        if needs_rebuild?
          # Save path_id before rebuild (widget will be replaced with new instance)
          widget_path = widget.path_id
          rebuild
          # Update @mouse_down_widget to point to NEW widget instance
          # (old instance's parent chain is broken after rebuild)
          if new_widget = find_by_path(widget_path)
            @mouse_down_widget = new_widget
          end
        end
      end
    end

    # Did the mouse-down land inside a click-interactive overlay SURFACE (a Popup or an open
    # Menu)? If so it's an interaction with that surface, not a dismiss gesture, so menus stay
    # open. Asked via the OverlaySurface capability — the App never type-checks Popup/Menu.
    private def is_inside_overlay_surface?(widget : Widget) : Bool
      current = widget
      while current
        return true if current.is_a?(OverlaySurface)
        current = current.parent
      end
      false
    end

    # Find the closest Draggable ancestor (including the widget itself)
    private def find_draggable_ancestor(widget : Widget) : Widget?
      current : Widget? = widget
      while current
        return current if current.is_a?(Draggable)
        current = current.parent
      end
      nil
    end

    # Dismiss every dismissable overlay in the tree (close menus, deactivate menubars).
    # Returns true iff something was actually open — so ESC can report it consumed the key.
    # Dispatched via the Dismissable capability; the App never type-checks Menu/MenuBar.
    private def close_all_menus(widget : Widget) : Bool
      dismissed = false
      widget.find_all { |w| w.is_a?(Dismissable) }.each do |w|
        dismissed = true if w.as(Dismissable).dismiss_overlay
      end
      dismissed
    end

    # Handle ESC key press - cancels drags and closes menus
    # Returns true if something was cancelled/closed
    def handle_escape : Bool
      # Priority 1: Cancel active drag
      if @drag_manager.dragging? || @drag_manager.state.pending?
        @drag_manager.cancel_drag
        return true
      end

      # Priority 2: Close menus
      if r = @root
        return close_all_menus(r)
      end

      false
    end

    # Handle mouse move events (for dragging and hover)
    # Returns true if needs redraw, false otherwise
    def handle_mouse_move(point : Vec2) : Bool
      # Drag-and-drop takes priority
      if @drag_manager.state.phase != DragPhase::Idle
        if root = @root
          return @drag_manager.update_drag(point, root)
        end
      end

      # Handle widget dragging if mouse is down (WindowPanel, ScrollView, etc.)
      if @mouse_down
        if widget = @mouse_down_widget
          widget.on_mouse_move(point)
          # Rebuild only if explicitly requested (not for layout-only changes)
          if needs_rebuild?
            # Save path_id before rebuild (widget will be replaced with new instance)
            widget_path = widget.path_id
            rebuild
            # Update @mouse_down_widget to point to NEW widget instance
            # (old instance's parent chain is broken after rebuild)
            if new_widget = find_by_path(widget_path)
              @mouse_down_widget = new_widget
            end
          end
          # Return true to trigger redraw during drag
          return true
        end
      end

      # Update hover when not dragging (matches SFML renderer behavior)
      update_hover(point)
    end

    # Handle mouse up events
    def handle_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      return unless root = @root

      # Complete drag-and-drop if active
      if @drag_manager.dragging?
        @drag_manager.end_drag(point)
        # Skip normal click processing after drag
        @mouse_down = false
        @mouse_down_widget = nil
        return
      end

      # Cancel pending drag if threshold not reached
      if @drag_manager.state.pending?
        @drag_manager.cancel_drag
      end

      # Call on_mouse_up on the widget that was pressed
      if widget = @mouse_down_widget
        widget.on_mouse_up(point, button)

        # If mouse released over the same widget, trigger click (left-click only)
        if button == MouseButton::Left
          if hit = root.hit_test(point)
            if hit == widget
              widget.trigger_click
            end
          end
        end

        # Rebuild if explicitly requested
        if needs_rebuild?
          rebuild
        end
      end

      @mouse_down = false
      @mouse_down_widget = nil
    end

    # Handle mouse wheel scroll events
    # delta: Vec2 where y is vertical scroll (positive = up, negative = down)
    # point: Mouse position in window coordinates
    # shift: Whether shift key is held (for horizontal scrolling)
    def handle_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false)
      return unless root = @root

      # Find widget under mouse
      if widget = root.hit_test(point)
        # Walk up tree to find first widget that handles wheel events
        current : Widget? = widget
        while current
          if current.responds_to?(:on_mouse_wheel)
            current.on_mouse_wheel(delta, point, shift: shift)
            # Rebuild only if explicitly requested
            rebuild if needs_rebuild?
            return
          end
          current = current.parent
        end
      end
    end

    # Get the widget currently under the mouse (for cursor updates)
    def widget_at(point : Vec2) : Widget?
      @root.try &.hit_test(point)
    end

    # Check if mouse is currently down (for cursor updates during drag)
    def mouse_down? : Bool
      @mouse_down
    end

    # Prepare layout if needed, update topmost panel cache
    # Returns true if layout happened OR topmost panel changed, false otherwise
    def prepare_layout(window_size : Size) : Bool
      return false unless root = @root

      did_layout = false
      if root.needs_layout?
        constraints = BoxConstraints.loose(window_size)
        root.layout(constraints, Vec2.new(0.0, 0.0))
        root.state = WidgetState::Clean
        did_layout = true
        Widget.increment_layout_count # Instrumentation
      end

      # Check if topmost panel changed (even without layout)
      # This forces cache rebuild when panel z-order changes
      old_topmost = @topmost_panel
      update_topmost_panel_cache
      topmost_changed = (old_topmost != @topmost_panel)

      did_layout || topmost_changed
    end

    # Get the current topmost panel (cached)
    def topmost_panel : WindowPanel?
      @topmost_panel
    end

    # Update topmost panel cache (call after layout or panel changes)
    def update_topmost_panel_cache
      @topmost_panel = @root.try &.find_topmost_panel
    end

    # Get cursor type for a point (decides based on panels and resize edges)
    def get_cursor_for_point(point : Vec2) : CursorType
      return CursorType::Arrow unless root = @root

      # FIRST: Check if point is inside any popup (popups block events to widgets below)
      # Popups have high z-index (1000+) and should block resize cursors from panels below
      popups = root.find_all_popups.sort_by(&.z_index).reverse!
      popups.each do |popup|
        if popup.absolute_bounds.contains_point(point)
          # Point is inside popup - popup blocks cursor changes from widgets below
          return CursorType::Arrow
        end
      end

      # SECOND: Check panels (only if NOT inside any popup)
      # Find all panels sorted by z_index (highest first)
      panels = root.find_all_panels.reject(&.closed).sort_by(&.z_index).reverse!

      # Check panels front-to-back, stop at first hit
      panels.each do |panel|
        if panel.absolute_bounds.contains_point(point)
          # Check if it's resizable and not maximized, and we're on an edge
          if panel.resizable && !panel.maximized
            resize_edge = panel.get_resize_edge(point)
            if resize_edge != ResizeEdge::None
              return case resize_edge
              when ResizeEdge::TopLeft, ResizeEdge::BottomRight
                CursorType::SizeNWSE
              when ResizeEdge::TopRight, ResizeEdge::BottomLeft
                CursorType::SizeNESW
              when ResizeEdge::Left, ResizeEdge::Right
                CursorType::SizeHorizontal
              when ResizeEdge::Top, ResizeEdge::Bottom
                CursorType::SizeVertical
              else
                CursorType::Arrow
              end
            end
          end
          # Over panel but not on resize edge
          return infer_widget_cursor(root, point)
        end
      end

      # Not over any panel or popup
      infer_widget_cursor(root, point)
    end

    # Infer cursor from widget under point via preferred_cursor
    private def infer_widget_cursor(root : Widget, point : Vec2) : CursorType
      widget = root.hit_test(point)
      return CursorType::Arrow if widget.nil?
      widget.preferred_cursor(point) || CursorType::Arrow
    end

    # Clear all widget render states
    def clear_render_state
      @root.try &.clear_render_state_recursive
    end

    # Reset all caches for recovery after exception (graceful degradation)
    # Clears all widget render caches, layer backends, and interaction state
    # Forces full re-render on next frame
    def reset_all_caches
      @root.try(&.reset_render_caches_recursive)
      reset_layers_recursive(@root)

      # Clear interaction state (widgets may be invalid after exception)
      @hovered_widget = nil
      @mouse_down_widget = nil
      @topmost_panel = nil
      @drag_manager.cancel_drag if @drag_manager.dragging?
    end

    # Helper: Reset all layers in widget tree
    private def reset_layers_recursive(widget : Widget?)
      return unless widget
      if layer = widget.layer
        layer.reset_for_recovery
      end
      widget.children.each { |child| reset_layers_recursive(child) }
    end

    # Dump widget tree for debugging
    def dump_tree
      @root.try &.dump_tree
    end

    # DEBUG: Find all widgets needing layout (for instrumentation)
    def find_widgets_needing_layout(widget : Widget, depth : Int32 = 0)
      indent = "  " * depth
      if widget.needs_layout?
        puts "#{indent}⚠️  #{widget.class.name.split("::").last}##{widget.path_id} [NeedsLayout]"
      end
      widget.children.each do |child|
        find_widgets_needing_layout(child, depth + 1)
      end
    end
  end
end
