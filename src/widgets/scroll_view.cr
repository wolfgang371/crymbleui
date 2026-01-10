require "../core/widget"
require "../core/types"
require "../core/layer"
require "../dsl/primitive_builder"

module CrymbleUI
  enum ScrollDirection
    Vertical
    Horizontal
    Both
  end

  # Interaction states for scrollbar dragging
  enum ScrollbarInteractionMode
    Idle
    DraggingThumb
  end

  class ScrollView < Widget
    include PrimitiveBuilder

    property direction : ScrollDirection

    # Scroll state - all use reconcile macros for automatic copy_state_from
    layout_property scroll_offset : Vec2 = Vec2.zero, reconcile: true
    reconcile_property viewport_size : Size = Size.zero
    reconcile_property content_size : Size = Size.zero

    # Scrollbar interaction state (reconcile for drag state preservation)
    reconcile_property interaction_mode : ScrollbarInteractionMode = ScrollbarInteractionMode::Idle
    reconcile_property drag_start_offset : Vec2 = Vec2.zero  # Scroll offset when drag started
    reconcile_property drag_start_point : Vec2 = Vec2.zero   # Mouse position when drag started (absolute coords)
    @dragging_axis : Symbol? = nil         # Which axis is being dragged (:vertical or :horizontal)

    @internal_layer : Layer?
    @scrollbar_layer : Layer?  # Separate layer for scrollbars (non-viewport_cache overlay)
    @content_widget : Widget?
    @visible_widgets : Set(Widget) = Set(Widget).new  # Track which widgets are in viewport
    @last_visibility_offset : Vec2 = Vec2.new(-1.0, -1.0)  # Last offset where visibility was updated (for dedup)

    # Resize state - captured at ancestor resize start, used during resize move
    # Avoids cumulative delta error by using original bounds + current delta
    @resize_start_content_bounds : Rect?
    @resize_start_scrollbar_bounds : Rect?

    def initialize(@direction = ScrollDirection::Vertical, id : String? = nil)
      super(id: id)
    end

    # Get z_index from parent layer (for proper z-ordering when inside Popup/etc.)
    # Returns 0 if no parent layer found
    private def parent_layer_z_index : Int32
      widget = self.parent
      while widget
        if widget.responds_to?(:layer)
          if layer = widget.layer
            return layer.z_index
          end
        end
        widget = widget.parent
      end
      0
    end

    def layer : Layer?
      @internal_layer
    end


    # Content layer (viewport_cache for efficient scrolling)
    def content_layer : Layer?
      @internal_layer
    end

    # Scrollbar layer (non-viewport_cache overlay)
    def scrollbar_layer : Layer?
      @scrollbar_layer
    end

    # Update layer z-indices when parent panel's z-index changes
    # Called by WindowPanel.bring_to_front() to fix scrollbar bleeding
    def update_layer_z_indices(parent_z : Int32)
      @internal_layer.try { |l| l.z_index = parent_z + 1 }
      @scrollbar_layer.try { |l| l.z_index = parent_z + 2 }
    end

    # Mark both layers as needing full render
    # Called by WindowPanel.bring_to_front() to fix blank content on click
    def mark_layers_need_render
      @internal_layer.try(&.mark_needs_layout)
      @scrollbar_layer.try(&.mark_needs_layout)
    end

    # Update layer positions during panel drag (called by WindowPanel during drag)
    # This is O(1) - just translates layer bounds, no size change, no re-render needed
    def update_layer_position_for_drag(delta : Vec2)
      # Update content layer position
      if layer = @internal_layer
        layer.bounds = Rect.new(
          layer.bounds.x + delta.x,
          layer.bounds.y + delta.y,
          layer.bounds.width,
          layer.bounds.height
        )
        # NO mark_needs_render - content unchanged, just position
      end

      # Update scrollbar layer position
      if sb_layer = @scrollbar_layer
        sb_layer.bounds = Rect.new(
          sb_layer.bounds.x + delta.x,
          sb_layer.bounds.y + delta.y,
          sb_layer.bounds.width,
          sb_layer.bounds.height
        )
        # NO mark_needs_render - scrollbar unchanged, just position
      end
    end

    # Update layer bounds during panel resize (called by WindowPanel during resize)
    # Uses ORIGINAL bounds + delta (not current + delta) to avoid cumulative error
    # Original bounds captured at resize start by WindowPanel
    #
    # IMPORTANT: Only SHRINK bounds (delta < 0), never EXPAND beyond original!
    # Reason: cache_extent pre-renders content beyond viewport. Expanding bounds
    # would show this pre-rendered content outside the panel border.
    def update_layer_bounds_for_resize(orig_content : Rect, orig_scrollbar : Rect, dw : Float64, dh : Float64)
      # Clamp deltas to not expand beyond original (only allow shrinking)
      clamped_dw = dw < 0 ? dw : 0.0
      clamped_dh = dh < 0 ? dh : 0.0

      if layer = @internal_layer
        layer.bounds = Rect.new(
          orig_content.x,
          orig_content.y,
          orig_content.width + clamped_dw,
          orig_content.height + clamped_dh
        )
      end

      if sb_layer = @scrollbar_layer
        sb_layer.bounds = Rect.new(
          orig_scrollbar.x,
          orig_scrollbar.y,
          orig_scrollbar.width + clamped_dw,
          orig_scrollbar.height + clamped_dh
        )
      end
    end

    # === LAYER OWNER NOTIFICATION HANDLERS ===
    # Respond to ancestor (WindowPanel) position/size/z-index changes.
    # This decouples WindowPanel from ScrollView-specific knowledge.

    def on_ancestor_position_changed(delta : Vec2)
      update_layer_position_for_drag(delta)
    end

    def on_ancestor_resize_start
      # Capture original bounds for delta calculation
      @resize_start_content_bounds = @internal_layer.try(&.bounds.dup)
      @resize_start_scrollbar_bounds = @scrollbar_layer.try(&.bounds.dup)
    end

    def on_ancestor_resize_move(dw : Float64, dh : Float64)
      orig_content = @resize_start_content_bounds
      orig_scrollbar = @resize_start_scrollbar_bounds
      return unless orig_content && orig_scrollbar

      update_layer_bounds_for_resize(orig_content, orig_scrollbar, dw, dh)
    end

    def on_ancestor_resize_end
      @resize_start_content_bounds = nil
      @resize_start_scrollbar_bounds = nil
    end

    def on_ancestor_z_index_changed(base_z : Int32)
      update_layer_z_indices(base_z)
      mark_layers_need_render
    end

    # Count of widgets currently visible in viewport
    def visible_widget_count : Int32
      @visible_widgets.size
    end

    def set_content(widget : Widget)
      @content_widget = widget
      widget.parent = self
      # Only add to children if not already there (DSL may have already added it)
      @children << widget unless @children.includes?(widget)
      mark_needs_layout
    end

    def measure(constraints : BoxConstraints) : Size
      # Fill available space if constraints are finite
      # Use reasonable default if constraints are infinite
      width = constraints.max_width.finite? ? constraints.max_width : 200.0
      height = constraints.max_height.finite? ? constraints.max_height : 200.0
      Size.new(width, height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      # Viewport size matches what we reported in measure()
      measured = measure(constraints)
      @viewport_size = measured
      @bounds = Rect.new(position, @viewport_size)

      # Measure content first to determine if scrollbars are needed
      if content = @content_widget
        # Direction-aware constraints: constrain the non-scrolling axis (TIGHT)
        # For vertical scroll: width TIGHT (items fill width), height infinite
        # For horizontal scroll: height TIGHT (items fill height), width infinite
        content_constraints = case @direction
        when ScrollDirection::Vertical
          # Reserve space for scrollbar, make width TIGHT so VStack fills it
          content_width = @viewport_size.width - SCROLLBAR_WIDTH
          BoxConstraints.new(
            min_width: content_width, max_width: content_width,  # TIGHT
            min_height: 0.0, max_height: Float64::INFINITY
          )
        when ScrollDirection::Horizontal
          # Reserve space for scrollbar, make height TIGHT so content fills it
          content_height = @viewport_size.height - SCROLLBAR_WIDTH
          BoxConstraints.new(
            min_width: 0.0, max_width: Float64::INFINITY,
            min_height: content_height, max_height: content_height  # TIGHT
          )
        else  # Both directions - both infinite
          BoxConstraints.loose(Size.new(Float64::INFINITY, Float64::INFINITY))
        end
        old_content_size = @content_size
        @content_size = content.measure(content_constraints)

        # Mark scrollbar layer for FULL re-render if content size changed
        # Must use mark_needs_layout (not mark_needs_render) to trigger buffer clear
        # Otherwise old scrollbar pixels remain when scrollbar becomes unnecessary
        # ALSO invalidate widget's primitive cache to force to_primitives regeneration
        if old_content_size != @content_size
          @state = WidgetState::NeedsRender if @state == WidgetState::Clean
          invalidate_primitive_cache
          if sbl = @scrollbar_layer
            sbl.mark_needs_layout
          end
        end
      end

      # Calculate effective viewport (content area excluding scrollbars)
      # Scrollbars render on top via to_primitives, so layer must not overlap them
      effective_width = @viewport_size.width
      effective_height = @viewport_size.height

      if needs_vertical_scrollbar?
        effective_width -= SCROLLBAR_WIDTH
      end
      if needs_horizontal_scrollbar?
        effective_height -= SCROLLBAR_WIDTH
      end

      # Create/update layer with effective bounds (excludes scrollbar area)
      effective_bounds = Rect.new(
        absolute_bounds.x,
        absolute_bounds.y,
        effective_width,
        effective_height
      )

      # Use parent's z_index as base to ensure proper layering inside popups/etc.
      base_z = parent_layer_z_index
      @internal_layer ||= Layer.new(
        "scrollview_#{id}",
        effective_bounds,
        z_index: base_z + 1,
        background_color: Color.new(0, 0, 0, 0),  # Transparent
        owner_widget: self
      )
      layer = @internal_layer.not_nil!
      layer.bounds = effective_bounds
      layer.z_index = base_z + 1  # Update z_index each layout (parent may have changed)
      layer.viewport_cache = true  # Enable viewport_cache buffer for efficient scrolling
      layer.cache_extent = 100.0  # Pre-render 100px margin around viewport for smooth scrolling
      layer.scroll_offset = @scroll_offset  # Sync layer scroll offset

      # Create separate scrollbar layer (non-viewport_cache overlay)
      # This layer sits above content and doesn't scroll with it
      scrollbar_bounds = Rect.new(
        absolute_bounds.x,
        absolute_bounds.y,
        @viewport_size.width,
        @viewport_size.height
      )
      @scrollbar_layer ||= Layer.new(
        "scrollbar_#{id}",
        scrollbar_bounds,
        z_index: base_z + 2,  # Above content layer
        background_color: Color.new(0, 0, 0, 0),  # Transparent
        owner_widget: self
      )
      @scrollbar_layer.not_nil!.bounds = scrollbar_bounds
      @scrollbar_layer.not_nil!.z_index = base_z + 2  # Update z_index each layout
      @scrollbar_layer.not_nil!.viewport_cache = false  # Scrollbars are fixed, not viewport_cache
      @scrollbar_layer.not_nil!.cache_extent = 0.0  # No extra buffer space for scrollbar layer

      # Layout content child
      if content = @content_widget
        # Clamp scroll offset to valid range after viewport/content size changes
        # This handles viewport resize (e.g., window enlarged while at bottom)
        clamp_scroll_offset

        # VIEWPORT_CACHE: Layout content at (0,0) in content-local coordinates
        # Scroll offset is handled by the layer, NOT by widget positions
        # This enables O(1) scrolling without re-layout
        content_position = Vec2.new(0.0, 0.0)
        content.layout(
          BoxConstraints.tight(@content_size),
          content_position
        )

        # Sync layer scroll_offset with widget scroll_offset
        layer.scroll_offset = @scroll_offset

        # Register content to layer for rendering
        @internal_layer.not_nil!.widgets.clear
        @internal_layer.not_nil!.widgets << content

        # Register self to scrollbar layer for scrollbar chrome rendering
        # (Widget-with-Chrome Pattern - LAYER_RENDERING_ARCHITECTURE.md lines 1416-1424)
        @scrollbar_layer.not_nil!.widgets.clear
        @scrollbar_layer.not_nil!.widgets << self

        # Update visibility tracking
        update_visibility_tracking(content)
      end
    end

    # Constants for scrollbar rendering
    SCROLLBAR_WIDTH = 16.0
    ARROW_SIZE = 16.0
    THUMB_MIN_SIZE = 30.0

    private def needs_vertical_scrollbar? : Bool
      @content_size.height > @viewport_size.height
    end

    private def needs_horizontal_scrollbar? : Bool
      @content_size.width > @viewport_size.width
    end

    # Effective viewport dimensions (excluding scrollbar space when scrollbars are visible)
    private def effective_viewport_width : Float64
      needs_vertical_scrollbar? ? @viewport_size.width - SCROLLBAR_WIDTH : @viewport_size.width
    end

    private def effective_viewport_height : Float64
      needs_horizontal_scrollbar? ? @viewport_size.height - SCROLLBAR_WIDTH : @viewport_size.height
    end

    # Maximum scroll offsets (content size minus effective viewport)
    private def max_scroll_x : Float64
      ((@content_size.width - effective_viewport_width).clamp(0.0, Float64::MAX))
    end

    private def max_scroll_y : Float64
      ((@content_size.height - effective_viewport_height).clamp(0.0, Float64::MAX))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      prims = [] of DrawPrimitive

      # When both scrollbars are visible, we need to leave a corner gap
      # to avoid arrow overlap at bottom-right
      both_visible = needs_vertical_scrollbar? && needs_horizontal_scrollbar?

      # Render vertical scrollbar if needed
      if needs_vertical_scrollbar?
        # If horizontal scrollbar also visible, shorten vertical track to leave corner
        track_height = both_visible ? bounds.height - SCROLLBAR_WIDTH : bounds.height

        track_rect = Rect.new(
          bounds.width - SCROLLBAR_WIDTH,
          0.0,
          SCROLLBAR_WIDTH,
          track_height
        )

        # Calculate thumb size and position
        thumb_height = calculate_vertical_thumb_height
        thumb_y = calculate_vertical_thumb_y.clamp(0.0, track_rect.height - thumb_height)

        thumb_rect = Rect.new(track_rect.x, thumb_y, SCROLLBAR_WIDTH, thumb_height)

        # Arrow geometry for vertical scrollbar
        arrow_color = Color.new(100, 100, 100, 255)
        arrow_margin = 4.0
        arrow_cx = track_rect.x + SCROLLBAR_WIDTH / 2.0

        # Up arrow (pointing up)
        up_top = arrow_margin
        up_bottom = ARROW_SIZE - arrow_margin
        up_left = track_rect.x + arrow_margin
        up_right = track_rect.x + SCROLLBAR_WIDTH - arrow_margin

        # Down arrow (pointing down) - position relative to track_rect.height (not bounds.height)
        down_top = track_rect.height - ARROW_SIZE + arrow_margin
        down_bottom = track_rect.height - arrow_margin
        down_left = track_rect.x + arrow_margin
        down_right = track_rect.x + SCROLLBAR_WIDTH - arrow_margin

        prims += primitives do
          fill_rect(track_rect, Color.new(220, 220, 220, 255))  # Light gray track
          fill_rect(thumb_rect, Color.new(150, 150, 150, 255))  # Darker gray thumb
          # Up arrow triangle (point at top)
          fill_triangle(
            Vec2.new(arrow_cx, up_top),           # Top center
            Vec2.new(up_left, up_bottom),         # Bottom left
            Vec2.new(up_right, up_bottom),        # Bottom right
            arrow_color
          )
          # Down arrow triangle (point at bottom)
          fill_triangle(
            Vec2.new(arrow_cx, down_bottom),      # Bottom center
            Vec2.new(down_left, down_top),        # Top left
            Vec2.new(down_right, down_top),       # Top right
            arrow_color
          )
        end
      end

      # Render horizontal scrollbar if needed
      if needs_horizontal_scrollbar?
        # If vertical scrollbar also visible, shorten horizontal track to leave corner
        track_width = both_visible ? bounds.width - SCROLLBAR_WIDTH : bounds.width

        track_rect = Rect.new(
          0.0,
          bounds.height - SCROLLBAR_WIDTH,
          track_width,
          SCROLLBAR_WIDTH
        )

        # Calculate thumb size and position
        thumb_width = calculate_horizontal_thumb_width
        thumb_x = calculate_horizontal_thumb_x.clamp(0.0, track_rect.width - thumb_width)

        thumb_rect = Rect.new(thumb_x, track_rect.y, thumb_width, SCROLLBAR_WIDTH)

        # Arrow geometry for horizontal scrollbar
        arrow_color = Color.new(100, 100, 100, 255)
        arrow_margin = 4.0
        arrow_cy = track_rect.y + SCROLLBAR_WIDTH / 2.0

        # Left arrow (pointing left)
        left_left = arrow_margin
        left_right = ARROW_SIZE - arrow_margin
        left_top = track_rect.y + arrow_margin
        left_bottom = track_rect.y + SCROLLBAR_WIDTH - arrow_margin

        # Right arrow (pointing right) - position relative to track_rect.width (not bounds.width)
        right_left = track_rect.width - ARROW_SIZE + arrow_margin
        right_right = track_rect.width - arrow_margin
        right_top = track_rect.y + arrow_margin
        right_bottom = track_rect.y + SCROLLBAR_WIDTH - arrow_margin

        prims += primitives do
          fill_rect(track_rect, Color.new(220, 220, 220, 255))  # Light gray track
          fill_rect(thumb_rect, Color.new(150, 150, 150, 255))  # Darker gray thumb
          # Left arrow triangle (point at left)
          fill_triangle(
            Vec2.new(left_left, arrow_cy),        # Left center
            Vec2.new(left_right, left_top),       # Top right
            Vec2.new(left_right, left_bottom),    # Bottom right
            arrow_color
          )
          # Right arrow triangle (point at right)
          fill_triangle(
            Vec2.new(right_right, arrow_cy),      # Right center
            Vec2.new(right_left, right_top),      # Top left
            Vec2.new(right_left, right_bottom),   # Bottom left
            arrow_color
          )
        end
      end

      prims
    end

    # Test helper: set scroll offset directly (for testing edge cases)
    def set_scroll_offset_for_test(offset : Vec2)
      @scroll_offset = offset
      mark_needs_layout  # Trigger re-layout so content position updates
      update_visibility_on_scroll  # Update visibility and re-detect hover
    end

    # No manual copy_state_from needed - all state uses reconcile macros:
    # - scroll_offset: layout_property (auto-reconcile + layout invalidation)
    # - viewport_size, content_size: reconcile_property (auto-reconcile, no invalidation)
    # - interaction_mode, drag_start_*: reconcile_property (auto-reconcile, no invalidation)

    # Mouse wheel scrolling
    SCROLL_WHEEL_SPEED = 20.0  # Pixels per wheel notch

    def on_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false)
      # Only handle scroll if point is within our bounds
      return unless absolute_bounds.contains_point(point)

      # Shift key swaps horizontal and vertical axes
      effective_delta = if shift
                          Vec2.new(delta.y, delta.x)  # Swap X and Y
                        else
                          delta
                        end

      # Update scroll offset based on direction
      # Each direction only responds to its matching axis
      case @direction
      when ScrollDirection::Vertical
        # Only responds to vertical scroll (effective_delta.y)
        # Horizontal touchpad swipes are ignored
        @scroll_offset = Vec2.new(@scroll_offset.x, @scroll_offset.y - effective_delta.y * SCROLL_WHEEL_SPEED)
      when ScrollDirection::Horizontal
        # Only responds to horizontal scroll (effective_delta.x)
        # Vertical touchpad swipes are ignored
        @scroll_offset = Vec2.new(@scroll_offset.x - effective_delta.x * SCROLL_WHEEL_SPEED, @scroll_offset.y)
      when ScrollDirection::Both
        # Responds to both axes independently
        @scroll_offset = Vec2.new(
          @scroll_offset.x - effective_delta.x * SCROLL_WHEEL_SPEED,
          @scroll_offset.y - effective_delta.y * SCROLL_WHEEL_SPEED
        )
      end

      # Clamp to valid range
      clamp_scroll_offset

      # VIEWPORT_CACHE: Update layer scroll_offset instead of triggering layout
      # Widget positions don't change, only the viewport offset changes
      if layer = @internal_layer
        layer.scroll_offset = @scroll_offset
      end

      # Update visibility and render only scrollbar (no layout needed!)
      update_visibility_on_scroll
      mark_scrollbar_needs_render
    end

    private def clamp_scroll_offset
      @scroll_offset = Vec2.new(
        @scroll_offset.x.clamp(0.0, max_scroll_x),
        @scroll_offset.y.clamp(0.0, max_scroll_y)
      )
    end

    # Mark self for re-render on scrollbar layer (for scrollbar primitives)
    # ScrollView is registered in @scrollbar_layer.widgets, so mark that layer dirty
    private def mark_scrollbar_needs_render
      @state = WidgetState::NeedsRender if @state == WidgetState::Clean
      if scrollbar_layer = @scrollbar_layer
        scrollbar_layer.mark_needs_render(self)
      end
    end

    # === SCROLL TO VISIBLE ===

    # Calculate widget bounds relative to content widget
    # For nested layouts (VStack → HStack → Button), we need to walk up
    # the parent chain accumulating offsets until we reach the content widget
    private def bounds_relative_to_content(widget : Widget) : Rect
      bounds = widget.bounds
      current = widget.parent

      while current && current != @content_widget
        # Accumulate parent's position offset
        parent_bounds = current.bounds
        bounds = Rect.new(
          bounds.x + parent_bounds.x,
          bounds.y + parent_bounds.y,
          bounds.width,
          bounds.height
        )
        current = current.parent
      end

      bounds
    end

    # Scroll to make a child widget visible in the viewport
    # Used for keyboard focus navigation to ensure focused widget is visible
    def scroll_to_visible(widget : Widget)
      # Get widget bounds relative to content (handles nested layouts)
      widget_bounds = bounds_relative_to_content(widget)

      # Calculate visible region (accounting for scrollbars)
      eff_height = effective_viewport_height
      eff_width = effective_viewport_width
      visible_top = @scroll_offset.y
      visible_bottom = @scroll_offset.y + eff_height
      visible_left = @scroll_offset.x
      visible_right = @scroll_offset.x + eff_width

      new_scroll_x = @scroll_offset.x
      new_scroll_y = @scroll_offset.y

      # Check vertical visibility (for Vertical and Both directions)
      if @direction == ScrollDirection::Vertical || @direction == ScrollDirection::Both
        if widget_bounds.y < visible_top
          # Widget is above viewport - scroll up to show it
          new_scroll_y = widget_bounds.y
        elsif widget_bounds.y + widget_bounds.height > visible_bottom
          # Widget is below viewport - scroll down to show it
          new_scroll_y = widget_bounds.y + widget_bounds.height - eff_height
        end
      end

      # Check horizontal visibility (for Horizontal and Both directions)
      if @direction == ScrollDirection::Horizontal || @direction == ScrollDirection::Both
        if widget_bounds.x < visible_left
          # Widget is left of viewport - scroll left to show it
          new_scroll_x = widget_bounds.x
        elsif widget_bounds.x + widget_bounds.width > visible_right
          # Widget is right of viewport - scroll right to show it
          new_scroll_x = widget_bounds.x + widget_bounds.width - eff_width
        end
      end

      # Only update if scroll actually changed
      if new_scroll_x != @scroll_offset.x || new_scroll_y != @scroll_offset.y
        @scroll_offset = Vec2.new(new_scroll_x, new_scroll_y)
        clamp_scroll_offset

        # Update layer scroll offset for viewport_cache rendering
        if layer = @internal_layer
          layer.scroll_offset = @scroll_offset
        end

        update_visibility_on_scroll
        mark_scrollbar_needs_render
      end
    end

    # === SCROLLBAR INTERACTION ===

    # Override hit_test to intercept clicks on scrollbar areas
    # Without this, clicks on scrollbars would go to content behind them
    # Also adjusts for scroll offset in viewport_cache mode
    def hit_test(point : Vec2) : Widget?
      abs = absolute_bounds
      return nil unless abs.contains_point(point)

      # Convert to local coordinates
      local_point = Vec2.new(point.x - abs.x, point.y - abs.y)

      # Check scrollbar areas FIRST - return self to handle these
      if needs_vertical_scrollbar? && point_in_vertical_scrollbar?(local_point)
        return self
      end
      if needs_horizontal_scrollbar? && point_in_horizontal_scrollbar?(local_point)
        return self
      end

      # For content area: adjust point by scroll_offset to convert from
      # screen coords to content coords in viewport_cache mode
      # Content widgets have abs_bounds based on layout (not rendered position)
      # so we need to shift the test point to match content coordinate system
      content_point = Vec2.new(point.x + @scroll_offset.x, point.y + @scroll_offset.y)


      # Check content children with adjusted point
      if content = @content_widget
        content.children.reverse_each do |child|
          if hit = hit_test_with_offset(child, content_point)
            return hit
          end
        end
        # Also check the content widget itself
        if hit = hit_test_with_offset(content, content_point)
          return hit
        end
      end
      # Return self if click is in content area but didn't hit any child
      self
    end

    # Helper for hit testing with scroll offset adjustment
    # Checks if adjusted point hits this widget or its children
    private def hit_test_with_offset(widget : Widget, adjusted_point : Vec2) : Widget?
      # Calculate what the adjusted point would be in the widget's coordinate system
      # Widget's abs_bounds is in layout coords, adjusted_point is also in layout coords
      abs = widget.absolute_bounds
      unless abs.contains_point(adjusted_point)
        # DEBUG: Show why widget was skipped
        # puts "    SKIP: #{widget.id || widget.class.name} abs=#{abs} doesn't contain #{adjusted_point}"
        return nil
      end

      # Check children first (front to back)
      widget.children.reverse_each do |child|
        if hit = hit_test_with_offset(child, adjusted_point)
          return hit
        end
      end

      widget
    end

    # Mouse down handler for scrollbar interactions
    def on_mouse_down(point : Vec2)
      super  # Call parent for panel z-ordering

      # Convert absolute click coordinates to widget-local coordinates
      # Must use absolute_bounds (not @bounds) because @bounds.x/y are relative to parent
      abs = absolute_bounds
      local_point = Vec2.new(point.x - abs.x, point.y - abs.y)

      # Check vertical scrollbar
      if needs_vertical_scrollbar? && point_in_vertical_scrollbar?(local_point)
        handle_vertical_scrollbar_click(local_point, point)
        return
      end

      # Check horizontal scrollbar
      if needs_horizontal_scrollbar? && point_in_horizontal_scrollbar?(local_point)
        handle_horizontal_scrollbar_click(local_point, point)
        return
      end
    end

    # Mouse move handler for scrollbar dragging
    def on_mouse_move(point : Vec2)
      return unless @interaction_mode == ScrollbarInteractionMode::DraggingThumb

      # Point and @drag_start_point are both in absolute coordinates
      # Calculate delta from drag start
      delta = Vec2.new(point.x - @drag_start_point.x, point.y - @drag_start_point.y)

      case @direction
      when ScrollDirection::Vertical
        # Convert thumb drag delta to scroll offset delta
        track_height = effective_vertical_track_height
        available_track = track_height - 2 * ARROW_SIZE  # Exclude arrows
        thumb_height = calculate_vertical_thumb_height

        if available_track > thumb_height && max_scroll_y > 0
          thumb_travel = available_track - thumb_height
          scroll_ratio = max_scroll_y / thumb_travel
          scroll_delta = delta.y * scroll_ratio

          @scroll_offset = Vec2.new(@scroll_offset.x, @drag_start_offset.y + scroll_delta)
        end

      when ScrollDirection::Horizontal
        # Convert thumb drag delta to scroll offset delta
        track_width = effective_horizontal_track_width
        available_track = track_width - 2 * ARROW_SIZE  # Exclude arrows
        thumb_width = calculate_horizontal_thumb_width

        if available_track > thumb_width && max_scroll_x > 0
          thumb_travel = available_track - thumb_width
          scroll_ratio = max_scroll_x / thumb_travel
          scroll_delta = delta.x * scroll_ratio

          @scroll_offset = Vec2.new(@drag_start_offset.x + scroll_delta, @scroll_offset.y)
        end

      when ScrollDirection::Both
        # Handle both directions, but ONLY apply delta for the axis being dragged
        # This prevents horizontal jitter from affecting vertical scrollbar drag and vice versa
        case @dragging_axis
        when :vertical
          # Only apply vertical delta
          v_track_height = effective_vertical_track_height
          v_available_track = v_track_height - 2 * ARROW_SIZE
          v_thumb_height = calculate_vertical_thumb_height

          if v_available_track > v_thumb_height && max_scroll_y > 0
            v_thumb_travel = v_available_track - v_thumb_height
            v_scroll_ratio = max_scroll_y / v_thumb_travel
            v_scroll_delta = delta.y * v_scroll_ratio
            @scroll_offset = Vec2.new(@scroll_offset.x, @drag_start_offset.y + v_scroll_delta)
          end

        when :horizontal
          # Only apply horizontal delta
          h_track_width = effective_horizontal_track_width
          h_available_track = h_track_width - 2 * ARROW_SIZE
          h_thumb_width = calculate_horizontal_thumb_width

          if h_available_track > h_thumb_width && max_scroll_x > 0
            h_thumb_travel = h_available_track - h_thumb_width
            h_scroll_ratio = max_scroll_x / h_thumb_travel
            h_scroll_delta = delta.x * h_scroll_ratio
            @scroll_offset = Vec2.new(@drag_start_offset.x + h_scroll_delta, @scroll_offset.y)
          end
        end
      end

      # Clamp and trigger render
      clamp_scroll_offset

      # VIEWPORT_CACHE: Update layer scroll_offset instead of triggering layout
      if layer = @internal_layer
        layer.scroll_offset = @scroll_offset
      end

      update_visibility_on_scroll
      mark_scrollbar_needs_render
    end

    # Mouse up handler to stop dragging
    def on_mouse_up(point : Vec2)
      was_dragging = @interaction_mode == ScrollbarInteractionMode::DraggingThumb
      @interaction_mode = ScrollbarInteractionMode::Idle
      @dragging_axis = nil

      # Do deferred full visibility update after drag ends
      if was_dragging
        @last_visibility_offset = Vec2.new(-1.0, -1.0)  # Force update
        update_visibility_on_scroll
      end
    end

    # Hit testing helpers (all use widget-local coordinates)

    # Effective track dimensions - when both scrollbars visible, exclude corner dead zone
    private def effective_vertical_track_height : Float64
      needs_horizontal_scrollbar? ? @bounds.height - SCROLLBAR_WIDTH : @bounds.height
    end

    private def effective_horizontal_track_width : Float64
      needs_vertical_scrollbar? ? @bounds.width - SCROLLBAR_WIDTH : @bounds.width
    end

    private def point_in_vertical_scrollbar?(local_point : Vec2) : Bool
      scrollbar_x = @bounds.width - SCROLLBAR_WIDTH
      local_point.x >= scrollbar_x && local_point.x < @bounds.width &&
        local_point.y >= 0.0 && local_point.y < effective_vertical_track_height
    end

    private def point_in_horizontal_scrollbar?(local_point : Vec2) : Bool
      scrollbar_y = @bounds.height - SCROLLBAR_WIDTH
      local_point.y >= scrollbar_y && local_point.y < @bounds.height &&
        local_point.x >= 0.0 && local_point.x < effective_horizontal_track_width
    end

    private def point_in_vertical_thumb?(local_point : Vec2) : Bool
      scrollbar_x = @bounds.width - SCROLLBAR_WIDTH
      return false unless local_point.x >= scrollbar_x

      thumb_y = calculate_vertical_thumb_y
      thumb_height = calculate_vertical_thumb_height
      local_point.y >= thumb_y && local_point.y < thumb_y + thumb_height
    end

    private def point_in_horizontal_thumb?(local_point : Vec2) : Bool
      scrollbar_y = @bounds.height - SCROLLBAR_WIDTH
      return false unless local_point.y >= scrollbar_y

      thumb_x = calculate_horizontal_thumb_x
      thumb_width = calculate_horizontal_thumb_width
      local_point.x >= thumb_x && local_point.x < thumb_x + thumb_width
    end

    # Arrow hit testing
    private def point_in_vertical_up_arrow?(local_point : Vec2) : Bool
      scrollbar_x = @bounds.width - SCROLLBAR_WIDTH
      local_point.x >= scrollbar_x && local_point.y >= 0.0 && local_point.y < ARROW_SIZE
    end

    private def point_in_vertical_down_arrow?(local_point : Vec2) : Bool
      scrollbar_x = @bounds.width - SCROLLBAR_WIDTH
      track_height = effective_vertical_track_height
      arrow_y = track_height - ARROW_SIZE
      local_point.x >= scrollbar_x && local_point.y >= arrow_y && local_point.y < track_height
    end

    private def point_in_horizontal_left_arrow?(local_point : Vec2) : Bool
      scrollbar_y = @bounds.height - SCROLLBAR_WIDTH
      local_point.y >= scrollbar_y && local_point.x >= 0.0 && local_point.x < ARROW_SIZE
    end

    private def point_in_horizontal_right_arrow?(local_point : Vec2) : Bool
      scrollbar_y = @bounds.height - SCROLLBAR_WIDTH
      track_width = effective_horizontal_track_width
      arrow_x = track_width - ARROW_SIZE
      local_point.y >= scrollbar_y && local_point.x >= arrow_x && local_point.x < track_width
    end

    # Thumb size calculations (same as in to_primitives)

    private def calculate_vertical_thumb_height : Float64
      track_height = effective_vertical_track_height
      available_track = track_height - 2 * ARROW_SIZE  # Exclude both arrows
      thumb_ratio = effective_viewport_height / @content_size.height
      (thumb_ratio * available_track).clamp(THUMB_MIN_SIZE, available_track)
    end

    private def calculate_horizontal_thumb_width : Float64
      track_width = effective_horizontal_track_width
      available_track = track_width - 2 * ARROW_SIZE  # Exclude both arrows
      thumb_ratio = effective_viewport_width / @content_size.width
      (thumb_ratio * available_track).clamp(THUMB_MIN_SIZE, available_track)
    end

    # Thumb position calculations

    private def calculate_vertical_thumb_y : Float64
      track_height = effective_vertical_track_height
      available_track = track_height - 2 * ARROW_SIZE
      return ARROW_SIZE unless max_scroll_y > 0  # Start after up arrow

      thumb_height = calculate_vertical_thumb_height
      # Thumb moves within [ARROW_SIZE, track_height - ARROW_SIZE - thumb_height]
      ARROW_SIZE + (@scroll_offset.y / max_scroll_y) * (available_track - thumb_height)
    end

    private def calculate_horizontal_thumb_x : Float64
      track_width = effective_horizontal_track_width
      available_track = track_width - 2 * ARROW_SIZE
      return ARROW_SIZE unless max_scroll_x > 0  # Start after left arrow

      thumb_width = calculate_horizontal_thumb_width
      # Thumb moves within [ARROW_SIZE, track_width - ARROW_SIZE - thumb_width]
      ARROW_SIZE + (@scroll_offset.x / max_scroll_x) * (available_track - thumb_width)
    end

    # Scrollbar click handlers (use widget-local coordinates for hit testing)

    private def handle_vertical_scrollbar_click(local_point : Vec2, abs_point : Vec2)
      # Check thumb FIRST (it can overlap with arrows visually)
      if point_in_vertical_thumb?(local_point)
        @interaction_mode = ScrollbarInteractionMode::DraggingThumb
        @dragging_axis = :vertical  # Track which axis for Both mode
        @drag_start_offset = @scroll_offset
        @drag_start_point = abs_point  # Store absolute point for drag tracking
        return
      end

      # Check up arrow
      if point_in_vertical_up_arrow?(local_point)
        scroll_by_line(-1, vertical: true)
        return
      end

      # Check down arrow
      if point_in_vertical_down_arrow?(local_point)
        scroll_by_line(1, vertical: true)
        return
      end

      # Click in track (above or below thumb) - page scroll
      thumb_y = calculate_vertical_thumb_y
      thumb_height = calculate_vertical_thumb_height

      if local_point.y < thumb_y
        # Click above thumb - scroll up by page
        scroll_by_page(-1, vertical: true)
      elsif local_point.y >= thumb_y + thumb_height
        # Click below thumb - scroll down by page
        scroll_by_page(1, vertical: true)
      end
    end

    private def handle_horizontal_scrollbar_click(local_point : Vec2, abs_point : Vec2)
      # Check thumb FIRST (it can overlap with arrows visually)
      if point_in_horizontal_thumb?(local_point)
        @interaction_mode = ScrollbarInteractionMode::DraggingThumb
        @dragging_axis = :horizontal  # Track which axis for Both mode
        @drag_start_offset = @scroll_offset
        @drag_start_point = abs_point  # Store absolute point for drag tracking
        return
      end

      # Check left arrow
      if point_in_horizontal_left_arrow?(local_point)
        scroll_by_line(-1, vertical: false)
        return
      end

      # Check right arrow
      if point_in_horizontal_right_arrow?(local_point)
        scroll_by_line(1, vertical: false)
        return
      end

      # Click in track (left or right of thumb) - page scroll
      thumb_x = calculate_horizontal_thumb_x
      thumb_width = calculate_horizontal_thumb_width

      if local_point.x < thumb_x
        # Click left of thumb - scroll left by page
        scroll_by_page(-1, vertical: false)
      elsif local_point.x >= thumb_x + thumb_width
        # Click right of thumb - scroll right by page
        scroll_by_page(1, vertical: false)
      end
    end

    # Scroll by line (arrow click)
    LINE_SCROLL_AMOUNT = 20.0

    private def scroll_by_line(direction : Int32, vertical : Bool)
      if vertical
        @scroll_offset = Vec2.new(@scroll_offset.x, @scroll_offset.y + direction * LINE_SCROLL_AMOUNT)
      else
        @scroll_offset = Vec2.new(@scroll_offset.x + direction * LINE_SCROLL_AMOUNT, @scroll_offset.y)
      end

      clamp_scroll_offset

      # VIEWPORT_CACHE: Update layer scroll_offset instead of triggering layout
      if layer = @internal_layer
        layer.scroll_offset = @scroll_offset
      end

      update_visibility_on_scroll
      mark_scrollbar_needs_render
    end

    # Scroll by page (track click)
    private def scroll_by_page(direction : Int32, vertical : Bool)
      if vertical
        page_amount = @viewport_size.height
        @scroll_offset = Vec2.new(@scroll_offset.x, @scroll_offset.y + direction * page_amount)
      else
        page_amount = @viewport_size.width
        @scroll_offset = Vec2.new(@scroll_offset.x + direction * page_amount, @scroll_offset.y)
      end

      clamp_scroll_offset

      # VIEWPORT_CACHE: Update layer scroll_offset instead of triggering layout
      if layer = @internal_layer
        layer.scroll_offset = @scroll_offset
      end

      update_visibility_on_scroll
      mark_scrollbar_needs_render
    end

    # === VISIBILITY TRACKING ===

    # Initial visibility tracking during layout
    # Finds all widgets that intersect the current viewport
    private def update_visibility_tracking(content : Widget)
      return unless layer = @internal_layer

      @visible_widgets.clear

      # Calculate viewport rectangle in content coordinates
      viewport = Rect.new(
        @scroll_offset.x,
        @scroll_offset.y,
        effective_viewport_width,
        effective_viewport_height
      )

      # Traverse content tree to find visible widgets
      collect_visible_widgets(content, viewport)
    end

    # Recursively collect widgets that intersect viewport
    # Uses content-relative bounds (accumulated from parent positions)
    private def collect_visible_widgets(widget : Widget, viewport : Rect, parent_offset : Vec2 = Vec2.zero)
      # Calculate widget bounds in content-relative coordinates
      content_bounds = Rect.new(
        widget.bounds.x + parent_offset.x,
        widget.bounds.y + parent_offset.y,
        widget.bounds.width,
        widget.bounds.height
      )

      # Check if widget's bounds intersect viewport
      if bounds_intersect?(content_bounds, viewport)
        @visible_widgets << widget
      end

      # Check children recursively with accumulated offset
      child_offset = Vec2.new(content_bounds.x, content_bounds.y)
      widget.children.each do |child|
        collect_visible_widgets(child, viewport, child_offset)
      end
    end

    # Check if two rects intersect
    private def bounds_intersect?(a : Rect, b : Rect) : Bool
      !(a.x + a.width <= b.x ||
        b.x + b.width <= a.x ||
        a.y + a.height <= b.y ||
        b.y + b.height <= a.y)
    end

    # Update visibility on scroll (without triggering layout)
    # Detects widgets entering/leaving viewport and wipes textures for exiting widgets
    private def update_visibility_on_scroll
      # NOTE: We CANNOT skip visibility tracking during drag for viewport_cache layers!
      # Even during drag, entering widgets must be marked dirty so they get rendered.
      # The per-widget texture approach requires each entering widget to be rendered
      # to the layer buffer at its buffer-relative position.

      # OPTIMIZATION: Skip if already updated at this scroll offset (dedup multiple calls per frame)
      if @scroll_offset.x == @last_visibility_offset.x && @scroll_offset.y == @last_visibility_offset.y
        return
      end
      @last_visibility_offset = @scroll_offset

      update_visibility_on_scroll_impl
    end

    private def update_visibility_on_scroll_impl
      return unless layer = @internal_layer
      return unless content = @content_widget

      # Calculate new viewport rectangle
      viewport = Rect.new(
        @scroll_offset.x,
        @scroll_offset.y,
        effective_viewport_width,
        effective_viewport_height
      )

      # Build new visible set
      new_visible = Set(Widget).new
      collect_visible_widgets_into(content, viewport, new_visible)

      # Find widgets that just left the viewport
      exiting = @visible_widgets - new_visible
      exiting.each do |widget|
        # Mark widget as needing fresh background when it re-enters
        # This prevents capturing stale content from layer (violates invariant h)
        widget.needs_fresh_background = true

        # Wipe widget's texture to free memory
        widget.widget_backend = nil
        widget.background_backend = nil
        # Clear hover state on widgets scrolling out of view
        widget.on_mouse_exit if widget.responds_to?(:on_mouse_exit)
      end

      # Mark only newly entering widgets as dirty (they need rendering)
      # For viewport_cache: widgets stay at fixed buffer positions, only viewport moves
      # - Small scroll: compositor shows different part of cached buffer (no re-render)
      # - Entering widgets: need rendering because their backends were cleared when they exited
      # - Large scroll: handle_viewport_cache_scroll triggers full re-render when cache exceeded
      entering = new_visible - @visible_widgets
      entering.each do |widget|
        widget.mark_needs_render
        layer.mark_needs_render(widget)
      end

      # Update visible set
      @visible_widgets = new_visible

      # Re-detect hover since widgets may have scrolled under/away from mouse
      Widget.app?.try(&.redetect_hover)
    end

    # Clear widget_backend for ALL widgets in content tree
    # Called by LayerRenderer when viewport_cache buffer is recentered.
    # CRITICAL: Must clear ALL widgets, not just @visible_widgets, because:
    # - @visible_widgets reflects OLD scroll position (updated during rendering)
    # - After recenter, widgets that WERE off-buffer but WILL be visible still have
    #   OLD backends with content rendered for OLD buffer_origin position
    # - The fast path would blit OLD content at NEW position → shifted garbling
    def clear_all_widget_backends
      return unless content = @content_widget
      clear_backends_recursive(content)
    end

    # Recursively clear widget_backend for widget and all descendants
    private def clear_backends_recursive(widget : Widget) : Int32
      count = 0
      if widget.widget_backend
        widget.widget_backend = nil
        widget.background_backend = nil
        count += 1
      end
      widget.children.each do |child|
        count += clear_backends_recursive(child)
      end
      count
    end

    # Helper to collect visible widgets into a provided set
    # OPTIMIZATION: Early-exit if widget is completely outside viewport (skip entire subtree)
    # Uses content-relative bounds (accumulated from parent positions)
    private def collect_visible_widgets_into(widget : Widget, viewport : Rect, result : Set(Widget), parent_offset : Vec2 = Vec2.zero)
      # Calculate widget bounds in content-relative coordinates
      content_bounds = Rect.new(
        widget.bounds.x + parent_offset.x,
        widget.bounds.y + parent_offset.y,
        widget.bounds.width,
        widget.bounds.height
      )

      # If widget doesn't intersect viewport, skip it AND all children
      return unless bounds_intersect?(content_bounds, viewport)

      result << widget

      # Pass accumulated offset to children
      child_offset = Vec2.new(content_bounds.x, content_bounds.y)
      widget.children.each do |child|
        collect_visible_widgets_into(child, viewport, result, child_offset)
      end
    end
  end
end
