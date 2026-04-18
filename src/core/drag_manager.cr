require "./drag_types"
require "./draggable"
require "./drop_target"
require "./layer"
require "../dsl/primitive_builder"
require "../widgets/highlight_widget"

module CrymbleUI
  # Simple ghost preview widget that renders a semi-transparent rectangle
  # representing the dragged item
  class GhostWidget < Widget
    include PrimitiveBuilder

    GHOST_BACKGROUND = Color.new(100, 150, 200, 180)
    GHOST_BORDER = Color.new(50, 100, 150, 255)

    @width : Float64
    @height : Float64
    @display_text : String?

    def initialize(@width : Float64, @height : Float64, @display_text : String? = nil)
      super(id: nil)
    end

    def measure(constraints : BoxConstraints) : Size
      Size.new(@width, @height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, Size.new(@width, @height))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        # Semi-transparent background
        fill_rect(Rect.new(0, 0, bounds.width, bounds.height), GHOST_BACKGROUND)

        # Border
        draw_rect(Rect.new(0, 0, bounds.width, bounds.height), GHOST_BORDER, 2.0)

        # Display text if provided
        if text = @display_text
          draw_text(text, Vec2.new(5, 5), Color.new(0, 0, 0, 255), 0)
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
        fill_rect(Rect.new(0, 0, bounds.width, bounds.height), Theme.current.drag_ghost)
      end
    end
  end

  # Coordinates drag-and-drop operations
  # Managed by App, similar to FocusManager
  class DragManager
    # Ghost layer configuration
    GHOST_Z_INDEX = 9999
    GHOST_OPACITY = 0.7_f32

    # Highlight layer configuration
    HIGHLIGHT_Z_INDEX = 1000  # Above content (0), below ghost (9999)
    # Drag highlight defaults (dynamic - must follow theme changes)

    # Current drag state
    getter state : DragState = DragState.new

    # Ghost layer for preview (high z-index, renders on top)
    getter ghost_layer : Layer?

    # Highlight layer for drop zone feedback
    getter highlight_layer : Layer?

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

    # Start tracking a potential drag
    # Called on mouse_down over a Draggable widget
    def begin_drag_tracking(widget : Widget, position : Vec2)
      return unless widget.is_a?(Draggable)

      @state.phase = DragPhase::Pending
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
      if target = @state.current_target
        if target.is_a?(DropTarget) && (data = @state.data)
          if target.accepts_drop?(data)
            target.on_drop(data, position)
            dropped = true
          end
        end
      end

      # Notify source widget
      if source = @state.source_widget
        if source.is_a?(Draggable) && (data = @state.data)
          source.on_drag_end(data, dropped)
        end
      end

      # Clean up
      cleanup
      true
    end

    # Cancel drag without dropping (e.g., Escape key)
    def cancel_drag
      return unless @state.active? || @state.pending?

      if source = @state.source_widget
        if source.is_a?(Draggable) && (data = @state.data)
          source.on_drag_end(data, dropped: false)
        end
      end

      cleanup
    end

    # --- Private Methods ---

    private def start_drag
      source = @state.source_widget
      return unless source
      return unless source.is_a?(Draggable)

      draggable = source.as(Draggable)

      # Get drag data from source
      data = draggable.get_drag_data
      if data.nil?
        # Drag cancelled by source
        @state.reset
        return
      end

      @state.data = data
      @state.phase = DragPhase::Active

      # Store source bounds for ghost sizing (use custom drag bounds if provided)
      @source_bounds = if source.is_a?(Draggable)
        source.as(Draggable).drag_ghost_bounds || source.absolute_bounds
      else
        source.absolute_bounds
      end

      # Calculate ghost offset (cursor position relative to widget origin)
      if bounds = @source_bounds
        @ghost_offset = Vec2.new(
          @state.start_position.x - bounds.x,
          @state.start_position.y - bounds.y
        )
      end

      # Notify source
      draggable.on_drag_start(data)

      # Create ghost layer
      create_ghost_layer(source)
    end

    private def create_ghost_layer(source : Widget)
      bounds = @source_bounds
      return unless bounds

      # Calculate initial ghost position
      ghost_x = @state.current_position.x - @ghost_offset.x
      ghost_y = @state.current_position.y - @ghost_offset.y

      # Check if source provides a custom ghost preview
      custom_preview = if source.is_a?(Draggable)
        source.as(Draggable).create_ghost_preview
      end

      if custom_preview
        ghost_w = bounds.width
        ghost_h = bounds.height
      else
        # Default ghost has extra padding for text
        ghost_w = bounds.width + 12.0
        ghost_h = bounds.height + 12.0
      end

      # Create overlay layer for ghost (transparent background)
      layer = Layer.new(
        "drag_ghost",
        Rect.new(ghost_x, ghost_y, ghost_w, ghost_h),
        z_index: GHOST_Z_INDEX,
        background_color: Color.new(0, 0, 0, 0)
      )
      layer.opacity = GHOST_OPACITY

      # Use custom preview or default GhostWidget
      ghost_widget = custom_preview || GhostWidget.new(ghost_w, ghost_h, @state.data.try(&.display_text))
      ghost_widget.perform_layout(
        BoxConstraints.tight(Size.new(ghost_w, ghost_h)),
        Vec2.new(ghost_x, ghost_y)
      )

      layer.widgets << ghost_widget
      layer.mark_needs_full_render

      @ghost_layer = layer
    end

    private def create_highlight_layer(target : Widget)
      bounds = target.absolute_bounds

      # Get highlight color from target (if DropTarget) or use default
      color = if target.is_a?(DropTarget)
        target.as(DropTarget).highlight_color
      else
        Theme.current.drag_highlight
      end

      # Get highlight opacity from target (if DropTarget) or use default
      opacity = if target.is_a?(DropTarget)
        target.as(DropTarget).highlight_opacity
      else
        Theme.current.brightness_drag_opacity
      end

      layer = Layer.new(
        "drop_highlight",
        bounds,
        z_index: HIGHLIGHT_Z_INDEX,
        background_color: Color.new(0, 0, 0, 0)  # Transparent
      )
      layer.opacity = opacity

      # Simple widget that fills with highlight color
      # Position at world coordinates (like ghost widget) so layer_local calculation works
      highlight_widget = HighlightWidget.new(bounds.width, bounds.height, color)
      highlight_widget.perform_layout(
        BoxConstraints.tight(Size.new(bounds.width, bounds.height)),
        Vec2.new(bounds.x, bounds.y)
      )

      layer.widgets << highlight_widget
      layer.mark_needs_full_render

      @highlight_layer = layer
    end

    # Update existing highlight layer to match new target, or create one.
    # Reusing the same Layer object avoids changing object identity,
    # which would trigger expensive layer recollection in render_all_layers.
    private def update_or_create_highlight_layer(target : Widget)
      bounds = target.absolute_bounds
      color = if target.is_a?(DropTarget)
        target.as(DropTarget).highlight_color
      else
        Theme.current.drag_highlight
      end
      opacity = if target.is_a?(DropTarget)
        target.as(DropTarget).highlight_opacity
      else
        Theme.current.brightness_drag_opacity
      end

      if layer = @highlight_layer
        # Reuse existing layer — update bounds and widget
        layer.bounds = bounds
        layer.opacity = opacity
        if highlight_widget = layer.widgets.first?
          highlight_widget.as(HighlightWidget).update(bounds.width, bounds.height, color)
          highlight_widget.perform_layout(
            BoxConstraints.tight(Size.new(bounds.width, bounds.height)),
            Vec2.new(bounds.x, bounds.y)
          )
        end
        layer.mark_needs_full_render
      else
        # First highlight — create new layer
        create_highlight_layer(target)
      end
    end

    # Hide highlight layer without destroying it (preserves object identity for layer cache).
    # Used when target becomes nil (gap between drop zones) or has opacity=0.
    private def hide_highlight_layer
      if layer = @highlight_layer
        layer.bounds = Rect.new(-1000.0, -1000.0, 0.0, 0.0)
      end
    end

    # Destroy highlight layer (only used in cleanup after drag ends)
    private def destroy_highlight_layer
      @highlight_layer = nil
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
      new_target = find_drop_target(position, root, data)

      # Handle target change
      old_target = @state.current_target

      if new_target != old_target
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
          if dt.highlight_opacity > 0.0
            # Reuse existing highlight layer (avoids layer recollection from object identity change)
            update_or_create_highlight_layer(new_target)
          else
            hide_highlight_layer
          end
        else
          # Target is nil (mouse in gap between drop zones) — hide, don't destroy.
          # Destroying forces layer recollection when re-entering a drop zone.
          hide_highlight_layer
        end

        @state.current_target = new_target
      elsif new_target && new_target.is_a?(DropTarget)
        # Same target, call on_drag_over for position updates
        new_target.as(DropTarget).on_drag_over(data, position)
      end
    end

    private def find_drop_target(position : Vec2, widget : Widget, data : DragData) : Widget?
      # Skip the source widget — unless it's also a DropTarget (supports self-drop,
      # e.g., VirtualMatrix cell drag within same grid)
      if widget == @state.source_widget && !widget.is_a?(DropTarget)
        return nil
      end

      # Skip closed/hidden widgets
      return nil if widget.responds_to?(:closed?) && widget.closed?
      return nil if widget.skip_render?

      # Check children first (reverse order for z-ordering - last child is on top)
      widget.children.reverse_each do |child|
        if target = find_drop_target(position, child, data)
          return target
        end
      end

      # Check if this widget is a valid drop target
      if widget.is_a?(DropTarget)
        if widget.absolute_bounds.contains_point(position)
          if widget.as(DropTarget).accepts_drop?(data)
            return widget
          end
        end
      end

      nil
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
      destroy_highlight_layer

      # Clear ghost layer
      @ghost_layer = nil
      @ghost_offset = Vec2.zero
      @source_bounds = nil

      # Reset state
      @state.reset
    end
  end
end
