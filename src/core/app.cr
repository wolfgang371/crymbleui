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
    # The panel in front takes the keyboard at the next frame (settle_keyboard)
    @enter_front_pending : Bool = false

    # Cheap-rebuild staleness: set at the end of rebuild(), consumed by the renderer AFTER prepare_layout
    # (once layer.widgets is repopulated) to run the per-layer content-staleness assessment
    # (LayerRenderer#assess_rebuild_staleness). One-shot; replaces the old unconditional post-rebuild
    # blanket clear so an unchanged layer keeps its carried buffer instead of full-re-rendering.
    property rebuild_needs_assessment : Bool = false

    # Request a DSL rebuild on the next frame.
    # Call this when app state changes require build() to produce a new widget tree.
    #
    # `blocks_input`: whether input queued behind this request must wait for the rebuilt tree (the
    # input barrier below). True unless the caller knows the change leaves everything the input acts
    # on in place - embrace's per-cell write, whose rebuild only refreshes the OTHER views of the
    # data. Such a request is applied at the end of the batch, like any rebuild, without ending it:
    # a script typing into a grid would otherwise pay a rebuild per committed cell.
    def request_rebuild(blocks_input : Bool = true)
      @needs_rebuild = true
      @frame_before_input = true if blocks_input
      @root.try &.mark_needs_layout  # layout needed after rebuild
    end

    def needs_rebuild? : Bool
      @needs_rebuild
    end

    # THE INPUT BARRIER. Structural work deferred to the next frame - a blocking rebuild request, or
    # a widget's announced structural change (VirtualMatrix#invalidate_all!) - leaves state that the
    # next queued event would read stale. EventBatch stops dispatching while this holds, and the run
    # loop renders the frame that applies the work; prepare_layout, which every frame runs, lifts it.
    # Layout, scrolling and content refreshes do not raise it: their coalescing is what keeps a drag
    # to one frame per batch.
    #
    # The frame that lifts it applies that work for EVERY widget that announced it - painted or not.
    # A widget applies it while it paints, but occlusion culling, a closed or hidden panel or an empty
    # viewport skip the painting, and the barrier comes down all the same; so an announcing widget
    # (`owner`) also registers, and finish_frame applies what it still holds before the next input.
    def request_frame_before_input(owner : Widget? = nil) : Nil
      @frame_before_input = true
      owner.try { |w| register_input_flush(w) }
    end

    # Registers structural work the next input depends on without raising the barrier - a per-cell
    # invalidation, a deferred scroll: they keep coalescing within a batch, and finish_frame applies
    # them after the frame whether or not the widget painted.
    def register_input_flush(owner : Widget) : Nil
      @input_flushers << owner
    end

    # Once per frame, after the frame is rendered and its render trigger stamped, before the next input
    # is dispatched: every registered widget still in the tree applies the structural work it holds
    # (Widget#flush_before_input - a no-op for one that painted). A widget a rebuild replaced is skipped:
    # its successor inherited the work and registered itself. A registration made during these flushes
    # lands in the next frame; nothing is carried forward. True when some work ran - its marks moved
    # the render trigger after the stamp, so the renderer must not idle before the next frame.
    #
    # Every registered widget is flushed even if one raises - one failure must not strand the others'
    # work behind a lowered barrier - and the first failure is raised after the last. What it means is
    # the renderer's to say, as for any frame: SFMLRenderer reports it, TestRenderer lets it out.
    def finish_frame : Bool
      return false if @input_flushers.empty?
      flushers = @input_flushers
      @input_flushers = Set(Widget).new
      return false unless root = @root
      failure : Exception? = nil
      ran = flushers.reduce(false) do |acc, widget|
        next acc unless widget.widget_in_tree?(root)
        begin
          widget.flush_before_input || acc
        rescue ex
          failure ||= ex
          acc
        end
      end
      failure.try { |ex| raise ex }
      ran
    end

    # An exception from handling input (or from a frame's end) that the app did not handle: to its
    # on_event_exception (embrace: the status bar), else STDERR.
    def report_event_exception(ex : Exception) : Nil
      if handler = @on_event_exception
        handler.call(ex.message.to_s)
      else
        STDERR.puts "Unhandled exception: #{ex.inspect_with_backtrace}"
      end
    end

    # A frame that raised was recovered from: `message` (the renderer already wrote the backtrace to STDERR) goes to
    # on_event_exception (embrace: the status bar). Without one, nothing more to say.
    def report_display_error(message : String) : Nil
      @on_event_exception.try(&.call(message))
    end

    @input_flushers = Set(Widget).new

    def input_waits_for_frame? : Bool
      @frame_before_input
    end

    @frame_before_input = false

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

    # During a rebuild: the widgets the gesture in progress holds (the pressed one, the drag's) and their
    # ancestors, each mapped to the new widget reconcile copied its state into, and whether that pairing was
    # by id.
    @counterparts = {} of UInt64 => {Widget, Bool}

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
    # Receives window dimensions; primitives use absolute screen coordinates. Drawn straight to the
    # window, with no clip stack: a PushClip/PopClip raises WindowDirectClipError.
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

    # Called once, when the app starts running: the renderer (and its scheduler, focus and shortcut
    # managers) is up and the tree is built, before the first frame. Start the app's timers here -
    # `build` describes the UI and runs again on every rebuild, and its first run (which reads the
    # window's size and title) comes before the renderer exists.
    #
    #   def on_start
    #     every(1.second) { self.now = Time.local.to_s("%H:%M:%S") }
    #   end
    def on_start
    end

    @started = false

    # Run on_start, once. Called by the renderer (WindowRenderer#start, TestRenderer#render_frame).
    def start : Nil
      return if @started
      @started = true
      on_start
    end

    # Run the block every `interval`, until the returned Timer is cancelled.
    def every(interval : Time::Span, &block : -> Nil) : Timer
      scheduler = Widget.scheduler
      Timer.new(scheduler, scheduler.schedule(interval, repeating: true, &block))
    end

    # Run the block once, after `delay`.
    def after(delay : Time::Span, &block : -> Nil) : Timer
      scheduler = Widget.scheduler
      Timer.new(scheduler, scheduler.schedule(delay, &block))
    end

    # Build and set the widget tree
    def build_tree
      # Clear shortcuts before rebuilding to avoid duplicates. Skipped before the renderer installs the
      # manager (first build); a real error from clear() now propagates instead of being swallowed by a
      # blanket rescue. Shortcuts re-register as widgets are created.
      Widget.shortcut_manager?.try(&.clear)

      install_root(build())
    end

    # Make `root` the app's tree as a first build does: its open panels count as seen (no raise), and the front
    # one takes the keyboard at the next frame, as any panel the app opens does - launch is an opening.
    protected def install_root(root : Widget) : Nil
      @root = root
      root.find_all_panels.each { |panel| panel.seen_open = !panel.closed }
      enter_front_panel if root.find_topmost_panel
    end

    # The panel in front takes the keyboard at the next frame, laid out (settle_keyboard); no input runs before.
    private def enter_front_panel : Nil
      @enter_front_pending = true
      request_frame_before_input
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

      # Clear shortcuts before rebuilding to avoid duplicates; a real error from clear() propagates
      # (no blanket rescue). Shortcuts re-register as widgets are created.
      Widget.shortcut_manager?.try(&.clear)

      old_root = @root

      # The widgets a gesture in progress holds (the pressed one - crucial for e.g. scrollbar scrolling - and
      # the drag's), with their ancestors: reconcile records what it pairs each with, and they are handed on
      # after it.
      @counterparts.clear
      held = @drag_manager.held_widgets
      @mouse_down_widget.try { |w| held << w }
      held.each do |widget|
        node = widget
        while node
          @counterparts[node.object_id] ||= {node, false}
          node = node.parent
        end
      end

      # Build new tree
      new_root = build()

      # Reconcile old and new trees. A panel open now that was not at the last rebuild (new, or reopened) comes to
      # the front and takes the keyboard - raise_z only: these instances are not laid out yet, settle_keyboard
      # hands the keyboard over at the next frame.
      if old_root
        reconcile(old_root, new_root)
        @root = new_root
        opened = false
        new_root.find_all_panels.each do |panel|
          if !panel.closed && !panel.seen_open
            panel.raise_z
            opened = true
          end
          panel.seen_open = !panel.closed
        end
        enter_front_panel if opened
      else
        install_root(new_root)
      end

      # Clear hovered widget - it points to old tree now
      # Will be re-detected on next layout+update_hover or mouse move
      @hovered_widget = nil

      # Reconcile keyboard focus to the new tree. A reconciled widget already had
      # focus transferred in reconcile() above; but a widget that was REMOVED
      # (e.g. a closed dialog) leaves focus dangling on an orphan that keeps
      # eating key events (a stale TextInput swallows Alt+Left so the panel
      # shortcut never fires). Mirrors the @hovered_widget reset.
      enter_front_panel if Widget.focus_manager?.try &.reconcile_focus(new_root)

      # Hand the gesture to the widgets that replaced the ones it holds - the pressed one (a drag of a
      # scrollbar or a panel goes on) and the drag's (a pending drag keeps the payload its pressed source
      # offered). Without this they point at dead nodes.
      @mouse_down_widget = @mouse_down_widget.try { |w| counterpart(w, new_root) }
      @drag_manager.rebind { |w| counterpart(w, new_root) }
      @counterparts.clear

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

      # Release the DISCARDED tree's pull-cache nodes. Each Dynamic widget's @primitives_node captured
      # the immortal global Sources (theme/zoom) during its last recompute; those Sources clear
      # @dependents only on their own `set` (a rare theme/zoom toggle), so without this every rebuild
      # would leave another dead generation pinned via Source→node→on_dirty→widget. Safe: reconcile
      # built new_root fresh and never copies @primitives_node, so old and new node sets are disjoint;
      # runs after all old→new ref repointing above. (Overlays are migrated-LIVE out of old_root and
      # disposed on their own drop paths — see Window#remove_overlay / cleanup_orphaned_overlays.)
      # NEVER on the LIVE tree. A build() that MEMOIZES its root — TestApp#build after
      # root_widget=, and any consumer that caches the widget it returns — makes old_root and
      # new_root the SAME object. dispose_subtree severs @children and drops backend references,
      # and an imperatively-assembled tree cannot rebuild itself from build(), so that would gut
      # the live tree unrecoverably. Window#copy_state_from guards the identical case at its own
      # seam (`return if old_window.same?(self)`, window.cr).
      old_root.try { |r| r.dispose_subtree unless r.same?(new_root) }

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
      record_counterpart(old, new)
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

    # Remember `new` as the counterpart of a widget the gesture holds (or of one of its ancestors). An old
    # widget can be paired twice - an id-less new sibling by index, an id'd one by id, in either order: the
    # id match wins, never the reverse. Everything inside it is then paired under BOTH copies (by index): a
    # pairing under the copy its container went to replaces one recorded under a copy the container has since
    # left (counterpart answers only a pairing under the container's copy).
    private def record_counterpart(old : Widget, new : Widget) : Nil
      key = old.object_id
      return unless recorded = @counterparts[key]?
      container = container_copy(old)
      by_id = !old.id.nil? && old.id == new.id
      unpaired = recorded[0].same?(old)
      left_behind = container && new.parent.same?(container) && !recorded[0].parent.same?(container)
      @counterparts[key] = {new, by_id} if unpaired || left_behind || (by_id && !recorded[1])
    end

    # The copy `old`'s container was paired with, if it was paired with a new one (not kept as itself).
    private def container_copy(old : Widget) : Widget?
      up = old.parent || return nil
      paired = @counterparts[up.object_id]?.try(&.[0])
      paired unless paired.nil? || paired.same?(up)
    end

    # The widget that is `old` after the rebuild into `new_root`: `old` itself if it is still in the new tree
    # (a memoized root, an overlay the window migrated) - its parent chain reaches the new root; else the one
    # reconcile paired it with; else nil (it is gone). (One false positive, accepted: an old child of a
    # memoized parent still points at it.)
    private def counterpart(old : Widget, new_root : Widget) : Widget?
      node = old
      while parent = node.parent
        node = parent
      end
      return old if node.same?(new_root)
      paired = @counterparts[old.object_id]?.try(&.[0])
      return nil if paired.nil? || paired.same?(old)
      # Paired under a copy its container has since left (the container went to its id match, which holds no
      # counterpart for it): gone, as when reconcile paired the id match first. Checked up the whole chain -
      # a container that is gone takes what is inside it along.
      if (up = old.parent) && container_copy(old)
        return nil unless paired.parent.same?(counterpart(up, new_root))
      end
      paired
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

      # Tell the hovered widget where the mouse is, in its own space: what it highlights may be a part of
      # it (a bar, a cell). Optional, duck-typed: `on_hover_move(point)`.
      if (hovered = current_hover) && hovered.responds_to?(:on_hover_move)
        hovered.on_hover_move(hovered.to_content(point))
      end

      # Always fire hover callback (position-dependent widgets like VirtualMatrix
      # need updates on every move, not just widget changes)
      @hover_change_callback.try &.call

      hover_changed
    end

    # Handle mouse down events
    def handle_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
      return unless root = @root

      dismiss_popups(point)

      @mouse_down = true
      # A press focuses what it hits - only a focusable widget, so a scrollbar leaves a TextInput its
      # focus - and clears focus on a press that hits nothing. Here, not in a renderer, so every path
      # to a press (both renderers, test helpers, a spec calling this) gives the focus a real one does.
      if widget = root.hit_test(point)
        Widget.focus_manager?.try &.focus(widget) if widget.takes_focus_on_click?
        @mouse_down_widget = widget
        dismiss_menus(widget)

        # Start drag tracking if widget or an ancestor is Draggable
        if draggable = find_draggable_ancestor(widget)
          @drag_manager.begin_drag_tracking(draggable, point)
        end

        # Into the widget's own space: hit_test already found it by converting the point on the
        # way down through every ScrollView; delivering the raw window point would make the
        # widget's own `point - absolute_bounds` wrong by exactly the scroll.
        widget.on_mouse_down(widget.to_content(point), button)

        # Cancel drag tracking if widget claimed the click for its own purpose
        # (e.g., VirtualMatrix resize — drag tracking would intercept mouse_move)
        if @drag_manager.state.pending? && widget.suppresses_drag?
          @drag_manager.cancel_drag
        end
        # Rebuild only if explicitly requested (not for layout-only changes); it hands the press to the pressed
        # widget's replacement
        rebuild if needs_rebuild?
      else
        Widget.focus_manager?.try &.clear_focus
      end
    end

    # The two dismissals a mouse-down makes around its handler, named so the test Driver runs the
    # same ones for an act by id (src/testing/driver.cr). Their ORDER is part of the contract and
    # is kept by handle_mouse_down: popups first, before the hit test, so a popup a click outside
    # closes can never be the widget that click lands on; menus after, because whether they close
    # depends on WHERE the click landed.

    # Close every popup the click at `point` (window space) is outside of.
    def dismiss_popups(point : Vec2) : Nil
      @root.as?(Window).try &.notify_overlays_of_click(point)
    end

    # A click that landed outside every overlay surface dismisses the open menus. `target` is what
    # the click landed on; nil (nothing hit) dismisses nothing, as ever.
    def dismiss_menus(target : Widget?) : Nil
      return unless (widget = target) && (root = @root)
      close_all_menus(root) unless is_inside_overlay_surface?(widget)
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

    # Close every open popup (Ctrl+Tab does, as a press elsewhere does)
    def close_popups : Nil
      @root.as?(Window).try &.close_popups
    end

    # Close every open menu (Ctrl+Tab does, as a press elsewhere does). True when one was open.
    def close_menus : Bool
      @root.try { |r| close_all_menus(r) } || false
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
      close_menus
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
          widget.on_mouse_move(widget.to_content(point))
          # Rebuild only if explicitly requested (not for layout-only changes)
          rebuild if needs_rebuild? # it hands the press to the pressed widget's replacement
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
        # The drop lands on what is under the release now - a scroll since the last move (with no frame
        # between, in one input batch) may have moved another target there.
        @drag_manager.follow_pointer(point, root)
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
        widget.on_mouse_up(widget.to_content(point), button)

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
    # Ctrl+wheel (`steps`: notches, positive away from the user). Offered first to the widgets under the
    # mouse, innermost first, that zoom content of their own - `on_zoom_wheel(steps, point) : Bool`, the
    # point in the widget's space - and only when none takes it, the whole UI's font zoom.
    def handle_ctrl_wheel(steps : Float64, point : Vec2) : Nil
      current : Widget? = @root.try(&.hit_test(point))
      while current
        if current.responds_to?(:on_zoom_wheel) && current.on_zoom_wheel(steps, current.to_content(point))
          rebuild if needs_rebuild?
          return
        end
        current = current.parent
      end
      if steps > 0
        FontSizing.zoom_in
      elsif steps < 0
        FontSizing.zoom_out
      end
    end

    def handle_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false)
      return unless root = @root

      # Find widget under mouse, then walk up the tree handing the wheel to each scroller in turn: each takes
      # the axes it can move on and returns the rest (ScrollView#on_mouse_wheel), in the input frame and in its
      # own space, until nothing is left - a scroller that cannot move that way passes the wheel on
      if widget = root.hit_test(point)
        left = delta
        current : Widget? = widget
        while current && (left.x != 0.0 || left.y != 0.0)
          if current.responds_to?(:on_mouse_wheel)
            left = current.on_mouse_wheel(left, current.to_content(point), shift: shift)
          end
          current = current.parent
        end
        # Rebuild only if explicitly requested
        rebuild if needs_rebuild?
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
      @frame_before_input = false # this frame applies what the barrier was waiting for
      return false unless root = @root

      did_layout = false
      if root.needs_layout?
        constraints = BoxConstraints.loose(window_size)
        root.layout(constraints, Vec2.new(0.0, 0.0))
        root.state = WidgetState::Clean
        did_layout = true
        Widget.increment_layout_count # Instrumentation
      end

      settle_keyboard(root)

      # Check if topmost panel changed (even without layout)
      # This forces cache rebuild when panel z-order changes
      old_topmost = @topmost_panel
      update_topmost_panel_cache
      topmost_changed = (old_topmost != @topmost_panel)

      # A drag follows the tree moving under a still pointer (a scroll moves nothing through layout, a
      # re-layout may): its target, highlight and on_drag_over are what is under the pointer this frame.
      @drag_manager.follow_pointer(@drag_manager.state.current_position, root)

      did_layout || topmost_changed
    end

    # The keyboard after a rebuild, on laid-out instances: a pending entry of the front panel (a panel opened,
    # the keyboard's panel closed or gone); then the rule that the keyboard's panel is the front one - a build's
    # own focus, or a programmatic one, into a panel behind raises that panel. In that order: a dialog opened in
    # the same rebuild as a Shape's build focused its grid stays in front.
    private def settle_keyboard(root : Widget) : Nil
      return unless fm = Widget.focus_manager?
      if @enter_front_pending
        @enter_front_pending = false
        root.find_topmost_panel.try { |front| fm.enter(front) }
      end
      return unless (focused = fm.focused_widget) && (panel = outermost_panel(focused))
      panel.raise_z unless panel.in_front?
    end

    private def outermost_panel(widget : Widget) : WindowPanel?
      outer = widget.find_panel
      while outer && (up = outer.find_panel)
        outer = up
      end
      outer
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

      # SECOND: the window's children front to back - its bars over the panels, the panels by z (the order a
      # click takes): the first one under the point decides, and only a panel's edge sets a resize cursor
      root.children_in_hit_order do |child|
        next unless child.absolute_bounds.contains_point(point)
        next if child.is_a?(WindowPanel) && child.closed
        unless child.is_a?(WindowPanel)
          next if child.hit_test(point).nil? # a click-through layer (a display-only LayerBox): what lies below decides
          break
        end
        if child.resizable && !child.maximized
          resize_edge = child.get_resize_edge(point)
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
        break # over the panel but not on a resize edge
      end

      infer_widget_cursor(root, point)
    end

    # Infer cursor from widget under point via preferred_cursor
    private def infer_widget_cursor(root : Widget, point : Vec2) : CursorType
      widget = root.hit_test(point)
      return CursorType::Arrow if widget.nil?
      widget.preferred_cursor(widget.to_content(point)) || CursorType::Arrow
    end

    # Clear all widget render states
    def clear_render_state
      @root.try &.clear_render_state_recursive
    end

    # Reset all caches for recovery after exception (graceful degradation)
    # Releases every surface a frame that raised may have left half-drawn - every widget's, every layer's
    # (owned layers too: a ScrollView's bands, a grid's overlays), the window overlays' and the widgets a layer
    # hosts (grid cells) - and the interaction state. Forces full re-render on next frame
    def reset_all_caches
      if root = @root
        roots = [root] + (root.as?(Window).try(&.overlays) || [] of Widget)
        roots.each do |top|
          top.reset_render_caches_recursive
          top.each_layer_in_subtree do |layer|
            layer.reset_for_recovery
            layer.widgets.each(&.reset_render_caches_recursive)
          end
        end
      end

      # Clear interaction state (widgets may be invalid after exception)
      @hovered_widget = nil
      @mouse_down_widget = nil
      @topmost_panel = nil
      @drag_manager.cancel_drag if @drag_manager.dragging?
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
