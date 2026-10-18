require "./drag_types"
require "./draggable"
require "./drop_target"
require "./layer"
require "../dsl/primitive_builder"
require "../widgets/highlight_widget"

module CrymbleUI
  # Ghost preview widget for a dragged item. Fill, border and label all track the active
  # theme (like the sibling SimpleGhostWidget), read at paint time. The fill is OPAQUE — the
  # see-through comes from the ghost layer's opacity (GHOST_OPACITY), never the fill alpha:
  # a semi-transparent fill on the transparent-black RT layer would premultiply over black
  # and darken to muddy grey (Theme.current.drag_ghost is opaque, so this holds).
  #
  # Its label is the payload's display_text - which can be longer than the source's own text - drawn at the font scale
  # the source shows its text at (DragManager passes its first Text's), centred, and always wholly inside: the ghost
  # is the source + 12, widened and heightened to the label + LABEL_PADDING around it where the label needs more.
  class GhostWidget < Widget
    include PrimitiveBuilder

    # Border = the themed fill darkened; 0.3 -> 70% HSV value (Color#darken(a) scales value by 1-a).
    BORDER_DARKEN = 0.3

    # Room around the label, each side
    LABEL_PADDING = 6.0

    getter size : Size
    @display_text : String?
    @label_size : Size # the label's box: its measured width x its block's ink extent

    # Measured once: the ghost keeps its size and its label's place for the whole drag.
    def initialize(source : Size, @display_text : String?, @font_scale : Int32)
      super(id: nil)
      font_size = FontSizing.calculate_size(@font_scale)
      @label_size = if text = @display_text
                      Size.new(Widget.measure_text(text, font_size).width, TextLines.block_extent(TextLines.count(text), font_size))
                    else
                      Size.new(0.0, 0.0)
                    end
      @size = Size.new({source.width + 12.0, @label_size.width + 2 * LABEL_PADDING}.max,
        {source.height + 12.0, @label_size.height + 2 * LABEL_PADDING}.max)
    end

    # Re-rendered every frame (the drag position drives it, not the reactive system) — same as
    # SimpleGhostWidget and the "drag ghost" Never category documented in Widget#primitives_version.
    def cache_policy : CachePolicy
      CachePolicy::Never
    end

    def measure(constraints : BoxConstraints) : Size
      @size
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, @size)
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      fill = Theme.current.drag_ghost
      primitives do
        # Opaque themed fill — see-through is the layer's job (GHOST_OPACITY), not the fill alpha
        fill_background(bounds, fill)

        # Border: a darker shade of the same themed fill
        draw_rect(Rect.new(0, 0, bounds.width, bounds.height), fill.darken(BORDER_DARKEN), 2.0)

        # The label, centred (themed so it stays readable on the themed fill)
        if text = @display_text
          at = Vec2.new((bounds.width - @label_size.width) / 2.0, (bounds.height - @label_size.height) / 2.0)
          draw_text(text, at, Theme.current.text_default, @font_scale)
        end
      end
    end
  end

  # Simple ghost widget: themed fill only (no border, no text)
  # Use via create_ghost_preview for widgets that handle their own visual feedback
  class SimpleGhostWidget < Widget
    include PrimitiveBuilder

    def cache_policy : CachePolicy
      CachePolicy::Never
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(constraints.max_width, constraints.max_height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        fill_background(bounds, Theme.current.drag_ghost)
      end
    end
  end

  # Coordinates drag-and-drop operations
  # Managed by App, similar to FocusManager
  class DragManager
    # perf-audit: nodes find_drop_target visits walking up from the hit test. Runs on every drag-move
    # (update_drop_target) - one hit test plus the hit's depth, not the whole tree. Bumped once per node.
    class_property drop_target_visits : Int32 = 0

    # Ghost layer configuration
    GHOST_Z_INDEX = 9999
    GHOST_OPACITY = 0.7_f32

    # Current drag state
    getter state : DragState = DragState.new

    # Ghost layer for preview (high z-index, renders on top)
    getter ghost_layer : Layer?

    # Highlight layer for drop zone feedback: composited with its target (Layer#composite_anchor), shown
    # while it has one
    getter highlight_layer : Layer?
    @highlight_widget : HighlightWidget?

    # Offset from cursor to ghost origin (for smooth dragging)
    @ghost_offset : Vec2 = Vec2.zero

    # Source widget bounds at drag start (for ghost sizing)
    @source_bounds : Rect?

    def initialize
    end

    # Check if drag is currently active
    def dragging? : Bool
      @state.active?
    end

    # Start tracking a potential drag - a fresh gesture, with no payload yet
    # Called on mouse_down over a Draggable widget
    def begin_drag_tracking(widget : Widget, position : Vec2)
      return unless widget.is_a?(Draggable)

      @state.phase = DragPhase::Pending
      @state.data = nil
      @state.source_widget = widget
      @state.start_position = position
      @state.current_position = position
    end

    # Update drag position and check threshold
    # Called on mouse_move during potential/active drag
    # Returns true if drag state changed (needs redraw)
    def update_drag(position : Vec2, root : Widget) : Bool
      return false if @state.phase == DragPhase::Idle

      @state.current_position = position

      case @state.phase
      when DragPhase::Pending
        # Check if threshold passed to start drag
        if @state.passed_threshold?(position)
          start_drag
          return true
        end
        false

      when DragPhase::Active
        # Update ghost position
        update_ghost_position(position)

        # Hit test for drop targets
        update_drop_target(position, root)

        true
      else
        false
      end
    end

    # Complete the drag operation
    # Called on mouse_up
    # Returns true if a drag was active (regardless of drop success)
    def end_drag(position : Vec2) : Bool
      return false unless @state.active?

      # Attempt drop if over valid target
      dropped = false
      begin
        if target = @state.current_target
          if target.is_a?(DropTarget) && (data = @state.data)
            if target.accepts_drop?(data)
              target.on_drop(data, target.to_content(position)) # its own space, as a mouse handler's point
              dropped = true
            end
          end
        end
      ensure
        # A target may REFUSE by raising in on_drop (embrace does, for a move it cannot make). The drag is
        # over all the same: the source hears it ended, undropped, and the state and ghost are cleared -
        # else the drag outlived the refusal and the next one could not start.
        begin
          if source = @state.source_widget
            if source.is_a?(Draggable) && (data = @state.data)
              source.on_drag_end(data, dropped)
            end
          end
        ensure
          cleanup
        end
      end
      true
    end

    # Cancel drag without dropping (e.g., Escape key)
    def cancel_drag
      return unless @state.active? || @state.pending?

      # on_drag_end pairs with on_drag_start: a pending drag never announced itself, even when a rebuild
      # gave it a payload.
      if @state.active? && (source = @state.source_widget)
        if source.is_a?(Draggable) && (data = @state.data)
          source.on_drag_end(data, dropped: false)
        end
      end

      cleanup
    end

    # Drag `source` onto `target` in one go - the test Driver's drag by id (src/testing/driver.cr)
    # - through the machinery a mouse drag uses: start (the payload, on_drag_start, ghost),
    # enter the target, then end_drag (drop, on_drag_end, cleanup's leave). `position` is where the
    # drop lands, in window space. Returns nil when the drop landed, else why it did not: a refused
    # target is never entered, so it never receives on_drop, and the source still hears
    # dropped: false. No hit test and no threshold - those stay the mouse path's (and its specs').
    def drag_onto(source : Widget, target : Widget, position : Vec2) : String?
      # A press that already began tracking this source (the Driver presses as App does) is continued.
      unless @state.pending? && @state.source_widget.same?(source)
        raise "drag_onto while a drag is in progress" unless @state.phase.idle?
        begin_drag_tracking(source, position)
      end
      start_drag
      return "#{describe(source)} gave no drag data" unless @state.active?
      data = @state.data.not_nil!
      reason = drop_refusal(target, source, data)
      retarget(reason ? nil : target, data)
      end_drag(position)
      reason
    end

    # Why `target` would refuse `data` dragged from `source`, or nil if it would take it. The same
    # two questions find_drop_target asks, asked of one target: nothing on its way up the tree may
    # prune it (a closed panel, a hidden widget, the source itself), and the target must accept.
    def drop_refusal(target : Widget, source : Widget, data : DragData) : String?
      node : Widget? = target
      while node
        if reason = prune_reason(node, source)
          return "#{describe(node)} #{reason}"
        end
        node = node.parent
      end
      if reason = accept_reason(target, data)
        "#{describe(target)} #{reason} #{data.data_type}"
      end
    end

    # What the tracked gesture drags: the payload taken at the first rebuild while it was pending, else what
    # the source offers now. The test Driver reads it too, to check what a drag would carry.
    def payload : DragData?
      return @state.data if @state.data
      source = @state.source_widget
      source.get_drag_data if source.is_a?(Draggable)
    end

    # The widgets a drag in progress holds - what App#rebuild must hand on to their replacements.
    def held_widgets : Array(Widget)
      return [] of Widget if @state.phase.idle?
      [@state.source_widget, @state.current_target, @state.data.as?(WidgetDragData).try(&.widget)].compact
    end

    # A rebuild replaced the tree: the drag's widgets are handed to their replacements (`resolve`: the widget
    # that is this one now, or nil if it is gone). The payload is the GESTURE's - a pending drag takes it at
    # the first rebuild, from the source it was pressed on, before that instance can be let go (a source that
    # offers nothing ends the drag). A source the rebuild REMOVED ends the drag cleanly - ghost, highlight,
    # the target's leave - and hears no on_drag_end (it is gone). Otherwise the replacement of an active
    # drag's source hears on_drag_start (it is the source now), a replaced target hears on_drag_enter and is
    # hovered (it is the target now), and a removed target's highlight is hidden; a replaced or removed target
    # is hovered no more. A widget the rebuild kept (a memoized root) hears nothing new.
    def rebind(& : Widget -> Widget?) : Nil
      return if @state.phase.idle?
      old_source, old_target = @state.source_widget, @state.current_target
      if @state.pending?
        return @state.reset unless @state.data ||= payload
      end
      @state.update_widget_references { |w| yield w }
      if old_target.is_a?(DropTarget) && !@state.current_target.same?(old_target)
        old_target.as(DropTarget).drag_hover = false
      end
      return cleanup unless source = @state.source_widget
      return unless @state.active? && (data = @state.data)
      source.on_drag_start(data) if source.is_a?(Draggable) && !source.same?(old_source)
      target = @state.current_target
      if target.nil?
        hide_highlight_layer if old_target
      elsif target.is_a?(DropTarget) && !target.same?(old_target)
        dt = target.as(DropTarget)
        dt.drag_hover = true
        dt.on_drag_enter(data)
        place_highlight(target)
      end
    end

    # The drop target a drag of `data` from `source` over `position` reaches - the search a drag runs on
    # every move and once a frame. The test Driver asks it before dropping on a grid cell.
    def drop_target_at(root : Widget, position : Vec2, source : Widget, data : DragData) : Widget?
      find_drop_target(position, root, source, data)
    end

    # --- Private Methods ---

    private def start_drag
      source = @state.source_widget
      return unless source
      return unless source.is_a?(Draggable)

      draggable = source.as(Draggable)

      data = payload
      if data.nil?
        # Drag cancelled by source
        @state.reset
        return
      end

      @state.data = data
      @state.phase = DragPhase::Active

      # Notify the source BEFORE sizing the ghost: a source that did not see the press (a rebuild replaced
      # it) learns here what it drags, and its drag_ghost_bounds must already say so.
      draggable.on_drag_start(data)

      # Store source bounds for ghost sizing (use custom drag bounds if provided)
      # Window space throughout: `drag_ghost_bounds` already converts (VirtualMatrix
      # answers where its drag box is painted), and `viewport_bounds` converts for everyone else.
      @source_bounds = if source.is_a?(Draggable)
        source.as(Draggable).drag_ghost_bounds || source.viewport_bounds
      else
        source.viewport_bounds
      end

      # Calculate ghost offset (cursor position relative to widget origin)
      if bounds = @source_bounds
        @ghost_offset = Vec2.new(
          @state.start_position.x - bounds.x,
          @state.start_position.y - bounds.y
        )
      end

      # Create ghost layer
      create_ghost_layer(source)
    end

    private def create_ghost_layer(source : Widget)
      bounds = @source_bounds
      # Nothing painted, no ghost: a source whose drag box shows nothing (a matrix's committed source
      # scrolled wholly out) says so with an empty rect.
      return unless bounds && bounds.width > 0 && bounds.height > 0

      # Calculate initial ghost position
      ghost_x = @state.current_position.x - @ghost_offset.x
      ghost_y = @state.current_position.y - @ghost_offset.y

      # Check if source provides a custom ghost preview
      custom_preview = if source.is_a?(Draggable)
        source.as(Draggable).create_ghost_preview
      end

      # A custom preview takes the source's size; the default ghost answers its own (room for its label), labelling
      # itself as the source shows its text
      ghost_widget, ghost_size = if custom_preview
                                   {custom_preview, bounds.size}
                                 else
                                   scale = source.find_all(&.is_a?(Text)).first?.try(&.as(Text).font_scale) || 0
                                   ghost = GhostWidget.new(bounds.size, @state.data.try(&.display_text).presence, scale)
                                   {ghost, ghost.size}
                                 end

      # Create overlay layer for ghost (transparent background)
      layer = Layer.new(
        "drag_ghost",
        Rect.new(Vec2.new(ghost_x, ghost_y), ghost_size),
        z_index: GHOST_Z_INDEX,
        background_color: Color.new(0, 0, 0, 0)
      )
      layer.opacity = GHOST_OPACITY

      ghost_widget.perform_layout(
        BoxConstraints.tight(ghost_size),
        Vec2.new(ghost_x, ghost_y)
      )

      layer.widgets << ghost_widget
      layer.mark_needs_full_render

      @ghost_layer = layer
    end

    # Show the highlight over `target`, in `color`, over `visible` - the part of it that shows. The layer is
    # composited WITH the target (Layer#composite_anchor), so what covers the target covers it too. One layer
    # per drag, re-placed; every re-place repaints it in full (one widget), so a grow within its buffer or a
    # new colour never leaves old pixels.
    private def show_highlight(target : Widget, visible : Rect, color : Color, opacity : Float64) : Nil
      widget = @highlight_widget ||= HighlightWidget.new(visible.width, visible.height, color)
      layer = @highlight_layer ||= Layer.new("drop_highlight", visible).tap { |l| l.widgets << widget }
      layer.bounds = visible
      layer.opacity = opacity
      layer.composite_anchor = target
      widget.update(visible.width, visible.height, color)
      widget.perform_layout(BoxConstraints.tight(visible.size), visible.position)
      layer.mark_needs_clear_and_render
    end

    # A highlight without a target is composited nowhere. Letting go of the target also lets go of the
    # widget generation it belongs to.
    private def hide_highlight_layer
      @highlight_layer.try(&.composite_anchor = nil)
    end

    private def update_ghost_position(position : Vec2)
      layer = @ghost_layer
      return unless layer

      # Update ghost position (O(1) - only bounds change, no re-render)
      ghost_x = position.x - @ghost_offset.x
      ghost_y = position.y - @ghost_offset.y

      layer.bounds = Rect.new(
        ghost_x,
        ghost_y,
        layer.bounds.width,
        layer.bounds.height
      )

      # Also update ghost widget bounds (needed for correct absolute_bounds calculation)
      if ghost_widget = layer.widgets.first?
        ghost_widget.bounds = Rect.new(
          ghost_x,
          ghost_y,
          ghost_widget.bounds.width,
          ghost_widget.bounds.height
        )
      end
    end

    private def update_drop_target(position : Vec2, root : Widget)
      data = @state.data
      return unless data

      # Find widget under cursor that accepts this drop
      new_target = find_drop_target(position, root, @state.source_widget, data)
      if new_target != @state.current_target
        retarget(new_target, data)
      elsif new_target && new_target.is_a?(DropTarget)
        # Same target: where the pointer is over it - and where it is now (it may have moved or scrolled)
        new_target.as(DropTarget).on_drag_over(data, new_target.to_content(position))
        place_highlight(new_target)
      end
    end

    # The pointer is at `position` - a move, the release, or (once a frame) still while the tree moved
    # under it (a scroll, a re-layout): the drop target, its highlight and on_drag_over follow what is under
    # it now. Only while a drag is active.
    def follow_pointer(position : Vec2, root : Widget) : Nil
      return unless @state.active?
      @state.current_position = position
      update_drop_target(position, root)
    end

    # The one placement rule for a target's highlight: shown over the part of the target that shows now,
    # in its colour, if it wants one (highlight_opacity > 0) and any of it shows; else hidden. Re-placed only
    # when one of those changed.
    private def place_highlight(target : Widget) : Nil
      dt = target.as(DropTarget)
      opacity = dt.highlight_opacity
      return hide_highlight_layer unless opacity > 0.0 && (visible = target.visible_bounds)
      color = dt.highlight_color
      layer, widget = @highlight_layer, @highlight_widget
      return if layer && widget && layer.composite_anchor.same?(target) && layer.bounds == visible &&
                layer.opacity == opacity && widget.color == color
      show_highlight(target, visible, color, opacity)
    end

    # Move the drag onto `new_target` (nil: onto nothing): leave the old target, enter the new one,
    # move the highlight. The one owner of those hooks - a mouse drag reaches it through
    # update_drop_target, drag_onto directly.
    private def retarget(new_target : Widget?, data : DragData) : Nil
      old_target = @state.current_target
      return if new_target == old_target

      # Leave old target
      if old_target && old_target.is_a?(DropTarget)
        dt = old_target.as(DropTarget)
        dt.drag_hover = false
        dt.on_drag_leave(data)
      end

      # Enter new target
      if new_target && new_target.is_a?(DropTarget)
        dt = new_target.as(DropTarget)
        dt.drag_hover = true
        dt.on_drag_enter(data)
        place_highlight(new_target)
      else
        hide_highlight_layer # onto nothing - a gap between drop zones
      end

      @state.current_target = new_target
    end

    # The drop target under `position`: where a click there would land - the hit test, so z order,
    # popups, scrollbars and click-through all hold - then up its ancestors to the first DropTarget
    # that takes `data`. A closed or hidden node on the way means no target at all - a click there
    # would reach nothing; the drag source hides what lies inside it, unless it is itself a DropTarget
    # (a grid's drag within itself).
    # The hit test is not a pure read (a panel keeps its last hit point) - harmless here, per move and
    # per frame alike: the last hit point is read only by a click (the mouse-up that ends a drag skips
    # click processing).
    private def find_drop_target(position : Vec2, root : Widget, source : Widget?, data : DragData) : Widget?
      target = nil
      node = root.hit_test(position)
      while node
        DragManager.drop_target_visits += 1 # perf-audit: bump once per node visited
        if prune_reason(node, source)
          return nil unless node == source
          target = nil # inside the source: not a place to drop it
        elsif target.nil? && accept_reason(node, data).nil?
          target = node
        end
        node = node.parent
      end
      target
    end

    # Why `widget` and everything inside it are out of the drop search, or nil. The source is
    # skipped unless it is itself a DropTarget (self-drop, e.g. a VirtualMatrix cell drag within the
    # same grid).
    private def prune_reason(widget : Widget, source : Widget?) : String?
      return "is the drag source" if widget == source && !widget.is_a?(DropTarget)
      return "is closed" if widget.responds_to?(:closed?) && widget.closed?
      return "is not shown" if widget.skip_render?
      nil
    end

    # Why `widget` itself would not take `data`, or nil if it would. Asked per node while a drag
    # moves, so the answers are fixed strings; drop_refusal adds the detail.
    private def accept_reason(widget : Widget, data : DragData) : String?
      return "is not a drop target" unless widget.is_a?(DropTarget)
      return "does not accept" unless widget.as(DropTarget).accepts_drop?(data)
      nil
    end

    private def describe(widget : Widget) : String
      widget.id ? "\"#{widget.id}\"" : "a #{widget.class.name}"
    end

    private def cleanup
      # Clear target highlight
      if target = @state.current_target
        if target.is_a?(DropTarget) && (data = @state.data)
          dt = target.as(DropTarget)
          dt.drag_hover = false
          dt.on_drag_leave(data)
        end
      end
      # The drag's two layers are its own - ownerless, their widgets in no tree - so released here, entirely
      @highlight_layer.try(&.release(nil))
      @ghost_layer.try(&.release(nil))
      @highlight_layer = nil
      @highlight_widget = nil
      @ghost_layer = nil
      @ghost_offset = Vec2.zero
      @source_bounds = nil

      # Reset state
      @state.reset
    end
  end
end
